#!/bin/bash
# =============================================================================
# ASID 2025/2026 — Tema 2: Escalabilidade Horizontal e Custo Marginal
# C2 — Escalamento Seletivo: productcatalogservice com 3 réplicas
# Execução COMPARATIVA com cargas fixas: 15, 20, 25 users
# =============================================================================
# DESCRIÇÃO:
#   Cenário C2 do projeto ASID. Escala o productcatalogservice para 3 réplicas
#   e corre execuções comparativas independentes a 15, 20 e 25 utilizadores.
#   Recolhe métricas de latência, throughput, CPU/RAM e sinais de contenção
#   no redis-cart. Cada nível de carga é uma execução independente.
#
# COMO USAR:
#   chmod +x c2.sh
#   ./c2.sh              # executa C2 completo
#   ./c2.sh scale_only   # só escala o productcatalogservice para 3 réplicas
#   ./c2.sh reset        # repõe productcatalogservice para 1 réplica
#
# ESTRUTURA DE SAÍDA:
#   cenarios_ob_YYYYMMDD_HHMMSS/
#     baseline/           — estado do cluster antes dos testes
#     load_15users/       — resultados a 15 users
#     load_20users/       — resultados a 20 users
#     load_25users/       — resultados a 25 users
#     monitoring/         — métricas CPU/RAM contínuas (10s de intervalo)
#     redis_metrics/      — snapshots do redis-cart INFO stats/clients
#     RESUMO_C2.txt       — tabela comparativa final
#     run.log             — log completo da execução
# =============================================================================

NAMESPACE="${NAMESPACE:-default}"
FRONTEND_URL="${FRONTEND_URL:-http://localhost}"
RESULTS_DIR="cenarios_ob_c2"
[ -d "$RESULTS_DIR" ] && mv "$RESULTS_DIR" "${RESULTS_DIR}_bak_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULTS_DIR"

# Parâmetros C2 — execução comparativa (cargas fixas)
WARMUP_DURATION=30        # segundos de warm-up antes de medir
MEASURE_DURATION=120      # segundos de janela de medição por nível
SPAWN_RATE=2              # utilizadores lançados por segundo (conforme CLAUDE.md)
COOLDOWN_BETWEEN=60       # segundos entre execuções (deixar cluster estabilizar)
LOAD_LEVELS="15 20 25"    # cargas fixas a testar (conforme C1 exploratório)

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$RESULTS_DIR/run.log"; }

# =============================================================================
# PRÉ-REQUISITOS
# =============================================================================
check_prerequisites() {
  log "A verificar pré-requisitos..."
  kubectl cluster-info > /dev/null 2>&1 || { log "ERRO: kubectl não conectado"; exit 1; }
  kubectl get namespace "$NAMESPACE" > /dev/null 2>&1 || { log "ERRO: namespace '$NAMESPACE' não existe"; exit 1; }

  # Localiza o Locust
  LOCUST_BIN=$(which locust 2>/dev/null)
  [ -z "$LOCUST_BIN" ] && LOCUST_BIN=$(find ~/Library/Python -name "locust" -type f 2>/dev/null | head -1)
  [ -z "$LOCUST_BIN" ] && LOCUST_BIN=$(find ~/.local/bin -name "locust" -type f 2>/dev/null | head -1)
  if [ -z "$LOCUST_BIN" ]; then
    log "locust não encontrado, a instalar..."
    pip3 install locust --quiet 2>/dev/null
    LOCUST_BIN=$(which locust 2>/dev/null)
    [ -z "$LOCUST_BIN" ] && LOCUST_BIN=$(find ~/Library/Python ~/.local -name "locust" -type f 2>/dev/null | head -1)
  fi
  [ -z "$LOCUST_BIN" ] && { log "ERRO: locust não encontrado"; exit 1; }
  export LOCUST_BIN
  log "Locust: $LOCUST_BIN"
  log "Pré-requisitos OK"
}

# =============================================================================
# ESCALAR productcatalogservice para 3 RÉPLICAS (C2)
# =============================================================================
scale_productcatalog() {
  log "=== C2: A escalar productcatalogservice → 3 réplicas ==="
  kubectl -n "$NAMESPACE" scale deployment/productcatalogservice --replicas=3
  log "A aguardar que as 3 réplicas fiquem prontas..."
  kubectl -n "$NAMESPACE" rollout status deployment/productcatalogservice --timeout=120s
  local replicas
  replicas=$(kubectl -n "$NAMESPACE" get deployment productcatalogservice -o jsonpath='{.status.readyReplicas}')
  log "productcatalogservice: ${replicas}/3 réplicas prontas"
  if [ "$replicas" != "3" ]; then
    log "AVISO: Nem todas as réplicas estão prontas. A continuar mesmo assim..."
  fi
}

# Repõe 1 réplica (útil para reset entre cenários)
reset_productcatalog() {
  log "A repor productcatalogservice → 1 réplica..."
  kubectl -n "$NAMESPACE" scale deployment/productcatalogservice --replicas=1
  kubectl -n "$NAMESPACE" rollout status deployment/productcatalogservice --timeout=60s
  log "productcatalogservice reposto para 1 réplica"
}

# =============================================================================
# PAUSA/RETOMA do loadgenerator nativo
# =============================================================================
pause_loadgenerator() {
  kubectl -n "$NAMESPACE" scale deploy/loadgenerator --replicas=0 2>/dev/null && \
    log "loadgenerator nativo pausado" || \
    log "AVISO: loadgenerator não encontrado"
}

resume_loadgenerator() {
  kubectl -n "$NAMESPACE" scale deploy/loadgenerator --replicas=1 2>/dev/null && \
    log "loadgenerator nativo retomado" || \
    log "AVISO: não foi possível retomar loadgenerator"
}

# =============================================================================
# BASELINE — estado do cluster antes dos testes
# =============================================================================
capture_baseline() {
  log "=== BASELINE: captura estado inicial ==="
  local out="$RESULTS_DIR/baseline"
  mkdir -p "$out"

  kubectl -n "$NAMESPACE" get deployments -o wide > "$out/deployments.txt"
  kubectl -n "$NAMESPACE" get deployments -o json | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(f'{'Serviço':<35} {'Réplicas':<10} {'CPU req':<12} {'CPU lim':<12} {'Mem req':<12} {'Mem lim':<12}')
print('-'*95)
for d in data['items']:
    name = d['metadata']['name']
    replicas = d['spec'].get('replicas', 1)
    for c in d['spec']['template']['spec']['containers']:
        res = c.get('resources', {})
        req = res.get('requests', {})
        lim = res.get('limits', {})
        print(f'{name:<35} {replicas:<10} {req.get(\"cpu\",\"n/a\"):<12} {lim.get(\"cpu\",\"n/a\"):<12} {req.get(\"memory\",\"n/a\"):<12} {lim.get(\"memory\",\"n/a\"):<12}')
" | tee "$out/resources_config.txt"

  kubectl -n "$NAMESPACE" top pods --sort-by=cpu > "$out/top_pods_idle.txt" 2>&1
  kubectl -n "$NAMESPACE" get pods -o wide > "$out/pods_status.txt"
  kubectl -n "$NAMESPACE" get hpa > "$out/hpa.txt" 2>&1
  log "Baseline em $out/"
}

# =============================================================================
# MONITORIZAÇÃO CONTÍNUA (CPU/RAM a cada 10s)
# =============================================================================
start_monitoring() {
  local out="$RESULTS_DIR/monitoring"
  mkdir -p "$out"
  echo "timestamp,snapshot,pod,cpu,ram" > "$out/pods_metrics.csv"
  log "A iniciar monitorização (10s) → $out/"
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
      sleep 10
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

# =============================================================================
# MÉTRICAS DO REDIS-CART
# Recolhe sinais de contenção para H2 (redis-cart como bottleneck)
# =============================================================================
capture_redis_metrics() {
  local label=$1
  local out="$RESULTS_DIR/redis_metrics"
  mkdir -p "$out"

  local redis_pod
  redis_pod=$(kubectl -n "$NAMESPACE" get pods --no-headers -l app=redis-cart 2>/dev/null | awk 'NR==1{print $1}')
  if [ -z "$redis_pod" ]; then
    log "AVISO: pod redis-cart não encontrado"
    return
  fi

  log "  Redis metrics (${label}) — pod: $redis_pod"
  {
    echo "=== Redis INFO stats (${label}) === $(date)"
    kubectl -n "$NAMESPACE" exec "$redis_pod" -- redis-cli INFO stats 2>/dev/null
    echo ""
    echo "=== Redis INFO clients (${label}) ==="
    kubectl -n "$NAMESPACE" exec "$redis_pod" -- redis-cli INFO clients 2>/dev/null
    echo ""
    echo "=== Redis SLOWLOG (últimas 20 entradas) ==="
    kubectl -n "$NAMESPACE" exec "$redis_pod" -- redis-cli SLOWLOG GET 20 2>/dev/null
    echo ""
    echo "=== Redis LATENCY LATEST ==="
    kubectl -n "$NAMESPACE" exec "$redis_pod" -- redis-cli LATENCY LATEST 2>/dev/null
    echo ""
    echo "=== Redis INFO memory ==="
    kubectl -n "$NAMESPACE" exec "$redis_pod" -- redis-cli INFO memory 2>/dev/null
  } > "$out/redis_${label}.txt"
  log "  Redis metrics guardadas em redis_metrics/redis_${label}.txt"
}

# =============================================================================
# LOCUSTFILE — 3 perfis de utilizador conforme CLAUDE.md
# CasualUser (30%), NormalUser (50%), PowerUser (20%)
# Pesos: index:1, setCurrency:2, browseProduct:10, addToCart:2, viewCart:3, checkout:1
# =============================================================================
create_locustfile() {
cat > "$RESULTS_DIR/locustfile.py" << 'LOCUST_EOF'
from locust import HttpUser, task, between
import random

PRODUCT_IDS = [
    "OLJCESPC7Z", "66VCHSJNUP", "1YMWWN1N4O",
    "L9ECAV7KIM", "2ZYFJ3GM2N", "0PUK6V6EV0",
    "LS4PSXUNUM", "9SIQT8TOJO", "6E92ZMYYFZ"
]

CHECKOUT_FORM = {
    "email": "test@asid.uc.pt",
    "street_address": "123 Main St",
    "zip_code": "10001",
    "city": "New York",
    "state": "NY",
    "country": "United States",
    "credit_card_number": "4432801561520454",
    "credit_card_expiration_month": "1",
    "credit_card_expiration_year": "2030",
    "credit_card_cvv": "672"
}

class CasualUser(HttpUser):
    """30% do tráfego — utilizador casual: browse e homepage, raramente cart"""
    weight = 3
    wait_time = between(5, 15)

    @task(10)
    def browse_product(self):
        pid = random.choice(PRODUCT_IDS)
        self.client.get(f"/product/{pid}", name="/product/[id]")

    @task(1)
    def index(self):
        self.client.get("/")

    @task(2)
    def set_currency(self):
        self.client.post("/setCurrency",
                         data={"currency_code": random.choice(["EUR", "USD", "GBP"])})


class NormalUser(HttpUser):
    """50% do tráfego — utilizador normal: browse, cart, checkout ocasional"""
    weight = 5
    wait_time = between(2, 6)

    @task(10)
    def browse_product(self):
        pid = random.choice(PRODUCT_IDS)
        self.client.get(f"/product/{pid}", name="/product/[id]")

    @task(2)
    def add_to_cart(self):
        pid = random.choice(PRODUCT_IDS)
        self.client.post("/cart",
                         data={"product_id": pid, "quantity": "1"},
                         name="/cart [add]")

    @task(3)
    def view_cart(self):
        self.client.get("/cart")

    @task(1)
    def checkout(self):
        pid = random.choice(PRODUCT_IDS)
        # Garante item no carrinho antes do checkout
        with self.client.post("/cart",
                              data={"product_id": pid, "quantity": "1"},
                              name="/cart [add]",
                              catch_response=True) as r:
            if r.status_code != 200:
                r.failure(f"add falhou ({r.status_code}), skip checkout")
                return
        self.client.post("/cart/checkout", data=CHECKOUT_FORM,
                         name="/cart/checkout")

    @task(2)
    def set_currency(self):
        self.client.post("/setCurrency",
                         data={"currency_code": random.choice(["EUR", "USD", "GBP", "JPY"])})

    @task(1)
    def index(self):
        self.client.get("/")


class PowerUser(HttpUser):
    """20% do tráfego — utilizador frequente: produto → cart → checkout"""
    weight = 2
    wait_time = between(0.5, 2)

    @task(10)
    def browse_product(self):
        pid = random.choice(PRODUCT_IDS)
        self.client.get(f"/product/{pid}", name="/product/[id]")

    @task(3)
    def add_to_cart(self):
        pid = random.choice(PRODUCT_IDS)
        self.client.post("/cart",
                         data={"product_id": pid, "quantity": "1"},
                         name="/cart [add]")

    @task(3)
    def view_cart(self):
        self.client.get("/cart")

    @task(2)
    def checkout(self):
        pid = random.choice(PRODUCT_IDS)
        with self.client.post("/cart",
                              data={"product_id": pid, "quantity": "1"},
                              name="/cart [add]",
                              catch_response=True) as r:
            if r.status_code != 200:
                r.failure(f"add falhou ({r.status_code}), skip checkout")
                return
        self.client.post("/cart/checkout", data=CHECKOUT_FORM,
                         name="/cart/checkout")

    @task(2)
    def set_currency(self):
        self.client.post("/setCurrency",
                         data={"currency_code": random.choice(["EUR", "USD"])})
LOCUST_EOF
  log "locustfile.py criado (3 perfis: CasualUser/NormalUser/PowerUser)"
}

# =============================================================================
# EXECUÇÃO COMPARATIVA — carga fixa com warm-up
# warm-up: WARMUP_DURATION segundos (dados descartados)
# medição: MEASURE_DURATION segundos (dados recolhidos)
# =============================================================================
run_fixed_load() {
  local users=$1
  local out="$RESULTS_DIR/load_${users}users"
  mkdir -p "$out"

  log "========================================================"
  log "C2 — ${users} utilizadores (warm-up ${WARMUP_DURATION}s + medição ${MEASURE_DURATION}s)"
  log "========================================================"

  # Snapshot antes
  kubectl -n "$NAMESPACE" top pods --sort-by=cpu > "$out/pods_before.txt" 2>/dev/null
  kubectl -n "$NAMESPACE" get pods > "$out/pods_status_before.txt"
  kubectl -n "$NAMESPACE" get deployment productcatalogservice -o jsonpath='{.status.readyReplicas}' > "$out/pcs_replicas.txt"

  # Métricas redis ANTES da carga
  capture_redis_metrics "${users}users_before"

  # Fase warm-up (sem recolha de CSV — apenas estabiliza o sistema)
  log "  Warm-up: ${WARMUP_DURATION}s a ${users} users..."
  "$LOCUST_BIN" \
    --locustfile "$RESULTS_DIR/locustfile.py" \
    --host "$FRONTEND_URL" \
    --users "$users" \
    --spawn-rate "$SPAWN_RATE" \
    --run-time "${WARMUP_DURATION}s" \
    --headless \
    --loglevel WARNING \
    2>> "$out/locust_warmup.log"

  # Fase de medição (com CSV e HTML)
  log "  Medição: ${MEASURE_DURATION}s a ${users} users..."
  "$LOCUST_BIN" \
    --locustfile "$RESULTS_DIR/locustfile.py" \
    --host "$FRONTEND_URL" \
    --users "$users" \
    --spawn-rate "$SPAWN_RATE" \
    --run-time "${MEASURE_DURATION}s" \
    --headless \
    --csv "$out/locust" \
    --html "$out/report.html" \
    --loglevel WARNING \
    2>> "$out/locust.log"

  # Snapshot depois
  kubectl -n "$NAMESPACE" top pods --sort-by=cpu > "$out/pods_after.txt" 2>/dev/null
  kubectl -n "$NAMESPACE" get pods > "$out/pods_status_after.txt"
  kubectl -n "$NAMESPACE" get events --sort-by=.lastTimestamp 2>/dev/null | tail -20 > "$out/events.txt"

  # Métricas redis DURANTE/APÓS a carga
  capture_redis_metrics "${users}users_after"

  # Extrai e mostra resultados
  log ""
  log "=== RESULTADOS — ${users} users ==="
  if [ -f "$out/locust_stats.csv" ]; then
    python3 -c "
import csv
with open('$out/locust_stats.csv') as f:
    rows = list(csv.DictReader(f))
agg  = [r for r in rows if r['Name'] == 'Aggregated']
rest = [r for r in rows if r['Name'] != 'Aggregated']
for row in rest + agg:
    name     = row.get('Name','?')[:45]
    p50      = row.get('50%','?')
    p90      = row.get('90%','?')
    p99      = row.get('99%','?')
    fails    = row.get('Failure Count','0')
    total    = int(row.get('Request Count','0') or 0)
    fail_n   = int(fails or 0)
    fail_pct = (fail_n/total*100) if total > 0 else 0
    rps      = row.get('Requests/s','?')
    marker   = ' *** FALHAS' if fail_n > 0 else ''
    print(f'  {name:<47} p50={p50:>5}ms  p90={p90:>5}ms  p99={p99:>5}ms  falhas={fail_n:>5} ({fail_pct:5.1f}%)  rps={rps:>6}{marker}')
" 2>/dev/null | tee -a "$RESULTS_DIR/run.log"
  else
    log "  AVISO: CSV de resultados não encontrado"
  fi
  log ""
  log "  HTML: $out/report.html"
  log "  CSV:  $out/locust_stats.csv"
}

# =============================================================================
# RESUMO FINAL — tabela comparativa C2
# =============================================================================
generate_report() {
  local report="$RESULTS_DIR/RESUMO_C2.txt"
  log "A gerar resumo C2..."

  python3 - "$RESULTS_DIR" << 'PYEOF' > "$report"
import csv, os, sys

results_dir = sys.argv[1]

# Referência C1 (baseline, 25 users, último patamar estável)
c1_ref = {"users": 25, "p50": 21, "p90": 65, "p99": 420, "rps": 8.35, "fail_pct": 0.0}

lines = []
lines.append("=" * 90)
lines.append("ASID 2025/2026 — Cenário C2: Escalamento Seletivo (productcatalogservice × 3)")
lines.append(f"Gerado em: {__import__('datetime').datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
lines.append("=" * 90)
lines.append("")
lines.append("CONFIGURAÇÃO C2")
lines.append("-" * 40)
lines.append("  productcatalogservice: 3 réplicas")
lines.append("  Todos os outros serviços: 1 réplica")
lines.append("  Warm-up: 30s | Medição: 120s | Spawn rate: 2/s")
lines.append("  Critério de quebra: p99 > 2000ms OU falhas > 5%")
lines.append("")
lines.append("REFERÊNCIA C1 (1 réplica, 25 users — último patamar estável):")
lines.append(f"  p50={c1_ref['p50']}ms  p90={c1_ref['p90']}ms  p99={c1_ref['p99']}ms  "
             f"rps={c1_ref['rps']}  falhas={c1_ref['fail_pct']}%")
lines.append("")
lines.append("RESULTADOS C2 POR NÍVEL DE CARGA")
lines.append("-" * 90)
lines.append(f"{'Users':<8} {'p50 (ms)':<12} {'p90 (ms)':<12} {'p99 (ms)':<12} "
             f"{'Falhas':<10} {'Falhas%':<10} {'RPS':<10} {'Estado'}")
lines.append("-" * 90)

for users in [15, 20, 25]:
    csv_path = os.path.join(results_dir, f"load_{users}users", "locust_stats.csv")
    if not os.path.exists(csv_path):
        lines.append(f"{users:<8} {'(pendente)'}")
        continue
    with open(csv_path) as f:
        rows = list(csv.DictReader(f))
    for row in rows:
        if row.get("Name") != "Aggregated":
            continue
        total  = int(row.get("Request Count", 0) or 0)
        fails  = int(row.get("Failure Count", 0) or 0)
        p50    = row.get("50%", "?")
        p90    = row.get("90%", "?")
        p99    = row.get("99%", "?")
        rps    = row.get("Requests/s", "?")
        fp     = (fails/total*100) if total > 0 else 0
        p99v   = int(p99) if str(p99).isdigit() else 0
        if fails > 0 and fp >= 5:
            estado = f"QUEBRA (falhas {fp:.1f}%)"
        elif p99v >= 2000:
            estado = f"QUEBRA (p99={p99}ms)"
        elif p99v >= 500:
            estado = "Aviso"
        else:
            estado = "OK"
        lines.append(f"{users:<8} {p50:<12} {p90:<12} {p99:<12} "
                     f"{fails:<10} {fp:<10.1f} {rps:<10} {estado}")

lines.append("")
lines.append("ANÁLISE DE CUSTO MARGINAL (C2 vs C1)")
lines.append("-" * 60)
lines.append("  Réplicas adicionadas: +2 (productcatalogservice: 1→3)")
lines.append("  RPS C1 referência (25 users): 8.35")

# Tenta calcular RPS C2 a 25 users se disponível
csv_25 = os.path.join(results_dir, "load_25users", "locust_stats.csv")
if os.path.exists(csv_25):
    with open(csv_25) as f:
        for row in csv.DictReader(f):
            if row.get("Name") == "Aggregated":
                rps_c2 = float(row.get("Requests/s", 0) or 0)
                rps_ganho = rps_c2 - c1_ref["rps"]
                cm = rps_ganho / 2 if rps_ganho > 0 else 0
                lines.append(f"  RPS C2 (25 users): {rps_c2:.2f}")
                lines.append(f"  RPS ganho: {rps_ganho:+.2f}")
                lines.append(f"  CM_throughput = {rps_ganho:.2f} / 2 = {cm:.2f} RPS/réplica")
                break
else:
    lines.append("  RPS C2 (25 users): (pendente)")
    lines.append("  CM_throughput: (pendente)")

lines.append("")
lines.append("FICHEIROS DE SAÍDA")
lines.append("-" * 40)
for users in [15, 20, 25]:
    d = os.path.join(results_dir, f"load_{users}users")
    exists = "✓" if os.path.isdir(d) else "✗"
    lines.append(f"  [{exists}] load_{users}users/")
lines.append(f"  [✓] monitoring/pods_metrics.csv  — métricas CPU/RAM (10s)")
lines.append(f"  [✓] redis_metrics/               — sinais de contenção redis-cart")
lines.append(f"  [✓] baseline/                    — estado inicial do cluster")
lines.append("")
lines.append("=" * 90)

print("\n".join(lines))
PYEOF

  log "Resumo: $report"
  cat "$report"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  case "${1:-}" in
    scale_only)
      check_prerequisites
      scale_productcatalog
      log "productcatalogservice escalado para 3 réplicas. Pronto para testes."
      kubectl -n "$NAMESPACE" get pods -l app=productcatalogservice
      ;;
    reset)
      reset_productcatalog
      log "productcatalogservice reposto para 1 réplica."
      ;;
    report)
      # Gera relatório a partir de resultados já existentes
      RESULTS_DIR="${2:-$(ls -td cenarios_ob_* 2>/dev/null | head -1)}"
      [ -z "$RESULTS_DIR" ] && { echo "ERRO: nenhuma pasta de resultados encontrada"; exit 1; }
      log "A gerar relatório para: $RESULTS_DIR"
      generate_report
      ;;
    ""|run)
      # Execução completa do C2
      log "=============================================="
      log "CENÁRIO C2 — ESCALAMENTO SELETIVO"
      log "productcatalogservice: 3 réplicas"
      log "Cargas fixas: ${LOAD_LEVELS} users"
      log "Resultados em: $RESULTS_DIR"
      log "=============================================="

      check_prerequisites
      pause_loadgenerator
      scale_productcatalog
      capture_baseline
      create_locustfile
      start_monitoring

      # Executa cada nível de carga de forma independente
      for users in $LOAD_LEVELS; do
        run_fixed_load "$users"
        if [ "$users" != "25" ]; then
          log "Cooldown entre execuções: ${COOLDOWN_BETWEEN}s..."
          # Cooldown: deixa o sistema estabilizar entre execuções
          end=$((SECONDS + COOLDOWN_BETWEEN))
          while [ $SECONDS -lt $end ]; do
            rem=$((end - SECONDS))
            echo -ne "\r  Cooldown: ${rem}s restantes...    "
            sleep 2
          done
          echo ""
        fi
      done

      stop_monitoring
      generate_report
      resume_loadgenerator

      log ""
      log "=============================================="
      log "C2 CONCLUÍDO — resultados em: $RESULTS_DIR"
      log "=============================================="
      log ""
      log "PRÓXIMO PASSO: analisar resultados antes de avançar para C3"
      log "  Ver HTML: open $RESULTS_DIR/load_25users/report.html"
      log "  Ver CSV:  $RESULTS_DIR/load_25users/locust_stats.csv"
      log "  Redis:    $RESULTS_DIR/redis_metrics/"
      ;;
    *)
      cat << 'HELP'
Uso: ./c2.sh [MODO]

MODOS:
  (sem argumento)  — execução completa do C2
  scale_only       — só escala productcatalogservice para 3 réplicas
  reset            — repõe productcatalogservice para 1 réplica
  report [dir]     — gera resumo de resultados já existentes

VARIÁVEIS:
  NAMESPACE=default        namespace Kubernetes
  FRONTEND_URL=http://...  URL do frontend (default: http://localhost)

EXEMPLOS:
  ./c2.sh                  # C2 completo
  ./c2.sh scale_only       # só escala, sem testes
  ./c2.sh reset            # repõe baseline
  ./c2.sh report cenarios_ob_20260419_120000  # relatório de run anterior
HELP
      ;;
  esac
}

main "$@"
