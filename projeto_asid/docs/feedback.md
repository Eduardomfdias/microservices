# Feedbacks da Professora — Grupo 3

**Tema:** Escalabilidade Horizontal e Custo Marginal — Online Boutique  
**UC:** Arquiteturas de Sistemas de Informação Distribuídos (ASID) 2025/2026

---

## Semana 7 — Relatório Intermédio (1.ª versão)

### Avaliação Global

O documento mostra bastante trabalho: arquitetura bem identificada, workflows adequados, tabela de risco encaminhada, traces Jaeger e resultados preliminares C1/C2. O principal problema não é falta de trabalho — é a organização. O documento tenta ser ao mesmo tempo descrição da aplicação, análise arquitetural, guia de deployment, formulação de hipóteses e relatório de resultados, o que enfraquece a leitura.

### O que estava bem

- Arquitetura global corretamente identificada (frontend HTTP, serviços internos gRPC, Redis/cart)
- Workflows W1, W2, W3 adequados ao tema (fan-out elevado, interação com estado, fluxo transacional)
- Diagramas de sequência úteis e bem construídos
- Tabela de risco com valor e contributo para escolha de serviços-alvo
- Comparação C1/C2 já produzia resultados interessantes para discussão

### Problemas identificados

- Documento cresceu por acumulação sem reorganização — conteúdos repetidos e mal posicionados
- Pesos Locust misturados com descrição funcional dos endpoints — mistura de workload com arquitetura
- Secção "Deployment para Múltiplos Utilizadores" confusa — mistura de nota operacional com análise de escalabilidade
- Secção "Workload Crítico" mistura definição de carga, interpretação arquitetural e identificação de bottlenecks
- Cenários C1/C2 referenciados antes de serem definidos formalmente
- Hipóteses surgem demasiado cedo e sem questões de investigação estabelecidas
- Secção "Manifestos Kubernetes" desnecessária no corpo principal
- cartservice classificado como stateful ao mesmo nível do Redis — falta de rigor conceptual: o estado está no redis-cart, o cartservice é um serviço aplicacional que depende de um backend stateful partilhado

### Questões de investigação sugeridas

- RQ1: Que serviços tendem a dominar a degradação de desempenho nos workflows principais à medida que a carga aumenta?
- RQ2: Escalar seletivamente o serviço mais pressionado melhora de forma mensurável throughput, latência e taxa de falhas?
- RQ3: O ganho obtido ao acrescentar réplicas justifica o custo adicional, ou surgem rendimentos marginais decrescentes?
- RQ4: Até que ponto a eficácia da escalabilidade horizontal é condicionada pela natureza stateless dos serviços ou pela dependência de componentes stateful partilhados?

### Reformulação de hipóteses sugerida

- H1: Escalar seletivamente o productcatalogservice melhora parcialmente o sistema, mas pode não deslocar o ponto de quebra se outro bottleneck passar a dominar
- H2: Após aliviar pressão sobre productcatalogservice, cartservice/Redis tende a emergir como limitação mais visível nos workflows com estado
- H3: O ganho por réplica adicional tende a diminuir à medida que o bottleneck se desloca para outras dependências
- H4: O custo marginal tende a aumentar quando réplicas adicionais deixam de produzir ganhos proporcionais
- H5: A eficácia da escalabilidade horizontal é maior em serviços stateless do que com dependência de componente stateful partilhado
- H6 (exploratória): O balanceamento de carga entre réplicas do productcatalogservice pode não ser uniforme, limitando a eficácia do scale-out

### Custo marginal — orientação

Definir custo proxy como: `C = α · CPU_time + β · RAM_time`  
CPU_time = taxa média de CPU × duração do teste (em CPU-seconds)  
Calcular custo por pedido com sucesso para comparação entre cenários.  
A expressão `ΔRPS / ΔRéplicas` mede ganho de throughput por réplica, não custo marginal diretamente — deve ficar claro no texto.

### Estrutura sugerida para o relatório

1. Introdução — tema, motivação, sistema de referência, objetivo geral, questão central
2. Arquitetura relevante — diagrama global, serviços principais, componentes stateful
3. Workflows analisados — W1/W2/W3 com diagramas de sequência
4. Análise arquitetural orientada ao tema — tabela risco e serviços-alvo
5. Objetivos, questões e hipóteses
6. Metodologia experimental — workload, cenários, carga, métricas, custo marginal
7. Resultados preliminares — C1, C2 e comparação
8. Discussão — bottlenecks, hipóteses, custo marginal
9. Próximos passos

---

## Semana 9 — Relatório Intermédio (2.ª versão)

### Avaliação Global

Evolução clara face ao acompanhamento anterior. Estrutura mais clara, questão de investigação explicitada, cenários C1/C2/C3 identificados, workflows consolidados, definição operacional de custo marginal presente. O relatório continua a precisar de maior rigor metodológico e prudência analítica — passa demasiado depressa de indícios para conclusões fortes.

### Pontos fortes

- Estrutura global mais clara: RQs, decisão arquitetural, metodologia, resultados preliminares, custo marginal, próximos passos
- Distinção entre escalamento seletivo (C2) e uniforme (C3) bem alinhada com o tema
- Definição operacional de custo marginal apropriada para a fase
- Resultados preliminares de C1 úteis como referência quantitativa

### O que faltava fechar

- Relação entre objetivos → questões → hipóteses → cenários ainda não suficientemente explícita
- Execuções exploratórias vs. comparativas não distinguidas com rigor: step-up progressivo útil para saturação, mas comparação C1/C2/C3 deve usar cargas equivalentes e condições de arranque comparáveis
- Afirmações demasiado fortes para evidência parcial — "bottleneck confirmado" deve ser sustentado por métricas e traces detalhados
- Distinção stateful/stateless ainda com falta de precisão: cartservice não é stateful no mesmo sentido que Redis
- H6 (connection affinity gRPC) deve ser tratada como hipótese exploratória, não como explicação já estabilizada
- Falta tabela final de comparação por cenário: configuração, carga, throughput, p95/p99, falhas, CPU/memória, custo proxy

### Próximos passos indicados

- Estabilizar metodologia e executar C2 com recolha completa de métricas e traces
- Analisar C2 com cuidado antes de avançar para C3
- Executar C3 apenas depois de C2 estar compreendido
- Consolidar leitura comparativa C1/C2/C3
- Melhorar discussão final: resultados confirmados vs. inconclusivos vs. limitações
- Verificar Redis: kubectl top, kubectl describe, redis-cli INFO, SLOWLOG GET 20, LATENCY LATEST — correlacionar com níveis de carga do Locust

---

## Relatório Final

### Avaliação Global

O resultado mais interessante é precisamente não ser intuitivo: o scale-out seletivo do productcatalogservice não melhorou o comportamento global sob carga severa, enquanto o scale-out uniforme deslocou o ponto de degradação para cargas mais altas, mas com maior custo. A versão precisa de maior rigor metodológico, maior prudência analítica e linha de leitura mais clara. **Faltam as figuras.**

### O que estava bem

- Introdução e questões de investigação alinhadas com o tema
- Descrição arquitetural correta: distinção entre serviços stateless, backend stateful e workflows principais
- Distinção conceptual entre cartservice e redis-cart melhor formulada do que em versões anteriores
- Decisão arquitetural clara: scale-out seletivo vs. uniforme
- Secção de alternativas consideradas útil e com valor arquitetural

### Problemas de escrita e rigor

- Formulações demasiado assertivas: "confirmado" e "bottleneck dominante é X" exigem evidência robusta com repetições, comparação consistente e dados auditáveis
- Distinguir explicitamente observação empírica, interpretação plausível e hipótese explicativa
- A progressão do texto cria dispersão: alternativas (cache, service mesh, etc.) surgem antes do problema principal estar estabilizado

### Desenho experimental — problemas

- Existência de dois locustfiles com perfis distintos sem papel claramente separado e justificado
- Workload misto não suficientemente relacionado com W1/W2/W3 — falta explicitar que W1 é o principal driver de fan-out sobre productcatalogservice, W2 associado ao carrinho/estado, W3 o workflow transacional de maior complexidade
- Parâmetros experimentais (warm-up, janela de medição, spawn rate, critério de quebra) presentes mas sem justificação explícita
- Critério de quebra (p99 > 2000ms ou falhas > 5%) aceitável mas deve ser apresentado como definição operacional de saturação, não como SLA real
- Execução progressiva por níveis não é equivalente a comparação rigorosa: efeitos herdados (caches aquecidas, ligações persistentes) podem distorcer resultados em cargas mais altas
- Ficheiros CSV exportados pelo Locust não foram submetidos

### Leitura dos resultados

Conclusões válidas e relevantes:

- C1 funciona bem como baseline com degradação progressiva, quebra a 75 utilizadores
- C2 quebra mais cedo do que C1 (a 50 utilizadores) — scale-out seletivo mal direcionado pode ser prejudicial
- C3 desloca o ponto de degradação para cargas muito superiores, mas com custo muito mais elevado

A hipótese de connection affinity em gRPC/HTTP2 é plausível e compatível com a distribuição de CPU entre réplicas, mas deve ser apresentada como explicação fortemente sugerida pelos resultados, não como prova causal fechada. **Deve ser acompanhada de referência bibliográfica** — existe documentação técnica e literatura sobre balanceamento ineficaz em Kubernetes com gRPC/HTTP2 por ligações longas e multiplexadas.

A conclusão sobre frontend e currencyservice como bottleneck dominante deve ser tratada como leitura das condições testadas, não como verdade geral.

### O que pode ser estudado adicionalmente (dentro do tempo disponível)

- Mais evidência por réplica sobre distribuição de carga em gRPC/HTTP2, com repetição dos testes
- Um ou dois testes dirigidos a workflows específicos para isolar comportamento de W1 face a W2/W3
- Discussão mais profunda de alternativa não implementada: caching no productcatalogservice ou balanceamento ao nível do pedido via service mesh

### Custo marginal — ponto a rever

- Métrica composta CPU_time + RAM_time aceitável como proxy analítico, mas deve ficar claro que é um índice relativo, não grandeza física ou monetária direta
- Os pesos usados são escolha metodológica simplificadora — não têm significado físico direto
- `ΔRPS / ΔRéplicas` mede ganho de throughput por réplica, não custo marginal — a interpretação deve ficar mais clara ou distinguida da métrica proxy

### Apresentação dos resultados — problemas e sugestões

- Resultados e interpretações demasiado intercalados — dificulta leitura
- Tabelas não são introduzidas nem referenciadas no texto antes da interpretação
- Discussão começa antes de encaminhar o leitor para a tabela ou figura relevante
- Usar formulações do tipo "como se observa na Tabela X" ou "os resultados da Figura Y mostram que..."
- Separar explicitamente "resultados observados" de "interpretação"
- Evitar repetir a mesma leitura em várias secções

### Tabelas sugeridas para a versão final

- **Tabela A:** Configuração dos cenários — réplicas por serviço, workload, warm-up, medição, critério de quebra
- **Tabela B:** Resultados comparativos em cargas equivalentes (ex: 15/20/25 utilizadores)
- **Tabela C:** Resultados exaustivos e ponto de saturação
- **Figura 1:** Throughput vs. carga por cenário
- **Figura 2:** p99 vs. carga por cenário
- **Figura 3:** Proxy de custo ou custo por pedido com sucesso

### Estrutura sugerida para versão final

1. Introdução — problema, motivação, sistema de referência, decisão arquitetural, RQs
2. Contexto e arquitetura relevante — Online Boutique, W1/W2/W3, serviços-alvo
3. Decisão arquitetural em estudo — C1 baseline, C2 scale-out seletivo, C3 scale-out uniforme
4. Desenho experimental — ambiente, modelo de carga, cenários, métricas, critério de quebra, custo
5. Resultados — comparativos primeiro, exaustivos depois, com tabelas e figuras compactas
6. Discussão e alternativas arquiteturais — interpretação, trade-offs, limitações, ameaças à validade, alternativas não implementadas (HPA, caching, service mesh, vertical scaling)
7. Conclusão — resposta às RQs, mensagem arquitetural principal, trabalho futuro

---

## Sumário dos pontos críticos para a versão final

| Área | Ação necessária |
|------|----------------|
| Escrita | Substituir "confirmado" / "bottleneck dominante é X" por linguagem analítica e prudente |
| Figuras | Incluir todas as figuras — estavam ausentes no relatório final |
| CSVs | Submeter ficheiros CSV do Locust |
| Resultados | Separar observação de interpretação em blocos distintos |
| Tabelas | Introduzir cada tabela antes da sua interpretação; referenciar no texto |
| Workload | Relacionar explicitamente o workload misto com W1/W2/W3 |
| gRPC affinity | Adicionar referência bibliográfica que suporte a hipótese H6 |
| Custo marginal | Clarificar distinção entre ΔRPS/ΔRéplicas e custo proxy |
| Metodologia | Justificar parâmetros experimentais (warm-up, spawn rate, critério de quebra) |
| Comparação C1/C2/C3 | Usar cargas equivalentes e condições de arranque comparáveis para comparação rigorosa |

---

## Estado das tarefas — v5.1 (atualizado 2026-05-17)

### Correcções do feedback da professora

- [x] Linguagem prudente ("consistente com", "nas condições testadas", "evidência sugere")
- [x] Distinguir observação / interpretação / hipótese em blocos separados
- [x] Referência bibliográfica H6 (gRPC/HTTP2 connection affinity em Kubernetes)
- [x] Justificar dois locustfiles distintos (comparativo vs. exaustivo)
- [x] Justificar parâmetros experimentais (warm-up 30s, spawn 2u/s, critério de quebra como definição operacional não SLA)
- [x] Clarificar step-up progressivo vs. arranque a frio (nota metodológica incluída)
- [x] "Como se observa na Tabela X" introduzido antes das interpretações
- [x] Distinguir ΔRPS/ΔRéplicas (CM_tp) de custo proxy (CPU_time + RAM_time)
- [x] Figuras inseridas no LaTeX e PDFs gerados em `figuras/` (fig_throughput_vs_users, fig_p99_vs_users, fig_saturacao, fig_custo_pedido, fig_distribuicao_cpu_c2, fig_cpu_servicos)
- [x] C4 e C5 integrados no relatório (tabelas, custo, Amdahl, subsecção Envoy)

### Melhorias estruturais aplicadas (2026-05-17)

- [x] **Autores removidos do corpo** — bloco `\author` suprimido do `\maketitle`; nomes constam apenas na capa personalizada
- [x] **Tabelas uniformizadas** — eliminado `\resizebox` de todas as 7 tabelas afetadas; substituído por `tabularx` (colunas X para texto longo) ou `\footnotesize` (tabelas de 8+ colunas); fontes agora consistentes em todo o documento
- [x] **Anexo A — Inventário dos microserviços** adicionado: tabela com linguagem, porta, tipo e responsabilidade dos 11 serviços; referenciado na secção de Arquitetura
- [x] **Anexo B — Diagrama de dependências** adicionado: flowchart gerado com Mermaid CLI, PDF em `figuras/fig_dependencias.pdf`; caption explica candidatos a saturação (productcatalogservice por fan-out, redis-cart por contenção de estado)
- [x] **Anexo C — Diagramas de sequência W1/W2/W3** adicionados: PDFs gerados em `figuras/fig_seq_w1/w2/w3.pdf`; referenciados na secção de Workflows

### Tarefas ainda pendentes (por ordem de prioridade)

- [ ] **Repetir C1/C2/C3 ×3 a 25/50/75u** para calcular média ± desvio-padrão (~80 min de testes) — necessário para robustez estatística
- [x] **Submeter CSVs do Locust** junto com a entrega no Blackboard
- [x] Confirmar ordem de chamadas em W3 — **payment ANTES de shipping** (confirmado no código `checkoutservice/main.go` linhas 252/258: `chargeCard` → `shipOrder`). O diagrama de sequência W3 já refletia esta ordem corretamente.
- [ ] Preparar slides + demo funcional para apresentação oral (semana 16-17)
- [ ] Auto-avaliação individual (1 pág/aluno) — deixar para depois da entrega
- [ ] Anexo uso de IA — deixar para depois da entrega
