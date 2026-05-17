#!/bin/bash
# =============================================================================
# ASID 2025/2026 — C5 Exaustivo
# Envoy L7 gRPC Load Balancer + todos os stateless ×3
# Step-up 25→50→75→100→125→150 users até p99>2000ms ou falhas>5%
#
# Objetivo: validar empiricamente que o Envoy (per-request LB) resolve H6
# e permite ganhos de escalamento que C3 (kube-proxy L4) não conseguia.
#
# Comparação directa com C3: mesmas réplicas (+20), só muda o routing.
#
# COMO USAR:
#   chmod +x c5.sh
#   ./c5.sh
#   # ou em background:
#   nohup ./c5.sh > c5.log 2>&1 &
#   tail -f c5.log
#
# Para verificar distribuição Envoy durante o teste (terminal separado):
#   kubectl port-forward svc/envoy-grpc-lb 9901:9901
#   curl -s http://localhost:9901/stats | grep upstream_rq_total
#   watch -n 2 'kubectl top pods --no-headers | grep productcatalog'
# =============================================================================

NAMESPACE="${NAMESPACE:-default}"
FRONTEND_URL="${FRONTEND_URL:-http://localhost}"
RESULTS_DIR="cenarios_ob_c5_exaustivo"
[ -d "$RESULTS_DIR" ] && mv "$RESULTS_DIR" "${RESULTS_DIR}_bak_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULTS_DIR"

WARMUP_DURATION=30
MEASURE_DURATION=120
SPAWN_RATE=2
COOLDOWN_BETWEEN=60

LOAD_LEVELS="25 50 75 100 125 150"
BREAK_P99=2000
BREAK_FAIL_PCT=5
MONITOR_PID=""

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$RESULTS_DIR/run.log"; }

# =============================================================================
check_prerequisites() {
  log "A verificar pré-requisitos..."
  kubectl cluster-info > /dev/null 2>&1 || { log "ERRO: kubectl não conectado"; exit 1; }
  kubectl top nodes > /dev/null 2>&1 || { log "ERRO: metrics-server não disponível"; exit 1; }

  LOCUST_BIN=$(which locust 2>/dev/null)
  [ -z "$LOCUST_BIN" ] && LOCUST_BIN=$(find ~/Library/Python -name "locust" -type f 2>/dev/null | head -1)
  [ -z "$LOCUST_BIN" ] && LOCUST_BIN=$(find ~/.local/bin -name "locust" -type f 2>/dev/null | head -1)
  [ -z "$LOCUST_BIN" ] && { log "ERRO: locust não encontrado"; exit 1; }
  export LOCUST_BIN
  log "Locust: $LOCUST_BIN"
  log "Pré-requisitos OK"
}

# =============================================================================
pause_loadgenerator() {
  kubectl -n "$NAMESPACE" scale deploy/loadgenerator --replicas=0 2>/dev/null && \
    log "loadgenerator pausado" || log "AVISO: loadgenerator não encontrado"
}

resume_loadgenerator() {
  kubectl -n "$NAMESPACE" scale deploy/loadgenerator --replicas=1 2>/dev/null || true
}

# =============================================================================
deploy_envoy() {
  log "=== C5: A fazer deploy do Envoy gRPC LB + headless services ==="
  kubectl -n "$NAMESPACE" apply -f projeto_asid/manifests/envoy-grpc-lb.yaml
  log "A aguardar Envoy ficar Ready..."
  kubectl -n "$NAMESPACE" rollout status deployment/envoy-grpc-lb --timeout=90s
  log "Envoy pronto"
}

teardown_envoy() {
  log "=== A remover Envoy e restaurar routing original ==="
  kubectl -n "$NAMESPACE" delete -f projeto_asid/manifests/envoy-grpc-lb.yaml 2>/dev/null || true
  kubectl -n "$NAMESPACE" apply -f kubernetes-manifests/frontend.yaml
  kubectl -n "$NAMESPACE" apply -f kubernetes-manifests/checkoutservice.yaml
  kubectl -n "$NAMESPACE" apply -f kubernetes-manifests/recommendationservice.yaml
  log "Routing restaurado para K8s Services diretos"
}

# =============================================================================
capture_baseline() {
  local out="$RESULTS_DIR/baseline"
  mkdir -p "$out"
  kubectl -n "$NAMESPACE" get deployments -o wide > "$out/deployments.txt"
  kubectl -n "$NAMESPACE" get deployments -o json | python3 -c "
import json, sys
data = json.load(sys.stdin)
print('Servico'.ljust(35) + 'Replicas'.ljust(10) + 'CPU_req'.ljust(12) + 'CPU_lim'.ljust(12) + 'Mem_req'.ljust(12) + 'Mem_lim')
print('-'*95)
for d in data['items']:
    name = d['metadata']['name']
    replicas = d['spec'].get('replicas', 1)
    for c in d['spec']['template']['spec']['containers']:
        res = c.get('resources', {})
        req = res.get('requests', {})
        lim = res.get('limits', {})
        print(name.ljust(35) + str(replicas).ljust(10) + req.get('cpu','n/a').ljust(12) + lim.get('cpu','n/a').ljust(12) + req.get('memory','n/a').ljust(12) + lim.get('memory','n/a'))
" | tee "$out/resources_config.txt"
  kubectl -n "$NAMESPACE" top pods --sort-by=cpu > "$out/top_pods_idle.txt" 2>&1
  kubectl -n "$NAMESPACE" get pods -o wide > "$out/pods_status.txt"
  log "Baseline capturado em $out/"
}

# =============================================================================
start_monitoring() {
  local out="$RESULTS_DIR/monitoring"
  mkdir -p "$out"
  echo "timestamp,load_label,pod,cpu_m,ram_mi" > "$out/pods_metrics.csv"
  log "A iniciar monitorização contínua (10s) → $out/pods_metrics.csv"
  (
    current_label="idle"
    while true; do
      ts=$(date +%H:%M:%S)
      [ -f "$RESULTS_DIR/monitoring/.current_label" ] && current_label=$(cat "$RESULTS_DIR/monitoring/.current_label")
      kubectl -n "$NAMESPACE" top pods --no-headers 2>/dev/null | \
        awk -v ts="$ts" -v lbl="$current_label" '{
          cpu=$2; ram=$3;
          gsub(/m/,"",cpu); gsub(/Mi/,"",ram);
          print ts","lbl","$1","cpu","ram
        }' >> "$out/pods_metrics.csv"
      kubectl -n "$NAMESPACE" get pods --no-headers 2>/dev/null | \
        awk -v ts="$ts" '$4>0{print ts" RESTART pod="$1" restarts="$4}' \
        >> "$out/restarts.log"
      sleep 10
    done
  ) &
  MONITOR_PID=$!
  echo "$MONITOR_PID" > "$RESULTS_DIR/monitor.pid"
  log "Monitor PID: $MONITOR_PID"
}

stop_monitoring() {
  if [ -f "$RESULTS_DIR/monitor.pid" ]; then
    kill "$(cat "$RESULTS_DIR/monitor.pid")" 2>/dev/null
    rm -f "$RESULTS_DIR/monitor.pid" "$RESULTS_DIR/monitoring/.current_label"
    log "Monitorização parada"
  fi
}

mark_load_start() {
  echo "${1}" > "$RESULTS_DIR/monitoring/.current_label"
}

# =============================================================================
set_replicas_c5() {
  log "=== C5: Todos stateless ×3, redis-cart ×1 (igual ao C3 + Envoy) ==="

  # Aplicar routing via Envoy nos callers
  kubectl -n "$NAMESPACE" apply -f projeto_asid/manifests/c5-frontend-with-envoy.yaml

  # Escalar todos os stateless para 3
  for svc in adservice cartservice checkoutservice currencyservice emailservice \
             frontend paymentservice productcatalogservice recommendationservice shippingservice; do
    kubectl -n "$NAMESPACE" scale deployment/$svc --replicas=3 2>/dev/null
  done
  # redis-cart mantém 1 réplica (stateful)
  kubectl -n "$NAMESPACE" scale deployment/redis-cart --replicas=1 2>/dev/null || true

  log "A aguardar rollouts..."
  for svc in frontend checkoutservice recommendationservice currencyservice \
             productcatalogservice cartservice; do
    kubectl -n "$NAMESPACE" rollout status deployment/$svc --timeout=120s 2>/dev/null
  done

  log "Réplicas C5 aplicadas"
  kubectl -n "$NAMESPACE" get deployments --no-headers | awk '{print "  "$1": "$3"/"$4}'

  # Verificar conectividade básica antes de começar os testes
  log "A verificar smoke test (frontend)..."
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$FRONTEND_URL/" 2>/dev/null)
  if [ "$http_code" = "200" ]; then
    log "Smoke test OK (HTTP $http_code)"
  else
    log "AVISO: smoke test retornou HTTP $http_code — verificar manualmente antes de continuar"
  fi

  # Capturar estado do Envoy admin
  log "A capturar estado inicial do Envoy..."
  kubectl -n "$NAMESPACE" exec deployment/envoy-grpc-lb -- \
    wget -qO- http://localhost:9901/server_info 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print('Envoy state:', d.get('state','?'), '| version:', d.get('version','?'))" \
    2>/dev/null || log "AVISO: não foi possível contactar admin Envoy"
}

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
    weight = 2
    wait_time = between(0.5, 1)

    @task(10)
    def browse_product(self):
        self.client.get(f"/product/{random.choice(PRODUCT_IDS)}", name="/product/[id]")

    @task(1)
    def index(self):
        self.client.get("/")

    @task(2)
    def set_currency(self):
        self.client.post("/setCurrency",
                         data={"currency_code": random.choice(["EUR", "USD", "GBP"])})


class NormalUser(HttpUser):
    weight = 5
    wait_time = between(0.2, 0.5)

    @task(10)
    def browse_product(self):
        self.client.get(f"/product/{random.choice(PRODUCT_IDS)}", name="/product/[id]")

    @task(2)
    def add_to_cart(self):
        self.client.post("/cart",
                         data={"product_id": random.choice(PRODUCT_IDS), "quantity": "1"},
                         name="/cart [add]")

    @task(3)
    def view_cart(self):
        self.client.get("/cart")

    @task(1)
    def checkout(self):
        pid = random.choice(PRODUCT_IDS)
        with self.client.post("/cart",
                              data={"product_id": pid, "quantity": "1"},
                              name="/cart [add]",
                              catch_response=True) as r:
            if r.status_code != 200:
                r.failure(f"add falhou ({r.status_code}), skip checkout")
                return
        self.client.post("/cart/checkout", data=CHECKOUT_FORM, name="/cart/checkout")

    @task(2)
    def set_currency(self):
        self.client.post("/setCurrency",
                         data={"currency_code": random.choice(["EUR", "USD", "GBP", "JPY"])})

    @task(1)
    def index(self):
        self.client.get("/")


class PowerUser(HttpUser):
    weight = 3
    wait_time = between(0.1, 0.2)

    @task(10)
    def browse_product(self):
        self.client.get(f"/product/{random.choice(PRODUCT_IDS)}", name="/product/[id]")

    @task(3)
    def add_to_cart(self):
        self.client.post("/cart",
                         data={"product_id": random.choice(PRODUCT_IDS), "quantity": "1"},
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
        self.client.post("/cart/checkout", data=CHECKOUT_FORM, name="/cart/checkout")

    @task(2)
    def set_currency(self):
        self.client.post("/setCurrency",
                         data={"currency_code": random.choice(["EUR", "USD"])})
LOCUST_EOF
  log "locustfile.py criado (3 perfis — idêntico ao C1/C2/C3 exaustivo)"
}

# =============================================================================
capture_redis_metrics() {
  local label=$1 out=$2
  local redis_pod
  redis_pod=$(kubectl -n "$NAMESPACE" get pods --no-headers -l app=redis-cart 2>/dev/null | awk 'NR==1{print $1}')
  [ -z "$redis_pod" ] && return
  {
    echo "=== Redis INFO stats (${label}) === $(date)"
    kubectl -n "$NAMESPACE" exec "$redis_pod" -- redis-cli INFO stats 2>/dev/null
    echo "=== Redis INFO clients ==="
    kubectl -n "$NAMESPACE" exec "$redis_pod" -- redis-cli INFO clients 2>/dev/null
    echo "=== Redis SLOWLOG ==="
    kubectl -n "$NAMESPACE" exec "$redis_pod" -- redis-cli SLOWLOG GET 10 2>/dev/null
  } > "$out/redis_${label}.txt" 2>/dev/null
}

# Captura métricas do Envoy admin para evidência de per-request LB
capture_envoy_metrics() {
  local label=$1 out=$2
  {
    echo "=== Envoy stats (${label}) === $(date)"
    kubectl -n "$NAMESPACE" exec deployment/envoy-grpc-lb -- \
      wget -qO- http://localhost:9901/stats 2>/dev/null | \
      grep -E "upstream_rq_total|upstream_cx_active|upstream_rq_active|lb_recalculate"
    echo ""
    echo "=== Envoy clusters (${label}) ==="
    kubectl -n "$NAMESPACE" exec deployment/envoy-grpc-lb -- \
      wget -qO- http://localhost:9901/clusters 2>/dev/null | \
      grep -E "productcatalogservice|currencyservice|health_flags|cx_active|rq_total" | head -60
  } > "$out/envoy_metrics_${label}.txt" 2>/dev/null
}

# =============================================================================
run_load_level() {
  local users=$1
  local out="$RESULTS_DIR/load_${users}users"
  mkdir -p "$out"

  log "========================================================"
  log "C5 Exaustivo — ${users} users (warm-up ${WARMUP_DURATION}s + medição ${MEASURE_DURATION}s)"
  log "========================================================"

  kubectl -n "$NAMESPACE" top pods --no-headers > "$out/pods_before.txt" 2>/dev/null
  capture_redis_metrics "${users}u_before" "$out"
  capture_envoy_metrics "${users}u_before" "$out"
  mark_load_start "${users}u"

  log "  Warm-up: ${WARMUP_DURATION}s..."
  "$LOCUST_BIN" \
    --locustfile "$RESULTS_DIR/locustfile.py" \
    --host "$FRONTEND_URL" \
    --users "$users" --spawn-rate "$SPAWN_RATE" \
    --run-time "${WARMUP_DURATION}s" \
    --headless --loglevel WARNING \
    < /dev/null >> "$out/locust_warmup.log" 2>&1

  log "  Medição: ${MEASURE_DURATION}s..."
  "$LOCUST_BIN" \
    --locustfile "$RESULTS_DIR/locustfile.py" \
    --host "$FRONTEND_URL" \
    --users "$users" --spawn-rate "$SPAWN_RATE" \
    --run-time "${MEASURE_DURATION}s" \
    --headless \
    --csv "$out/locust" \
    --html "$out/report.html" \
    --loglevel WARNING \
    < /dev/null >> "$out/locust.log" 2>&1

  kubectl -n "$NAMESPACE" top pods --no-headers > "$out/pods_after.txt" 2>/dev/null
  capture_redis_metrics "${users}u_after" "$out"
  capture_envoy_metrics "${users}u_after" "$out"

  # Verificar distribuição de CPU entre réplicas (evidência de H6 resolvido)
  log "  Distribuição CPU por réplica (productcatalogservice):"
  grep productcatalog "$out/pods_after.txt" | awk '{printf "    %s CPU=%s RAM=%s\n",$1,$2,$3}' | tee -a "$RESULTS_DIR/run.log"

  local result
  result=$(python3 - "$out/locust_stats.csv" "$BREAK_P99" "$BREAK_FAIL_PCT" << 'PYEOF'
import csv, sys
fpath, bp99, bfail = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
try:
    with open(fpath) as f:
        for row in csv.DictReader(f):
            if row.get("Name") != "Aggregated": continue
            total = int(row.get("Request Count","0") or 0)
            fails = int(row.get("Failure Count","0") or 0)
            fp    = (fails/total*100) if total > 0 else 0
            p99v  = int(row.get("99%","0") or 0)
            broke = int((fp >= bfail) or (p99v >= bp99))
            estado = "QUEBRA" if broke else ("Aviso" if p99v >= 400 else "OK")
            print(f"{row.get('50%','?')}|{row.get('90%','?')}|{p99v}|{fails}|{fp:.1f}|{row.get('Requests/s','?')}|{estado}|{broke}")
except Exception:
    print("?|?|0|0|0.0|?|ERRO|0")
PYEOF
  )

  local p50 p90 p99 fails failpct rps estado broke_flag
  IFS='|' read -r p50 p90 p99 fails failpct rps estado broke_flag <<< "$result"

  log "  RESULTADO: p50=${p50}ms  p90=${p90}ms  p99=${p99}ms  falhas=${fails}(${failpct}%)  rps=${rps}  [${estado}]"
  log "  CPU/RAM após medição:"
  awk '{printf "    %-50s CPU=%-8s RAM=%s\n", $1, $2, $3}' "$out/pods_after.txt" 2>/dev/null | tee -a "$RESULTS_DIR/run.log"

  echo "${users},${p50},${p90},${p99},${fails},${failpct},${rps},${estado}" >> "$RESULTS_DIR/resultados.csv"

  [ "$broke_flag" = "1" ] && return 1 || return 0
}

# =============================================================================
generate_report() {
  local report="$RESULTS_DIR/RESUMO_C5_exaustivo.txt"
  python3 - "$RESULTS_DIR" "$BREAK_P99" "$BREAK_FAIL_PCT" << 'PYEOF' | tee "$report"
import csv, os, sys
d, bp99, bfail = sys.argv[1], sys.argv[2], sys.argv[3]
print("=" * 70)
print("ASID 2025/2026 — C5 Exaustivo (Envoy L7 + todos stateless ×3)")
print(f"Critério de quebra: p99 > {bp99}ms  OU  falhas > {bfail}%")
print("=" * 70)
csv_path = os.path.join(d, "resultados.csv")
if not os.path.exists(csv_path):
    print("(sem dados)")
else:
    with open(csv_path) as f:
        rows = list(csv.DictReader(f))
    print(f"{'Users':>6}  {'p50':>6}  {'p90':>6}  {'p99':>7}  {'Falhas':>7}  {'Falhas%':>8}  {'RPS':>8}  Estado")
    print("-" * 70)
    break_users = None
    for row in rows:
        marker = " ◄ QUEBRA" if row.get("estado") == "QUEBRA" else ("  ◄ aviso" if row.get("estado") == "Aviso" else "")
        print(f"  {row.get('users','?'):>4}  {row.get('p50','?'):>6}  {row.get('p90','?'):>6}  {row.get('p99','?'):>7}  {row.get('fails','?'):>7}  {row.get('failpct','?'):>7}%  {row.get('rps','?'):>8}  {row.get('estado','?')}{marker}")
        if row.get("estado") == "QUEBRA" and break_users is None:
            break_users = row.get("users")
    print()
    if break_users:
        print(f"→ Ponto de quebra: {break_users} users")
    else:
        print("→ Sistema estável até ao máximo testado")
    print()
    print("Comparação esperada com C3 (kube-proxy L4, sem Envoy):")
    print("  C3: saturação ~150u, RPS máx ~130")
    print("  C5: se H6 resolvido → saturação >= 150u e distribuição uniforme")
PYEOF
  log "Resumo: $report"
}

# =============================================================================
main() {
  log "=============================================="
  log "C5 EXAUSTIVO — Envoy L7 gRPC LB + todos stateless ×3"
  log "Níveis: ${LOAD_LEVELS}"
  log "Resultados em: $RESULTS_DIR"
  log "=============================================="

  check_prerequisites
  pause_loadgenerator
  deploy_envoy
  set_replicas_c5
  capture_baseline
  create_locustfile
  start_monitoring

  echo "users,p50,p90,p99,fails,failpct,rps,estado" > "$RESULTS_DIR/resultados.csv"

  for users in $LOAD_LEVELS; do
    run_load_level "$users"
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
      log "*** QUEBRA DETECTADA a ${users} users — a terminar ***"
      break
    fi

    local next_users=""
    local found=0
    for l in $LOAD_LEVELS; do
      [ $found -eq 1 ] && { next_users=$l; break; }
      [ "$l" = "$users" ] && found=1
    done

    if [ -n "$next_users" ]; then
      log "Cooldown: ${COOLDOWN_BETWEEN}s antes de ${next_users} users..."
      sleep "$COOLDOWN_BETWEEN"
    fi
  done

  stop_monitoring
  generate_report

  # Teardown: restaurar routing original antes de sair
  teardown_envoy
  resume_loadgenerator

  log ""
  log "=============================================="
  log "C5 Exaustivo CONCLUÍDO — $RESULTS_DIR"
  log "Routing original restaurado."
  log "=============================================="
}

main "$@"
