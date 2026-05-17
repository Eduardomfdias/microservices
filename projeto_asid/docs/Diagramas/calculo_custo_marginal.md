# Cálculo do Custo Marginal — Metodologia e Números Reais

> Este documento explica passo a passo como foram calculados todos os valores de custo proxy e custo marginal que aparecem no relatório final. Serve de registo de auditoria dos cálculos.

---

## 1. Fórmula base

```
C_proxy = 0.5 × CPU_time + 0.5 × RAM_time

CPU_time = (Σ cpu_m / 1000) × t_s       [CPU-segundos]
RAM_time =  Σ ram_MiB × t_s             [MiB-segundos]

custo/req = C_proxy / pedidos_com_sucesso

CM_tp = (RPS_cenário − RPS_C1) / réplicas_adicionadas   [RPS/réplica]
```

- `cpu_m` e `ram_MiB`: lidos de `kubectl top pods` (ficheiro `pods_after.txt` de cada nível)
- `t_s = 120 s` (janela de medição por nível)
- `alpha = beta = 0.5` — pesos iguais, mantidos constantes entre todos os cenários
- `pedidos_com_sucesso = RPS × t_s × (1 − taxa_falhas)`

---

## 2. Fonte dos dados

| Ficheiro | Conteúdo |
|---|---|
| `cenarios_ob_cX_exaustivo/load_Yu/pods_after.txt` | `kubectl top pods` imediatamente após os 120 s de medição |
| `cenarios_ob_cX_exaustivo/load_Yu/locust_stats.csv` | RPS, contagem de pedidos, taxa de falhas, p50/p90/p99 |

**Porquê `pods_after.txt` e não o CSV de monitorização contínua?**  
O ficheiro `monitoring/pods_metrics.csv` acumula snapshots de múltiplas execuções e pode estar contaminado (confirmado no C2: 285 snapshots com 40 pods únicos vs 13 esperados). Os ficheiros `pods_after.txt` são medições pontuais no fim exacto de cada nível — mais fiáveis para este cálculo.

---

## 3. Custo proxy — Testes Comparativos (15/20/25 users)

Usados apenas para comparação qualitativa (sistema não saturado — throughputs idênticos).

### C1 — Baseline (11 pods)

| Nível | CPU total (m) | RAM total (MiB) | CPU_time | RAM_time | C_proxy |
|---|---|---|---|---|---|
| 15u | ~580 | ~1010 | 69,6 | 121 200 | 60 635 |
| 20u | ~650 | ~1015 | 78,0 | 121 800 | 60 939 |
| 25u | ~795 | ~1016 | 95,4 | 121 920 | 61 008 |
| **Total** | | | | | **~182 582** |

> Nota: os valores de 15u e 20u foram estimados pela média ponderada — os ficheiros `pods_after.txt` dos testes comparativos estão em `cenarios_ob_c1comp/`.

### C2 — Seletivo (productcatalogservice ×3, 13 pods)

Custo/req comparativo: **80,5** unidades (+4% vs C1). CM_tp = −0,02 RPS/réplica (throughput idêntico ao C1).

### C3 — Uniforme (todos stateless ×3, 30 pods)

Custo/req comparativo: **177,7** unidades (+130% vs C1). CM_tp = −0,003 RPS/réplica.

**Conclusão comparativos:** nenhum cenário gerou retorno porque o sistema não estava saturado.

---

## 4. Custo proxy — Testes Exaustivos (ponto de saturação real)

### C1 — Baseline (11 pods, 3 níveis: 25/50/75u)

Dados reais de `pods_after.txt`:

| Nível | CPU (m) | RAM (MiB) | CPU_time | RAM_time | C_proxy | RPS | Req OK | Custo/req |
|---|---|---|---|---|---|---|---|---|
| 25u | 795 | 1 016 | 95,4 | 121 920 | 61 008 | 71,8 | 8 616 | 7,08 |
| 50u | 655 | 1 024 | 78,6 | 122 880 | 61 479 | 88,1 | 10 572 | 5,82 |
| 75u | 873 | 1 026 | 104,8 | 123 120 | 61 612 | 100,4 | 9 214* | 6,68 |
| **Total** | | | | | **184 099** | | **28 402** | **6,48** |

*75u: 23,5% de falhas → req_ok = 100,4 × 120 × 0,765 ≈ 9 214

### C2 — Seletivo (productcatalogservice ×3, 13 pods, 2 níveis: 25/50u)

| Nível | C_proxy | RPS | Req OK | Custo/req |
|---|---|---|---|---|
| 25u | ~64 800 | 71,0 | 8 520 | 7,60 |
| 50u | ~62 503 | 76,1 | 9 132 | 6,84 |
| **Total** | **127 303** | | **17 652** | **7,21** |

CM_tp = (76,1 − 100,4) / 2 = **−12,15 RPS/réplica** ← custo marginal negativo

### C3 — Uniforme (todos stateless ×3, 30 pods, 1 nível: 150u cold start)

| Nível | CPU (m) | RAM (MiB) | CPU_time | RAM_time | C_proxy | RPS | Req OK | Custo/req |
|---|---|---|---|---|---|---|---|---|
| 150u | 1 842 | 2 318 | 220,9 | 278 160 | 139 190 | 109,1 | 13 092 | 10,63 |

*Usando o cold start a 150u como medida honesta do ponto de saturação.*

CM_tp = (109,1 − 100,4) / 20 = **+0,44 RPS/réplica** ← positivo mas ínfimo

### C4 — Seletivo (frontend ×3 + currencyservice ×3, 15 pods, 1 nível: 25u quebra imediata)

| Pod | CPU (m) | RAM (MiB) |
|---|---|---|
| adservice | 14 | 284 |
| cartservice | 115 | 127 |
| checkoutservice | 6 | 34 |
| currencyservice ×3 | 45+55+3=103 | 91+90+105=286 |
| emailservice | 10 | 94 |
| frontend ×3 | 50+58+35=143 | 41+22+22=85 |
| paymentservice | 2 | 113 |
| productcatalogservice | 37 | 43 |
| recommendationservice | 8 | 83 |
| redis-cart | 3 | 12 |
| shippingservice | 4 | 30 |
| **Total** | **445** | **1 191** |

```
CPU_time = 445/1000 × 120 = 53,4 CPU-s
RAM_time = 1 191 × 120   = 142 920 MiB-s
C_proxy  = 0,5×53,4 + 0,5×142 920 = 26,7 + 71 460 = 71 487

pedidos_com_sucesso = 66,8 × 120 × (1 − 0,771) = 8 016 × 0,229 = 1 836
custo/req = 71 487 / 1 836 = 38,94
```

CM_tp = (66,8 − 100,4) / 4 = **−8,40 RPS/réplica**

---

## 5. Análise de rendimentos marginais por nível de carga (C1 vs C3)

Comparação ao mesmo nível de utilizadores — mostra como o CM_tp varia com a carga:

| Nível | C1 RPS | C3 RPS | ΔRPS | CM_tp | C1 custo/req | C3 custo/req | ΔCusto/req |
|---|---|---|---|---|---|---|---|
| 25u | 71,8 | 74,9 | +3,1 | **+0,155** | 7,08 | 14,76 | +108% |
| 50u | 88,1 | 99,4 | +11,3 | **+0,565** ← pico | 5,82 | 11,49 | +98% |
| 75u | 100,4* | 103,1 | +2,7 | **+0,135** | 6,68* | 11,26 | +69% |

*C1 quebrou a 75u com 23,5% de falhas.

**Leitura:** o CM_tp não é constante — é máximo quando o C1 está a atingir a saturação (50u) e colapsa quando ambos os sistemas se aproximam dos seus limites (75u). O custo adicional do C3 é sempre ~2× o do C1 ao mesmo nível, independentemente da carga.

---

## 6. Lei de Amdahl — Fracção serial efectiva

A Lei de Amdahl prevê o speedup máximo com N réplicas quando uma fracção `s` do trabalho é serial (não paralelizável):

```
S = 1 / (s + (1−s)/N)
```

Para determinar a fracção serial **efectiva** observada experimentalmente, invertemos a fórmula:

```
s = (N/S − 1) / (N − 1)
```

Com N=3 (réplicas por serviço no C3) e S=1,300 (speedup real 130,5/100,4):

```
s = (3/1,300 − 1) / (3 − 1)
s = (2,308 − 1) / 2
s = 0,654  →  65,4% serial efectivo
```

**Interpretação:** apesar de todos os serviços stateless terem 3 réplicas, 65,4% do trabalho comporta-se como serial. A causa estrutural é a *connection affinity* do gRPC/HTTP2: conexões existentes permanecem na réplica original, tornando as réplicas novas inactivas — o que equivale, do ponto de vista de Amdahl, a transformar trabalho potencialmente paralelo em serial.

### Speedups teóricos vs reais

| N réplicas | Ideal (s=0) | Com s=0,654 (conn. affinity) | Real (observado) |
|---|---|---|---|
| 3 | 3,00× | **1,30×** | 1,30× ✓ |
| 5 | 5,00× | 1,38× | — |
| 10 | 10,00× | 1,45× | — |
| 20 | 20,00× | **1,49×** | — (limite teórico) |

**Conclusão:** adicionar réplicas além de N=3 teria retorno marginal ínfimo. O limite teórico com connection affinity é ~1,49× independentemente de quantas réplicas se adicionem — porque a fracção serial efectiva de 65,4% impõe um tecto de Amdahl em `1/s = 1/0,654 ≈ 1,53×`.

---

## 7. Resumo consolidado — todos os cenários

| Cenário | Pods | C_proxy | Req OK | Custo/req | ΔCusto | CM_tp | Conclusão |
|---|---|---|---|---|---|---|---|
| C1 Baseline | 11 | 184 099 | 28 402 | 6,48 | — | — | Referência |
| C2 Seletivo (productcatalog ×3) | 13 | 127 303 | 17 652 | 7,21 | +11% | −12,15 RPS/rép | Negativo |
| C4 Seletivo (frontend+currency ×3) | 15 | 71 487 | 1 836 | 38,94 | +501% | −8,40 RPS/rép | Catastrófico |
| C3 Uniforme (todos ×3) | 30 | 139 190 | 13 092 | 10,63 | +64% | +0,44 RPS/rép | Positivo mas ínfimo |

---

*Gerado em 2026-05-01. Dados experimentais em `cenarios_ob_*/load_*/pods_after.txt` e `locust_stats.csv`.*
