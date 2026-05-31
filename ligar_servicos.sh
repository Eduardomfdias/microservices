#!/usr/bin/env bash
set -euo pipefail

# ─── cores ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $1"; }
info() { echo -e "${YELLOW}→${NC} $1"; }
err()  { echo -e "${RED}✗${NC} $1"; exit 1; }

# ─── 1. Docker Desktop ────────────────────────────────────────────────────────
info "A verificar Docker Desktop..."

if ! pgrep -x "Docker Desktop" > /dev/null 2>&1; then
  info "A abrir Docker Desktop..."
  open -a "Docker Desktop"
  echo -n "  A aguardar que o Docker arranque"
  until docker info > /dev/null 2>&1; do
    echo -n "."
    sleep 3
  done
  echo ""
  ok "Docker Desktop pronto"
else
  ok "Docker Desktop já está a correr"
fi

# ─── 2. Cluster Kubernetes ────────────────────────────────────────────────────
info "A verificar cluster Kubernetes (docker-desktop)..."

echo -n "  A aguardar kubectl ficar disponível"
until kubectl cluster-info > /dev/null 2>&1; do
  echo -n "."
  sleep 3
done
echo ""
ok "Cluster disponível: $(kubectl config current-context)"

# ─── 3. Aplicar manifests ─────────────────────────────────────────────────────
info "A aplicar manifests do Online Boutique..."
kubectl apply -k kubernetes-manifests/ > /dev/null
kubectl apply -f kubernetes-manifests/loadgenerator.yaml > /dev/null
ok "Manifests aplicados"

# ─── 3b. Forçar imagePullPolicy=Never (usar imagens locais) ──────────────────
info "A definir imagePullPolicy=Never para usar imagens locais..."
for svc in adservice checkoutservice currencyservice emailservice \
           frontend paymentservice productcatalogservice recommendationservice shippingservice; do
  kubectl patch deployment/$svc \
    -p "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"server\",\"imagePullPolicy\":\"Never\"}]}}}}" \
    > /dev/null 2>&1 || true
done
# cartservice tem dois containers; só o server usa imagem local
kubectl patch deployment/cartservice \
  -p "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"server\",\"imagePullPolicy\":\"Never\"}]}}}}" \
  > /dev/null 2>&1 || true
# loadgenerator usa container chamado "main"
kubectl patch deployment/loadgenerator \
  -p "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"main\",\"imagePullPolicy\":\"Never\"}]}}}}" \
  > /dev/null 2>&1 || true
ok "imagePullPolicy definido"

# ─── 4. Parar loadgenerator nativo ───────────────────────────────────────────
info "A parar loadgenerator nativo (para não misturar carga com Locust)..."
kubectl scale deployment/loadgenerator --replicas=0 > /dev/null 2>&1 || true
ok "Loadgenerator pausado"

# ─── 5. Repor C1 baseline (1 réplica por serviço) ────────────────────────────
info "A repor C1 baseline (1 réplica por serviço)..."
for svc in adservice cartservice checkoutservice currencyservice emailservice \
           frontend paymentservice productcatalogservice recommendationservice shippingservice; do
  kubectl scale deployment/$svc --replicas=1 > /dev/null 2>&1 || true
done
ok "Todos os serviços a 1 réplica (C1 baseline)"

# ─── 6. Aguardar pods ficarem Ready ──────────────────────────────────────────
info "A aguardar todos os pods ficarem Running..."
echo -n "  "
until [[ $(kubectl get pods --no-headers 2>/dev/null \
           | grep -v "Running\|Completed" | grep -v "^$" | wc -l) -eq 0 ]]; do
  echo -n "."
  sleep 4
done
echo ""
ok "Todos os pods estão Running"

# ─── 7. Verificar frontend ────────────────────────────────────────────────────
info "A verificar frontend (http://localhost)..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 http://localhost 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
  ok "Frontend responde (HTTP $HTTP_CODE)"
else
  echo -e "${YELLOW}⚠${NC}  Frontend devolveu HTTP $HTTP_CODE — pode ainda estar a iniciar"
  echo "   Tenta abrir http://localhost daqui a alguns segundos"
fi

# ─── 8. Resumo ────────────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────"
kubectl get pods --no-headers | awk '{printf "  %-45s %s\n", $1, $3}'
echo "────────────────────────────────────────"
echo ""
ok "Sistema pronto — Online Boutique em http://localhost"
