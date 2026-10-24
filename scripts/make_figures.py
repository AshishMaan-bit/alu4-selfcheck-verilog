#!/usr/bin/env python3
"""
make_figures.py - generates every figure used in the report from the real
result files (synth/synthesis_summary.csv, fault/results/*.csv, sim/waves/*.vcd).

Output: docs/figures/*.png (+ the Graphviz / Yosys sources they come from)
"""
import csv, os, subprocess
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIG = os.path.join(ROOT, "docs", "figures")
os.makedirs(FIG, exist_ok=True)

# palette (validated categorical order + reserved status colours)
S1, S2, S3, S4 = "#2a78d6", "#eb6834", "#1baf7a", "#6250d6"
GOOD, WARN, CRIT, GREY = "#0ca30c", "#fab219", "#d03b3b", "#b4b2ab"
INK, INK2, GRID, SURF = "#0b0b0b", "#52514e", "#e4e3df", "#fcfcfb"

plt.rcParams.update({
    "figure.facecolor": SURF, "axes.facecolor": SURF, "savefig.facecolor": SURF,
    "axes.edgecolor": GRID, "axes.labelcolor": INK2, "xtick.color": INK2, "ytick.color": INK2,
    "text.color": INK, "axes.grid": True, "grid.color": GRID, "grid.linewidth": 0.8,
    "axes.axisbelow": True, "axes.spines.top": False, "axes.spines.right": False,
    "font.size": 9, "axes.titlesize": 10.5, "axes.titleweight": "bold", "legend.frameon": False,
})

DESIGNS = ["base", "base_bs", "dmr", "sc_res3dup", "sc_res3par", "sc_invdup",
           "sc_invpar", "sc_res3par_bs", "sc_invpar_bs"]
LABEL = {"base": "Base\n(no CED)", "base_bs": "Base\nbit-sliced", "dmr": "DMR",
         "sc_res3dup": "RES3\n+DUP", "sc_res3par": "RES3\n+PAR", "sc_invdup": "INV\n+DUP",
         "sc_invpar": "INV\n+PAR", "sc_res3par_bs": "RES3+PAR\nbit-sliced",
         "sc_invpar_bs": "INV+PAR\nbit-sliced\n(proposed)"}
ARCHS = [("rca", "RCA", S1), ("cla", "CLA", S2), ("ks", "Kogge-Stone", S3)]

summ = {r["variant"]: r for r in csv.DictReader(open(os.path.join(ROOT, "fault", "results", "summary.csv")))}


def save(fig, name):
    fig.tight_layout()
    fig.savefig(os.path.join(FIG, name), dpi=200)
    plt.close(fig)


# ---------------------------------------------------------------- 1 area
def fig_area():
    fig, axes = plt.subplots(1, 2, figsize=(10, 3.8), sharey=False)
    for ax, flow, title in ((axes[0], "opt", "ABC-optimised netlist"),
                            (axes[1], "struct", "Structure-preserving netlist")):
        w = 0.26
        for k, (a, lab, col) in enumerate(ARCHS):
            xs = [i + (k - 1) * w for i in range(len(DESIGNS))]
            ys = [int(summ[f"{d}_{a}_{flow}"]["cells"]) for d in DESIGNS]
            ax.bar(xs, ys, w - 0.03, color=col, label=lab)
        ax.set_xticks(range(len(DESIGNS)))
        ax.set_xticklabels([LABEL[d] for d in DESIGNS], fontsize=6.5)
        ax.set_ylabel("Gate count (2-input generic cells)")
        ax.set_title(title, loc="left")
        ax.grid(axis="x", visible=False)
    axes[0].legend(title="Adder", loc="upper left", fontsize=8)
    save(fig, "fig_area.png")


# ---------------------------------------------------------------- 2 coverage
def fig_coverage():
    ds = [d for d in DESIGNS if not d.startswith("base")]
    fig, ax = plt.subplots(figsize=(8.5, 3.6))
    w = 0.38
    for k, (flow, lab, col) in enumerate((("opt", "ABC-optimised", S1), ("struct", "Structure-preserving", S2))):
        ys = [float(summ[f"{d}_cla_{flow}"]["int_fault_secure_cov_pct"]) for d in ds]
        xs = [i + (k - 0.5) * w for i in range(len(ds))]
        bars = ax.bar(xs, ys, w - 0.04, color=col, label=lab)
        for x, y in zip(xs, ys):
            ax.text(x, y + 0.6, f"{y:.1f}", ha="center", fontsize=7, color=INK2)
    ax.set_xticks(range(len(ds)))
    ax.set_xticklabels([LABEL[d] for d in ds], fontsize=7)
    ax.set_ylim(60, 104)
    ax.set_ylabel("Fault-secure coverage of\ninternal stuck-at faults (%)")
    ax.set_title("Internal faults that never cause a silent error (CLA adder)", loc="left")
    ax.legend(loc="lower right", bbox_to_anchor=(1.0, 1.0), ncol=2, fontsize=8)
    ax.grid(axis="x", visible=False)
    save(fig, "fig_coverage.png")


# ---------------------------------------------------------------- 3 trade-off
def fig_tradeoff():
    fig, ax = plt.subplots(figsize=(7.2, 4.2))
    for d in DESIGNS:
        if d.startswith("base"):
            continue
        r = summ[f"{d}_cla_opt"]
        x, y = int(r["transistors"]), float(r["int_sdc_probability_pct"])
        col = GOOD if d in ("dmr", "sc_invpar_bs") else S1
        ax.scatter(x, y, s=60, color=col, edgecolor=SURF, linewidth=2, zorder=3)
        ax.annotate(LABEL[d].replace("\n", " "), (x, y), xytext=(6, 4), textcoords="offset points", fontsize=7.5)
    ax.set_xlabel("Estimated transistor count (static CMOS, ABC netlist, CLA)")
    ax.set_ylabel("P(silent data corruption) per\n(internal fault, random op)  [%]")
    ax.set_title("Area vs. residual silent-error probability", loc="left")
    save(fig, "fig_tradeoff.png")


# ---------------------------------------------------------------- 4 fault classes
def fig_classes():
    ds = DESIGNS
    fig, ax = plt.subplots(figsize=(9, 3.8))
    cats = [("sdc", "Silent data corruption", CRIT), ("det", "Detected (fault-secure)", GOOD),
            ("alarm", "Alarm only (no wrong output)", WARN), ("silent", "No effect", GREY)]
    bottoms = [0] * len(ds)
    for key, lab, col in cats:
        vals = []
        for d in ds:
            rows = list(csv.DictReader(open(os.path.join(ROOT, "fault", "results", f"{d}_cla_opt_faults.csv"))))
            rows = [r for r in rows if r["location"] != "input"]
            m = {"sdc": "SDC", "det": "DETECTED", "alarm": "ALARM_ONLY", "silent": "SILENT"}[key]
            vals.append(100.0 * sum(r["class"] == m for r in rows) / len(rows))
        ax.bar(range(len(ds)), vals, 0.6, bottom=bottoms, color=col, label=lab, edgecolor=SURF, linewidth=1.5)
        bottoms = [b + v for b, v in zip(bottoms, vals)]
    ax.set_xticks(range(len(ds)))
    ax.set_xticklabels([LABEL[d] for d in ds], fontsize=7)
    ax.set_ylabel("Share of internal faults (%)")
    ax.set_ylim(0, 100)
    ax.set_title("Outcome of every internal stuck-at fault (CLA, ABC netlist)", loc="left")
    ax.legend(loc="upper center", bbox_to_anchor=(0.5, -0.28), ncol=4, fontsize=7.5)
    ax.grid(axis="x", visible=False)
    save(fig, "fig_fault_classes.png")


# ---------------------------------------------------------------- 5 waveform
def parse_vcd(path, wanted):
    ids, depth, vals, t = {}, 0, {w: [] for w in wanted}, 0
    cur = {}
    with open(path) as f:
        for line in f:
            s = line.split()
            if not s:
                continue
            if s[0] == "$scope":
                depth += 1
            elif s[0] == "$upscope":
                depth -= 1
            elif s[0] == "$var" and depth == 1 and s[4] in wanted and s[4] not in ids.values():
                ids[s[3]] = s[4]
            elif s[0].startswith("#"):
                t = int(s[0][1:])
            elif s[0][0] in "01xz" and s[0][1:] in ids:
                n = ids[s[0][1:]]; cur[n] = s[0][0]; vals[n].append((t, s[0][0]))
            elif s[0][0] == "b" and len(s) == 2 and s[1] in ids:
                vals[ids[s[1]]].append((t, s[0][1:]))
    return vals


def fig_wave(t_lo=0, t_hi=1920, name="fig_waveform_fault_demo.png", width=11):
    sig = ["phase", "op", "a", "b", "r_g", "r_d", "c_g", "c_d", "corrupted", "err_d"]
    v = parse_vcd(os.path.join(ROOT, "sim", "waves", "fault_demo.vcd"), sig)
    tmax = 1920000
    fig, ax = plt.subplots(figsize=(width, 4.6))
    names = ["phase", "op", "a", "b", "r (golden)", "r (faulty DUT)", "c (golden)", "c (faulty DUT)",
             "corrupted", "err (checker)"]
    for row, (s, nm) in enumerate(zip(sig, names)):
        y0 = len(sig) - 1 - row
        ev = v[s] + [(tmax, v[s][-1][1])]
        bus = s not in ("c_g", "c_d", "corrupted", "err_d")
        for (t0, val), (t1, _) in zip(ev[:-1], ev[1:]):
            if t1 <= t0:
                continue
            x0, x1 = t0 / 1000, t1 / 1000
            if bus:
                ax.fill_between([x0, x1], y0 + 0.15, y0 + 0.85, color="#e8f0fb", edgecolor=S1, linewidth=0.6)
                if x1 - x0 > 14 * (t_hi - t_lo) / 1920 and t_lo <= (x0 + x1) / 2 <= t_hi:
                    ax.text((x0 + x1) / 2, y0 + 0.5, format(int(val, 2), "X") if "x" not in val else "x",
                            ha="center", va="center", fontsize=5.5, color=INK)
            else:
                hi = val == "1"
                col = CRIT if (s == "corrupted" and hi) else (GOOD if (s == "err_d" and hi) else S1)
                ax.plot([x0, x1], [y0 + (0.85 if hi else 0.15)] * 2, color=col, linewidth=1.4)
                if hi:
                    ax.fill_between([x0, x1], y0 + 0.15, y0 + 0.85, color=col, alpha=0.18, linewidth=0)
    ax.set_yticks([len(sig) - 1 - i + 0.5 for i in range(len(sig))])
    ax.set_yticklabels(names, fontsize=7.5)
    ax.set_xlim(t_lo, t_hi)
    ax.set_xlabel("time (ns)")
    for p in range(1, 8):
        ax.axvline(p * 240, color=INK2, linewidth=0.6, linestyle=(0, (3, 3)))
    labels = ["no fault", "CLA c2 SA0", "y[1] SA1", "r[1] SA1", "r[2] SA0", "c SA1", "z SA0", "released"]
    for p, l in enumerate(labels):
        xc = min(max(p * 240 + 120, t_lo + 40), t_hi - 40)
        if p * 240 < t_hi and (p + 1) * 240 > t_lo:
            ax.text(xc, len(sig) + 0.15, l, ha="center", fontsize=7, color=INK2)
    ax.set_ylim(0, len(sig) + 0.6)
    ax.grid(False)
    ax.set_title("RTL fault-injection simulation (Icarus Verilog, tb_alu4_fault_demo)", loc="left", pad=16)
    save(fig, name)


# ---------------------------------------------------------------- 6 block diagram
BLOCK_DOT = r"""
digraph alu {
  rankdir=LR; splines=ortho; nodesep=0.35; ranksep=0.55;
  node [shape=box, style="rounded,filled", fontname="Helvetica", fontsize=10, color="#52514e", fillcolor="#ffffff"];
  edge [color="#52514e", arrowsize=0.6, fontname="Helvetica", fontsize=8];
  in [label="a[3:0]  b[3:0]\nop[3:0]  cin", shape=box, style="rounded", color="#52514e"];
  subgraph cluster_dp { label="alu4_datapath_bs  (bit-sliced, no logic sharing between bits)"; fontname="Helvetica"; fontsize=10; color="#2a78d6"; style="rounded";
    opc [label="operand\nconditioning\ny = b | ~b | 0 | F\nci"];
    add [label="4-bit adder\nRCA / CLA / KS"];
    rs [label="result slices\nu_r0 .. u_r3\n(own decoder,\nlogic, shift, mux)", fillcolor="#e8f0fb"];
    cs [label="C slice", fillcolor="#e8f0fb"];
    vs [label="V slice", fillcolor="#e8f0fb"];
    zn [label="Z = NOR(r)\nN = r[3]"];
  }
  subgraph cluster_chk { label="alu4_checker  (independent decoder, sees only ALU inputs/outputs)"; fontname="Helvetica"; fontsize=10; color="#1baf7a"; style="rounded";
    inv [label="ARITH: inverse operation\nr + ~y + ~ci == {~c, a}\n+ V recomputation", fillcolor="#e6f6ef"];
    par [label="LOGIC/XOR/NOT/SHIFT:\nshared parity predictor\np({r,c}) vs f(pa, pb, p(a&b))", fillcolor="#e6f6ef"];
    flg [label="Z/N recomputation", fillcolor="#e6f6ef"];
    orr [label="OR", shape=circle, width=0.4];
  }
  out [label="r  c  v  z  n", shape=box, style="rounded"];
  er  [label="err, err_vec[3:0]", shape=box, style="rounded", color="#d03b3b"];
  in -> opc; opc -> add; in -> rs; add -> rs; add -> cs; add -> vs; in -> cs;
  rs -> zn; rs -> out; cs -> out; vs -> out; zn -> out;
  in -> inv; in -> par; out -> inv; out -> par; out -> flg;
  inv -> orr; par -> orr; flg -> orr; orr -> er;
}
"""


def fig_block():
    p = os.path.join(FIG, "block_diagram.dot")
    open(p, "w").write(BLOCK_DOT)
    subprocess.run(["dot", "-Tpng", "-Gdpi=170", p, "-o", os.path.join(FIG, "fig_block_diagram.png")], check=True)


def fig_slice_schematic():
    """Yosys-generated schematic of one result slice (real tool output)"""
    base = os.path.join(FIG, "rslice_bit1")
    subprocess.run(["yosys", "-q", "-p",
                    "read_verilog -Irtl rtl/alu4_datapath_bs.v; chparam -set BIT 1 alu4_rslice; "
                    "hierarchy -top alu4_rslice; synth -flatten -top alu4_rslice; "
                    "abc -g AND,NAND,OR,NOR,XOR,XNOR,ANDNOT,ORNOT,MUX; opt_clean; "
                    f"show -format dot -prefix {base} -notitle"], cwd=ROOT, check=True)
    subprocess.run(["dot", "-Tpng", "-Gdpi=150", base + ".dot", "-o", os.path.join(FIG, "fig_rslice_schematic.png")],
                   check=True)


if __name__ == "__main__":
    fig_area(); fig_coverage(); fig_tradeoff(); fig_classes(); fig_wave(); fig_wave(200, 760, "fig_waveform_zoom.png", 11); fig_block(); fig_slice_schematic()
    print("figures written to", FIG)
    for f in sorted(os.listdir(FIG)):
        print("  ", f)
