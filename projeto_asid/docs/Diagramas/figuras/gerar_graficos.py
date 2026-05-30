"""
Gera os 6 gráficos para o relatório ASID 2025/2026.
Tema 2 — Escalabilidade Horizontal e Custo Marginal em Microserviços
"""

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

import numpy as np

OUTPUT_DIR = "/Users/edias/microservices/projeto_asid/docs/Diagramas/figuras/"

# --- Style ---
plt.rcParams['font.family'] = 'serif'
plt.rcParams['font.size'] = 10
plt.rcParams['axes.titlesize'] = 11
plt.rcParams['axes.labelsize'] = 10
plt.rcParams['xtick.labelsize'] = 9
plt.rcParams['ytick.labelsize'] = 9
plt.rcParams['legend.fontsize'] = 9
plt.rcParams['figure.dpi'] = 150

COLORS = {
    'C1': '#1f77b4',   # blue
    'C2': '#ff7f0e',   # orange
    'C3': '#2ca02c',   # green
    'C4': '#d62728',   # red
    'C5': '#9467bd',   # purple
}

# ============================================================
# Figure 1 — Throughput vs Utilizadores (exaustivos)
# ============================================================
def fig1():
    fig, ax = plt.subplots(figsize=(6.5, 4))

    # C1 data (médias 3 runs; ends at 75u)
    c1_users = [25, 50, 75]
    c1_rps   = [79.7, 106.5, 126.7]

    # C2 data (médias 3 runs; ends at 50u)
    c2_users = [25, 50]
    c2_rps   = [81.3, 103.8]

    # C3 data (3 runs avg para 25-75u; execução única para 100-400u)
    c3_users = [25, 50, 75, 100, 200, 300, 400]
    c3_rps   = [83.1, 115.8, 133.6, 194.3, 207.7, 196.4, 195.3]

    # C4 data (médias 3 runs; 100-400u)
    c4_users = [100, 200, 300, 400]
    c4_rps   = [123.8, 142.4, 147.0, 149.6]

    # C5 data (step-up test original 25-150u)
    c5_users = [25, 50, 75, 100, 125, 150]
    c5_rps   = [89.1, 116.6, 184.3, 201.7, 201.8, 218.7]

    ax.plot(c1_users, c1_rps, color=COLORS['C1'], marker='o', linewidth=1.8,
            label='C1: Baseline (1×)', zorder=3)
    ax.plot(c2_users, c2_rps, color=COLORS['C2'], marker='s', linewidth=1.8,
            linestyle='--', label='C2: Seletivo (productcatalog ×3)', zorder=3)
    ax.plot(c3_users, c3_rps, color=COLORS['C3'], marker='^', linewidth=1.8,
            label='C3: Uniforme (todos ×3)', zorder=3)
    ax.plot(c4_users, c4_rps, color=COLORS['C4'], marker='D', linewidth=1.8,
            linestyle=':', label='C4: Frontend + Currency ×3', zorder=3)
    ax.plot(c5_users, c5_rps, color=COLORS['C5'], marker='p', linewidth=1.8,
            label='C5: Uniforme ×3 + Envoy L7', zorder=3)

    # Break markers (red X) — C1@75u, C2@50u
    ax.plot(75,  126.7, 'rx', markersize=12, markeredgewidth=2.5, zorder=5)
    ax.plot(50,  103.8, 'rx', markersize=12, markeredgewidth=2.5, zorder=5)

    ax.annotate('QUEBRA C1\n(75u)', xy=(75, 126.7), xytext=(80, 118),
                fontsize=8, color='red',
                arrowprops=dict(arrowstyle='->', color='red', lw=1))
    ax.annotate('QUEBRA C2\n(50u)', xy=(50, 103.8), xytext=(30, 90),
                fontsize=8, color='red',
                arrowprops=dict(arrowstyle='->', color='red', lw=1))

    # Reference line
    ax.axhline(y=126.7, color='grey', linestyle='--', linewidth=1, alpha=0.7,
               label='RPS máx. C1 (126.7)')

    ax.set_xlabel('Utilizadores Concorrentes')
    ax.set_ylabel('Throughput (RPS)')
    ax.set_title('Throughput vs. Carga: Testes Exaustivos')
    ax.set_xlim(15, 420)
    ax.set_ylim(40, 240)
    ax.set_xticks([25, 50, 75, 100, 150, 200, 300, 400])
    ax.grid(True, alpha=0.3)
    ax.legend(loc='lower right')

    fig.tight_layout()
    fig.savefig(OUTPUT_DIR + 'fig_throughput_vs_users.pdf', bbox_inches='tight')
    plt.close(fig)
    print("fig_throughput_vs_users.pdf saved")


# ============================================================
# Figure 2 — p99 Latência vs Utilizadores (exaustivos)
# ============================================================
def fig2():
    fig, ax = plt.subplots(figsize=(6.5, 4))

    c1_users = [25, 50, 75]
    c1_p99   = [633, 1043, 1500]   # médias 3 runs

    c2_users = [25, 50]
    c2_p99   = [417, 1743]         # médias 3 runs

    c3_users = [25, 50, 75, 100, 200, 300, 400]
    c3_p99   = [542, 757, 613, 850, 1100, 1400, 1100]

    c4_users = [100, 200, 300, 400]
    c4_p99   = [947, 1433, 1667, 1533]  # médias 3 runs

    c5_users = [25, 50, 75, 100, 125, 150]
    c5_p99   = [45, 140, 540, 500, 720, 660]

    ax.plot(c1_users, c1_p99, color=COLORS['C1'], marker='o', linewidth=1.8,
            label='C1: Baseline')
    ax.plot(c2_users, c2_p99, color=COLORS['C2'], marker='s', linewidth=1.8,
            linestyle='--', label='C2: Seletivo')
    ax.plot(c3_users, c3_p99, color=COLORS['C3'], marker='^', linewidth=1.8,
            label='C3: Uniforme')
    ax.plot(c4_users, c4_p99, color=COLORS['C4'], marker='D', linewidth=1.8,
            linestyle=':', label='C4: Seletivo Real')
    ax.plot(c5_users, c5_p99, color=COLORS['C5'], marker='p', linewidth=1.8,
            label='C5: Uniforme + Envoy L7')

    # Break criterion
    ax.axhline(y=2000, color='red', linestyle='--', linewidth=1.2,
               label='Critério de quebra (2 000 ms)')

    # Break markers — quebra por falhas, não por p99
    ax.plot(75,  1500, 'rx', markersize=12, markeredgewidth=2.5, zorder=5)
    ax.plot(50,  1743, 'rx', markersize=12, markeredgewidth=2.5, zorder=5)
    ax.annotate('C1: quebra\n(23% falhas)', xy=(75, 1500), xytext=(90, 1200),
                fontsize=7.5, color='red',
                arrowprops=dict(arrowstyle='->', color='red', lw=0.8))
    ax.annotate('C2: quebra\n(9,3% falhas)', xy=(50, 1743), xytext=(30, 1200),
                fontsize=7.5, color='red', ha='center',
                arrowprops=dict(arrowstyle='->', color='red', lw=0.8))

    ax.set_yscale('log')
    ax.set_xlabel('Utilizadores Concorrentes')
    ax.set_ylabel('Latência p99 (ms)')
    ax.set_title('Latência p99 vs. Carga: Testes Exaustivos')
    ax.set_xlim(15, 420)
    ax.set_xticks([25, 50, 75, 100, 150, 200, 300, 400])

    # Custom y-tick labels
    ax.set_yticks([20, 50, 100, 200, 500, 1000, 2000, 4000])
    ax.set_yticklabels(['20', '50', '100', '200', '500', '1 000', '2 000', '4 000'])

    ax.grid(True, alpha=0.3, which='both')
    ax.legend(loc='lower left')

    fig.tight_layout()
    fig.savefig(OUTPUT_DIR + 'fig_p99_vs_users.pdf', bbox_inches='tight')
    plt.close(fig)
    print("fig_p99_vs_users.pdf saved")


# ============================================================
# Figure 3 — CPU por Serviço no Ponto de Saturação
# ============================================================
def fig3():
    services = ['frontend', 'currencyservice', 'productcatalog', 'cartservice',
                'recommend.', 'redis-cart']

    # CPU values at saturation/max load (millicores, totais por serviço, 3-run averages)
    cpu_c1 = [199,  173,  90,   86,   200,  8]   # @75u (quebra) — 1 réplica cada
    cpu_c2 = [199,  174,  94,   104,  199,  8]   # @50u (quebra) — productcatalog ×3 ≈ mesmos totais
    cpu_c3 = [288,  196,  124,  101,  203,  8]   # @100u (3-run avg) — todos ×3
    cpu_c4 = [224,  168,   76,   76,  132,  7]   # @400u (3-run avg) — frontend+currency ×3, outros ×1
    cpu_c5 = [451,  443,  256,  197,  404, 13]   # @400u (run1) — todos ×3 + Envoy excluído

    n = len(services)
    x = np.arange(n)
    h = 0.14  # bar height

    fig, ax = plt.subplots(figsize=(7, 4.5))

    bars_c5 = ax.barh(x + 2*h, cpu_c5, h, color=COLORS['C5'], label='C5 @400u (Uniforme×3+Envoy, total)')
    bars_c4 = ax.barh(x + 1*h, cpu_c4, h, color=COLORS['C4'], label='C4 @400u (Frontend+Currency×3)')
    bars_c3 = ax.barh(x,       cpu_c3, h, color=COLORS['C3'], label='C3 @100u (Uniforme×3, total)')
    bars_c2 = ax.barh(x - 1*h, cpu_c2, h, color=COLORS['C2'], label='C2 @50u (QUEBRA)')
    bars_c1 = ax.barh(x - 2*h, cpu_c1, h, color=COLORS['C1'], label='C1 @75u (QUEBRA)')

    ax.set_yticks(x)
    ax.set_yticklabels(services)
    ax.set_xlabel('CPU (millicores)')
    ax.set_title('CPU por Serviço no Ponto de Saturação (millicores)')
    ax.legend(loc='lower right')
    ax.grid(True, alpha=0.3, axis='x')

    # Add note
    ax.annotate('* C3/C4/C5: soma de todas as réplicas ativas do serviço',
                xy=(0.02, 0.01), xycoords='axes fraction',
                fontsize=7.5, color='grey', style='italic')

    fig.tight_layout()
    fig.savefig(OUTPUT_DIR + 'fig_cpu_servicos.pdf', bbox_inches='tight')
    plt.close(fig)
    print("fig_cpu_servicos.pdf saved")


# ============================================================
# Figure 4 — Ponto de Saturação por Cenário
# ============================================================
def fig4():
    scenarios = ['C2\n(Seletivo)', 'C1\n(Baseline)', 'C4\n(Seletivo Real)', 'C3\n(Uniforme)', 'C5\n(Uniforme + Envoy)']
    break_pts = [50, 75, 400, 400, 400]
    colors_bar = [COLORS['C2'], COLORS['C1'], COLORS['C4'], COLORS['C3'], COLORS['C5']]
    notes = ['C2 < C1 !', '', 'Sem quebra (>400u)', 'Sem quebra (>400u)', 'Sem quebra (>400u)']

    fig, ax = plt.subplots(figsize=(6.5, 3.5))

    bars = ax.barh(scenarios, break_pts, color=colors_bar, height=0.45, edgecolor='white')

    # Value labels
    for bar, val, note in zip(bars, break_pts, notes):
        label = f'{val}u'
        if note:
            label += f'  ← {note}'
        ax.text(bar.get_width() + 2, bar.get_y() + bar.get_height()/2,
                label, va='center', fontsize=9,
                color='red' if 'pior' in note or '<' in note else 'black',
                fontweight='bold' if note else 'normal')

    # C1 reference line
    ax.axvline(x=75, color='grey', linestyle='--', linewidth=1.2, alpha=0.8,
               label='Referência C1 (75u)')

    ax.set_xlabel('Utilizadores até Quebra')
    ax.set_title('Ponto de Saturação por Cenário (utilizadores)')
    ax.set_xlim(0, 450)
    ax.set_xticks([0, 50, 75, 100, 200, 300, 400])
    ax.grid(True, alpha=0.3, axis='x')
    ax.legend(loc='lower right', fontsize=8)

    fig.tight_layout()
    fig.savefig(OUTPUT_DIR + 'fig_saturacao.pdf', bbox_inches='tight')
    plt.close(fig)
    print("fig_saturacao.pdf saved")


# ============================================================
# Figure 5 — Custo Proxy por Pedido
# ============================================================
def fig5():
    # Comparativo: C1, C2, C3 (sem C4, sem C5)
    comp_labels = ['C1', 'C2', 'C3']
    comp_vals   = [77.4, 80.5, 177.7]
    comp_colors = [COLORS['C1'], COLORS['C2'], COLORS['C3']]

    # Exaustivo: C4, C1, C2, C3, C5 (ordenado do menor para o maior custo)
    exau_labels = ['C4', 'C1', 'C2', 'C3', 'C5']
    exau_vals   = [4.56, 5.58, 6.20, 6.50, 7.44]
    exau_colors = [COLORS['C4'], COLORS['C1'], COLORS['C2'], COLORS['C3'], COLORS['C5']]

    fig, axes = plt.subplots(1, 2, figsize=(8, 4))

    # Left — comparativo
    ax = axes[0]
    bars = ax.bar(comp_labels, comp_vals, color=comp_colors, width=0.5, edgecolor='white')
    for bar, val in zip(bars, comp_vals):
        ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 1.5,
                f'{val:.1f}', ha='center', va='bottom', fontsize=8)
    ax.set_title('Testes Comparativos\n(carga sub-saturação)', fontsize=10)
    ax.set_ylabel('Custo proxy / pedido (u.r.)')
    ax.set_ylim(0, 215)
    ax.grid(True, alpha=0.3, axis='y')
    ax.set_xlabel('Cenário')

    # Right — exaustivo
    ax = axes[1]
    bars = ax.bar(exau_labels, exau_vals, color=exau_colors, width=0.5, edgecolor='white')
    for bar, val in zip(bars, exau_vals):
        ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.3,
                f'{val:.2f}', ha='center', va='bottom', fontsize=8)
    ax.set_title('Testes Exaustivos\n(carga severa)', fontsize=10)
    ax.set_ylabel('Custo proxy / pedido (u.r.)')
    ax.set_ylim(0, 10)
    ax.grid(True, alpha=0.3, axis='y')
    ax.set_xlabel('Cenário')

    fig.suptitle('Custo Proxy por Pedido (índice relativo)', fontsize=11, y=1.01)
    fig.tight_layout()
    fig.savefig(OUTPUT_DIR + 'fig_custo_pedido.pdf', bbox_inches='tight')
    plt.close(fig)
    print("fig_custo_pedido.pdf saved")


# ============================================================
# Figure 6 — CPU distribution productcatalogservice in C2 (H6)
# ============================================================
def fig6():
    replicas = ['Réplica #1\n(original)', 'Réplica #2\n(nova)', 'Réplica #3\n(nova)']
    cpu_vals = [31, 2, 1]   # valores reais: tab:cpu, C2 @25u comparativos
    bar_colors = [COLORS['C1'], COLORS['C2'], COLORS['C3']]
    percentages = ['91.2%', '5.9%', '2.9%']

    fig, ax = plt.subplots(figsize=(5.5, 3.5))

    bars = ax.bar(replicas, cpu_vals, color=bar_colors, width=0.45, edgecolor='white')

    for bar, val, pct in zip(bars, cpu_vals, percentages):
        ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.8,
                f'{val}m\n({pct})', ha='center', va='bottom', fontsize=9)

    ax.set_ylabel('CPU (millicores)')
    ax.set_title('Distribuição de CPU: productcatalogservice em C2\n(connection affinity gRPC, H6)')
    ax.set_ylim(0, 40)
    ax.grid(True, alpha=0.3, axis='y')

    # Annotation
    ax.annotate('Réplicas novas recebem\n<9% do tráfego gRPC',
                xy=(1.5, 2), xytext=(1.2, 20),
                fontsize=8, color='red',
                ha='center',
                arrowprops=dict(arrowstyle='->', color='red', lw=1))

    # Total note
    ax.text(0.98, 0.97, 'Total: 34 millicores\n(@ 25u, testes comparativos)',
            transform=ax.transAxes, fontsize=7.5, va='top', ha='right',
            bbox=dict(boxstyle='round,pad=0.3', facecolor='lightyellow', alpha=0.8))

    fig.tight_layout()
    fig.savefig(OUTPUT_DIR + 'fig_distribuicao_cpu_c2.pdf', bbox_inches='tight')
    plt.close(fig)
    print("fig_distribuicao_cpu_c2.pdf saved")


# ============================================================
# Run all
# ============================================================
if __name__ == '__main__':
    fig1()
    fig2()
    fig3()
    fig4()
    fig5()
    fig6()
    print("\nTodos os gráficos gerados com sucesso.")
