import os

file_path = "/Users/edias/Documents/Mestrado /1º Ano - 2º Semestre/Arquiteturas de Sistemas de Informação Distribuídos/Trabalho Pratico /microservices-demo-main/microservices/projeto_asid/docs/Diagramas/relatorio_final_asid.tex"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

replacements = [
    (
        r"A escalabilidade horizontal — adicionar réplicas de serviços em vez de aumentar os recursos de uma instância — é uma das promessas centrais das arquiteturas de microserviços.",
        r"A escalabilidade horizontal, ou seja, adicionar réplicas de serviços em vez de aumentar os recursos de uma instância, é uma das promessas centrais das arquiteturas de microserviços."
    ),
    (
        r"O \textbf{escalamento horizontal} (\textit{scale-out}) — adicionar réplicas em vez de aumentar recursos de uma instância — é a estratégia preferida porque não tem teto físico e aumenta a disponibilidade. Porém, a Lei de Amdahl~\cite{amdahl} quantifica um limite fundamental: se uma fração $s$ do trabalho é serial, o speedup máximo é $1/s$, independentemente do número de réplicas. Neste estudo, derivou-se empiricamente $s \approx 0{,}654$ (Secção~\ref{subsec:amdahl}), imposta pelo protocolo de comunicação — não apenas pelo código.",
        r"O \textbf{escalamento horizontal} (\textit{scale-out}), que consiste em adicionar réplicas em vez de aumentar recursos de uma instância, é a estratégia preferida porque não tem teto físico e aumenta a disponibilidade. Porém, a Lei de Amdahl~\cite{amdahl} quantifica um limite fundamental: se uma fração $s$ do trabalho é serial, o speedup máximo é $1/s$, independentemente do número de réplicas. Neste estudo, derivou-se empiricamente $s \approx 0{,}654$ (Secção~\ref{subsec:amdahl}), imposta pelo protocolo de comunicação, e não apenas pelo código."
    ),
    (
        r"Ao contrário do HTTP/1.1, onde cada pedido pode ser roteado independentemente, os pedidos gRPC partilham conexões de longa duração — o balanceamento de carga ao nível TCP (L4) distribui conexões, não pedidos.",
        r"Ao contrário do HTTP/1.1, onde cada pedido pode ser roteado independentemente, os pedidos gRPC partilham conexões de longa duração, uma vez que o balanceamento de carga ao nível TCP (L4) distribui conexões, não pedidos."
    ),
    (
        r"sem observabilidade, a seleção do candidato a bottleneck teria de assentar em suposições arquiteturais — exatamente o que levou o C4 a falhar.",
        r"sem observabilidade, a seleção do candidato a bottleneck teria de assentar em suposições arquiteturais, exatamente o que levou o C4 a falhar."
    ),
    (
        r"A \textbf{Amazon} opera com escalamento por serviço independente, mas enfatiza que o escalamento de um serviço aumenta a carga nos seus dependentes — exatamente o efeito cascata observado no C4 deste estudo.",
        r"A \textbf{Amazon} opera com escalamento por serviço independente, mas enfatiza que o escalamento de um serviço aumenta a carga nos seus dependentes, reproduzindo exatamente o efeito cascata observado no C4 deste estudo."
    ),
    (
        r"A arquitetura segue o padrão \textit{Database-per-Service} — apenas o \texttt{redis-cart} mantém estado persistente.",
        r"A arquitetura segue o padrão \textit{Database-per-Service}, onde apenas o \texttt{redis-cart} mantém estado persistente."
    ),
    (
        r"O inventário completo dos 11 microserviços — linguagem, porta, tipo e responsabilidade — encontra-se no Anexo~\ref{apx:inventario} (Tabela~\ref{tab:inventario}).",
        r"O inventário completo dos 11 microserviços, detalhando linguagem, porta, tipo e responsabilidade, encontra-se no Anexo~\ref{apx:inventario} (Tabela~\ref{tab:inventario})."
    ),
    (
        r"desencadeia 6 chamadas gRPC paralelas ao \texttt{productcatalogservice} por pedido — confirmado com traces Jaeger.",
        r"desencadeia 6 chamadas gRPC paralelas ao \texttt{productcatalogservice} por pedido, conforme confirmado com traces Jaeger."
    ),
    (
        r"o \texttt{checkoutservice} orquestra 6 serviços em sequência — a latência total é a soma das latências individuais, sem paralelismo.",
        r"o \texttt{checkoutservice} orquestra 6 serviços em sequência, pelo que a latência total é a soma das latências individuais, sem paralelismo."
    ),
    (
        r"A escolha entre estas estratégias tem impacto direto nos quatro atributos de qualidade em avaliação — \textbf{Performance}, \textbf{Availability}, \textbf{Deployability} e \textbf{Cost}.",
        r"A escolha entre estas estratégias tem impacto direto nos quatro atributos de qualidade em avaliação: \textbf{Performance}, \textbf{Availability}, \textbf{Deployability} e \textbf{Cost}."
    ),
    (
        r"O gRPC usa conexões persistentes e multiplexadas — uma vez estabelecida uma conexão a uma réplica, todos os pedidos nessa conexão continuam a ir para a mesma réplica.",
        r"O gRPC usa conexões persistentes e multiplexadas. Uma vez estabelecida uma conexão a uma réplica, todos os pedidos nessa conexão continuam a ir para a mesma réplica."
    ),
    (
        r"\textbf{Service mesh com balanceamento por pedido (Istio/Linkerd).} Um \textit{service mesh}~\cite{servicemesh} introduz um proxy \textit{sidecar} (ex: Envoy) em cada pod, funcionando como middleware acima do Kubernetes ao nível L7. Este middleware intercepta todo o tráfego gRPC e substitui o balanceamento por conexão por balanceamento por pedido (\textit{round-robin} ou \textit{least-connections}), resolvendo estruturalmente a \textit{connection affinity} identificada em H6~\cite{k8sgrpc}. Impacto nos atributos de qualidade: melhoria substancial de \textbf{Performance} ao distribuir carga uniformemente — as réplicas novas passariam a receber tráfego imediatamente, sem aguardar novas conexões; melhoria de \textbf{Availability} com \textit{circuit breaking}, \textit{retry} automático e deteção de réplicas degradadas; aumento significativo de complexidade operacional (\textbf{Deployability}) — o service mesh adiciona um componente de infraestrutura com a sua própria curva de aprendizagem, configuração e potencial de falha; overhead de CPU/memória do sidecar ($\sim$20--50~m por pod) impacta o \textbf{Cost}. Esta é a alternativa não implementada com maior potencial para resolver o problema central identificado neste estudo.",
        r"\textbf{Service mesh com balanceamento por pedido (Istio/Linkerd).} Um \textit{service mesh}~\cite{servicemesh} introduz um proxy \textit{sidecar} (ex: Envoy) em cada pod, funcionando como middleware acima do Kubernetes ao nível L7. Este middleware intercepta todo o tráfego gRPC e substitui o balanceamento por conexão por balanceamento por pedido (\textit{round-robin} ou \textit{least-connections}), resolvendo estruturalmente a \textit{connection affinity} identificada em H6~\cite{k8sgrpc}. Impacto nos atributos de qualidade: melhoria substancial de \textbf{Performance} ao distribuir carga uniformemente, fazendo com que as réplicas novas passem a receber tráfego imediatamente, sem aguardar novas conexões; melhoria de \textbf{Availability} com \textit{circuit breaking}, \textit{retry} automático e deteção de réplicas degradadas; aumento significativo de complexidade operacional (\textbf{Deployability}), dado que o service mesh adiciona um componente de infraestrutura com a sua própria curva de aprendizagem, configuração e potencial de falha; overhead de CPU/memória do sidecar ($\sim$20--50~m por pod) impacta o \textbf{Cost}. Esta é a alternativa não implementada com maior potencial para resolver o problema central identificado neste estudo."
    ),
    (
        r"Todos os \textit{deployments} usam \texttt{imagePullPolicy: Never} — imagens construídas e \textit{tagged} localmente.",
        r"Todos os \textit{deployments} usam \texttt{imagePullPolicy: Never}, sendo as imagens construídas e \textit{tagged} localmente."
    ),
    (
        r"A 25 utilizadores gera $\approx$8~RPS — insuficiente para saturar o sistema.",
        r"A 25 utilizadores gera $\approx$8~RPS, o que se revela insuficiente para saturar o sistema."
    ),
    (
        r"As inferências sobre throughput máximo sustentável e custo por pedido provêm exclusivamente do segundo perfil. \textbf{Os resultados dos dois conjuntos de testes não são diretamente comparáveis entre si} — locustfiles diferentes, objetivos diferentes.",
        r"As inferências sobre throughput máximo sustentável e custo por pedido provêm exclusivamente do segundo perfil. \textbf{Os resultados dos dois conjuntos de testes não são diretamente comparáveis entre si}, devido à utilização de locustfiles diferentes e objetivos distintos."
    ),
    (
        r"O critério de quebra (p99~>~2000~ms OU falhas~>~5\%) é um limiar operacional consistente para identificar degradação severa e tornar comparável o ponto de rutura entre cenários — não representa um Service Level Agreement real da aplicação.",
        r"O critério de quebra (p99~>~2000~ms OU falhas~>~5\%) é um limiar operacional consistente para identificar degradação severa e tornar comparável o ponto de rutura entre cenários, não representando um Service Level Agreement real da aplicação."
    ),
    (
        r"Throughput (RPS), latências p50/p90/p99 e taxa de falhas — exportados pelo Locust em CSV.",
        r"Throughput (RPS), latências p50/p90/p99 e taxa de falhas foram exportados pelo Locust em CSV."
    ),
    (
        r"\textbf{Leitura:} o C2 adicionou 2 réplicas e aumentou o custo por pedido apenas 4\% — mas sem qualquer ganho de throughput ($CM_{tp}=-0{,}02$~RPS/réplica). O C3 adicionou 20 réplicas (+182\% de pods) e o custo por pedido subiu 130\% — com throughput marginalmente inferior ao C1 ($CM_{tp}=-0{,}003$~RPS/réplica).",
        r"\textbf{Leitura:} o C2 adicionou 2 réplicas e aumentou o custo por pedido apenas 4\%, mas sem qualquer ganho de throughput ($CM_{tp}=-0{,}02$~RPS/réplica). O C3 adicionou 20 réplicas (+182\% de pods) e o custo por pedido subiu 130\%, com throughput marginalmente inferior ao C1 ($CM_{tp}=-0{,}003$~RPS/réplica)."
    ),
    (
        r"\textbf{Throughput:} praticamente idêntico nos 3 cenários ($\approx$7,9--8,0~RPS a 25 utilizadores). O escalamento não produz ganho de throughput porque o sistema não está saturado — resultado consistente com H3 e H4 nesta gama de carga.",
        r"\textbf{Throughput:} praticamente idêntico nos 3 cenários ($\approx$7,9--8,0~RPS a 25 utilizadores). O escalamento não produz ganho de throughput porque o sistema não está saturado, o que se revela um resultado consistente com H3 e H4 nesta gama de carga."
    ),
    (
        r"\textbf{Latência cauda (p99):} o C1 tem os melhores p99. O C2 e C3 mostram picos mais altos (290~ms e 110~ms vs.\ 69~ms no C1 a 25u) — padrão consistente com réplicas novas menos ``aquecidas'' (JIT não otimizado, caches frias) e com a hipótese de H6.",
        r"\textbf{Latência cauda (p99):} o C1 tem os melhores p99. O C2 e C3 mostram picos mais altos (290~ms e 110~ms vs.\ 69~ms no C1 a 25u), padrão que se revela consistente com réplicas novas menos ``aquecidas'' (JIT não otimizado, caches frias) e com a hipótese de H6."
    ),
    (
        r"Como se observa na Tabela~\ref{tab:cpu}, a distribuição de CPU no C2 revela: \texttt{productcatalogservice} \#1: 31m | \#2: 2m | \#3: 1m — distribuição de 91\%/6\%/3\%. As duas réplicas novas ficaram praticamente inativas porque as conexões HTTP/2 existentes permaneceram na réplica original — observação fortemente sugerida pela hipótese H6 (\textit{connection affinity} gRPC/HTTP2).",
        r"Como se observa na Tabela~\ref{tab:cpu}, a distribuição de CPU no C2 revela: \texttt{productcatalogservice} \#1: 31m | \#2: 2m | \#3: 1m, com uma distribuição de 91\%/6\%/3\%. As duas réplicas novas ficaram praticamente inativas porque as conexões HTTP/2 existentes permaneceram na réplica original, numa observação fortemente sugerida pela hipótese H6 (\textit{connection affinity} gRPC/HTTP2)."
    ),
    (
        r"  \caption{Distribuição de CPU entre as 3 réplicas do \texttt{productcatalogservice} em C2 a 25u. A réplica original absorve 97,9\% do tráfego — evidência empírica da \textit{connection affinity} gRPC/HTTP2 (H6).}",
        r"  \caption{Distribuição de CPU entre as 3 réplicas do \texttt{productcatalogservice} em C2 a 25u. A réplica original absorve 97,9\% do tráfego, servindo de evidência empírica da \textit{connection affinity} gRPC/HTTP2 (H6).}"
    ),
    (
        r"O \texttt{frontend} é o único serviço que distribui bem a carga em C3 ($\sim$16m+17m+16m), porque recebe conexões HTTP/1.1 externas — sem persistência HTTP/2, cada pedido pode ser roteado independentemente.",
        r"O \texttt{frontend} é o único serviço que distribui bem a carga em C3 ($\sim$16m+17m+16m), porque recebe conexões HTTP/1.1 externas, pelo que, sem persistência HTTP/2, cada pedido pode ser roteado independentemente."
    ),
    (
        r"  \item \textbf{Connection affinity do gRPC/HTTP2:} as réplicas novas do \texttt{productcatalogservice} receberam 2m e 1m de CPU (vs.\ 31m da réplica original) — distribuição de 91\%/6\%/3\%.",
        r"  \item \textbf{Connection affinity do gRPC/HTTP2:} as réplicas novas do \texttt{productcatalogservice} receberam 2m e 1m de CPU (vs.\ 31m da réplica original), refletindo uma distribuição de 91\%/6\%/3\%."
    ),
    (
        r"Esta implementação é uma versão simplificada do service mesh descrito na Secção~\ref{sec:metodologia} — sem injeção de sidecar nem control plane, mas com o mesmo mecanismo fundamental: substituir balanceamento por conexão por balanceamento por pedido.",
        r"Esta implementação é uma versão simplificada do service mesh descrito na Secção~\ref{sec:metodologia}, ou seja, sem injeção de sidecar nem control plane, mas com o mesmo mecanismo fundamental: substituir balanceamento por conexão por balanceamento por pedido."
    ),
    (
        r"O ganho de 218,7~RPS (C5) vs 109,1~RPS (C3 arranque a frio) — um factor de 2,0× — com o mesmo número de réplicas é evidência directa de que a \textit{connection affinity} era o factor limitante dominante, não a capacidade de computação agregada.",
        r"O ganho de 218,7~RPS (C5) vs 109,1~RPS (C3 arranque a frio), correspondente a um factor de 2,0× com o mesmo número de réplicas, é evidência directa de que a \textit{connection affinity} era o factor limitante dominante, não a capacidade de computação agregada."
    ),
    (
        r"\textbf{Availability:} o C3 distribui a redundância por todos os serviços \textit{stateless}, eliminando pontos únicos de falha ao nível aplicacional. O \texttt{redis-cart} permanece como único ponto de falha em todos os cenários — limitação estrutural da arquitetura atual.",
        r"\textbf{Availability:} o C3 distribui a redundância por todos os serviços \textit{stateless}, eliminando pontos únicos de falha ao nível aplicacional; o \texttt{redis-cart} permanece como único ponto de falha em todos os cenários, limitando estruturalmente a arquitetura atual."
    ),
    (
        r"\textbf{Deployability:} o escalamento seletivo exige identificação prévia do bottleneck (tracing, análise de CPU por réplica), o que requer instrumentação e capacidade de observabilidade. O escalamento uniforme é operacionalmente mais simples mas implica gestão de mais réplicas.",
        r"\textbf{Deployability:} o escalamento seletivo exige identificação prévia do bottleneck (tracing, análise de CPU por réplica), o que requer instrumentação e capacidade de observabilidade; o escalamento uniforme é operacionalmente mais simples, mas implica a gestão de mais réplicas."
    ),
    (
        r"\textbf{Cost:} os dois cálculos de custo proxy (Tabelas~\ref{tab:custo} e~\ref{tab:custo-exaustivo}) contam histórias complementares. Nos testes comparativos (sistema não saturado), nenhum cenário gerou retorno. Nos testes exaustivos, o C2 tem $CM_{tp}=-12{,}15$~RPS/réplica e o C4 tem $CM_{tp}=-8{,}40$~RPS/réplica — ambos com custo marginal negativo. O C4 é o caso extremo: custo por pedido de 38,96 unidades (498\% acima do C1) porque a taxa de 77,1\% de falhas colapsa o denominador de pedidos com sucesso. O único cenário com $CM_{tp}$ positivo é o C3 ($+0{,}44$~RPS/réplica), mas com custo por pedido 67\% superior ao C1. O RAM\_time domina em todos os casos porque réplicas inativas ocupam memória sem processar pedidos. A conclusão é inequívoca: em sistemas gRPC sem balanceamento ao nível de pedido, o escalamento horizontal simples apresenta custo marginal crescente e tende a ser negativo nos cenários seletivos.",
        r"\textbf{Cost:} os dois cálculos de custo proxy (Tabelas~\ref{tab:custo} e~\ref{tab:custo-exaustivo}) contam histórias complementares. Nos testes comparativos (sistema não saturado), nenhum cenário gerou retorno. Nos testes exaustivos, o C2 tem $CM_{tp}=-12{,}15$~RPS/réplica e o C4 tem $CM_{tp}=-8{,}40$~RPS/réplica, apresentando ambos um custo marginal negativo. O C4 é o caso extremo: custo por pedido de 38,96 unidades (498\% acima do C1) porque a taxa de 77,1\% de falhas colapsa o denominador de pedidos com sucesso. O único cenário com $CM_{tp}$ positivo é o C3 ($+0{,}44$~RPS/réplica), mas com custo por pedido 67\% superior ao C1. O tempo de RAM domina em todos os casos, já que réplicas inativas ocupam memória sem processar pedidos. A conclusão é inequívoca: em sistemas gRPC, o escalamento horizontal simples apresenta custo marginal crescente e tende a ser negativo nos cenários seletivos."
    ),
    (
        r"O \texttt{redis-cart} manteve-se abaixo de 15~m em todos os níveis — sem sinais de contenção stateful nas cargas testadas.",
        r"O \texttt{redis-cart} manteve-se abaixo de 15~m em todos os níveis, não apresentando sinais de contenção stateful nas cargas testadas."
    ),
    (
        r"As réplicas adicionais do \texttt{productcatalogservice} absorveram apenas 2\% do tráfego (97,9\% permaneceu na réplica original — Figura~\ref{fig:distrib-cpu}), mas consumiram RAM e CPU do nó, degradando os serviços realmente pressionados.",
        r"As réplicas adicionais do \texttt{productcatalogservice} absorveram apenas 2\% do tráfego (97,9\% permaneceu na réplica original, conforme ilustrado na Figura~\ref{fig:distrib-cpu}), mas consumiram RAM e CPU do nó, degradando os serviços realmente pressionados."
    ),
    (
        r"A fração serial efetiva de 65\% (Lei de Amdahl) mostra que o teto teórico é $\approx$1,53$\times$ — próximo do observado (1,30$\times$).",
        r"A fração serial efetiva de 65\% (Lei de Amdahl) mostra que o teto teórico é $\approx$1,53$\times$, valor muito próximo do observado (1,30$\times$)."
    ),
    (
        r"O pior resultado: quebra a 25u com 77,1\% de falhas. Escalar o \texttt{frontend} (ponto de entrada HTTP/1.1) triplicou as conexões gRPC nos backends não escalados: o \texttt{cartservice} atingiu 115~m de CPU (Figura~\ref{fig:cpu-servicos}), tornando-se o novo bottleneck. O C4 demonstra que identificar os serviços mais pressionados em métricas de CPU não é suficiente — é necessário escalar toda a cadeia de dependências.",
        r"O pior resultado: quebra a 25u com 77,1\% de falhas. Escalar o \texttt{frontend} (ponto de entrada HTTP/1.1) triplicou as conexões gRPC nos backends não escalados: o \texttt{cartservice} atingiu 115~m de CPU (Figura~\ref{fig:cpu-servicos}), tornando-se o novo bottleneck. O C4 demonstra que identificar os serviços mais pressionados em métricas de CPU não é suficiente, sendo necessário escalar toda a cadeia de dependências."
    ),
    (
        r"A fracção serial efectiva (Lei de Amdahl) baixou de 65\% (C3) para 19\% (C5), elevando o tecto teórico de 1,53$\times$ para 5,32$\times$. O C5 confirma que a \textit{connection affinity} era o factor limitante dominante — não a capacidade de computação agregada.",
        r"A fracção serial efectiva (Lei de Amdahl) baixou de 65\% (C3) para 19\% (C5), elevando o tecto teórico de 1,53$\times$ para 5,32$\times$. O C5 confirma que a \textit{connection affinity} era o factor limitante dominante, e não a capacidade de computação agregada."
    ),
    (
        r"Com Envoy: C5 tem $CM_{tp}=+5{,}63$~RPS/componente e custo/req 18\% abaixo do C1 — o balanceamento L7 inverte o sinal dos rendimentos marginais.",
        r"Com Envoy: C5 tem $CM_{tp}=+5{,}63$~RPS/componente e custo/req 18\% abaixo do C1, demonstrando que o balanceamento L7 inverte o sinal dos rendimentos marginais."
    ),
    (
        r"H2 e H5 permanecem inconclusivas — cargas superiores seriam necessárias para observar a limitação stateful.",
        r"H2 e H5 permanecem inconclusivas, dado que cargas superiores seriam necessárias para observar a limitação stateful."
    ),
    (
        r"O Envoy no C5 introduz um novo SPOF (1 réplica) — mitigável com 2 réplicas em produção.",
        r"O Envoy no C5 introduz um novo SPOF (1 réplica), que é mitigável com 2 réplicas em produção."
    ),
    (
        r"C5 tem custo por pedido 18\% \emph{abaixo} do C1 — demonstrando que o custo do Envoy é amplamente compensado pela eficiência do throughput.",
        r"C5 tem custo por pedido 18\% \emph{abaixo} do C1, demonstrando que o custo do Envoy é amplamente compensado pela eficiência do throughput."
    ),
    (
        r"A Tabela~\ref{tab:marginal-nivel} revela que o $CM_{tp}$ não é constante — é máximo quando o C1 está perto da saturação (50u: $+$0,565~RPS/réplica) e colapsa quando ambos os sistemas se aproximam dos seus limites (75u: $+$0,135~RPS/réplica). A 25u, com o sistema ainda confortavelmente abaixo da saturação, o ganho é mínimo ($+$0,155~RPS/réplica). O custo por pedido do C3 é sistematicamente $\approx 2\times$ o do C1 ao mesmo nível de carga, independentemente da intensidade — confirmando que o custo das réplicas adicionais é fixo enquanto o ganho de throughput é variável e dependente do estado de saturação do sistema.",
        r"A Tabela~\ref{tab:marginal-nivel} revela que o $CM_{tp}$ não é constante, sendo máximo quando o C1 está perto da saturação (50u: $+$0,565~RPS/réplica) e colapsando quando ambos os sistemas se aproximam dos seus limites (75u: $+$0,135~RPS/réplica). A 25u, com o sistema ainda confortavelmente abaixo da saturação, o ganho é mínimo ($+$0,155~RPS/réplica). O custo por pedido do C3 é sistematicamente $\approx 2\times$ o do C1 ao mesmo nível de carga, independentemente da intensidade, confirmando que o custo das réplicas adicionais é fixo enquanto o ganho de throughput é variável e dependente do estado de saturação do sistema."
    ),
    (
        r"Apesar de todos os serviços stateless terem sido escalados para 3 réplicas, \textbf{65,4\% do trabalho comporta-se como serial} — como se não pudesse ser paralelizado. A causa estrutural é a \textit{connection affinity} do gRPC/HTTP2: as conexões existentes permanecem nas réplicas originais, tornando as novas réplicas praticamente inactivas. Do ponto de vista de Amdahl, isto é equivalente a converter trabalho potencialmente paralelo em serial.",
        r"Apesar de todos os serviços stateless terem sido escalados para 3 réplicas, \textbf{65,4\% do trabalho comporta-se como serial}, ou seja, como se não pudesse ser paralelizado. A causa estrutural é a \textit{connection affinity} do gRPC/HTTP2: as conexões existentes permanecem nas réplicas originais, tornando as novas réplicas praticamente inactivas. Do ponto de vista de Amdahl, isto é equivalente a converter trabalho potencialmente paralelo em serial."
    ),
    (
        r"\textbf{Kubernetes e balanceamento de carga.} O Kubernetes opera ao nível L4 através do kube-proxy (iptables/IPVS), adequado para HTTP/1.1 mas insuficiente para gRPC. A resolução requer balanceamento ao nível L7 (pedido), tipicamente fornecido por um \textit{service mesh} (Istio, Linkerd) ou por balanceamento do lado do cliente. O \textit{Horizontal Pod Autoscaler} (HPA)~\cite{k8shpa} oferece escalamento reativo, mas pressupõe que o escalamento é eficaz — pressuposto questionado pelos resultados deste estudo.",
        r"\textbf{Kubernetes e balanceamento de carga.} O Kubernetes opera ao nível L4 através do kube-proxy (iptables/IPVS), adequado para HTTP/1.1 mas insuficiente para gRPC. A resolução requer balanceamento ao nível L7 (pedido), tipicamente fornecido por um \textit{service mesh} (Istio, Linkerd) ou por balanceamento do lado do cliente. O \textit{Horizontal Pod Autoscaler} (HPA)~\cite{k8shpa} oferece escalamento reativo, mas pressupõe que o escalamento é eficaz, um pressuposto questionado pelos resultados deste estudo."
    ),
    (
        r"Antes dos testes comparativos foi executado um teste exploratório de C1 com um \textit{locustfile} simplificado (1 perfil, \texttt{wait\_time} entre(0{,}5,1)) com carga crescente progressiva, para identificar o ponto de saturação do sistema e calibrar os níveis de carga. \textbf{Estes resultados não são comparáveis com os testes comparativos} — locustfile diferente, metodologia diferente.",
        r"Antes dos testes comparativos foi executado um teste exploratório de C1 com um \textit{locustfile} simplificado (1 perfil, \texttt{wait\_time} entre(0{,}5,1)) com carga crescente progressiva, para identificar o ponto de saturação do sistema e calibrar os níveis de carga. \textbf{Estes resultados não são comparáveis com os testes comparativos}, dada a utilização de um locustfile diferente e de uma metodologia distinta."
    ),
    (
        r"\textbf{Nota metodológica (carga incremental vs.\ arranque a frio):} no C3, o teste com carga incremental (25→150u) chegou a 150u sem quebrar (p99=1500ms), mantendo conexões gRPC aquecidas e JIT compilado. O teste de arranque a frio direto a 150u quebrou (p99=2500ms). O arranque a frio é a medida mais honesta do ponto de saturação real — a carga incremental subestima a latência por efeito de aquecimento progressivo.",
        r"\textbf{Nota metodológica (carga incremental vs.\ arranque a frio):} no C3, o teste com carga incremental (25→150u) chegou a 150u sem quebrar (p99=1500ms), mantendo conexões gRPC aquecidas e JIT compilado. O teste de arranque a frio direto a 150u quebrou (p99=2500ms). O arranque a frio é a medida mais honesta do ponto de saturação real, dado que a carga incremental subestima a latência por efeito de aquecimento progressivo."
    )
]

for target, replacement in replacements:
    if target in content:
        content = content.replace(target, replacement)
    else:
        # Fallback without LaTeX escaping differences
        target_norm = target.replace(r"\\", "\\")
        replacement_norm = replacement.replace(r"\\", "\\")
        if target_norm in content:
            content = content.replace(target_norm, replacement_norm)
        else:
            print(f"Warning: target not found:\n{target[:100]}...")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("Done cleaning dashes.")
