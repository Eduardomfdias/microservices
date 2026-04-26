# CLAUDE.md — Projeto ASID 2025/2026

> Este ficheiro existe para dar contexto ao Claude Code (ou a qualquer instância de Claude) sobre o estado atual do projeto, o que já foi feito, o que falta, e como o ambiente funciona. Lê isto antes de fazer qualquer coisa.

---

## Contexto geral

**Unidade curricular:** Arquiteturas de Sistemas de Informação Distribuídos (ASID)  
**Universidade:** Universidade do Minho  
**Mestrado:** Engenharia e Gestão de Sistemas de Informação (MEGSI) — confirmar na capa do relatório final que é este e não Engenharia de Ciência de Dados (o handout menciona ambos)  
**Ano letivo:** 2025/2026 — 2.º Semestre  
**Professor:** Helena Rodrigues  
**Tema:** Tema 2 — Escalabilidade Horizontal e Custo Marginal em Microserviços  
**Sistema em estudo:** [Google Online Boutique](https://github.com/GoogleCloudPlatform/microservices-demo)  

**Grupo:**
- PG61463 – Eduardo Dias
- PG47542 – Nuno Martinho
- PG58760 – Clementina Kulivala
- PG58761 – Golda Kangunga

**Entrega final:** 31 de maio de 2026, 23h59, via Blackboard, formato ACM, máximo 20 páginas (sem figuras).  
**Peso na nota:** 90% da nota final.

**Apresentação oral:** ~30 minutos com demonstração funcional incluída. Vale 5% (incluído nos 90%). Cronograma do enunciado coloca a preparação na semana 16-17, a seguir à entrega do relatório.

---

## Critérios de avaliação (ENUNCIADO)

| Critério | Peso |
|---|---|
| Fundamentação e coerência arquitetural | **40%** |
| Qualidade da avaliação experimental | 30% |
| Implementação e deployment (suporte experimental) | 15% |
| Discussão crítica e conclusões | 10% |
| Apresentação oral e demonstração | 5% |

**Atributos de qualidade obrigatórios** (têm de ser ligados às decisões arquiteturais): Performance, Availability, Deployability, Cost.

---

## Sistema em estudo

**Online Boutique** é uma aplicação de e-commerce com 11 microserviços + Redis, disponibilizada pela Google como referência de boas práticas.

### Serviços

| Serviço | Linguagem | Tipo | Nota |
|---|---|---|---|
| frontend | Go | Stateless | Ponto de entrada HTTP/1.1 |
| productcatalogservice | Go | Stateless | Chamado ×6 por browse — candidato inicial a bottleneck, mas **não é o bottleneck real sob carga severa** |
| cartservice | C# (.NET) | Stateless aplicacional | Depende criticamente do redis-cart |
| checkoutservice | Go | Stateless | Orquestrador de 6 serviços em sequência |
| currencyservice | Node.js | Stateless | Converte moedas (BCE) — **bottleneck real sob carga severa** (junto com frontend) |
| paymentservice | Node.js | Stateless | Pagamento simulado |
| shippingservice | Go | Stateless | Envio simulado |
| emailservice | Python | Stateless | Email confirmação simulado |
| recommendationservice | Python | Stateless | Chama o productcatalogservice |
| adservice | Java | Stateless | Anúncios contextuais |
| redis-cart | — | **Stateful** | Único backend com estado persistente; single-threaded |

**Atenção importante:** o `cartservice` NÃO é stateful — é um serviço aplicacional stateless que depende de um backend stateful partilhado (`redis-cart`). Escalar réplicas do cartservice não escala o redis-cart.

**Descoberta experimental:** sob carga severa (testes exaustivos), os bottlenecks reais são **frontend** e **currencyservice**, não o productcatalogservice. Este último é muito chamado (×6 por browse) mas é rápido. O frontend e currencyservice acumulam CPU porque processam cada pedido HTTP de entrada.

### Comunicação
- Externa: HTTP/1.1 (frontend → browser/Locust)
- Interna: gRPC sobre HTTP/2 (todos os serviços entre si)
- **Problema confirmado empiricamente:** gRPC/HTTP2 faz balanceamento ao nível de conexão (connection affinity) — novas réplicas recebem quase zero tráfego até novas conexões serem abertas. Confirmado em C2: réplicas novas do productcatalogservice ficaram em 1–2m CPU enquanto a réplica original estava em 31m.

---

## Decisão arquitetural em estudo (PARA O RELATÓRIO FINAL)

> Este ponto vale 40% da nota. O enunciado exige descrição explícita da decisão E de pelo menos uma alternativa relevante, com discussão de trade-offs ligada aos quatro atributos de qualidade.

**Decisão arquitetural principal:** escalamento horizontal **seletivo** (escalar apenas o(s) serviço(s) candidato(s) a bottleneck) por oposição a escalamento horizontal **uniforme** (escalar todos os serviços stateless igualmente).

**Alternativas a discutir explicitamente no relatório final:**

| Alternativa | Trade-offs (P / A / D / C) |
|---|---|
| **Auto-scaling (HPA por CPU/memória)** | P: reage a carga real; A: melhor sob carga variável; D: requer métricas e configuração extra; C: custo variável, potencialmente menor em períodos calmos |
| **Caching no productcatalogservice** | P: elimina o fan-out ×6; A: TTL pode causar inconsistências curtas; D: alteração de código; C: pode evitar todo o scale-out |
| **Service mesh (Linkerd/Istio) com balanceamento por pedido** | P: mitiga o connection affinity gRPC (resolve H6); A: introduz componente extra que pode falhar; D: complexidade operacional significativa; C: overhead de CPU/memória |
| **Não escalar — ajustar limites de recursos** | P: explora capacidade não usada; A: limite duro; D: simples; C: barato mas não resolve a longo prazo |

**Trade-offs do escalamento seletivo vs uniforme** (esta é a comparação central do trabalho — corresponde a C2 vs C3):

- **Performance:** uniforme atinge maior throughput (C3: 130 RPS vs C1: 100 RPS); seletivo pode degradar se atingir o serviço errado (C2: 76 RPS — pior que C1)
- **Availability:** seletivo deixa serviços não escalados como pontos únicos de falha; uniforme distribui risco
- **Deployability:** seletivo requer identificação prévia do bottleneck (análise de tracing); uniforme é mecânico
- **Cost:** seletivo tem menor custo absoluto mas pior CM se mal direcionado; uniforme tem custo proporcional ao número de serviços (×N)

---

## Ambiente de desenvolvimento

- **OS:** macOS Apple Silicon (M4, arm64) — MacBook Air 2026
- **Kubernetes:** Docker Desktop com Kubernetes ativo
- **Namespace:** `default`
- **Hardware:** M4 10 cores (4P+6E), 16 GB RAM. Kubernetes recebe todos os 10 cores e ~7.6 GB RAM.
- **Registo de imagens:** `us-central1-docker.pkg.dev/google-samples/microservices-demo/`
- **Ficheiro de specs completo:** `ambiente_experimental.md`

### Fixes obrigatórios para Apple Silicon (JÁ APLICADOS)
```bash
# 1. Memory limit do cartservice aumentado de 128Mi para 512Mi (evita OOMKill sob carga)
# 2. Env var DOTNET_EnableWriteXorExecute=0 no cartservice (fix bug JIT .NET em ARM64)
# 3. imagePullPolicy: Never em todos os deployments (imagens locais — não pull do registry remoto)
# 4. loadgenerator: 0 réplicas (carga gerada externamente pelo Locust)
```

### Ferramentas instaladas/usadas
- **Locust** — gerador de carga (Python). Locustfile com 3 perfis de utilizador.
- **Jaeger** (all-in-one) — rastreio distribuído. Manifesto em `kubernetes-manifests/jaeger.yaml`
- **OpenTelemetry Collector** — agrega traces dos microserviços e exporta para Jaeger. Manifesto em `kubernetes-manifests/otel-collector.yaml`
- **kubectl top** — métricas CPU/RAM por pod (requer metrics-server)

### Scripts de teste
- `c1comp.sh` — C1 comparativo (15, 20, 25 users; think times realistas)
- `c2.sh` — C2 comparativo
- `c3.sh` — C3 comparativo
- `c1_exaustivo.sh` — C1 exaustivo (25→150 users; locustfile severo) ✅ executado
- `c2_exaustivo.sh` — C2 exaustivo ✅ executado
- `c3_exaustivo.sh` — C3 exaustivo ✅ executado

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

## Modelo de carga — Locust

O loadgenerator nativo deve ser **pausado** antes dos testes:
```bash
kubectl scale deployment loadgenerator --replicas=0
```

### Perfis comparativos (think times realistas — c1comp/c2/c3)
```python
# CasualUser — 30% · wait 5–15 s · browse, homepage, moeda
# NormalUser — 50% · wait 2–6 s · browse, cart, checkout ocasional
# PowerUser  — 20% · wait 0.5–2 s · browse, cart, checkout frequente
```
A 25 users gera ~8 RPS — insuficiente para saturar o sistema.

### Perfis exaustivos (think times severos — c1/c2/c3_exaustivo)
```python
# CasualUser — 20% · wait 0.5–1 s · browse, homepage, moeda
# NormalUser — 50% · wait 0.2–0.5 s · browse, cart, checkout ocasional
# PowerUser  — 30% · wait 0.1–0.2 s · browse, cart, checkout frequente
```
A 25 users gera ~72 RPS. Encontra o ponto de saturação real de cada cenário.

**Pesos das tarefas (ambos os locustfiles):**
```
index:1, setCurrency:2, browseProduct:10, addToCart:2, viewCart:3, checkout:1
```

**Parâmetros dos testes exaustivos:**
- Níveis: 25 → 50 → 75 → 100 → 125 → 150 users
- Spawn rate: 2 users/s
- Warm-up: 30s + medição 120s por nível
- Cooldown entre níveis: 60s
- Critério de quebra: p99 > 2000ms OU falhas > 5%

**Decisão técnica:** o checkout usa `catch_response=True` para não contaminar métricas de checkout com falhas do add-to-cart.

**zip_code correto no form de checkout:** `10001` (só aceita 4–5 dígitos).

---

## Cenários experimentais

| Cenário | Réplicas | Réplicas adicionadas vs C1 | Objetivo |
|---|---|---|---|
| **C1** — Baseline | 1 por serviço | 0 | Referência. Ponto de saturação natural. |
| **C2** — Seletivo | productcatalogservice: 3; restantes: 1 | +2 | Escalar o candidato a bottleneck primário. |
| **C3** — Uniforme | Todos stateless: 3; redis-cart: 1 | +20 | Escalar tudo — rendimentos marginais? |

**Elemento constante:** redis-cart mantém 1 réplica em todos os cenários (stateful, single-threaded, não beneficia de scale-out simples).

---

## Resultados — Testes Comparativos (15/20/25 users, locustfile realista — 2026-04-19)

Estes resultados mostram comportamento a carga sub-saturação. A carga de 25 users não satura nenhum cenário.

### C1 Comparativo
| Users | p50 | p90 | p99 | Falhas% | RPS |
|---|---|---|---|---|---|
| 15 | 20ms | 30ms | 62ms | 0.0% | 4.80 |
| 20 | 18ms | 31ms | 52ms | 0.0% | 6.36 |
| 25 | 18ms | 31ms | 69ms | 0.0% | 7.98 |

### C2 Comparativo (productcatalogservice ×3)
| Users | p50 | p90 | p99 | Falhas% | RPS |
|---|---|---|---|---|---|
| 15 | 16ms | 27ms | 170ms | 0.0% | 4.92 |
| 20 | 16ms | 25ms | 86ms | 0.0% | 6.42 |
| 25 | 14ms | 25ms | 290ms | 0.0% | 7.94 |

### C3 Comparativo (todos stateless ×3)
| Users | p50 | p90 | p99 | Falhas% | RPS |
|---|---|---|---|---|---|
| 15 | 21ms | 38ms | 200ms | 0.0% | 4.78 |
| 20 | 19ms | 32ms | 96ms | 0.0% | 6.57 |
| 25 | 19ms | 31ms | 110ms | 0.0% | 7.92 |

**Conclusão comparativos:** RPS idêntico nos 3 cenários (~8 RPS). C2 tem melhor p50 (−22%). C1 tem melhores p99. Não houve saturação — a carga não é suficiente para revelar os bottlenecks.

---

## Resultados — Testes Exaustivos (locustfile severo — 2026-04-26)

### C1 Exaustivo — Baseline (1 réplica por serviço)
**Ponto de quebra: 75 users**

| Users | p50 | p90 | p99 | Falhas% | RPS | Estado |
|---|---|---|---|---|---|---|
| 25 | 47ms | 130ms | 660ms | 0.0% | 71.8 | Aviso |
| 50 | 160ms | 280ms | 1500ms | 0.0% | 88.1 | Aviso |
| **75** | **330ms** | **520ms** | **1800ms** | **23.5%** | **100.4** | **QUEBRA** |

Resultados em: `cenarios_ob_c1_exaustivo/`

### C2 Exaustivo — Seletivo (productcatalogservice ×3)
**Ponto de quebra: 50 users — PIOR QUE C1**

| Users | p50 | p90 | p99 | Falhas% | RPS | Estado |
|---|---|---|---|---|---|---|
| 25 | 50ms | 140ms | 460ms | 0.0% | 71.0 | Aviso |
| **50** | **160ms** | **390ms** | **3700ms** | **27.9%** | **76.1** | **QUEBRA** |

Resultados em: `cenarios_ob_c2_exaustivo/`

**Resultado contra-intuitivo:** C2 quebrou antes do C1 (50u vs 75u). As 2 réplicas adicionais do productcatalogservice não recebem tráfego significativo (afinidade gRPC) mas consomem RAM e CPU do nó, deixando menos recursos para o frontend e currencyservice — os bottlenecks reais. **Confirma H6 empiricamente.**

### C3 Exaustivo — Uniforme (todos stateless ×3)
**Ponto de saturação: ~150 users (2× mais que C1)**

| Users | p50 | p90 | p99 | Falhas% | RPS | Estado |
|---|---|---|---|---|---|---|
| 25 | 20ms | 110ms | 720ms | 0.0% | 74.9 | Aviso |
| 50 | 140ms | 370ms | 560ms | 0.0% | 99.4 | Aviso |
| 75 | 210ms | 700ms | 1100ms | 0.1% | 103.1 | Aviso |
| 100 | 240ms | 710ms | 1000ms | 0.0% | 124.2 | Aviso |
| 125 | 310ms | 970ms | 1300ms | 0.5% | 123.4 | Aviso |
| 150 *(step-up)* | 350ms | 1200ms | 1500ms | 0.0% | 130.5 | Aviso |
| **150 *(cold start)*** | **340ms** | **1500ms** | **2500ms** | **0.0%** | **109.1** | **QUEBRA** |

Resultados em: `cenarios_ob_c3_exaustivo/` (cold start) e `cenarios_ob_c3_exaustivo_bak_20260426_103651/` (step-up)

**Nota step-up vs cold start:** o step-up gradual manteve conexões gRPC aquecidas e JIT compilado, chegando a 150u sem quebrar (p99=1500ms). O cold start directo a 150u quebrou (p99=2500ms). O cold start é a medida mais honesta do ponto de saturação real.

### Comparação de pontos de saturação (testes exaustivos)

| Cenário | Réplicas adicionadas | Ponto de quebra | RPS máximo | Conclusão |
|---|---|---|---|---|
| **C1** Baseline | 0 | **75 users** | 100.4 | Referência |
| **C2** Seletivo | +2 | **50 users ◄ pior** | 76.1 | Escalamento prejudicou o sistema |
| **C3** Uniforme | +20 | **~150 users** | 130.5 | ~2× mais que C1 |

---

## Repetição de experiências e análise estatística (PEDIDO PELO ENUNCIADO)

> O enunciado pede explicitamente "repetição de experiências sempre que aplicável" e "análise estatística básica (médias, variação, comparação entre cenários)". Os testes atuais foram executados uma vez por nível de carga — para o relatório final convém repetir e reportar variação.

**Plano mínimo de repetição** (executar antes do relatório final):
- Repetir C1, C2 e C3 três vezes a 25, 50 e 75 users (níveis críticos comuns aos três cenários)
- Para cada cenário/nível: reportar média ± desvio-padrão de p50, p99, RPS e taxa de falhas
- Comparar variação entre execuções para validar estabilidade do ponto de quebra
- Tempo estimado: 3 cenários × 3 repetições × 3 níveis × ~3min = ~80 minutos de carga + cooldowns

**Justificação metodológica:** num ambiente local Docker Desktop, há ruído proveniente de processos do sistema operativo, garbage collection do JIT e variabilidade do gRPC connection affinity. A repetição permite separar sinal de ruído.

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
| H1 | Escalar seletivamente o productcatalogservice melhora parcialmente o sistema, mas pode não deslocar significativamente o ponto de quebra se outro bottleneck passar a dominar | ✅ Confirmado (parcialmente) | C2 melhora p50 (~22%) nos comparativos, mas nos exaustivos quebra antes do C1 — outro bottleneck passou a dominar (frontend/currencyservice). |
| H2 | Após aliviar pressão no productcatalogservice, o redis-cart tende a emergir como limitação mais visível (especialmente em W2/W3) | ⬜ Sem evidência | redis-cart manteve-se a 4–14m CPU mesmo a 150 users — sem sinais de contenção. Pode emergir a cargas muito superiores. |
| H3 | O ganho por réplica adicional tende a diminuir à medida que o bottleneck se desloca para outras dependências | ✅ Confirmado | C3 (+20 réplicas) desloca o ponto de quebra para ~150u (vs 75u do C1), mas o ganho por réplica é decrescente: C2 (+2) degradou o sistema; C3 (+20) melhorou ~2×. |
| H4 | O custo marginal tende a aumentar quando réplicas deixam de produzir ganhos proporcionais | ✅ Confirmado | C2: +2 réplicas com custo negativo (quebrou antes). C3: +20 réplicas para ganhar ~2× no ponto de quebra — custo marginal crescente. |
| H5 | A escalabilidade horizontal é mais eficaz em serviços stateless do que quando o desempenho depende de um componente stateful partilhado | ⬜ Inconclusivo | O redis-cart não saturou nas cargas testadas. Não foi possível observar o efeito limitador do componente stateful. |
| H6 (exploratória) | O balanceamento gRPC/HTTP2 pode ser não uniforme entre réplicas (connection affinity), limitando o ganho do scale-out | ✅ Confirmado empiricamente | C2 quebrou **antes** do C1 nos exaustivos: réplicas extras do productcatalogservice consomem recursos sem receber tráfego (1–2m CPU vs 31m da réplica original). Resultado C2 < C1 é a evidência mais forte de H6. |

**Mapeamento Hipótese → Atributo de Qualidade** (para a discussão final):
- H1, H3 → Performance, Cost
- H2, H5 → Performance, Availability
- H4 → Cost
- H6 → Performance, Deployability

---

## Definição operacional de custo marginal

```
CM_throughput = RPS_ganho / Replicas_adicionadas

Custo proxy C = alpha * CPU_time + beta * RAM_time
```

Onde:
- `RPS_ganho` = RPS do cenário − RPS do C1 (referência)
- `Replicas_adicionadas` = réplicas adicionadas face ao baseline (C2: +2; C3: +20)
- `CPU_time` = taxa média de CPU (millicores/1000) × duração (s), somada por réplica
- `RAM_time` = memória média (MiB) × duração (s), somada por réplica
- `alpha = beta = 0.5` (pesos iguais — manter constante entre cenários)
- `Custo por pedido com sucesso` = C / pedidos_com_sucesso

Dados para calcular: `cenarios_ob_*/monitoring/pods_metrics.csv` (CSV com timestamp, load_label, pod, cpu_m, ram_mi a cada 10s)

---

## Distinção metodológica

**Execuções comparativas** (cargas fixas 15/20/25 users, locustfile realista):
- Usadas para comparar C1/C2/C3 em condições sub-saturação
- Think times: 5–15s (Casual), 2–6s (Normal), 0.5–2s (Power)
- Resultados em: `cenarios_ob_c1comp/`, `cenarios_ob_c2/`, `cenarios_ob_c3/`

**Execuções exaustivas** (step-up 25→150 users, locustfile severo):
- Usadas para encontrar o ponto de saturação real de cada cenário
- Think times: 0.5–1s (Casual), 0.2–0.5s (Normal), 0.1–0.2s (Power)
- Resultados em: `cenarios_ob_c1_exaustivo/`, `cenarios_ob_c2_exaustivo/`, `cenarios_ob_c3_exaustivo/`
- **Não misturar com os comparativos** — locustfiles diferentes, não comparáveis diretamente entre si mas comparáveis dentro de cada tipo

---

## Ficheiro de resultados HTML

`Diagramas/Resultados-C1-C2-C3.html` — **contém apenas os testes exaustivos** (atualizado 2026-04-26)

Estrutura atual (8 secções):
1. Modelo de carga — Locust (perfis exaustivos)
2. Desenho experimental — C1/C2/C3
3. Testes exaustivos — metodologia
4. C1 Exaustivo (quebra a 75u)
5. C2 Exaustivo (quebra a 50u — pior que C1)
6. C3 Exaustivo (saturação 125–150u)
7. Comparação pontos de saturação
8. Próximos passos

---

## Estado atual do relatório

**Versão atual:** v4.0 (Abril 2026, formato Word) — **a migrar para v5.0 em template ACM**

**Decisão pendente:** escolher entre template ACM Word ou LaTeX. Recomendação: começar a migração esta semana — a formatação ACM consome mais tempo do que se imagina e o limite são 20 páginas (sem figuras).
- Word: https://authors.acm.org/proceedings/production-information/preparing-your-article-with-microsoft-word
- LaTeX: https://authors.acm.org/proceedings/production-information/preparing-your-article-with-latex

**Estrutura do documento:**
1. Introdução + objetivo geral
2. Arquitetura (inventário, diagrama, workflows W1/W2/W3, tabela chamada→dependências→risco, serviços-alvo)
3. **Decisão arquitetural em estudo + alternativas + trade-offs (P/A/D/C)** — secção crítica para os 40%
4. Questões de investigação (RQ1–RQ4) + Hipóteses (H1–H6)
5. Metodologia experimental (Locust, cenários, warm-up, comparativos vs. exaustivos, métricas, custo marginal, repetição/estatística)
6. Resultados comparativos C1/C2/C3 (15/20/25 users)
7. Resultados exaustivos C1/C2/C3 (25→150 users) — **a adicionar**
8. Tabela comparativa de pontos de saturação — **a adicionar**
9. Discussão (desempenho + leitura arquitetural ligada aos 4 atributos de qualidade) — **a expandir**
10. Conclusões e limitações

---

## Apresentação oral e demonstração (PARA SEMANA 16-17)

- **Duração:** ~30 minutos (apresentação + demonstração funcional)
- **Peso:** 5% da nota final
- **Critérios de avaliação:** clareza da apresentação, estrutura do relatório, capacidade de responder a questões técnicas, demonstração funcional da solução

**Estrutura sugerida** (a preparar após relatório final):
- Contexto e tema (~3 min)
- Sistema em estudo + decisão arquitetural + alternativas (~5 min)
- Metodologia experimental (~5 min)
- Resultados — destaque para a descoberta C2 < C1 e H6 (~10 min)
- Discussão arquitetural ligada aos 4 atributos de qualidade (~4 min)
- **Demonstração funcional ao vivo:** deploy do Online Boutique + Locust em tempo real + Jaeger UI mostrando traces (~3 min)
- Q&A

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
- Definição de custo marginal apropriada
- Resultados C1 úteis como referência

**O que faltava (corrigido no v4):**
- ✅ Questões de investigação RQ1–RQ4
- ✅ Cada hipótese ligada ao cenário que a testa
- ✅ Linguagem prudente (candidato/indício)
- ✅ Distinção cartservice vs. redis-cart
- ✅ H6 marcada como exploratória
- ✅ Distinção exploratório vs. comparativo
- ✅ Warm-up de 30s explicitado
- ✅ CPU_time e RAM_time operacionalizados
- ✅ Tabela comparativa C1/C2/C3
- ✅ Locust explicitado como ferramenta

**O que falta fazer para o relatório final (v5.0):**
- [x] Executar C1 comparativo (2026-04-19)
- [x] Executar C2 comparativo (2026-04-19)
- [x] Executar C3 comparativo (2026-04-19)
- [x] Preencher tabela comparativa com dados reais
- [x] Executar testes exaustivos C1 (2026-04-26) — quebra a 75u
- [x] Executar testes exaustivos C2 (2026-04-26) — quebra a 50u (pior que C1)
- [x] Executar testes exaustivos C3 (2026-04-26) — saturação a 150u
- [x] Determinar ponto de quebra de cada cenário
- [ ] **Escrever secção "Decisão arquitetural + alternativas + trade-offs (P/A/D/C)" — vale 40% da nota**
- [ ] **Repetir C1/C2/C3 três vezes a 25/50/75 users e reportar média ± desvio-padrão**
- [ ] Calcular custo proxy C (CPU_time + RAM_time) para C1, C2, C3 — dados em `monitoring/pods_metrics.csv`
- [ ] Confirmar no Jaeger a ordem das chamadas no W3 (payment antes/depois de ship?)
- [ ] Confirmar que EmptyCart ocorre após checkout bem-sucedido (já no diagrama, mas confirmar no Jaeger)
- [ ] Discutir implicações de consistência em caso de falha parcial no W3
- [ ] Escrever discussão final com leitura dupla: desempenho + arquitetural, ligada aos 4 atributos de qualidade
- [ ] Incorporar descoberta C2 < C1 como evidência empírica de H6 (resultado mais forte do trabalho)
- [ ] **Escolher template ACM (Word ou LaTeX) e iniciar migração esta semana**
- [ ] Redigir relatório final em formato ACM (template da Blackboard), máximo 20 páginas sem figuras
- [ ] Preparar slides + demonstração funcional ao vivo para apresentação oral (30 min)
- [ ] Auto-avaliação individual (1 página por aluno) — **deixar para o fim**
- [ ] Anexo de uso de IA (ferramentas, prompts, contributo) — **deixar para o fim**

---

## Regras para o Claude Code

**NÃO inventar dados.** Todos os números nos resultados são reais e validados. Nunca adicionar dados de execuções que não aconteceram.

**NÃO remover** a tabela de risco chamada→dependências→risco — a professora pediu-a explicitamente e é um entregável obrigatório.

**NÃO assumir GKE ou cloud.** O ambiente é Docker Desktop local em Apple Silicon. Não sugerir comandos ou configs específicos de GKE.

**Linguagem prudente nos bottlenecks.** Usar "candidato a bottleneck", "indício de saturação", "evidência sugere" — nunca "confirmado" sem evidência experimental. Exceção: H6 pode ser descrita como "confirmado empiricamente" porque C2 < C1 é evidência direta.

**Cartservice ≠ Stateful.** O cartservice é aplicacional stateless. O redis-cart é o componente stateful. Esta distinção é central e foi explicitamente corrigida pela professora.

**Locust, não k6.** A ferramenta de carga é Locust (Python). A professora questionou o uso de k6.

**Relatório final usa template ACM** — não Word. O Word foi para o intercalar; o final segue o template ACM da Blackboard.

**productcatalogservice não é o bottleneck real.** Nos testes exaustivos, os bottlenecks reais são frontend e currencyservice. O productcatalogservice é muito chamado mas é rápido. Não afirmar que escalar o productcatalogservice resolve o problema — a evidência mostra o contrário (C2 < C1).

**Sempre ligar resultados aos 4 atributos de qualidade.** Performance, Availability, Deployability, Cost. A fundamentação arquitetural pesa 40% e exige esta ligação explícita. Não basta apresentar números — é preciso explicar o que significam para cada atributo de qualidade.

**Análise estatística.** Quando reportar resultados, incluir média e desvio-padrão sempre que houver repetição. Comparações entre cenários devem ser feitas com base nos valores médios e considerar a variação observada.