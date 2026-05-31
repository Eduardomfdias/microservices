# Comandos do Projeto ASID 2025/2026

## Tema 2 — Escalabilidade Horizontal e Custo Marginal em Microserviços

---

## 1. Cluster e Estado Geral

```bash
kubectl cluster-info                          # verifica se o kubectl está ligado ao cluster
kubectl get nodes                             # lista os nós do cluster (aqui: só docker-desktop)
kubectl get namespaces                        # lista os namespaces existentes

kubectl get pods -o wide                      # lista todos os pods com IP e nó onde correm
kubectl get pods --watch                      # fica a observar mudanças de estado em tempo real

kubectl get deployments                       # lista os deployments e número de réplicas
kubectl get deployments -o wide               # idem com mais detalhe (imagem, selector)

kubectl top nodes                             # consumo de CPU/RAM do nó
kubectl top pods                              # consumo de CPU/RAM de cada pod
kubectl top pods --sort-by=cpu               # ordena por CPU (descrescente)
kubectl top pods --sort-by=memory            # ordena por memória (descrescente)

kubectl get events --sort-by=.lastTimestamp   # lista eventos do cluster por ordem cronológica
kubectl get events --sort-by=.lastTimestamp | tail -20   # mostra só os 20 mais recentes
```

---

## 2. Aplicar / Restaurar Manifests

```bash
kubectl apply -f kubernetes-manifests/        # aplica todos os YAMLs base do Online Boutique

# Serviços individualmente (para atualizar só um sem tocar nos outros)
kubectl apply -f kubernetes-manifests/frontend.yaml
kubectl apply -f kubernetes-manifests/checkoutservice.yaml
kubectl apply -f kubernetes-manifests/currencyservice.yaml
kubectl apply -f kubernetes-manifests/productcatalogservice.yaml
kubectl apply -f kubernetes-manifests/cartservice.yaml
kubectl apply -f kubernetes-manifests/recommendationservice.yaml
kubectl apply -f kubernetes-manifests/redis-cart.yaml

# C5 — aplicar Envoy e redirecionar callers para usar o proxy
kubectl apply -f projeto_asid/manifests/envoy-grpc-lb.yaml           # cria o proxy Envoy com LEAST_REQUEST
kubectl apply -f projeto_asid/manifests/c5-frontend-with-envoy.yaml  # reconfigura frontend/checkout/recommendation para apontarem ao Envoy

# Teardown C5 — remover Envoy
kubectl delete -f projeto_asid/manifests/envoy-grpc-lb.yaml  # apaga o Envoy e os headless services
```

---

## 3. Escalar Serviços (por cenário)

```bash
# --- C1 — Baseline (1 réplica por serviço) ---
for svc in adservice cartservice checkoutservice currencyservice emailservice \
           frontend paymentservice productcatalogservice recommendationservice shippingservice; do
  kubectl scale deployment/$svc --replicas=1   # repõe todos os stateless a 1 réplica
done

# --- C2 — Seletivo (productcatalogservice ×3, restantes ×1) ---
kubectl scale deployment/productcatalogservice --replicas=3  # escala só o candidato a bottleneck

# --- C3 — Uniforme (todos os stateless ×3) ---
for svc in adservice cartservice checkoutservice currencyservice emailservice \
           frontend paymentservice productcatalogservice recommendationservice shippingservice; do
  kubectl scale deployment/$svc --replicas=3   # escala todos os stateless para 3 réplicas
done
kubectl scale deployment/redis-cart --replicas=1  # redis-cart mantém sempre 1 (stateful, single-thread)

# --- C4 — Seletivo real (frontend + currencyservice ×3) ---
kubectl scale deployment/frontend --replicas=3       # escala frontend (bottleneck real identificado)
kubectl scale deployment/currencyservice --replicas=3 # escala currencyservice (bottleneck real)

# --- C5 — Uniforme ×3 + Envoy (igual ao C3 mas com proxy L7) ---
for svc in adservice cartservice checkoutservice currencyservice emailservice \
           frontend paymentservice productcatalogservice recommendationservice shippingservice; do
  kubectl scale deployment/$svc --replicas=3   # mesmas réplicas que C3
done
kubectl scale deployment/redis-cart --replicas=1  # redis-cart sempre 1

# Verificar que o rollout terminou antes de iniciar testes
kubectl rollout status deployment/frontend             # aguarda frontend estar pronto
kubectl rollout status deployment/productcatalogservice # aguarda productcatalog estar pronto
kubectl rollout status deployment/currencyservice      # aguarda currencyservice estar pronto
```

---

## 4. Loadgenerator (pausa/resume)

```bash
kubectl scale deployment/loadgenerator --replicas=0  # pausa o loadgenerator nativo (obrigatório antes dos testes com Locust para não misturar carga)
kubectl scale deployment/loadgenerator --replicas=1  # retoma o loadgenerator nativo após os testes
```

---

## 5. Locust — Gerador de Carga

```bash
which locust        # verifica onde está instalado o Locust
locust --version    # confirma a versão instalada

pip3 install locust  # instala o Locust via pip se não existir

# Interface web — inicia o Locust com UI no browser (útil para demo ao vivo)
locust --locustfile projeto_asid/scripts/locustfile.py \
       --host http://localhost
# Depois abrir http://localhost:8089 no browser e configurar número de users

# Headless — teste rápido de validação (10 users durante 60 segundos)
locust --locustfile projeto_asid/scripts/locustfile.py \
       --host http://localhost \
       --users 10 \          # número de utilizadores simultâneos
       --spawn-rate 5 \      # quantos users por segundo são criados no arranque
       --run-time 60s \      # duração total do teste
       --headless \          # sem interface gráfica
       --csv resultados_demo  # exporta resultados para CSVs com este prefixo

# Headless — simular cenário exaustivo (25 users: 30s warm-up + 120s medição)
locust --locustfile projeto_asid/scripts/locustfile.py \
       --host http://localhost \
       --users 25 \           # 25 utilizadores simultâneos
       --spawn-rate 2 \       # 2 users por segundo (spawn gradual)
       --run-time 120s \      # 120 segundos de medição efectiva
       --headless \
       --csv resultados_25u \ # exporta locust_stats.csv, locust_stats_history.csv, etc.
       --html report_25u.html  # gera relatório HTML com gráficos
```

---

## 6. Scripts de Teste do Projeto

```bash
chmod +x projeto_asid/scripts/*.sh   # dar permissão de execução a todos os scripts (só é preciso fazer uma vez)

# C1 — Comparativo (15/20/25 users com locustfile realista)
./projeto_asid/scripts/c1comp.sh

# C1 — Exaustivo (25→150 users com locustfile severo, passo a passo até quebrar)
./projeto_asid/scripts/c1_exaustivo.sh

# Executar em background e acompanhar pelo log (recomendado para testes longos)
nohup ./projeto_asid/scripts/c1_exaustivo.sh > c1_exaustivo.log 2>&1 &  # lança em background
tail -f c1_exaustivo.log   # segue o log em tempo real

# C2 — Exaustivo (productcatalogservice ×3, testa o problema H6)
nohup ./projeto_asid/scripts/c2_exaustivo.sh > c2_exaustivo.log 2>&1 &
tail -f c2_exaustivo.log

# C3 — Exaustivo (todos stateless ×3, escalonamento uniforme sem Envoy)
nohup ./projeto_asid/scripts/c3_exaustivo.sh > c3_exaustivo.log 2>&1 &
tail -f c3_exaustivo.log

# C4 — Exaustivo (frontend + currencyservice ×3, escalamento dos bottlenecks reais)
nohup ./projeto_asid/scripts/c4_exaustivo.sh > c4_exaustivo.log 2>&1 &
tail -f c4_exaustivo.log

# C5 — Exaustivo (todos stateless ×3 + Envoy L7, resolve o problema H6)
nohup ./projeto_asid/scripts/c5.sh > c5.log 2>&1 &
tail -f c5.log
```

---

## 7. Monitorização Durante Testes

```bash
watch -n 2 kubectl top pods   # atualiza consumo CPU/RAM de todos os pods a cada 2 segundos

# Ver só réplicas de um serviço específico (útil para verificar distribuição de carga)
watch -n 2 'kubectl top pods --no-headers | grep productcatalog'  # réplicas do productcatalogservice
watch -n 2 'kubectl top pods --no-headers | grep -E "frontend|currency"'  # frontend e currencyservice

# Logs de um deployment (mostra todas as réplicas)
kubectl logs deployment/frontend --tail=50 --follow        # segue os últimos 50 logs do frontend
kubectl logs deployment/currencyservice --tail=50 --follow # segue logs do currencyservice

# Logs de um pod específico (quando se quer ver uma réplica em particular)
kubectl logs <nome-do-pod> --follow   # substituir <nome-do-pod> pelo nome real (ex: frontend-abc123)

# Detetar pods com problemas (estado diferente de Running)
kubectl get pods | grep -v Running  # mostra pods que não estão Running (ex: CrashLoopBackOff, Pending)
```

---

## 8. Envoy — Verificar Balanceamento (C5)

```bash
# Abrir acesso ao admin HTTP do Envoy na porta local 9901
kubectl port-forward svc/envoy-grpc-lb 9901:9901  # reencaminha porta 9901 do Envoy para localhost:9901

# Nos comandos abaixo, abrir um segundo terminal com o port-forward activo

curl -s http://localhost:9901/stats | grep upstream_rq_total  # total de pedidos enviados para cada upstream (evidência de distribuição)

# Ver distribuição por cluster (quantos pedidos e ligações activas por serviço)
curl -s http://localhost:9901/clusters | \
  grep -E "productcatalogservice|currencyservice|cx_active|rq_total"  # filtra só os clusters relevantes

curl -s http://localhost:9901/server_info  # estado geral do Envoy (versão, uptime, estado)

# Confirmar H6 resolvida: distribuição uniforme entre réplicas
watch -n 2 'kubectl top pods --no-headers | grep productcatalog'
# C3 sem Envoy (kube-proxy L4): ~91% / 6% / 3% — muito desequilibrado
# C5 com Envoy (LEAST_REQUEST): ~121m / 121m / 122m — uniforme
```

---

## 9. Redis — Verificar Estado

```bash
kubectl get pods -l app=redis-cart   # obtém o nome do pod do redis-cart

kubectl exec deployment/redis-cart -- redis-cli INFO stats    # estatísticas de operações (comandos por segundo, hits/misses)
kubectl exec deployment/redis-cart -- redis-cli INFO clients  # número de ligações activas ao redis
kubectl exec deployment/redis-cart -- redis-cli INFO memory   # consumo de memória do redis

kubectl exec deployment/redis-cart -- redis-cli SLOWLOG GET 10  # últimas 10 operações lentas (detetar contenção)

kubectl exec deployment/redis-cart -- redis-cli CLIENT LIST | wc -l  # conta quantas ligações TCP estão abertas ao redis
```

---

## 10. Jaeger — Tracing Distribuído

```bash
kubectl apply -f kubernetes-manifests/jaeger.yaml   # aplica o Jaeger all-in-one (se ainda não estiver a correr)

kubectl port-forward svc/jaeger-query 16686:16686   # abre acesso à UI do Jaeger na porta local 16686

open http://localhost:16686  # abre a UI do Jaeger no browser (macOS)
# Na UI: selecionar serviço "frontend" e clicar "Find Traces" para ver os traces das workflows W1/W2/W3
```

---

## 11. Acesso ao Frontend

```bash
kubectl get svc frontend-external   # mostra a porta NodePort exposta pelo frontend (coluna PORT(S))

kubectl port-forward svc/frontend-external 8080:80  # alternativa: reencaminha para localhost:8080 se o NodePort não funcionar

curl -s -o /dev/null -w "%{http_code}" http://localhost  # testa se o frontend responde (deve devolver 200)

open http://localhost   # abre o Online Boutique no browser (macOS)
```

---

## 12. Guião para a Demonstração

### Passo 1 — Mostrar o sistema a correr (C1 baseline)

```bash
kubectl get pods                  # mostrar todos os pods em Running (11 serviços + 1 redis)
kubectl get deployments           # mostrar 1 réplica por serviço (configuração C1)
open http://localhost             # abrir o Online Boutique no browser e navegar
```

### Passo 2 — Aplicar carga e observar baseline

```bash
# Terminal 1: monitorização de CPU/RAM em tempo real
watch -n 2 kubectl top pods

# Terminal 2: iniciar Locust com interface web
locust --locustfile projeto_asid/scripts/locustfile.py \
       --host http://localhost   # depois abrir http://localhost:8089 e iniciar com 25 users
```

### Passo 3 — Demonstrar o problema H6 (C2: escalar sem Envoy não resolve)

```bash
kubectl scale deployment/productcatalogservice --replicas=3  # escalar o serviço mais chamado (×6 por browse)
kubectl rollout status deployment/productcatalogservice      # aguardar as 3 réplicas ficarem prontas

# Mostrar que 2 das 3 réplicas ficam quase sem tráfego (H6: gRPC reutiliza ligações TCP)
watch -n 2 'kubectl top pods --no-headers | grep productcatalog'
# Resultado esperado: pod1 com CPU alto, pod2 e pod3 com ~0m
```

### Passo 4 — Demonstrar C5 com Envoy (solução para H6)

```bash
kubectl apply -f projeto_asid/manifests/envoy-grpc-lb.yaml            # lançar o proxy Envoy com LEAST_REQUEST per-request
kubectl apply -f projeto_asid/manifests/c5-frontend-with-envoy.yaml   # redirecionar frontend/checkout/recommendation para usar o Envoy
kubectl rollout status deployment/envoy-grpc-lb                        # aguardar Envoy ficar pronto

# Terminal separado: abrir admin do Envoy
kubectl port-forward svc/envoy-grpc-lb 9901:9901   # mantém este terminal aberto

# Ver distribuição uniforme de pedidos
watch -n 2 'kubectl top pods --no-headers | grep productcatalog'
# Resultado esperado: ~121m / 121m / 122m — H6 resolvida

# Ver estatísticas de pedidos no Envoy
curl -s http://localhost:9901/stats | grep upstream_rq_total   # confirma pedidos distribuídos pelas 3 réplicas
```

### Passo 5 — Mostrar resultados comparativos

```bash
cat projeto_asid/cenarios/resultados_consolidados.csv   # tabela com métricas de todos os cenários
# Resumo:
# C1: quebra 75u, RPS máx ~127
# C2: quebra 75u, p99 pior (H6 consome recursos sem benefício)
# C3: sem quebra até 400u, RPS ~196
# C5: 218.7 RPS a 150u, distribuição uniforme (melhor custo/pedido: -18%)
```

### Passo 6 — Restaurar o estado inicial (C1)

```bash
kubectl delete -f projeto_asid/manifests/envoy-grpc-lb.yaml  # remover o Envoy

# Restaurar o routing original dos serviços que foram alterados no C5
kubectl apply -f kubernetes-manifests/frontend.yaml
kubectl apply -f kubernetes-manifests/checkoutservice.yaml
kubectl apply -f kubernetes-manifests/recommendationservice.yaml

# Repor 1 réplica em todos os stateless
for svc in adservice cartservice checkoutservice currencyservice emailservice \
           frontend paymentservice productcatalogservice recommendationservice shippingservice; do
  kubectl scale deployment/$svc --replicas=1   # volta ao estado C1 baseline
done
```

---

## 13. Diagnóstico / Troubleshooting

```bash
kubectl describe pod <nome-do-pod>     # detalhe de um pod (útil para ver eventos de erro, OOMKill, ImagePull)
kubectl logs <nome-do-pod> --previous  # logs da execução anterior do pod (ver o que causou um crash)

# OOMKill no cartservice (problema específico do Apple Silicon M4)
kubectl describe pod <cartservice-pod> | grep -A5 "OOMKilled"  # confirmar se foi OOMKill
# Fix já aplicado: memory limit 512Mi e variável DOTNET_EnableWriteXorExecute=0 no YAML

kubectl top nodes  # ver se o metrics-server está activo (se falhar, metrics-server não está instalado)
kubectl get deployment metrics-server -n kube-system  # confirmar que o metrics-server está Running

kubectl get hpa   # listar Horizontal Pod Autoscalers (não usamos HPA — útil para confirmar que não está activo)

kubectl describe node docker-desktop | grep -A10 "Allocated resources"  # ver CPU/RAM total alocada vs disponível no nó

kubectl get svc       # listar todos os Services e portas expostas
kubectl get endpoints # listar os endpoints de cada Service (confirmar que os pods estão associados)
```
