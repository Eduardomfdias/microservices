#!/bin/bash
# =============================================================================
# ASID 2025/2026 — C1 Comparativo
# Mesmo locustfile do C2 (3 perfis) + cargas fixas 15/20/25 + metrics-server
# Garante comparabilidade directa com C2 e C3 para o custo marginal
# =============================================================================
# COMO USAR:
#   chmod +x c1comp.sh
#   ./c1comp.sh
# =============================================================================

NAMESPACE="${NAMESPACE:-default}"
FRONTEND_URL="${FRONTEND_URL:-http://localhost}"
RESULTS_DIR="cenarios_ob_c1comp"
[ -d "$RESULTS_DIR" ] && mv "$RESULTS_DIR" "${RESULTS_DIR}_bak_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULTS_DIR"

WARMUP_DURATION=30
MEASURE_DURATION=120
SPAWN_RATE=2
COOLDOWN_BETWEEN=60
LOAD_LEVELS="15 20 25"

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$RESULTS_DIR/run.log"; }

# =============================================================================
check_prerequisites() {
  log "A verificar pré-requisitos..."
  kubectl cluster-info > /dev/null 2>&1 || { log "ERRO: kubectl não conectado"; exit 1; }

  kubectl top nodes > /dev/null 2>&1 || { log "ERRO: metrics-server não disponível. Instala com: kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"; exit 1; }

  LOCUST_BIN=$(which locust 2>/dev/null)
  [ -z "$LOCUST_BIN" ] && LOCUST_BIN=$(find ~/Library/Python -name "locust" -type f 2>/dev/null | head -1)
  [ -z "$LOCUST_BIN" ] && LOCUST_BIN=$(find ~/.local/bin -name "locust" -type f 2>/dev/null | head -1)
  [ -z "$LOCUST_BIN" ] && { log "ERRO: locust não encontrado"; exit 1; }
  export LOCUST_BIN
  log "Locust: $LOCUST_BIN"
  log "Pré-requisitos OK (inclui metrics-server)"
}

# =============================================================================
pause_loadgenerator() {
  kubectl -n "$NAMESPACE" scale deploy/loadgenerator --replicas=0 2>/dev/null && \
    log "loadgenerator pausado" || log "AVISO: loadgenerator não encontrado"
}

resume_loadgenerator() {
  kubectl -n "$NAMESPACE" scale deploy/loadgenerator --replicas=1 2>/dev/null && \
    log "loadgenerator retomado" || log "AVISO: não foi possível retomar loadgenerator"
}

# =============================================================================
# C1 COMPARATIVO — garante 1 réplica em tudo
# =============================================================================
set_baseline_replicas() {
  log "=== C1comp: a garantir 1 réplica em todos os serviços ==="
  for svc in adservice cartservice checkoutservice currencyservice emailservice \
             frontend paymentservice productcatalogservice recommendationservice shippingservice; do
    kubectl -n "$NAMESPACE" scale deployment/$svc --replicas=1 2>/dev/null
  done
  kubectl -n "$NAMESPACE" rollout status deployment/productcatalogservice --timeout=60s 2>/dev/null
  log "Todos os serviços com 1 réplica"
  kubectl -n "$NAMESPACE" get deployments -o wide | grep -v "^NAME" | awk '{print "  "$1": "$3"/"$4" réplicas"}'
}

# =============================================================================
capture_baseline() {
  log "=== BASELINE ==="
  local out="$RESULTS_DIR/baseline"
  mkdir -p "$out"
  kubectl -n "$NAMESPACE" get deployments -o wide > "$out/deployments.txt"
  kubectl -n "$NAMESPACE" get deployments -o json | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(f'Servico'.ljust(35) + 'Replicas'.ljust(10) + 'CPU_req'.ljust(12) + 'CPU_lim'.ljust(12) + 'Mem_req'.ljust(12) + 'Mem_lim')
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
  log "Baseline em $out/"
}

# =============================================================================
start_monitoring() {
  local out="$RESULTS_DIR/monitoring"
  mkdir -p "$out"
  echo "timestamp,snapshot,pod,cpu_m,ram_mi" > "$out/pods_metrics.csv"
  log "A iniciar monitorização (10s) → $out/"
  (
    i=0
    while true; do
      ts=$(date +%H:%M:%S)
      kubectl -n "$NAMESPACE" top pods --no-headers 2>/dev/null | \
        awk -v ts="$ts" -v i="$i" '{
          cpu=$2; ram=$3;
          gsub(/m/,"",cpu); gsub(/Mi/,"",ram);
          print ts","i","$1","cpu","ram
        }' >> "$out/pods_metrics.csv"
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
    weight = 3
    wait_time = between(5, 15)

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
    wait_time = between(2, 6)

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
    weight = 2
    wait_time = between(0.5, 2)

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
  log "locustfile.py criado (3 perfis — idêntico ao C2)"
}

# =============================================================================
capture_redis_metrics() {
  local label=$1
  local out="$RESULTS_DIR/redis_metrics"
  mkdir -p "$out"
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
  } > "$out/redis_${label}.txt"
}

# =============================================================================
run_fixed_load() {
  local users=$1
  local out="$RESULTS_DIR/load_${users}users"
  mkdir -p "$out"

  log "========================================================"
  log "C1comp — ${users} users (warm-up ${WARMUP_DURATION}s + medição ${MEASURE_DURATION}s)"
  log "========================================================"

  kubectl -n "$NAMESPACE" top pods --no-headers > "$out/pods_before.txt" 2>/dev/null
  capture_redis_metrics "${users}users_before"

  log "  Warm-up: ${WARMUP_DURATION}s..."
  "$LOCUST_BIN" \
    --locustfile "$RESULTS_DIR/locustfile.py" \
    --host "$FRONTEND_URL" \
    --users "$users" --spawn-rate "$SPAWN_RATE" \
    --run-time "${WARMUP_DURATION}s" \
    --headless --loglevel WARNING \
    2>> "$out/locust_warmup.log"

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
    2>> "$out/locust.log"

  kubectl -n "$NAMESPACE" top pods --no-headers > "$out/pods_after.txt" 2>/dev/null
  capture_redis_metrics "${users}users_after"

  log ""
  log "=== RESULTADOS — ${users} users ==="
  if [ -f "$out/locust_stats.csv" ]; then
    python3 -c "
import csv
with open('$out/locust_stats.csv') as f:
    rows = list(csv.DictReader(f))
for row in rows:
    if row.get('Name') != 'Aggregated': continue
    total = int(row.get('Request Count','0') or 0)
    fails = int(row.get('Failure Count','0') or 0)
    fp    = (fails/total*100) if total > 0 else 0
    print(f'  p50={row.get(\"50%\",\"?\"):>5}ms  p90={row.get(\"90%\",\"?\"):>5}ms  p99={row.get(\"99%\",\"?\"):>5}ms  falhas={fails} ({fp:.1f}%)  rps={row.get(\"Requests/s\",\"?\")}')
" 2>/dev/null | tee -a "$RESULTS_DIR/run.log"
  fi

  # CPU máximo por pod neste step
  log "  CPU/RAM após medição:"
  awk '{printf "    %-50s CPU=%-8s RAM=%s\n", $1, $2, $3}' "$out/pods_after.txt" 2>/dev/null | tee -a "$RESULTS_DIR/run.log"
  log ""
}

# =============================================================================
generate_report() {
  local report="$RESULTS_DIR/RESUMO_C1comp.txt"
  python3 - "$RESULTS_DIR" << 'PYEOF' > "$report"
import csv, os, sys
results_dir = sys.argv[1]

lines = []
lines.append("=" * 80)
lines.append("ASID 2025/2026 — C1 Comparativo (1 réplica, mesmo locustfile do C2)")
lines.append(f"Gerado em: {__import__('datetime').datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
lines.append("=" * 80)
lines.append("")
lines.append(f"{'Users':<8} {'p50':>8} {'p90':>8} {'p99':>8} {'Falhas':>8} {'Falhas%':>9} {'RPS':>10}  Estado")
lines.append("-" * 70)

for users in [15, 20, 25]:
    csv_path = os.path.join(results_dir, f"load_{users}users", "locust_stats.csv")
    if not os.path.exists(csv_path):
        lines.append(f"{users:<8} (pendente)")
        continue
    with open(csv_path) as f:
        for row in csv.DictReader(f):
            if row.get("Name") != "Aggregated": continue
            total = int(row.get("Request Count", 0) or 0)
            fails = int(row.get("Failure Count", 0) or 0)
            fp    = (fails/total*100) if total > 0 else 0
            p99v  = int(row.get("99%","0") or 0)
            estado = "QUEBRA" if (fp >= 5 or p99v >= 2000) else ("Aviso" if p99v >= 400 else "OK")
            lines.append(f"{users:<8} {row.get('50%','?'):>8} {row.get('90%','?'):>8} {row.get('99%','?'):>8} {fails:>8} {fp:>8.1f}% {row.get('Requests/s','?'):>10}  {estado}")

lines.append("")
lines.append("CPU/RAM (snapshots após cada nível de carga)")
lines.append("-" * 70)
for users in [15, 20, 25]:
    f = os.path.join(results_dir, f"load_{users}users", "pods_after.txt")
    if not os.path.exists(f): continue
    lines.append(f"  --- {users} users ---")
    with open(f) as fh:
        for line in fh:
            lines.append("  " + line.rstrip())

print("\n".join(lines))
PYEOF
  log "Resumo: $report"
  cat "$report"
}

# =============================================================================
main() {
  log "=============================================="
  log "C1 COMPARATIVO — 1 réplica, locustfile v2"
  log "Cargas fixas: ${LOAD_LEVELS} users"
  log "Resultados em: $RESULTS_DIR"
  log "=============================================="

  check_prerequisites
  pause_loadgenerator
  set_baseline_replicas
  capture_baseline
  create_locustfile
  start_monitoring

  for users in $LOAD_LEVELS; do
    run_fixed_load "$users"
    if [ "$users" != "25" ]; then
      log "Cooldown: ${COOLDOWN_BETWEEN}s..."
      end=$((SECONDS + COOLDOWN_BETWEEN))
      while [ $SECONDS -lt $end ]; do
        remaining=$((end - SECONDS))
        echo -ne "\r  ${remaining}s restantes...   "
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
  log "C1comp CONCLUÍDO — $RESULTS_DIR"
  log "Próximo passo: ./c2.sh (já com metrics-server activo)"
  log "=============================================="
}

main "$@"
