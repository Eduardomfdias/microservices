# CLAUDE.md — Projeto ASID 2025/2026

> Este ficheiro existe para dar contexto ao Claude Code (ou a qualquer instância de Claude) sobre o estado atual do projeto, o que já foi feito, o que falta, e como o ambiente funciona. Lê isto antes de fazer qualquer coisa.

---

## Contexto geral

**Unidade curricular:** Arquiteturas de Sistemas de Informação Distribuídos (ASID)  
**Universidade:** Universidade do Minho  
**Mestrado:** Engenharia e Gestão de Sistemas de Informação  
**Ano letivo:** 2025/2026 — 2.º Semestre  
**Professor:** Helena Rodrigues  
**Tema:** Tema 2 — Escalabilidade Horizontal e Custo Marginal em Microserviços  
**Sistema em estudo:** [Google Online Boutique](https://github.com/GoogleCloudPlatform/microservices-demo)  

**Grupo:**
- PG61463 – Eduardo Dias
- PG47542 – Nuno Martinho
- PG 58760 – Clementina Kulivala
- PG 58761 – Golda Kangunga

**Entrega final:** 31 de maio de 2026, 23h59, via Blackboard, formato ACM, máximo 20 páginas (sem figuras).  
**Peso na nota:** 90% da nota final.

---

## Sistema em estudo

**Online Boutique** é uma aplicação de e-commerce com 11 microserviços + Redis, disponibilizada pela Google como referência de boas práticas.

### Serviços

| Serviço | Linguagem | Tipo | Nota |
|---|---|---|---|
| frontend | Go | Stateless | Ponto de entrada HTTP/1.1 |
| productcatalogservice | Go | Stateless | **Bottleneck primário candidato** — sem cache, chamado ×6 por browse |
| cartservice | C# (.NET) | Stateless aplicacional | Depende criticamente do redis-cart |
| checkoutservice | Go | Stateless | Orquestrador de 6 serviços em sequência |
| currencyservice | Node.js | Stateless | Converte moedas (BCE) |
| paymentservice | Node.js | Stateless | Pagamento simulado |
| shippingservice | Go | Stateless | Envio simulado |
| emailservice | Python | Stateless | Email confirmação simulado |
| recommendationservice | Python | Stateless | Chama o productcatalogservice |
| adservice | Java | Stateless | Anúncios contextuais |
| redis-cart | — | **Stateful** | Único backend com estado persistente; single-threaded |

**Atenção importante:** o `cartservice` NÃO é stateful — é um serviço aplicacional stateless que depende de um backend stateful partilhado (`redis-cart`). Escalar réplicas do cartservice não escala o redis-cart.

### Comunicação
- Externa: HTTP/1.1 (frontend → browser/Locust)
- Interna: gRPC sobre HTTP/2 (todos os serviços entre si)
- Problema conhecido: gRPC/HTTP2 faz balanceamento ao nível de conexão, não de pedido (connection affinity) — pode causar distribuição desigual entre réplicas

---

## Ambiente de desenvolvimento

- **OS:** macOS Apple Silicon (M-series, arm64)
- **Kubernetes:** Docker Desktop com Kubernetes ativo
- **Namespace:** `default`
- **Registo de imagens:** `us-central1-docker.pkg.dev/google-samples/microservices-demo/`

### Fixes obrigatórios para Apple Silicon
```bash
# 1. Aumentar memory limit do cartservice (evita OOMKill)
# Editar kubernetes-manifests/cartservice.yaml — aumentar memory limit

# 2. Fix do .NET JIT bug no arm64
# Adicionar env var ao deployment do cartservice:
# DOTNET_EnableWriteXorExecute=0
```

### Ferramentas instaladas/usadas
- **Locust** — gerador de carga (Python). Locustfile com 3 perfis de utilizador.
- **Jaeger** (all-in-one) — rastreio distribuído. Manifesto em `kubernetes-manifests/jaeger.yaml`
- **OpenTelemetry Collector** — agrega traces dos microserviços e exporta para Jaeger. Manifesto em `kubernetes-manifests/otel-collector.yaml`
- **kubectl top** — métricas CPU/RAM por pod (requer metrics-server)
- **Prometheus/Grafana** — monitorização adicional

### Scripts de teste
- `c1.sh` — executa o Cenário C1 (baseline)
- `experimentos_escalamento.sh` — scripts de escalamento
- `testes_cenarios_ob.sh` — testes gerais

---

## Workflows analisados

### W1 — Browse Product `GET /product/{id}` (peso 10)
- **Fan-out:** 6 chamadas gRPC paralelas ao productcatalogservice por pedido
- **Serviços ativados:** frontend → productcatalogservice (×6), currencyservice, recommendationservice → productcatalogservice, cartservice (verificação), adservice
- **Relevância:** operação mais frequente; principal driver de carga do productcatalogservice

### W2 — Add to Cart `POST /cart` (peso 3)
- **Fan-out:** 2 chamadas gRPC sequenciais
- **Serviços ativados:** frontend → productcatalogservice (GetProduct), frontend → cartservice → redis-cart (HSET)
- **Relevância:** pré-requisito do checkout; falha aqui → checkout falha 100%; HSET no redis-cart é bloqueante

### W3 — Checkout `POST /cart/checkout` (peso 1)
- **Fan-out:** 6 chamadas gRPC sequenciais do checkoutservice
- **Serviços ativados:** frontend → checkoutservice → redis-cart (GetCart), productcatalogservice, currencyservice, shippingservice, paymentservice, emailservice, redis-cart (EmptyCart)
- **Relevância:** maior valor de negócio; latência = soma de todas as dependências; EmptyCart ocorre no final (confirmado no Jaeger)

---

## Modelo de carga — Locust v2

O loadgenerator nativo deve ser **pausado** antes dos testes:
```bash
kubectl scale deployment loadgenerator --replicas=0
```

### 3 perfis de utilizador
```python
# CasualUser — 30% do tráfego
wait_time = between(5, 15)  # segundos
# Ações: browse, homepage; raramente add-to-cart; nunca checkout

# NormalUser — 50% do tráfego  
wait_time = between(2, 6)
# Ações: browse, add-to-cart, view-cart, checkout ocasional, set-currency

# PowerUser — 20% do tráfego
wait_time = between(0.5, 2)
# Ações: produto → add-to-cart → checkout com alta frequência
```

**Pesos das tarefas:**
```
index:1, setCurrency:2, browseProduct:10, addToCart:2, viewCart:3, checkout:1
```

**Parâmetros de execução:**
- Spawn rate: 2 utilizadores/segundo
- Step: 5 utilizadores por patamar
- Duração por step: 60 segundos
- Cooldown entre steps: 15 segundos

**Decisão técnica:** o checkout usa `catch_response=True` para não contaminar métricas de checkout com falhas que são do add-to-cart.

**zip_code correto no form de checkout:** `10001` (só aceita 4–5 dígitos; formatos como "3030-199" causam 100% de falhas no checkout).

---

## Cenários experimentais

### Descrição dos cenários e diferenças entre eles

Os três cenários foram desenhados para isolar progressivamente o efeito do escalamento horizontal sobre o desempenho do sistema. Todos usam o **mesmo locustfile** (3 perfis de utilizador: CasualUser 30%, NormalUser 50%, PowerUser 20%), as **mesmas cargas fixas** (15, 20, 25 users), o **mesmo método** (warm-up 30s + medição 120s, spawn rate 2/s), e os mesmos **critérios de quebra** (`p99 > 2000ms` OU `taxa de falhas > 5%`). A única variável entre cenários é o **número de réplicas**.

| Cenário | O que foi feito | Réplicas | Réplicas adicionadas vs C1 | Objetivo |
|---|---|---|---|---|
| **C1** — Baseline | Todos os serviços com **1 réplica** (configuração original) | 1 por serviço (total: 11 + Redis) | 0 | Estabelecer a referência de desempenho sem qualquer escalamento. Identificar o ponto de saturação natural do sistema. |
| **C2** — Escalamento Seletivo | Apenas o **productcatalogservice** escalado para **3 réplicas**; todos os restantes mantêm 1 réplica | productcatalogservice: 3; restantes: 1 | +2 | Testar se escalar **apenas** o serviço identificado como candidato a bottleneck primário (chamado ×6 em cada browse) melhora significativamente o desempenho. Avalia a eficácia do escalamento cirúrgico. |
| **C3** — Escalamento Uniforme | **Todos os 10 serviços stateless** escalados para **3 réplicas**; redis-cart mantém 1 réplica (stateful, não escalável horizontalmente) | Todos stateless: 3; redis-cart: 1 | +20 | Testar se escalar uniformemente todos os serviços produz ganhos proporcionais adicionais face ao C2, ou se surgem rendimentos marginais decrescentes (por saturação do redis-cart ou por distribuição desigual do gRPC/HTTP2). |

**Diferenças-chave entre cenários:**
1. **C1 → C2:** Apenas +2 réplicas (productcatalogservice). Testa H1 (escalamento seletivo melhora parcialmente) e H2 (redis-cart pode emergir como nova limitação).
2. **C2 → C3:** Mais +18 réplicas (todos os outros stateless). Testa H3 (ganho por réplica diminui) e H5 (stateless vs. stateful). O contraste entre +2 réplicas (C2) e +20 réplicas (C3) permite calcular se o custo marginal compensa.
3. **Elemento constante:** O redis-cart (único componente stateful) permanece com **1 réplica** em todos os cenários. Isto é intencional — o redis-cart é single-threaded e não beneficia de escalamento horizontal simples, servindo como potencial limite superior do sistema.

---

### C1 — Baseline ✅ (executado — 2026-04-19)
- **Script:** `c1comp.sh`
- Todos os serviços com **1 réplica** (configuração original)
- Execução comparativa (cargas fixas: 15, 20, 25 users; warm-up 30s + medição 120s)
- Resultados em: `cenarios_ob_c1comp/`

### C2 — Escalamento Seletivo ✅ (executado — 2026-04-19)
- **Script:** `c2.sh`
- productcatalogservice: **3 réplicas**
- Todos os outros: 1 réplica
- Execução comparativa (cargas fixas: 15, 20, 25 users; warm-up 30s + medição 120s)
- Resultados em: `cenarios_ob_c2/`

### C3 — Escalamento Uniforme ✅ (executado — 2026-04-19)
- **Script:** `c3.sh`
- Todos os 10 serviços stateless: **3 réplicas**
- redis-cart: **1 réplica** (stateful — não escalado)
- Execução comparativa (mesmas condições de C1 e C2)
- Resultados em: `cenarios_ob_c3/`

---

## Resultados do C1 — Baseline (dados reais, validados — 2026-04-19)

**Configuração:** 1 réplica por serviço (configuração original, sem qualquer escalamento)  
**Locustfile:** 3 perfis (CasualUser 30%, NormalUser 50%, PowerUser 20%)  
**Método:** warm-up 30s + medição 120s por nível; spawn rate 2/s

| Users | p50 (ms) | p90 (ms) | p99 (ms) | Falhas | Falhas% | RPS | Estado |
|---|---|---|---|---|---|---|---|
| 15 | 20 | 30 | 62 | 0 | 0.0% | 4.80 | OK |
| 20 | 18 | 31 | 52 | 0 | 0.0% | 6.36 | OK |
| 25 | 18 | 31 | 69 | 0 | 0.0% | 7.98 | OK |

**Observações C1:**
- Sistema estável nos 3 níveis de carga testados com zero falhas
- Latência p99 mantém-se abaixo de 70ms em todos os patamares
- RPS escala de forma aproximadamente linear com o número de utilizadores
- A 25 users, os serviços com maior consumo de CPU são: frontend (50m), currencyservice (47m), recommendationservice (31m), productcatalogservice (21m)

**Nota:** estes resultados substituem os dados exploratórios do C1 original (step-up 5→30 users com locustfile diferente). Esta execução foi feita com o **mesmo locustfile** dos cenários C2 e C3 para garantir comparabilidade direta.

---

## Resultados do C2 — Escalamento Seletivo (dados reais, validados — 2026-04-19)

**Configuração:** productcatalogservice **3 réplicas**, todos os outros 1 réplica  
**Locustfile:** 3 perfis (CasualUser 30%, NormalUser 50%, PowerUser 20%)  
**Método:** warm-up 30s + medição 120s por nível; spawn rate 2/s

| Users | p50 (ms) | p90 (ms) | p99 (ms) | Falhas | Falhas% | RPS | Estado |
|---|---|---|---|---|---|---|---|
| 15 | 16 | 27 | 170 | 0 | 0.0% | 4.92 | OK |
| 20 | 16 | 25 | 86 | 0 | 0.0% | 6.42 | OK |
| 25 | 14 | 25 | 290 | 0 | 0.0% | 7.94 | OK |

**Observações C2:**
- Sistema estável em todos os níveis, zero falhas
- Melhoria visível na mediana (p50): 18→14ms a 25 users (redução de ~22%)
- O p99 apresenta variabilidade maior do que o C1 (290ms vs 69ms a 25 users), provavelmente associada a picos esporádicos nos serviços não escalados
- A 25 users, o frontend (70m CPU) e o currencyservice (55m) são agora os maiores consumidores de CPU, enquanto o productcatalogservice distribui carga entre 3 pods (31m + 2m + 1m)
- As 2 réplicas adicionais do productcatalogservice recebem significativamente menos tráfego que a original, indício de connection affinity do gRPC/HTTP2 (H6)

**Custo marginal (C2 vs C1, a 25 users):**
- Réplicas adicionadas: +2 (productcatalogservice: 1→3)
- RPS: 7.94 vs 7.98 (C1) → sem ganho significativo em throughput (∆ = −0.04 RPS)
- Melhoria principal: na latência p50. O throughput mantém-se estável porque a carga usada (25 users) não saturou o C1

---

## Resultados do C3 — Escalamento Uniforme (dados reais, validados — 2026-04-19)

**Configuração:** todos os 10 serviços stateless com **3 réplicas**; redis-cart com 1 réplica  
**Locustfile:** 3 perfis (CasualUser 30%, NormalUser 50%, PowerUser 20%)  
**Método:** warm-up 30s + medição 120s por nível; spawn rate 2/s

| Users | p50 (ms) | p90 (ms) | p99 (ms) | Falhas | Falhas% | RPS | Estado |
|---|---|---|---|---|---|---|---|
| 15 | 21 | 38 | 200 | 0 | 0.0% | 4.78 | OK |
| 20 | 19 | 32 | 96 | 0 | 0.0% | 6.57 | OK |
| 25 | 19 | 31 | 110 | 0 | 0.0% | 7.92 | OK |

**Observações C3:**
- Sistema estável em todos os níveis, zero falhas
- Latência p50 e p90 semelhantes ao C1. O C3 **não apresenta melhorias significativas** face ao C2 apesar de ter +18 réplicas adicionais
- O p99 a 15 users (200ms) é substancialmente superior ao C1 (62ms) e ao C2 (170ms), o que pode reflecir overhead de startup das novas réplicas ou distribuição desigual de carga
- A distribuição de CPU entre réplicas é **muito desigual**: ex. a 25 users, currencyservice tem 26m + 17m + 2m; frontend tem 16m + 17m + 16m (melhor distribuição); productcatalogservice tem 14m + 7m + 3m
- O redis-cart (único componente não escalado) mantém-se a 4m de CPU — sem sinais de saturação a este nível de carga

**Custo marginal (C3 vs C1, a 25 users):**
- Réplicas adicionadas: +20 (10 serviços × 2 réplicas adicionais cada)
- RPS: 7.92 vs 7.98 (C1) → sem ganho em throughput (∆ = −0.06 RPS)
- Custo marginal negativo: mais réplicas, ≈ mesmo throughput, latência semelhante ou pior
- Resultado esperado: a carga de 25 users não satura o sistema mesmo com 1 réplica; escalar sem saturação produz overhead sem benefício

---

## Tabela comparativa C1 / C2 / C3 (dados reais)

### Comparação de latência e throughput a 25 users

| Métrica | C1 (Baseline) | C2 (Seletivo) | C3 (Uniforme) | Melhor cenário |
|---|---|---|---|---|
| **Réplicas totais** | 11 (+ Redis) | 13 (+ Redis) | 31 (+ Redis) | — |
| **Réplicas adicionadas** | 0 | +2 | +20 | — |
| **p50 (ms)** | 18 | 14 | 19 | C2 (−22% vs C1) |
| **p90 (ms)** | 31 | 25 | 31 | C2 (−19% vs C1) |
| **p99 (ms)** | 69 | 290 | 110 | C1 (menor variabilidade) |
| **RPS** | 7.98 | 7.94 | 7.92 | C1 (≈ equivalente) |
| **Falhas** | 0 | 0 | 0 | Todos iguais |
| **Falhas%** | 0.0% | 0.0% | 0.0% | Todos iguais |

### Comparação por nível de carga — p50 (ms)

| Users | C1 | C2 | C3 |
|---|---|---|---|
| 15 | 20 | 16 | 21 |
| 20 | 18 | 16 | 19 |
| 25 | 18 | 14 | 19 |

### Comparação por nível de carga — p99 (ms)

| Users | C1 | C2 | C3 |
|---|---|---|---|
| 15 | 62 | 170 | 200 |
| 20 | 52 | 86 | 96 |
| 25 | 69 | 290 | 110 |

### Comparação por nível de carga — RPS

| Users | C1 | C2 | C3 |
|---|---|---|---|
| 15 | 4.80 | 4.92 | 4.78 |
| 20 | 6.36 | 6.42 | 6.57 |
| 25 | 7.98 | 7.94 | 7.92 |

### Análise comparativa

**1. Throughput (RPS):** Praticamente idêntico nos 3 cenários (~7.9–8.0 RPS a 25 users). Isto indica que **a carga de 25 users não satura o sistema** mesmo na configuração baseline. O escalamento horizontal, tanto seletivo como uniforme, não produz ganhos de throughput porque o sistema não é o bottleneck — é a carga que é insuficiente para o revelar.

**2. Latência mediana (p50):** O C2 apresenta a melhor mediana (14ms a 25 users vs 18–19ms nos outros). Este ganho de ~22% deve-se à distribuição de carga no productcatalogservice (serviço mais chamado em W1). O C3, apesar de ter todas as réplicas extras, não melhora a mediana — o overhead de coordenação entre réplicas pode anular o benefício.

**3. Latência cauda (p99):** Paradoxalmente, o C1 (baseline) tem os **melhores p99** em quase todos os patamares. O C2 e C3 mostram picos esporádicos mais altos (290ms no C2 a 25 users, 200ms no C3 a 15 users), provavelmente causados por:
- **Connection affinity do gRPC/HTTP2** (a carga distribui-se desigualmente entre réplicas)
- **Overhead de startup** das réplicas novas (menos "aquecidas")
- **Variabilidade natural** com mais componentes no sistema

**4. Custo marginal:** Com ∆RPS ≈ 0 em todos os cenários, o custo marginal por réplica é efetivamente nulo ou negativo. Mais réplicas = mais CPU+RAM consumidos sem retorno. Isto confirma H3 (rendimentos marginais decrescentes) e H4 (custo marginal crescente). A relação custo-benefício é particularmente desfavorável no C3 (+20 réplicas sem qualquer melhoria tangível face ao C2).

**5. Limitação do estudo:** Para uma comparação mais robusta, seria necessário testar cargas superiores (30, 35, 40+ users) para encontrar os pontos de quebra do C2 e C3 e verificar se o escalamento horizontal desloca efetivamente esse ponto. Na gama testada (15–25 users), nenhum cenário atingiu saturação, o que limita as conclusões sobre a eficácia do escalamento.

---

## Questões de investigação

- **RQ1:** Que serviços dominam a degradação de desempenho nos workflows principais à medida que a carga aumenta?
- **RQ2:** Escalar seletivamente o serviço mais pressionado melhora de forma mensurável throughput, latência e taxa de falhas?
- **RQ3:** O ganho por réplica adicional justifica o custo, ou surgem rapidamente rendimentos marginais decrescentes?
- **RQ4:** Até que ponto a eficácia do escalamento horizontal é condicionada pela natureza stateless vs. dependência de componentes stateful partilhados?

---

## Hipóteses

| H | Hipótese | Estado | Evidência |
|---|---|---|---|
| H1 | Escalar seletivamente o productcatalogservice melhora parcialmente o sistema, mas pode não deslocar significativamente o ponto de quebra se outro bottleneck passar a dominar | ✅ Indício favorável | C2 melhora p50 (~22%) mas não desloca throughput. A carga testada (25 users) não atinge saturação, pelo que o ponto de quebra não foi atingido em nenhum cenário. |
| H2 | Após aliviar pressão no productcatalogservice, o redis-cart tende a emergir como limitação mais visível (especialmente em W2/W3) | ⬜ Sem evidência | redis-cart mantém-se a 4–5m CPU em todos os cenários — sem sinais de contenção a 25 users. Necessitaria de cargas superiores para testar. |
| H3 | O ganho por réplica adicional tende a diminuir à medida que o bottleneck se desloca para outras dependências | ✅ Confirmado | C3 (+20 réplicas) não produz melhorias face a C2 (+2 réplicas). Rendimentos marginais decrescentes evidentes. |
| H4 | O custo marginal tende a aumentar quando réplicas deixam de produzir ganhos proporcionais | ✅ Confirmado | C3 consome ~3× mais recursos (CPU+RAM totais) sem ganho de throughput. CM_throughput ≈ 0 em ambos os cenários. |
| H5 | A escalabilidade horizontal é mais eficaz em serviços stateless do que quando o desempenho depende de um componente stateful partilhado | ⬜ Inconclusivo | A carga testada não saturou o redis-cart, pelo que não foi possível observar o efeito limitador do componente stateful. |
| H6 (exploratória) | O balanceamento gRPC/HTTP2 pode ser não uniforme entre réplicas (connection affinity), limitando o ganho do scale-out | ✅ Indício favorável | Em C2, productcatalogservice pod original recebe 31m CPU vs 2m e 1m nas réplicas novas. Em C3, padrão semelhante em múltiplos serviços (ex: currencyservice 26m + 17m + 2m). |

---

## Definição operacional de custo marginal

```
CM_throughput = RPS_ganho / Replicas_adicionadas

Custo proxy C = alpha * CPU_time + beta * RAM_time
```

Onde:
- `RPS_ganho` = RPS do cenário − RPS do C1 (referência: 8.35 RPS a 25 users)
- `Replicas_adicionadas` = réplicas adicionadas face ao baseline (C2: +2; C3: ~+18)
- `CPU_time` = taxa média de CPU (cores) × duração do teste (s), somada por réplicas. Ex: 0.5 cores × 120s = 60 CPU-seconds
- `RAM_time` = memória média (MiB) × duração (s), somada por réplicas
- `alpha = beta = 0.5` (pesos iguais — manter constante entre cenários)
- `Custo por pedido com sucesso` = C / pedidos_com_sucesso

---

## Distinção metodológica importante

**Execuções exploratórias** (step-up progressivo):
- Usadas para descobrir o ponto de saturação
- Resultados a cargas altas podem refletir estado herdado das fases anteriores
- Não usar para comparação entre cenários

**Execuções comparativas** (carga fixa):
- Usadas para comparar C1, C2 e C3
- Cada execução é independente, com cluster em estado limpo
- 30 segundos de warm-up antes da janela de medição
- Cargas fixas nos níveis identificados pelo C1 exploratório (15, 20, 25 users)

---

## Métricas a recolher em cada execução

```bash
# Throughput, latência (p50/p90/p95/p99), taxa de erro — Locust CSV
# CPU e memória por pod — a cada 10s durante os testes
kubectl top pods --sort-by=cpu

# Pod restarts e réplicas
kubectl get pods
kubectl get deployments

# Sinais de contenção no redis-cart (executar durante C2)
kubectl exec -it <redis-cart-pod> -- redis-cli INFO stats
kubectl exec -it <redis-cart-pod> -- redis-cli INFO clients
kubectl exec -it <redis-cart-pod> -- redis-cli SLOWLOG GET 20
kubectl exec -it <redis-cart-pod> -- redis-cli LATENCY LATEST

# Traces distribuídos — Jaeger UI (por workflow, por nível de carga)
kubectl port-forward svc/jaeger 16686:16686
```

Outputs em `cenarios_ob_YYYYMMDD_HHMMSS/` com CSVs Locust, snapshots kubectl e log completo.

---

## Estado atual do relatório

**Versão atual:** v4.0 (Abril 2026)  
**Estrutura do documento:**
1. Introdução + objetivo geral
2. Arquitetura (inventário, diagrama, workflows W1/W2/W3 com diagramas de sequência, tabela chamada→dependências→risco, serviços-alvo)
3. Questões de investigação (RQ1–RQ4) + Hipóteses (H1–H6)
4. Metodologia experimental (Locust, cenários, warm-up, execuções comparativas, métricas, custo marginal operacionalizado)
5. Resultados C1 (dados reais — execução comparativa)
6. Resultados C2 (dados reais)
7. Resultados C3 (dados reais)
8. Tabela comparativa C1/C2/C3 (preenchida)
9. Discussão e próximos passos

---

## Feedback da professora (resumo acumulado)

### Semana 7 — Primeiro feedback detalhado
A professora pediu explicitamente:
1. Diagrama arquitetural global único e final ✅
2. Diagramas de sequência por workflow (W1, W2, W3) ✅
3. Tabela chamada → dependências → risco ✅
4. Definição operacional de custo marginal ✅
5. Hipóteses explícitas com critérios de confirmação ✅
6. Serviços-alvo justificados (análise stateful vs. stateless) ✅

### Semana 9 — Feedback ao relatório intercalar (v3→v4)
**Pontos positivos reconhecidos:**
- Estrutura global mais clara
- W1/W2/W3 adequados ao tema
- Análise arquitetural objetiva
- Distinção C2 (seletivo) vs. C3 (uniforme) é boa base de comparação
- Definição de custo marginal apropriada para esta fase
- Resultados C1 úteis como referência

**O que ainda faltava (corrigido no v4):**
- ✅ Questões de investigação RQ1–RQ4 adicionadas
- ✅ Cada hipótese ligada ao cenário que a testa
- ✅ Linguagem "confirmado" → substituída por "candidato/indício/hipótese arquitetural"
- ✅ Distinção cartservice vs. redis-cart corrigida com rigor conceptual
- ✅ H6 (balanceamento gRPC) marcada como exploratória
- ✅ Distinção execuções exploratórias vs. comparativas explicada
- ✅ Warm-up de 30s explicitado
- ✅ CPU_time e RAM_time operacionalizados com unidades concretas
- ✅ Tabela comparativa C1/C2/C3 adicionada (C2/C3 marcados como "a preencher")
- ✅ Locust explicitado como ferramenta (a professora tinha ficado com dúvida se usavam k6)

**O que falta fazer para o relatório final:**
- [x] Executar C1 comparativo com mesmo locustfile (2026-04-19) — `cenarios_ob_c1comp/`
- [x] Executar C2 com recolha completa de métricas (2026-04-19) — `cenarios_ob_c2/`
- [x] Verificar sinais de contenção no redis-cart durante C2 — `cenarios_ob_c2/redis_metrics/`
- [x] Executar C3 (2026-04-19) — `cenarios_ob_c3/`
- [x] Preencher tabela comparativa com dados reais
- [ ] Calcular custo proxy C para C1, C2, C3 (CPU_time + RAM_time por cenário)
- [ ] Confirmar no Jaeger a ordem exata das chamadas no W3 (payment antes/depois de ship?)
- [ ] Confirmar que EmptyCart ocorre após checkout bem-sucedido (já no diagrama, mas confirmar no Jaeger sob carga)
- [ ] Discutir brevemente implicações de consistência em caso de falha parcial no W3
- [ ] Melhorar discussão final com leitura dupla: desempenho + arquitetural (não basta "houve melhoria" — explicar porquê)
- [ ] Eliminar afirmações categóricas; substituir por "evidência sugere", "indício de", etc.
- [ ] Testar cargas superiores (30, 35, 40 users) para encontrar ponto de quebra em C2 e C3

---

## Regras para o Claude Code

**NÃO inventar dados.** Todos os números nos resultados são reais e validados. Se precisares de mostrar resultados de C2 ou C3, marca sempre como "A preencher" ou "pendente de execução".

**NÃO remover** a tabela de risco chamada→dependências→risco — a professora pediu-a explicitamente e é um entregável obrigatório.

**NÃO assumir GKE ou cloud.** O ambiente é Docker Desktop local em Apple Silicon. Não sugerir comandos ou configs específicos de GKE.

**Linguagem prudente nos bottlenecks.** Usar "candidato a bottleneck", "indício de saturação", "hipótese arquitetural" — nunca "confirmado" sem evidência experimental detalhada.

**Cartservice ≠ Stateful.** O cartservice é aplicacional stateless. O redis-cart é o componente stateful. Esta distinção é central para o tema e foi explicitamente corrigida pela professora.

**Locust, não k6.** A ferramenta de carga é Locust. A professora questionou o uso de k6 — garantir que qualquer referência à ferramenta de carga menciona Locust e a razão da escolha.

**Relatório final usa template ACM** — não Word. O Word é para o intercalar; o final tem de seguir o template ACM da Blackboard.
