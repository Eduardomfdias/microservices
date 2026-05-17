"""
Gera os 6 gráficos para o relatório ASID 2025/2026.
Tema 2 — Escalabilidade Horizontal e Custo Marginal em Microserviços
"""

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np

OUTPUT_DIR = "/Users/edias/Documents/Mestrado /1º Ano - 2º Semestre/Arquiteturas de Sistemas de Informação Distribuídos/Trabalho Pratico /microservices-demo-main/microservices/projeto_asid/docs/Diagramas/figuras/"

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
}

# ============================================================
# Figure 1 — Throughput vs Utilizadores (exaustivos)
# ============================================================
def fig1():
    fig, ax = plt.subplots(figsize=(6.5, 4))

    # C1 data (ends at 75u)
    c1_users = [25, 50, 75]
    c1_rps   = [71.8, 88.1, 100.4]

    # C2 data (ends at 50u)
    c2_users = [25, 50]
    c2_rps   = [71.0, 76.1]

    # C3 data
    c3_users = [25, 50, 75, 100, 125, 150]
    c3_rps   = [74.9, 99.4, 103.1, 124.2, 123.4, 130.5]

    # C4 data (only 25u)
    c4_users = [25]
    c4_rps   = [66.8]

    ax.plot(c1_users, c1_rps, color=COLORS['C1'], marker='o', linewidth=1.8,
            label='C1 — Baseline (1×)', zorder=3)
    ax.plot(c2_users, c2_rps, color=COLORS['C2'], marker='s', linewidth=1.8,
            linestyle='--', label='C2 — Seletivo (productcatalog ×3)', zorder=3)
    ax.plot(c3_users, c3_rps, color=COLORS['C3'], marker='^', linewidth=1.8,
            label='C3 — Uniforme (todos ×3)', zorder=3)
    ax.plot(c4_users, c4_rps, color=COLORS['C4'], marker='D', linewidth=1.8,
            linestyle=':', label='C4 — Frontend + Currency ×3', zorder=3)

    # Break markers (red X)
    ax.plot(75,  100.4, 'rx', markersize=12, markeredgewidth=2.5, zorder=5)
    ax.plot(50,  76.1,  'rx', markersize=12, markeredgewidth=2.5, zorder=5)
    ax.plot(25,  66.8,  'rx', markersize=12, markeredgewidth=2.5, zorder=5)

    ax.annotate('QUEBRA C1', xy=(75, 100.4), xytext=(80, 96),
                fontsize=8, color='red',
                arrowprops=dict(arrowstyle='->', color='red', lw=1))
    ax.annotate('QUEBRA C2', xy=(50, 76.1), xytext=(55, 72),
                fontsize=8, color='red',
                arrowprops=dict(arrowstyle='->', color='red', lw=1))
    ax.annotate('QUEBRA C4', xy=(25, 66.8), xytext=(30, 62),
                fontsize=8, color='red',
                arrowprops=dict(arrowstyle='->', color='red', lw=1))

    # Reference line
    ax.axhline(y=100.4, color='grey', linestyle='--', linewidth=1, alpha=0.7,
               label='RPS máx. C1 (100.4)')

    ax.set_xlabel('Utilizadores Concorrentes')
    ax.set_ylabel('Throughput (RPS)')
    ax.set_title('Throughput vs. Carga — Testes Exaustivos')
    ax.set_xlim(15, 160)
    ax.set_ylim(50, 145)
    ax.set_xticks([25, 50, 75, 100, 125, 150])
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
    c1_p99   = [660, 1500, 1800]

    c2_users = [25, 50]
    c2_p99   = [460, 3700]

    c3_users = [25, 50, 75, 100, 125, 150]
    c3_p99   = [720, 560, 1100, 1000, 1300, 1500]

    ax.plot(c1_users, c1_p99, color=COLORS['C1'], marker='o', linewidth=1.8,
            label='C1 — Baseline')
    ax.plot(c2_users, c2_p99, color=COLORS['C2'], marker='s', linewidth=1.8,
            linestyle='--', label='C2 — Seletivo')
    ax.plot(c3_users, c3_p99, color=COLORS['C3'], marker='^', linewidth=1.8,
            label='C3 — Uniforme')

    # Break criterion
    ax.axhline(y=2000, color='red', linestyle='--', linewidth=1.2,
               label='Critério de quebra (2 000 ms)')

    # Break markers
    ax.plot(75,  1800, 'rx', markersize=12, markeredgewidth=2.5, zorder=5)
    ax.plot(50,  3700, 'rx', markersize=12, markeredgewidth=2.5, zorder=5)

    ax.set_yscale('log')
    ax.set_xlabel('Utilizadores Concorrentes')
    ax.set_ylabel('Latência p99 (ms)')
    ax.set_title('Latência p99 vs. Carga — Testes Exaustivos')
    ax.set_xlim(15, 160)
    ax.set_xticks([25, 50, 75, 100, 125, 150])

    # Custom y-tick labels
    ax.set_yticks([100, 200, 500, 1000, 2000, 4000])
    ax.set_yticklabels(['100', '200', '500', '1 000', '2 000', '4 000'])

    ax.grid(True, alpha=0.3, which='both')
    ax.legend(loc='upper left')

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

    # CPU values at break point (millicores)
    cpu_c1 = [199,  173,  90,   86,   200, 8]   # @75u
    cpu_c2 = [199,  174,  94,   104,  199, 8]   # @50u (productcatalog total)
    cpu_c3 = [482,  330,  207,  159,  276, 13]  # @150u (totals)
    cpu_c4 = [143,  103,  37,   115,  8,   3]   # @25u

    n = len(services)
    x = np.arange(n)
    h = 0.18  # bar height

    fig, ax = plt.subplots(figsize=(7, 4.5))

    bars_c4 = ax.barh(x + 1.5*h, cpu_c4, h, color=COLORS['C4'], label='C4 @25u')
    bars_c3 = ax.barh(x + 0.5*h, cpu_c3, h, color=COLORS['C3'], label='C3 @150u (total réplicas)')
    bars_c2 = ax.barh(x - 0.5*h, cpu_c2, h, color=COLORS['C2'], label='C2 @50u')
    bars_c1 = ax.barh(x - 1.5*h, cpu_c1, h, color=COLORS['C1'], label='C1 @75u')

    ax.set_yticks(x)
    ax.set_yticklabels(services)
    ax.set_xlabel('CPU (millicores)')
    ax.set_title('CPU por Serviço no Ponto de Saturação (millicores)')
    ax.legend(loc='lower right')
    ax.grid(True, alpha=0.3, axis='x')

    # Add note
    ax.annotate('* C3: soma de todas as réplicas do serviço',
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
    scenarios = ['C4\n(Frontend+Currency ×3)', 'C2\n(Seletivo)', 'C1\n(Baseline)', 'C3\n(Uniforme)']
    break_pts = [25, 50, 75, 150]
    colors_bar = [COLORS['C4'], COLORS['C2'], COLORS['C1'], COLORS['C3']]
    notes = ['pior de todos', 'C2 < C1 !', '', '']

    fig, ax = plt.subplots(figsize=(6.5, 3.5))

    bars = ax.barh(scenarios, break_pts, color=colors_bar, height=0.45, edgecolor='white')

    # Value labels
    for bar, val, note in zip(bars, break_pts, notes):
        label = f'{val}u'
        if note:
            label += f'  ← {note}'
        ax.text(bar.get_width() + 2, bar.get_y() + bar.get_height()/2,
                label, va='center', fontsize=9,
                color='red' if note else 'black',
                fontweight='bold' if note else 'normal')

    # C1 reference line
    ax.axvline(x=75, color='grey', linestyle='--', linewidth=1.2, alpha=0.8,
               label='Referência C1 (75u)')

    ax.set_xlabel('Utilizadores até Quebra')
    ax.set_title('Ponto de Saturação por Cenário (utilizadores)')
    ax.set_xlim(0, 175)
    ax.set_xticks([0, 25, 50, 75, 100, 125, 150])
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
    # Comparativo: C1, C2, C3 (sem C4)
    comp_labels = ['C1', 'C2', 'C3']
    comp_vals   = [77.4, 80.5, 177.7]
    comp_colors = [COLORS['C1'], COLORS['C2'], COLORS['C3']]

    # Exaustivo: C1, C2, C3, C4
    exau_labels = ['C1', 'C2', 'C3', 'C4']
    exau_vals   = [6.52, 8.47, 10.87, 38.96]
    exau_colors = [COLORS['C1'], COLORS['C2'], COLORS['C3'], COLORS['C4']]

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
    ax.set_ylim(0, 46)
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
    cpu_vals = [92, 1, 1]
    bar_colors = [COLORS['C1'], COLORS['C2'], COLORS['C3']]
    percentages = ['97.9%', '1.1%', '1.1%']

    fig, ax = plt.subplots(figsize=(5.5, 3.5))

    bars = ax.bar(replicas, cpu_vals, color=bar_colors, width=0.45, edgecolor='white')

    for bar, val, pct in zip(bars, cpu_vals, percentages):
        ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.8,
                f'{val}m\n({pct})', ha='center', va='bottom', fontsize=9)

    ax.set_ylabel('CPU (millicores)')
    ax.set_title('Distribuição de CPU — productcatalogservice em C2\n(connection affinity gRPC — H6)')
    ax.set_ylim(0, 110)
    ax.grid(True, alpha=0.3, axis='y')

    # Annotation
    ax.annotate('Réplicas novas recebem\n<2% do tráfego gRPC',
                xy=(1.5, 3), xytext=(1.2, 50),
                fontsize=8, color='red',
                ha='center',
                arrowprops=dict(arrowstyle='->', color='red', lw=1))

    # Total note
    ax.text(0.98, 0.97, 'Total: 94 millicores\n(@ ponto de saturação C2, 50u)',
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
