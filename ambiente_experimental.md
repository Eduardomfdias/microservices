# Ambiente Experimental — ASID 2025/2026

## Hardware

| Atributo | Valor |
|---|---|
| Modelo | MacBook Air (2026) |
| Chip | Apple M4 (ARM64 / Apple Silicon) |
| Cores | 10 total — 4 Performance + 6 Efficiency |
| RAM | 16 GB |

## Docker Desktop — Kubernetes

| Atributo | Valor |
|---|---|
| Plataforma de virtualização | Docker Desktop (macOS) |
| Orquestrador | Kubernetes (built-in Docker Desktop) |
| Disco alocado ao Docker | 128 GB |
| CPU alocada ao nó Kubernetes | 10 cores (totalidade dos cores do M4) |
| RAM alocada ao nó Kubernetes | ~7.6 GB (~7836 MiB) |
| Tipo de cluster | Single-node |
| Namespace utilizado | `default` |

## Configuração dos Pods

| Atributo | Valor |
|---|---|
| `imagePullPolicy` | `Never` — imagens construídas e tagged localmente |
| `cartservice` memory limit | 512 MiB (aumentado face ao default de 128 MiB) |
| `cartservice` env var | `DOTNET_EnableWriteXorExecute=0` (fix bug JIT .NET em ARM64) |
| `loadgenerator` | 0 réplicas durante todos os testes (geração de carga via Locust externo) |

## Ferramenta de Carga

| Atributo | Valor |
|---|---|
| Ferramenta | Locust (Python) |
| Versão | instalada via pip em `~/Library/Python/3.9/bin/locust` |
| Perfis de utilizador | 3 (CasualUser, NormalUser, PowerUser) |
| URL alvo | `http://localhost` (frontend exposto via `NodePort`) |

### Perfis — Testes Comparativos (C1 / C2 / C3)

| Perfil | Peso | Think time | Comportamento |
|---|---|---|---|
| CasualUser | 30% | 5–15 s | browse, homepage, moeda |
| NormalUser | 50% | 2–6 s | browse, cart, checkout ocasional |
| PowerUser | 20% | 0.5–2 s | browse, cart, checkout frequente |

### Perfis — Testes Exaustivos (C1 / C2 / C3 exaustivo)

| Perfil | Peso | Think time | Comportamento |
|---|---|---|---|
| CasualUser | 20% | 0.5–1 s | browse, homepage, moeda |
| NormalUser | 50% | 0.2–0.5 s | browse, cart, checkout ocasional |
| PowerUser | 30% | 0.1–0.2 s | browse, cart, checkout frequente |

> Os testes exaustivos usam think times agressivos para encontrar o ponto de saturação do sistema. Os testes comparativos usam think times realistas para simular comportamento típico de e-commerce.

## Método de Execução

| Parâmetro | Testes Comparativos | Testes Exaustivos |
|---|---|---|
| Warm-up | 30 s | 30 s |
| Medição | 120 s | 120 s |
| Cooldown entre níveis | 60 s | 60 s |
| Spawn rate | 2 users/s | 2 users/s |
| Níveis de carga (comparativos) | 15, 20, 25 users | — |
| Níveis de carga (exaustivos) | — | 25, 50, 75, 100, 125, 150 users |
| Critério de quebra | — | p99 > 2000 ms OU falhas > 5% |

## Notas

- O M4 expõe os 10 cores ao nó Kubernetes. Em ambiente de produção real os pods teriam limites de recursos por nó muito mais apertados, o que reduziria significativamente a capacidade de carga do sistema.
- O fix `DOTNET_EnableWriteXorExecute=0` é obrigatório para o `cartservice` (.NET) em Apple Silicon — sem este fix o JIT do .NET causa crashes imediatos.
- O aumento do memory limit do `cartservice` de 128 MiB para 512 MiB foi necessário para evitar OOMKill sob carga, que causava 500 errors em cascata nos workflows W2 e W3.
