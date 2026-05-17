#!/bin/bash
# =============================================================================
# ASID 2025/2026 — Tema 2: Escalabilidade Horizontal e Custo Marginal
# Script de Cenários de Teste — Online Boutique (baseado nos cenários da prof.)
# Ficheiro: test1.sh
# =============================================================================
NAMESPACE="${NAMESPACE:-default}"
DISABLE_LG="true"
MAX_USERS="${MAX_USERS:-50}"
STEP_DURATION="${STEP_DURATION:-60}"
DEMO_USERS="${DEMO_USERS:-10}"
DEMO_DURATION="${DEMO_DURATION:-120}"
P99_THRESHOLD="${P99_THRESHOLD:-2000}"
FAIL_THRESHOLD="${FAIL_THRESHOLD:-5}"
COOLDOWN="${COOLDOWN:-15}"

RESULTS_DIR="cenarios_ob_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULTS_DIR"

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$RESULTS_DIR/run.log"; }

check_prerequisites() {
  log "A verificar pré-requisitos..."
  kubectl cluster-info > /dev/null 2>&1 || { log "ERRO: kubectl não conectado ao cluster"; exit 1; }
  kubectl get namespace "$NAMESPACE" > /dev/null 2>&1 || {
    log "AVISO: namespace '$NAMESPACE' não encontrado."
    log "       Verifica com: kubectl get namespaces"
    exit 1
  }
  if [ -n "$HOST_IP" ]; then
    NODEPORT=$(kubectl -n "$NAMESPACE" get svc frontend-external \
      -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
    if [ -n "$NODEPORT" ]; then
      FRONTEND_URL="http://${HOST_IP}:${NODEPORT}"
    else
      LB_IP=$(kubectl -n "$NAMESPACE" get svc frontend-external \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
      [ -n "$LB_IP" ] && FRONTEND_URL="http://${LB_IP}" || {
        log "ERRO: não foi possível determinar a URL do frontend."
        exit 1
      }
    fi
  else
    FRONTEND_URL="http://localhost"
  fi
  log "Frontend URL: $FRONTEND_URL"

  # Warm-up: aguarda frontend responder com 200
  log "A aguardar warm-up do sistema (2 minutos)..."
  WARMUP_END=$((SECONDS + 120))
  while [ $SECONDS -lt $WARMUP_END ]; do
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$FRONTEND_URL" 2>/dev/null)
    if [ "$HTTP_STATUS" = "200" ]; then
      log "Frontend OK (HTTP 200). Aguarda estabilização..."
      sleep $((WARMUP_END - SECONDS))
      break
    fi
    sleep 5
  done
  log "Warm-up concluído."

  LOCUST_BIN=$(which locust 2>/dev/null)
  [ -z "$LOCUST_BIN" ] && LOCUST_BIN=$(find ~/Library/Python -name "locust" -type f 2>/dev/null | head -1)
  [ -z "$LOCUST_BIN" ] && LOCUST_BIN=$(find ~/.local/bin -name "locust" -type f 2>/dev/null | head -1)
  if [ -z "$LOCUST_BIN" ]; then
    log "locust não encontrado, a instalar..."
    pip3 install locust --quiet 2>/dev/null || pip install locust --quiet 2>/dev/null
    LOCUST_BIN=$(which locust 2>/dev/null)
    [ -z "$LOCUST_BIN" ] && LOCUST_BIN=$(find ~/Library/Python ~/.local -name "locust" -type f 2>/dev/null | head -1)
  fi
  [ -z "$LOCUST_BIN" ] && { log "ERRO: locust não encontrado após instalação"; exit 1; }
  export LOCUST_BIN FRONTEND_URL
  log "Locust: $LOCUST_BIN"
  log "Pré-requisitos OK"
}

pause_loadgenerator() {
  log "A pausar o loadgenerator nativo (namespace: $NAMESPACE)..."
  kubectl -n "$NAMESPACE" scale deploy/loadgenerator --replicas=0 2>/dev/null && \
    log "loadgenerator pausado." || \
    log "AVISO: loadgenerator não encontrado ou já parado."
  echo "paused" > "$RESULTS_DIR/lg_state.txt"
}

resume_loadgenerator() {
  log "A retomar o loadgenerator nativo (namespace: $NAMESPACE)..."
  kubectl -n "$NAMESPACE" scale deploy/loadgenerator --replicas=1 2>/dev/null && \
    log "loadgenerator retomado." || \
    log "AVISO: não foi possível retomar o loadgenerator."
  echo "running" > "$RESULTS_DIR/lg_state.txt"
}

pause_lg_standalone() {
  kubectl -n "${NAMESPACE}" scale deploy/loadgenerator --replicas=0 2>/dev/null && \
    echo "loadgenerator pausado (namespace: ${NAMESPACE})" || \
    echo "AVISO: loadgenerator não encontrado em namespace '${NAMESPACE}'"
}

resume_lg_standalone() {
  kubectl -n "${NAMESPACE}" scale deploy/loadgenerator --replicas=1 2>/dev/null && \
    echo "loadgenerator retomado (namespace: ${NAMESPACE})" || \
    echo "AVISO: não foi possível retomar o loadgenerator"
}

capture_baseline() {
  log "=== BASELINE: captura estado inicial (namespace: $NAMESPACE) ==="
  local out="$RESULTS_DIR/baseline"
  mkdir -p "$out"
  kubectl -n "$NAMESPACE" get deployments -o wide > "$out/deployments.txt"
  kubectl -n "$NAMESPACE" get deployments -o json | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(f'{'Serviço':<30} {'Réplicas':<10} {'CPU req':<12} {'CPU lim':<12} {'Mem req':<12} {'Mem lim':<12}')
print('-'*90)
for d in data['items']:
    name = d['metadata']['name']
    replicas = d['spec'].get('replicas', 1)
    for c in d['spec']['template']['spec']['containers']:
        res = c.get('resources', {})
        req = res.get('requests', {})
        lim = res.get('limits', {})
        print(f'{name:<30} {replicas:<10} {req.get(\"cpu\",\"n/a\"):<12} {lim.get(\"cpu\",\"n/a\"):<12} {req.get(\"memory\",\"n/a\"):<12} {lim.get(\"memory\",\"n/a\"):<12}')
" | tee "$out/resources_config.txt"
  kubectl -n "$NAMESPACE" top pods --sort-by=cpu > "$out/top_pods_idle.txt" 2>&1
  kubectl -n "$NAMESPACE" get pods -o wide > "$out/pods_status.txt"
  kubectl -n "$NAMESPACE" get hpa > "$out/hpa_inicial.txt" 2>&1
  log "Baseline em $out/"
}

start_monitoring() {
  local interval=${1:-15}
  local out="$RESULTS_DIR/monitoring"
  mkdir -p "$out"
  log "A iniciar monitorização (${interval}s) → $out/"
  (
    i=0
    while true; do
      ts=$(date +%H:%M:%S)
      kubectl -n "$NAMESPACE" top pods --sort-by=cpu 2>/dev/null | \
        awk -v ts="$ts" -v i="$i" 'NR>1{print ts","i","$1","$2","$3}' \
        >> "$out/pods_metrics.csv"
      kubectl -n "$NAMESPACE" get pods --no-headers 2>/dev/null | \
        awk -v ts="$ts" '$4>0{print ts" RESTART pod="$1" restarts="$4}' \
        >> "$out/restarts.log"
      i=$((i+1))
      sleep "$interval"
    done
  ) &
  MONITOR_PID=$!
  echo $MONITOR_PID > "$RESULTS_DIR/monitor.pid"
  log "Monitor PID: $MONITOR_PID"
}

stop_monitoring() {
  if [ -f "$RESULTS_DIR/monitor.pid" ]; then
    kill "$(cat "$RESULTS_DIR/monitor.pid")" 2>/dev/null
    log "Monitorização parada"
  fi
}

create_locustfile() {
cat > "$RESULTS_DIR/locustfile.py" << 'LOCUST_EOF'
from locust import HttpUser, task, between
import random

PRODUCT_IDS = [
    "OLJCESPC7Z", "66VCHSJNUP", "1YMWWN1N4O",
    "L9ECAV7KIM", "2ZYFJ3GM2N", "0PUK6V6EV0",
    "LS4PSXUNUM", "9SIQT8TOJO", "6E92ZMYYFZ"
]

class OnlineBoutiqueUser(HttpUser):
    wait_time = between(1, 3)

    @task(10)
    def browse_product(self):
        pid = random.choice(PRODUCT_IDS)
        self.client.get(f"/product/{pid}", name="/product/[id]")

    @task(5)
    def index(self):
        self.client.get("/")

    @task(3)
    def add_to_cart(self):
        pid = random.choice(PRODUCT_IDS)
        self.client.post("/cart", data={"product_id": pid, "quantity": "1"}, name="/cart [add]")

    @task(2)
    def view_cart(self):
        self.client.get("/cart")

    @task(1)
    def checkout(self):
        pid = random.choice(PRODUCT_IDS)
        # FIX: só faz checkout se o add ao carrinho tiver sucesso
        with self.client.post("/cart", data={"product_id": pid, "quantity": "1"},
                              name="/cart [add]", catch_response=True) as r:
            if r.status_code != 200:
                r.failure(f"add falhou ({r.status_code}), skip checkout")
                return
        self.client.post("/cart/checkout", data={
            "email": "test@asid.uc.pt",
            "street_address": "Rua Pedro Hispano 1",
            "zip_code": "3030-199",
            "city": "Coimbra",
            "state": "Coimbra",
            "country": "Portugal",
            "credit_card_number": "4432801561520454",
            "credit_card_expiration_month": "1",
            "credit_card_expiration_year": "2030",
            "credit_card_cvv": "672"
        }, name="/cart/checkout")

    @task(2)
    def set_currency(self):
        currency = random.choice(["EUR", "USD", "GBP", "JPY"])
        self.client.post("/setCurrency", data={"currency_code": currency})
LOCUST_EOF
  log "locustfile.py criado (com fix no checkout)"
}

run_demo() {
  log "========================================================"
  log "MODO DEMO — ${DEMO_USERS} users durante ${DEMO_DURATION}s"
  log "========================================================"
  local out="$RESULTS_DIR/demo_${DEMO_USERS}users"
  mkdir -p "$out"
  kubectl -n "$NAMESPACE" top pods --sort-by=cpu > "$out/pods_before.txt" 2>/dev/null
  kubectl -n "$NAMESPACE" get pods > "$out/pods_status_before.txt"
  log "A correr Locust (${DEMO_USERS} users, ${DEMO_DURATION}s)..."
  "$LOCUST_BIN" \
    --locustfile "$RESULTS_DIR/locustfile.py" \
    --host "$FRONTEND_URL" \
    --users "$DEMO_USERS" \
    --spawn-rate "$DEMO_USERS" \
    --run-time "${DEMO_DURATION}s" \
    --headless \
    --csv "$out/locust" \
    --html "$out/report.html" \
    --loglevel WARNING \
    2>> "$out/locust.log"
  kubectl -n "$NAMESPACE" top pods --sort-by=cpu > "$out/pods_after.txt" 2>/dev/null
  kubectl -n "$NAMESPACE" get events --sort-by=.lastTimestamp 2>/dev/null | tail -20 > "$out/events.txt"
  log ""
  log "=== RESULTADOS DEMO ==="
  if [ -f "$out/locust_stats.csv" ]; then
    python3 -c "
import csv
with open('$out/locust_stats.csv') as f:
    rows = list(csv.DictReader(f))
agg = [r for r in rows if r['Name']=='Aggregated']
rest = [r for r in rows if r['Name']!='Aggregated']
for row in rest + agg:
    print(f'  {row.get(\"Name\",\"?\")[:42]:<44} p50={row.get(\"50%\",\"?\"):>6}ms  p99={row.get(\"99%\",\"?\"):>6}ms  fails={row.get(\"Failure Count\",\"0\"):>5}  rps={row.get(\"Requests/s\",\"?\"):>6}')
" 2>/dev/null | tee -a "$RESULTS_DIR/run.log"
  fi
  log "HTML: $out/report.html"
  log "CSV:  $out/locust_stats.csv"
}

find_breaking_point() {
  log "========================================================"
  log "MODO INCREMENTAL: 5 users → ${MAX_USERS} users (escada de 5 em 5)"
  log "  Namespace       : ${NAMESPACE}"
  log "  Duração/step    : ${STEP_DURATION}s"
  log "  Cooldown        : ${COOLDOWN}s"
  log "  Limite p99      : ${P99_THRESHOLD}ms"
  log "  Limite falhas   : ${FAIL_THRESHOLD}%"
  log "========================================================"
  local breaking_point=0
  local breaking_reason=""
  local progress="$RESULTS_DIR/progresso_incremental.csv"
  echo "users,p50,p90,p99,fail_count,fail_pct,rps,status" > "$progress"

  for users in $(seq 5 5 "$MAX_USERS"); do
    local out="$RESULTS_DIR/step_${users}users"
    mkdir -p "$out"
    log "--- Step: ${users} user(s) ---"
    "$LOCUST_BIN" \
      --locustfile "$RESULTS_DIR/locustfile.py" \
      --host "$FRONTEND_URL" \
      --users "$users" \
      --spawn-rate "$users" \
      --run-time "${STEP_DURATION}s" \
      --headless \
      --csv "$out/locust" \
      --html "$out/report.html" \
      --loglevel WARNING \
      2>> "$out/locust.log"
    kubectl -n "$NAMESPACE" top pods --sort-by=cpu > "$out/top_pods.txt" 2>/dev/null

    local status="OK"
    if [ -f "$out/locust_stats.csv" ]; then
      result=$(python3 - "$out/locust_stats.csv" "$P99_THRESHOLD" "$FAIL_THRESHOLD" << 'PYEOF'
import csv, sys
csv_file  = sys.argv[1]
p99_limit = int(sys.argv[2])
fail_limit = float(sys.argv[3])
with open(csv_file) as f:
    rows = list(csv.DictReader(f))
for row in rows:
    if row.get('Name') != 'Aggregated':
        continue
    total    = int(row.get('Request Count', 0) or 0)
    failures = int(row.get('Failure Count', 0) or 0)
    p50  = row.get('50%', '0') or '0'
    p90  = row.get('90%', '0') or '0'
    p99  = row.get('99%', '0') or '0'
    rps  = row.get('Requests/s', '0') or '0'
    fail_pct = (failures / total * 100) if total > 0 else 0
    p99_val  = int(p99) if str(p99).isdigit() else 0
    if failures > 0 and fail_pct >= fail_limit:
        status = f"QUEBRA_FALHAS({fail_pct:.1f}%)"
    elif p99_val >= p99_limit:
        status = f"QUEBRA_LATENCIA(p99={p99}ms)"
    else:
        status = "OK"
    print(f"{p50},{p90},{p99},{failures},{fail_pct:.1f},{rps},{status}")
    break
PYEOF
)
      if [ -n "$result" ]; then
        echo "${users},${result}" >> "$progress"
        status=$(echo "$result" | cut -d',' -f7)
        p50=$(echo "$result" | cut -d',' -f1)
        p90=$(echo "$result" | cut -d',' -f2)
        p99=$(echo "$result" | cut -d',' -f3)
        fail=$(echo "$result" | cut -d',' -f4)
        rps=$(echo "$result" | cut -d',' -f6)
        log "  ${users} users → p50=${p50}ms  p90=${p90}ms  p99=${p99}ms  falhas=${fail}  rps=${rps}  [${status}]"
      fi
    fi

    if [[ "$status" == QUEBRA* ]]; then
      breaking_point=$users
      breaking_reason=$status
      log "========================================================"
      log "PONTO DE QUEBRA: ${users} users — ${breaking_reason}"
      log "========================================================"
      break
    fi

    sleep "$COOLDOWN"
  done

  if [ $breaking_point -eq 0 ]; then
    log "Sistema aguentou até ${MAX_USERS} users sem quebrar."
    log "Aumenta MAX_USERS para continuar: MAX_USERS=100 $0 incremental"
  fi

  log ""
  log "=== PROGRESSO COMPLETO ==="
  column -t -s',' "$progress" 2>/dev/null || cat "$progress"
  log ""
  log "CSV: $progress"
}

generate_report() {
  local report="$RESULTS_DIR/RESUMO.txt"
  log "A gerar resumo..."
  cat > "$report" << REPORT_EOF
=============================================================================
ASID 2025/2026 — Tema 2: Escalabilidade Horizontal
Online Boutique — Resumo de Testes
Namespace: ${NAMESPACE}
Gerado em: $(date)
=============================================================================

CONFIGURAÇÃO INICIAL
--------------------
$(cat "$RESULTS_DIR/baseline/resources_config.txt" 2>/dev/null || echo "(baseline não encontrado)")

FASES EXECUTADAS
----------------
REPORT_EOF

  for dir in "$RESULTS_DIR"/step_* "$RESULTS_DIR"/demo_*; do
    [ -d "$dir" ] || continue
    phase=$(basename "$dir")
    [ -f "$dir/locust_stats.csv" ] || continue
    echo "" >> "$report"
    echo "--- $phase ---" >> "$report"
    python3 -c "
import csv
with open('$dir/locust_stats.csv') as f:
    rows = list(csv.DictReader(f))
for row in rows:
    if row.get('Name') == 'Aggregated':
        print(f'  Pedidos : {row.get(\"Request Count\",\"?\")}')
        print(f'  Falhas  : {row.get(\"Failure Count\",\"?\")}')
        print(f'  p50={row.get(\"50%\",\"?\")}ms  p90={row.get(\"90%\",\"?\")}ms  p99={row.get(\"99%\",\"?\")}ms')
        print(f'  RPS     : {row.get(\"Requests/s\",\"?\")}')
" 2>/dev/null >> "$report"
  done

  if [ -f "$RESULTS_DIR/progresso_incremental.csv" ]; then
    echo "" >> "$report"
    echo "PROGRESSO INCREMENTAL (users → métricas)" >> "$report"
    echo "----------------------------------------" >> "$report"
    column -t -s',' "$RESULTS_DIR/progresso_incremental.csv" 2>/dev/null >> "$report" || \
      cat "$RESULTS_DIR/progresso_incremental.csv" >> "$report"
  fi

  log "Resumo: $report"
  cat "$report"
}

main() {
  case "${1:-}" in
    pause_lg)
      pause_lg_standalone
      ;;
    resume_lg)
      resume_lg_standalone
      ;;
    baseline)
      check_prerequisites
      capture_baseline
      ;;
    demo)
      check_prerequisites
      capture_baseline
      create_locustfile
      pause_loadgenerator
      run_demo
      resume_loadgenerator
      generate_report
      ;;
    incremental)
      check_prerequisites
      capture_baseline
      create_locustfile
      pause_loadgenerator
      start_monitoring 10
      find_breaking_point
      stop_monitoring
      resume_loadgenerator
      generate_report
      ;;
    report)
      generate_report
      ;;
    *)
      cat << 'HELP_EOF'
Uso: ./test1.sh [MODO]

MODOS:
  demo          run único de validação (10 users, 2 min)
  incremental   escada 5→MAX_USERS até o sistema quebrar (C1)
  baseline      captura estado inicial do cluster
  pause_lg      pausa o loadgenerator nativo
  resume_lg     retoma o loadgenerator nativo
  report        gera resumo de resultados já existentes

VARIÁVEIS OPCIONAIS:
  NAMESPACE=default      namespace Kubernetes (default: default)
  MAX_USERS=50           limite de users no modo incremental
  STEP_DURATION=60       segundos por step
  FAIL_THRESHOLD=5       % falhas para quebra
  P99_THRESHOLD=2000     ms de p99 para quebra

EXEMPLOS:
  # Docker Desktop — demo de validação
  ./test1.sh demo

  # Docker Desktop — C1: escada até 80 users
  MAX_USERS=80 ./test1.sh incremental

  # Docker Desktop — C1 mais lento (2 min por step)
  MAX_USERS=80 STEP_DURATION=120 ./test1.sh incremental
HELP_EOF
      ;;
  esac
}

main "$@"