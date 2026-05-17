# CLAUDE.md — Projeto ASID 2025/2026

> Contexto para o Claude Code sobre o estado do projeto. Lê isto antes de fazer qualquer coisa.

---

## Contexto geral

**UC:** Arquiteturas de Sistemas de Informação Distribuídos (ASID) — MEGSI, UMinho, 2025/2026  
**Tema:** Tema 2 — Escalabilidade Horizontal e Custo Marginal em Microserviços  
**Sistema:** [Google Online Boutique](https://github.com/GoogleCloudPlatform/microservices-demo)  
**Professor:** Helena Rodrigues

**Grupo:** PG61463 – Eduardo Dias · PG47542 – Nuno Martinho · PG58760 – Clementina Kulivala · PG58761 – Golda Kangunga

**Entrega final:** 31 maio 2026, 23h59, Blackboard, formato ACM, máx. 20 páginas (sem figuras). Peso: 90%.  
**Apresentação oral:** ~30 min com demo funcional, semana 16-17. Vale 5% (incluído nos 90%).

---

## Critérios de avaliação

| Critério | Peso |
|---|---|
| Fundamentação e coerência arquitetural | **40%** |
| Qualidade da avaliação experimental | 30% |
| Implementação e deployment | 15% |
| Discussão crítica e conclusões | 10% |
| Apresentação oral e demonstração | 5% |

**Atributos de qualidade obrigatórios** (ligar às decisões): Performance, Availability, Deployability, Cost.

---

## Sistema em estudo

| Serviço | Lang | Tipo | Nota |
|---|---|---|---|
| frontend | Go | Stateless | Entrada HTTP/1.1 |
| productcatalogservice | Go | Stateless | ×6 por browse — candidato inicial a bottleneck, **não é o bottleneck real** |
| cartservice | C# | Stateless aplicacional | Depende do redis-cart — **NÃO é stateful** |
| checkoutservice | Go | Stateless | Orquestrador de 6 serviços em sequência |
| currencyservice | Node.js | Stateless | Bottleneck sob carga severa (junto com frontend) |
| paymentservice | Node.js | Stateless | Pagamento simulado |
| shippingservice | Go | Stateless | Envio simulado |
| emailservice | Python | Stateless | Email simulado |
| recommendationservice | Python | Stateless | Chama productcatalogservice |
| adservice | Java | Stateless | Anúncios contextuais |
| redis-cart | — | **Stateful** | Único backend com estado; single-threaded |

**Comunicação:** externa HTTP/1.1; interna gRPC/HTTP2.  
**H6 (confirmada empiricamente):** gRPC/HTTP2 faz balanceamento por conexão — novas réplicas recebem quase zero tráfego até novas conexões serem abertas. C2 quebrou antes do C1 como evidência direta. **C5 (Envoy) resolve H6.**

---

## Decisão arquitetural em estudo

**Decisão principal:** escalamento horizontal **seletivo** vs. **uniforme** (C2 vs. C3). C5 adiciona a dimensão do balanceamento L7.

**Alternativas discutidas no relatório:**

| Alternativa | Trade-offs (P / A / D / C) |
|---|---|
| **Auto-scaling (HPA)** | P: reage a carga real; A: melhor sob carga variável; D: requer métricas; C: variável |
| **Caching no productcatalogservice** | P: elimina fan-out ×6; A: TTL pode causar inconsistências; D: altera código; C: evita scale-out |
| **Service mesh / proxy L7 (Envoy)** | P: resolve H6 (balanceamento por pedido); A: Envoy SPOF (mitigável); D: complexidade operacional; C: overhead proxy compensado pelo throughput |
| **Não escalar — ajustar limites** | P: explora capacidade existente; A: limite duro; D: simples; C: barato mas não escala |

---

## Ambiente de desenvolvimento

- **OS:** macOS Apple Silicon (M4, arm64) — Docker Desktop Kubernetes
- **Namespace:** `default` | **Hardware:** M4 10 cores, 16 GB RAM

### Fixes Apple Silicon (JÁ APLICADOS em kubernetes-manifests/)
```
- cartservice: memory limit 128Mi → 512Mi (evita OOMKill)
- cartservice: DOTNET_EnableWriteXorExecute=0 (fix JIT .NET ARM64)
- imagePullPolicy: Never em todos os deployments (imagens locais)
- loadgenerator: 0 réplicas (carga gerada pelo Locust)
- metrics-server: instalado + patch --kubelet-insecure-tls (para kubectl top)
- Imagens retagged com nomes curtos (ex: docker tag gcr.io/.../frontend frontend)
```

### Ferramentas
- **Locust** — gerador de carga. Locustfile com 3 perfis.
- **Jaeger** (all-in-one) — tracing. `kubernetes-manifests/jaeger.yaml`
- **OpenTelemetry Collector** — `kubernetes-manifests/otel-collector.yaml`
- **kubectl top** — métricas CPU/RAM (requer metrics-server)
- **Envoy** (C5) — proxy L7 gRPC. `kubernetes-manifests/envoy-grpc-lb.yaml`

### Scripts de teste
- `c1comp.sh` — C1 comparativo ✅
- `c2.sh` — C2 comparativo ✅
- `c3.sh` — C3 comparativo ✅
- `c1_exaustivo.sh` — C1 exaustivo ✅
- `c2_exaustivo.sh` — C2 exaustivo ✅
- `c3_exaustivo.sh` — C3 exaustivo ✅
- `c5.sh` — C5 exaustivo (Envoy) ✅ executado 2026-05-05

### Ficheiros C5 (criados 2026-05-05)
- `kubernetes-manifests/envoy-grpc-lb.yaml` — 9 headless services + ConfigMap (LEAST_REQUEST) + Deployment + Service
- `kubernetes-manifests/c5-frontend-with-envoy.yaml` — frontend/checkoutservice/recommendationservice com *_SERVICE_ADDR → envoy-grpc-lb
- `cenarios_ob_c5_exaustivo/` — resultados dos testes C5

---

## Workflows analisados

### W1 — Browse Product `GET /product/{id}` (peso 10)
frontend → productcatalogservice (×6), currencyservice, recommendationservice→productcatalogservice, cartservice, adservice

### W2 — Add to Cart `POST /cart` (peso 3)
frontend → productcatalogservice (GetProduct) → cartservice → redis-cart (HSET bloqueante)

### W3 — Checkout `POST /cart/checkout` (peso 1)
frontend → checkoutservice → redis-cart (GetCart), productcatalogservice, currencyservice, shippingservice, paymentservice, emailservice, redis-cart (EmptyCart — confirmado no Jaeger)

---

## Modelo de carga — Locust

```bash
kubectl scale deployment loadgenerator --replicas=0  # pausar antes dos testes
```

**Comparativo** (locustfile realista): CasualUser 30% wait 5–15s · NormalUser 50% wait 2–6s · PowerUser 20% wait 0.5–2s → ~8 RPS a 25u  
**Exaustivo** (locustfile severo): CasualUser 20% wait 0.5–1s · NormalUser 50% wait 0.2–0.5s · PowerUser 30% wait 0.1–0.2s → ~72 RPS a 25u

**Pesos tarefas:** `index:1, setCurrency:2, browseProduct:10, addToCart:2, viewCart:3, checkout:1`  
**Parâmetros exaustivos:** 25→50→75→100→125→150u · spawn 2u/s · warm-up 30s · medição 120s · cooldown 60s  
**Critério de quebra:** p99 > 2000ms OU falhas > 5% (critério operacional, não SLA real)  
**zip_code checkout:** `10001` (4–5 dígitos)

---

## Cenários experimentais

| Cenário | Réplicas | +Comp. vs C1 | Objetivo |
|---|---|---|---|
| **C1** — Baseline | 1 por serviço | 0 | Referência |
| **C2** — Seletivo | productcatalogservice ×3; restantes ×1 | +2 | Escalar candidato a bottleneck |
| **C3** — Uniforme | Todos stateless ×3; redis-cart ×1 | +20 | Escalar tudo |
| **C4** — Seletivo real | frontend ×3 + currencyservice ×3; restantes ×1 | +4 | Escalar bottlenecks reais |
| **C5** — Uniforme ×3 + Envoy L7 | Todos stateless ×3 + Envoy proxy | +20+Envoy | Mitigar connection affinity; validar H6 |

**redis-cart sempre ×1** (stateful, single-threaded, não beneficia de scale-out simples).

---

## Resultados — Testes Comparativos (locustfile realista — 2026-04-19)

A 25u (~8 RPS) não satura nenhum cenário. C2 tem melhor p50 (−22%). RPS idêntico nos 3 cenários.

| Users | C1 p50/p99/RPS | C2 p50/p99/RPS | C3 p50/p99/RPS |
|---|---|---|---|
| 15 | 20/62ms · 4.80 | 16/170ms · 4.92 | 21/200ms · 4.78 |
| 20 | 18/52ms · 6.36 | 16/86ms · 6.42 | 19/96ms · 6.57 |
| 25 | 18/69ms · 7.98 | 14/290ms · 7.94 | 19/110ms · 7.92 |

---

## Resultados — Testes Exaustivos (locustfile severo)

### C1 Exaustivo — Baseline · quebra: **75u** (2026-04-26)
| Users | p50 | p90 | p99 | Falhas% | RPS |
|---|---|---|---|---|---|
| 25 | 47ms | 130ms | 660ms | 0.0% | 71.8 |
| 50 | 160ms | 280ms | 1500ms | 0.0% | 88.1 |
| **75** | **330ms** | **520ms** | **1800ms** | **23.5%** | **100.4** |

### C2 Exaustivo — Seletivo · quebra: **50u — PIOR QUE C1** (2026-04-26)
| Users | p50 | p99 | Falhas% | RPS |
|---|---|---|---|---|
| 25 | 50ms | 460ms | 0.0% | 71.0 |
| **50** | **160ms** | **3700ms** | **27.9%** | **76.1** |

Réplicas extras sem tráfego (H6) consomem CPU/RAM do nó → deixam menos recursos para frontend/currencyservice.

### C3 Exaustivo — Uniforme · saturação: **~150u** (2026-04-26)
| Users | p50 | p99 | Falhas% | RPS |
|---|---|---|---|---|
| 25–125 | 20–310ms | 720–1300ms | 0.0–0.5% | 74.9–123.4 |
| 150 *(step-up)* | 350ms | 1500ms | 0.0% | 130.5 |
| **150 *(cold start)*** | **340ms** | **2500ms** | **0.0%** | **109.1 — QUEBRA** |

Step-up mantém conexões gRPC aquecidas; cold start é a medida mais honesta.

### C4 Exaustivo — Seletivo real · quebra: **25u — PIOR DE TODOS** (2026-04-26)
| Users | p50 | p99 | Falhas% | RPS |
|---|---|---|---|---|
| **25** | **6ms** | **2300ms** | **77.1%** | **66.8** |

Escalar frontend+currencyservice deslocou bottleneck para cartservice (115m CPU) e productcatalogservice. H6 de novo: réplica 3 do currencyservice ficou a 3m CPU.

### C5 Exaustivo — Envoy L7 · **sem quebra até 150u** (2026-05-05)
| Users | p50 | p90 | p99 | Falhas% | RPS |
|---|---|---|---|---|---|
| 25 | 12ms | 19ms | 45ms | 0.0% | 89.1 |
| 50 | 15ms | 50ms | 140ms | 0.0% | 116.6 |
| 75 | 53ms | 150ms | 540ms | 0.0% | 184.3 |
| 100 | 97ms | 240ms | 500ms | 0.0% | 201.7 |
| 125 | 150ms | 340ms | 720ms | 0.0% | 201.8 |
| 150 | 160ms | 380ms | 660ms | 0.0% | **218.7** |

**H6 resolvida:** productcatalogservice réplicas a 121m/121m/122m CPU (vs 91%/6%/3% no C3). Envoy: 481m CPU a 150u.  
Resultados em: `cenarios_ob_c5_exaustivo/`

---

## Comparação de pontos de saturação

| Cenário | +Comp. | Quebra | RPS máx. | Custo/req | CM_tp |
|---|---|---|---|---|---|
| **C1** Baseline | 0 | **75u** | 100.4 | 6.52 | — |
| **C2** Seletivo | +2 | **50u** | 76.1 | 10.87 | −12.15 RPS/rep |
| **C3** Uniforme | +20 | **~150u** | 130.5 (step-up) / 109.1 (cold) | 10.87 | +0.44 RPS/rep |
| **C4** Seletivo real | +4 | **25u ◄ pior** | 66.8 | — | −8.40 RPS/rep |
| **C5** Uniforme+Envoy | +20+Env | **>150u** | 218.7 | **5.34 (−18%)** | +5.63 RPS/comp |

**Amdahl:** C3 determina s=0.654 (tecto 1.53×); C5 determina s=0.188 (tecto 5.32×). Envoy reduziu fracção serial de 65% → 19%.

---

## Questões de investigação e Hipóteses

**RQ1:** Que serviços dominam a degradação à medida que a carga aumenta?  
**RQ2:** Escalar seletivamente melhora throughput/latência/falhas?  
**RQ3:** O ganho por réplica justifica o custo?  
**RQ4:** A eficácia do escalamento é condicionada por componentes stateful?

| H | Estado | Evidência resumida |
|---|---|---|
| H1 — Seletivo melhora parcialmente | ✅ Confirmado (parcialmente) | C2 melhora p50 comparativo mas quebra antes do C1 nos exaustivos |
| H2 — redis-cart emerge como limitação | ⬜ Inconclusivo | redis-cart: máx. 18m CPU a 150u (C5) — sem sinais de contenção |
| H3 — Rendimentos marginais decrescentes | ✅ Confirmado | C2 (+2 rep) degradou; C3 (+20) melhorou ~2×; C5 inverte com Envoy |
| H4 — Custo marginal crescente | ✅ Confirmado | C2/C4: CM negativo; C3: +67% custo/req; C5: −18% custo/req |
| H5 — Stateless mais escalável que stateful | ⬜ Inconclusivo | redis-cart não saturou nas cargas testadas |
| H6 — Connection affinity limita scale-out | ✅ Confirmado empiricamente | C2<C1; C5 (Envoy) resolve: 121m/121m/122m vs 91%/6%/3% |

---

## Definição operacional de custo marginal

```
CM_throughput = (RPS_cenário − RPS_C1) / componentes_adicionados
Custo proxy C = 0.5 × CPU_time + 0.5 × RAM_time
Custo por pedido = C / pedidos_com_sucesso
```

- `CPU_time` = média CPU (mcore/1000) × duração (s), somada por réplica
- `RAM_time` = média RAM (MiB) × duração (s), somada por réplica
- alpha=beta=0.5: escolha metodológica para índice relativo comparável entre cenários (não grandeza física)
- Dados: `cenarios_ob_*/monitoring/pods_metrics.csv` (timestamp, load_label, pod, cpu_m, ram_mi a cada 10s)

---

## Distinção metodológica

**Comparativo** (15/20/25u, locustfile realista): comparação controlada sub-saturação. Resultados em `cenarios_ob_c1comp/`, `cenarios_ob_c2/`, `cenarios_ob_c3/`  
**Exaustivo** (25→150u, locustfile severo): encontrar ponto de saturação. Resultados em `cenarios_ob_c*_exaustivo/`  
**Não misturar** — locustfiles diferentes, não comparáveis entre tipos.  
Testes exaustivos são **progressivos na mesma execução** (caches aquecidas, ligações persistentes) — não equivalentes a execuções independentes por nível.

---

## Estado atual do relatório

**Versão:** v5.0 — LaTeX ACM sigconf (`Diagramas/relatorio_final_asid.tex`, 858 linhas, 18 tabelas balanceadas)  
**Editado via:** Overleaf/Prism (grupo usa este sistema)

**Integrado no v5.0 (Eduardo + sessão 2026-05-05):**
- C4 e C5 na tabela de cenários
- Tabela C5 exaustivo (tab:c5ex) com 6 níveis
- Custo proxy e CM_tp para todos os cenários incluindo C5
- Amdahl com C5 (s=0.188, tecto 5.32×)
- Subsecção "C5 — Envoy como Prova de Conceito da Alternativa Arquitetural"
- RQ2, RQ3 atualizados; conclusões com C5; implicação arquitetural central reescrita
- Referências gRPC connection affinity em Kubernetes
- Linguagem suavizada (evidência sugere / consistente com / nas condições testadas)

**Estrutura do documento (atual):**
1. Introdução + RQs
2. Contexto e arquitetura (W1/W2/W3, tabela risco)
3. Decisão arquitetural + alternativas + trade-offs (P/A/D/C) — **vale 40%**
4. Desenho experimental (Locust, cenários, métricas, custo)
5. Resultados comparativos C1/C2/C3
6. Resultados exaustivos C1/C2/C3/C4/C5
7. Discussão (hipóteses, Amdahl, custo, atributos de qualidade)
8. Conclusões e trabalho futuro

---

## Feedback da professora (2026-05-04 — v4→v5)

**Pontos positivos:** RQs bem alinhadas, arquitetura correta, distinção cartservice/redis-cart, decisão arquitetural clara, resultado C2<C1 reconhecido como relevante.

**O que corrigir (maioria já corrigido no v5.0):**
- ✅ Linguagem prudente ("consistente com", "nas condições testadas")
- ✅ Distinguir observação / interpretação / hipótese
- ✅ Referência bibliográfica H6 (gRPC/HTTP2 Kubernetes)
- ✅ Justificar dois locustfiles (comparativo vs. exaustivo)
- ✅ Justificar parâmetros (warm-up, spawn rate, critério de quebra como operacional não SLA)
- ✅ Clarificar step-up progressivo vs. execuções independentes
- ✅ "Como se observa na Tabela X" antes das interpretações
- ✅ Distinção ΔRPS/ΔRéplicas vs. custo proxy
- ✅ **Faltam as figuras** — ainda pendente (ver todo list)

---

## Todo list

- [x] Executar C1/C2/C3 comparativos (2026-04-19)
- [x] Executar C1/C2/C3/C4 exaustivos (2026-04-26)
- [x] Implementar C5 com Envoy (2026-05-05)
- [x] Executar C5 exaustivo (2026-05-05) — estável >150u, 218.7 RPS
- [x] Atualizar relatorio_final_asid.tex com C5 completo
- [x] Referências bibliográficas gRPC/HTTP2
- [x] Linguagem suavizada + estrutura resultados/interpretação
- [ ] **Inserir figuras** (throughput vs carga, p99 vs carga, custo proxy — Figura 1/2/3 pedidas pela professora)
- [ ] **Repetir C1/C2/C3 ×3 a 25/50/75u → média ± desvio-padrão** (~80 min de testes)
- [ ] Calcular custo proxy com dados CSV completos (`monitoring/pods_metrics.csv`)
- [ ] Incluir/referenciar CSVs do Locust na submissão
- [ ] Confirmar no Jaeger ordem W3 (payment antes/depois de ship?)
- [ ] Preparar slides + demo funcional (semana 16-17)
- [ ] Auto-avaliação individual (1 pág/aluno) — deixar para o fim
- [ ] Anexo uso de IA — deixar para o fim

---

## Regras para o Claude Code

**NÃO inventar dados.** Todos os números são reais e validados. Nunca adicionar dados de execuções que não aconteceram.

**NÃO remover** a tabela chamada→dependências→risco — entregável obrigatório pedido pela professora.

**NÃO assumir GKE ou cloud.** Ambiente Docker Desktop local em Apple Silicon.

**Linguagem prudente nos bottlenecks.** "Candidato a bottleneck", "evidência sugere", "nas condições testadas". Exceção: H6 pode ser "confirmado empiricamente" (C2<C1 é evidência direta; C5 resolve estruturalmente).

**Cartservice ≠ Stateful.** É aplicacional stateless que depende do redis-cart (stateful).

**Locust, não k6.** A professora questionou k6.

**Template ACM LaTeX** (`Diagramas/relatorio_final_asid.tex`). Grupo usa Overleaf/Prism para editar.

**productcatalogservice não é o bottleneck real.** Escalar o productcatalogservice não resolve — evidência: C2<C1.

**C5/Envoy:** o Envoy resolveu H6 estruturalmente (LEAST_REQUEST + headless services). O paymentservice usa porta 50052 no Envoy (evitar colisão com shippingservice :50051). O emailservice usa listener :5000 → upstream :8080.

**Ligar sempre aos 4 atributos de qualidade.** Performance, Availability, Deployability, Cost — fundamentação arquitetural vale 40%.

**Análise estatística.** Incluir média ± desvio-padrão quando houver repetição.
