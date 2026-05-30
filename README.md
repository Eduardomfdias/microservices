# Projeto ASID 2025/2026 - Tema 2: Escalabilidade Horizontal e Custo Marginal em Microsserviços

Este repositório contém o código e os recursos utilizados para o projeto prático da unidade curricular de **Arquiteturas de Sistemas de Informação Distribuídos (ASID)**.

O sistema base utilizado é o [Online Boutique](https://github.com/GoogleCloudPlatform/microservices-demo) da Google Cloud, uma aplicação de demonstração de microsserviços *cloud-native*.

## Grupo de Trabalho
* PG61463
* PG47542
* PG58760
* PG58761

## Estrutura do Repositório

As modificações e adições feitas ao longo do projeto estão organizadas nas seguintes pastas principais:

* **`/docs/`**: Contém toda a documentação do projeto, incluindo o relatório final em LaTeX (`/docs/Diagramas/relatorio_final_asid.tex`) e a sua versão compilada em PDF.
* **`/Anexos/`**: Pasta com os resultados brutos de todas as experiências (`.csv` extraídos do Locust), organizados por cenário (C1 a C5). Esta pasta cumpre o requisito de disponibilização dos resultados.
* **`/scripts/`**: Scripts Python utilizados para gerar os gráficos presentes no relatório a partir dos ficheiros CSV.
* **`/manifests/`**: Ficheiros de configuração Kubernetes, incluindo as alterações necessárias para aplicar o *Horizontal Pod Autoscaling* (HPA) e a configuração do proxy Envoy L7.
* **`/src/loadgenerator/`**: Modificações no gerador de carga (Locust) para implementar os testes exaustivos e comparativos com *think times* agressivos.

## Resumo dos Cenários Testados

O projeto avaliou o impacto do escalamento horizontal e a viabilidade do balanceamento L7 através de 5 cenários experimentais:

* **C1 (Baseline)**: 1 réplica por serviço. Ponto de saturação: 75 utilizadores.
* **C2 (Escalamento Seletivo)**: `productcatalogservice` escalado para 3 réplicas. Demonstrou ineficácia devido à *connection affinity* do gRPC, quebrando a 50 utilizadores.
* **C3 (Escalamento Uniforme)**: Todos os serviços *stateless* escalados para 3 réplicas. Suportou 400 utilizadores sem quebras.
* **C4 (Escalamento Seletivo Real)**: Escalamento dos *bottlenecks* identificados no C1 (`frontend` e `currencyservice`). Suportou 400 utilizadores sem quebras e revelou-se a solução mais custo-eficiente.
* **C5 (Envoy Proxy L7)**: Introdução de um Proxy Envoy para balanceamento gRPC *per-request*. Resolveu o problema de *connection affinity* verificado no C2, atingindo distribuição perfeita de tráfego, embora com *overhead* de consumo de CPU.

Para consultar a análise detalhada, consulte o relatório disponível na pasta `/docs/`.
