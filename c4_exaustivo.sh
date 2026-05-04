#!/bin/bash
# =============================================================================
# ASID 2025/2026 — C4 Exaustivo
# frontend ×3 + currencyservice ×3 (bottlenecks reais identificados nos exaustivos)
# restantes serviços: 1 réplica
# Step-up 25→50→75→100→125→150 users até p99>2000ms ou falhas>5%
# =============================================================================
# COMO USAR:
#   chmod +x c4_exaustivo.sh
#   ./c4_exaustivo.sh
#   # ou em background:
#   nohup ./c4_exaustivo.sh > c4_exaustivo.log 2>&1 &
#   tail -f c4_exaustivo.log
# =============================================================================

NAMESPACE="${NAMESPACE:-default}"
FRONTEND_URL="${FRONTEND_URL:-http://localhost}"
RESULTS_DIR="cenarios_ob_c4_exaustivo"
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
set_replicas() {
  log "=== C4: frontend ×3, currencyservice ×3, restantes ×1 ==="
  for svc in adservice cartservice checkoutservice emailservice \
             paymentservice productcatalogservice recommendationservice shippingservice; do
    kubectl -n "$NAMESPACE" scale deployment/$svc --replicas=1 2>/dev/null
  done
  kubectl -n "$NAMESPACE" scale deployment/frontend --replicas=3
  kubectl -n "$NAMESPACE" scale deployment/currencyservice --replicas=3
  kubectl -n "$NAMESPACE" rollout status deployment/frontend --timeout=90s 2>/dev/null
  kubectl -n "$NAMESPACE" rollout status deployment/currencyservice --timeout=90s 2>/dev/null
  log "Réplicas C4 aplicadas"
  kubectl -n "$NAMESPACE" get deployments --no-headers | awk '{print "  "$1": "$3"/"$4}'
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

# =============================================================================
run_load_level() {
  local users=$1
  local out="$RESULTS_DIR/load_${users}users"
  mkdir -p "$out"

  log "========================================================"
  log "C4 Exaustivo — ${users} users (warm-up ${WARMUP_DURATION}s + medição ${MEASURE_DURATION}s)"
  log "========================================================"

  kubectl -n "$NAMESPACE" top pods --no-headers > "$out/pods_before.txt" 2>/dev/null
  capture_redis_metrics "${users}u_before" "$out"
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

  local result broke=0
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
  local report="$RESULTS_DIR/RESUMO_C4_exaustivo.txt"
  python3 - "$RESULTS_DIR" "$BREAK_P99" "$BREAK_FAIL_PCT" << 'PYEOF' | tee "$report"
import csv, os, sys
d, bp99, bfail = sys.argv[1], sys.argv[2], sys.argv[3]
print("=" * 70)
print("ASID 2025/2026 — C4 Exaustivo (frontend ×3 + currencyservice ×3)")
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
PYEOF
  log "Resumo: $report"
}

# =============================================================================
main() {
  log "=============================================="
  log "C4 EXAUSTIVO — frontend ×3, currencyservice ×3"
  log "Níveis: ${LOAD_LEVELS}"
  log "Resultados em: $RESULTS_DIR"
  log "=============================================="

  check_prerequisites
  pause_loadgenerator
  set_replicas
  capture_baseline
  create_locustfile
  start_monitoring

  echo "users,p50,p90,p99,fails,failpct,rps,estado" > "$RESULTS_DIR/resultados.csv"

  local prev_users=""
  for users in $LOAD_LEVELS; do
    run_load_level "$users"
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
      log "*** QUEBRA DETECTADA a ${users} users — a terminar ***"
      break
    fi

    prev_users="$users"
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
  resume_loadgenerator

  log ""
  log "=============================================="
  log "C4 Exaustivo CONCLUÍDO — $RESULTS_DIR"
  log "=============================================="
}

main "$@"
