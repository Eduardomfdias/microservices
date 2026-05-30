DADOS EXPERIMENTAIS — ASID 2025/2026
Tema 2: Escalabilidade Horizontal e Custo Marginal em Microsserviços
Grupo: PG61463, PG47542, PG58760, PG58761

======================================================================
CONTEÚDO DESTA PASTA
======================================================================

Cada ficheiro CSV corresponde a uma execução independente (run) de um
cenário experimental, a um dado nível de carga. Nome do ficheiro:

    <CENÁRIO>_<RUN>_<UTILIZADORES>_locust_stats.csv

Exemplo: C1_run2_50u_locust_stats.csv
    → Cenário C1 (Baseline), execução 2, carga de 50 utilizadores

----------------------------------------------------------------------
FICHEIRO RESUMO
----------------------------------------------------------------------
_RESUMO_TODAS_EXECUCOES.csv
    Todas as 57 execuções numa só tabela, com colunas:
    cenario, run, utilizadores, rps, p50_ms, p90_ms, p99_ms,
    falhas_pct, pedidos_total, falhas_total

----------------------------------------------------------------------
CENÁRIOS
----------------------------------------------------------------------
C1 — Baseline (1 réplica por serviço)
    Execuções: run1, run2, run3
    Cargas: 25u, 50u, 75u  (quebra a 75u, média 23,0% falhas)

C2 — Seletivo (productcatalogservice ×3)
    Execuções: run1 (25u, 50u), run2 (25u, 50u, 75u), run3 (25u, 50u, 75u)
    Quebra média a 50u (9,3% falhas, critério >5%)

C3 — Uniforme (todos os serviços stateless ×3)
    Execuções run1/run2/run3: 25u, 50u, 75u (médias de 3 execuções)
    Execução progressiva única: 100u, 200u, 300u, 400u
    Sem quebra até 400u.

C4 — Seletivo Real (frontend ×3 + currencyservice ×3)
    Execuções: run1, run2, run3
    Cargas: 100u, 200u, 300u, 400u
    Sem quebra até 400u.

C5 — Uniforme ×3 + Proxy Envoy L7
    Execução progressiva única (n=1)
    Cargas: 25u, 50u, 75u, 100u, 125u, 150u
    Sem quebra até 150u.

----------------------------------------------------------------------
METODOLOGIA
----------------------------------------------------------------------
Ferramenta: Locust (Python)
Locustfile: perfil exaustivo (think times agressivos, ~72 RPS a 25u)
Critério de quebra: p99 > 2000 ms OU taxa de falhas > 5%
Warm-up: 30 s | Medição: 120 s por nível | Cooldown: 60 s
Hardware: MacBook Air M4, Apple Silicon ARM64, Docker Desktop Kubernetes

Cada "run" é uma execução independente com o cluster em estado limpo.
Os valores do relatório são médias das execuções disponíveis por
cenário e nível de carga.
