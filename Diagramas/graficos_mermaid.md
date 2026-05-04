# Gráficos ASID 2025/2026 — Mermaid

> Copiar cada bloco para https://mermaid.live → exportar PNG ou SVG → incluir no relatório.

---

## Gráfico 1 — Throughput vs. Carga (C1, C2, C3, C4)

```mermaid
xychart-beta
    title "Throughput vs. Carga — Testes Exaustivos"
    x-axis ["25u", "50u", "75u", "100u", "125u", "150u"]
    y-axis "Throughput (RPS)" 0 --> 140
    line [71.8, 88.1, 100.4, 0, 0, 0]
    line [71.0, 76.1, 0, 0, 0, 0]
    line [74.9, 99.4, 103.1, 124.2, 123.4, 130.5]
    line [66.8, 0, 0, 0, 0, 0]
```

> **Legenda (por ordem):** C1 (quebra a 75u) · C2 (quebra a 50u) · C3 (aguentou até 150u) · C4 (quebra a 25u — pior)
> Os zeros após a quebra indicam fim de execução — não zero RPS.

---

## Gráfico 2 — Latência p99 vs. Carga

```mermaid
xychart-beta
    title "Latência p99 (ms) vs. Carga — Testes Exaustivos"
    x-axis ["25u", "50u", "75u"]
    y-axis "p99 (ms)" 0 --> 4000
    line [660, 1500, 1800]
    line [460, 3700, 0]
    line [2300, 0, 0]
```

> **Legenda:** C1 · C2 (p99=3700ms a 50u, ultrapassa critério de 2000ms) · C4 (p99=2300ms já a 25u)
> Linha de referência critério de quebra: **2000 ms**

---

## Gráfico 3 — Ponto de Saturação por Cenário

```mermaid
xychart-beta
    title "Ponto de Saturação por Cenário (utilizadores até quebra)"
    x-axis ["C4 (+4 rép.)", "C2 (+2 rép.)", "C1 (baseline)", "C3 (+20 rép.)"]
    y-axis "Utilizadores até quebra" 0 --> 160
    bar [25, 50, 75, 150]
```

> C4 é o pior (25u), C2 pior que o baseline (50u < 75u), C3 o melhor (~150u).

---

## Gráfico 4 — Custo Proxy por Pedido — Testes Exaustivos

```mermaid
xychart-beta
    title "Custo Proxy por Pedido — Testes Exaustivos (índice relativo)"
    x-axis ["C1 (ref.)", "C2 +30%", "C3 +67%", "C4 +498%"]
    y-axis "Custo proxy / pedido (u.r.)" 0 --> 42
    bar [6.52, 8.47, 10.87, 38.96]
```

> C4 tem custo 6× superior ao C2 e ~40× superior ao C1 — 77,1% de falhas colapsam o denominador.

---

## Gráfico 5 — Distribuição de CPU entre Réplicas (C2 — connection affinity H6)

```mermaid
xychart-beta
    title "CPU por Réplica — productcatalogservice em C2 a 25u (millicores)"
    x-axis ["Réplica #1 (original)", "Réplica #2 (nova)", "Réplica #3 (nova)"]
    y-axis "CPU (millicores)" 0 --> 100
    bar [92, 1, 1]
```

> Réplica original absorve 97,9% do tráfego. As novas réplicas ficam quase inativas — evidência de connection affinity gRPC/HTTP2 (H6).

---

## Gráfico 6 — CPU por Serviço no Ponto de Saturação — C1 (75u, baseline)

```mermaid
xychart-beta
    title "CPU por Serviço — C1 a 75 utilizadores (ponto de quebra)"
    x-axis ["frontend", "recommend.", "currency", "productcatalog", "cartservice", "checkout", "adservice", "shipping", "payment", "redis-cart"]
    y-axis "CPU (millicores)" 0 --> 210
    bar [199, 200, 173, 90, 86, 23, 55, 17, 9, 8]
```

> frontend, recommendationservice e currencyservice são os mais pressionados. productcatalogservice (90m) é muito chamado mas rápido.

---

## Gráfico 7 — CPU por Serviço — C2 a 50u (ponto de quebra)

```mermaid
xychart-beta
    title "CPU por Serviço — C2 a 50 utilizadores (ponto de quebra)"
    x-axis ["frontend", "recommend.", "currency", "productcatalog*", "cartservice", "checkout", "adservice", "shipping", "payment", "redis-cart"]
    y-axis "CPU (millicores)" 0 --> 210
    bar [199, 199, 174, 94, 104, 27, 48, 18, 9, 8]
```

> *productcatalog total = 92m (#1) + 1m (#2) + 1m (#3). O escalamento não ajudou — os bottlenecks reais são frontend/currencyservice.

---

## Gráfico 8 — CPU por Serviço — C3 a 150u (total por serviço, 3 réplicas)

```mermaid
xychart-beta
    title "CPU por Serviço — C3 a 150 utilizadores (total 3 réplicas)"
    x-axis ["frontend", "recommend.", "currency", "productcatalog", "cartservice", "checkout", "adservice", "shipping", "payment", "redis-cart"]
    y-axis "CPU (millicores)" 0 --> 490
    bar [482, 276, 330, 207, 159, 39, 102, 32, 15, 13]
```

> Escalamento uniforme distribui a carga. redis-cart permanece baixo (13m) mesmo a 150u.

---

## Gráfico 9 — CPU por Serviço — C4 a 25u (ponto de quebra)

```mermaid
xychart-beta
    title "CPU por Serviço — C4 a 25 utilizadores (ponto de quebra)"
    x-axis ["cartservice", "frontend*", "currency*", "productcatalog", "recommend.", "adservice", "email", "checkout", "shipping", "payment", "redis-cart"]
    y-axis "CPU (millicores)" 0 --> 145
    bar [115, 143, 103, 37, 8, 14, 10, 6, 4, 2, 3]
```

> *frontend e currencyservice foram escalados para ×3 (totais: 143m e 103m).
> cartservice (115m, 1 réplica) torna-se o novo bottleneck — efeito cascata.

---

## Gráfico 10 — Comparação Custo Marginal de Throughput (CMₜₕ)

```mermaid
xychart-beta
    title "Custo Marginal de Throughput (RPS por réplica adicional)"
    x-axis ["C2 (+2 rép.)", "C4 (+4 rép.)", "C3 (+20 rép.)"]
    y-axis "CMtp (RPS / réplica)" -14 --> 2
    bar [-12.15, -8.40, 0.44]
```

> C2 e C4 têm CMₜₕ negativo — cada réplica adicional reduziu o throughput. C3 é o único com CMₜₕ positivo.

---

## Gráfico 11 — Latência p50 Comparativo (15/20/25 users)

```mermaid
xychart-beta
    title "Latência p50 (ms) — Testes Comparativos"
    x-axis ["15u", "20u", "25u"]
    y-axis "p50 (ms)" 0 --> 25
    line [20, 18, 18]
    line [16, 16, 14]
    line [21, 19, 19]
```

> **Legenda:** C1 · C2 · C3
> C2 tem melhor mediana a 25u (14ms, −22% face ao C1) — efeito das novas conexões a réplicas com menos carga.

---

## Gráfico 12 — Speedup Real vs. Teórico (Lei de Amdahl, s=0.654)

```mermaid
xychart-beta
    title "Speedup: Ideal vs. Amdahl (s=0.654) vs. Real"
    x-axis ["N=1", "N=3", "N=5", "N=10", "N=20"]
    y-axis "Speedup" 0 --> 5.5
    line [1.0, 3.0, 5.0, 10.0, 20.0]
    line [1.0, 1.30, 1.38, 1.45, 1.49]
```

> **Legenda:** Ideal (s=0) · Com s=0,654 (fração serial efetiva observada)
> O speedup real com N=3 réplicas foi 1,30× — idêntico ao previsto por Amdahl com s=0,654.

---

## Notas de exportação

Para exportar cada gráfico:
1. Ir a **https://mermaid.live**
2. Colar o bloco de código (sem as ``` )
3. Clicar em **Actions → Download PNG** (ou SVG para qualidade vetorial)
4. Renomear o ficheiro e inserir no relatório LaTeX com `\includegraphics`

**Alternativa:** Notion, Obsidian e GitHub renderizam Mermaid nativamente — copiar o bloco completo incluindo as ```.
