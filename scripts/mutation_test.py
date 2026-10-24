#!/usr/bin/env python3
"""
mutation_test.py - checks that the exhaustive testbench is strong enough.

Each mutant is a copy of the RTL with ONE deliberate design bug. The exhaustive
testbench must report FAIL for every mutant (a "killed" mutant). A surviving
mutant would mean the testbench has a blind spot.

Usage:  python3 scripts/mutation_test.py        (run from the project root)
Output: sim/logs/mutation_test.log
"""
import os, re, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RTL = ["adder4.v", "alu4_datapath.v", "alu4_datapath_bs.v", "alu4_checker.v", "alu4_sc_core.v", "alu4_dmr_core.v"]
# checker configuration per mutant: residue-3 mutant needs ARITH_CHK=0

# (file, original text, mutated text, description)
MUTANTS = [
    ("alu4_datapath.v", "`OP_SBB: begin y = ~b;    ci = ~cin; end",
                        "`OP_SBB: begin y = ~b;    ci = cin;  end",   "SBB uses wrong borrow polarity"),
    ("alu4_datapath.v", "wire ovf = (a[3] ~^ y[3]) & (sum[3] ^ a[3]);",
                        "wire ovf = (a[3] ~^ b[3]) & (sum[3] ^ a[3]);", "overflow uses B instead of adder operand"),
    ("alu4_datapath.v", "`OP_ASR: begin r_i = {a[3], a[3:1]}; c_i = a[0]; end",
                        "`OP_ASR: begin r_i = {1'b0, a[3:1]}; c_i = a[0]; end", "ASR does not sign-extend"),
    ("alu4_datapath.v", "`OP_ROR: begin r_i = {a[0], a[3:1]}; c_i = a[0]; end",
                        "`OP_ROR: begin r_i = {a[0], a[3:1]}; c_i = a[3]; end", "ROR carry from wrong bit"),
    ("alu4_datapath.v", "`OP_DEC: begin y = 4'hF;  ci = 1'b0; end",
                        "`OP_DEC: begin y = 4'hE;  ci = 1'b0; end",    "DEC subtracts 2 instead of 1"),
    ("alu4_datapath_bs.v", "`OP_ROR: ri = a_up;",
                        "`OP_ROR: ri = a_dn;",                         "bit-sliced: ROR uses wrong neighbour"),
    ("alu4_datapath_bs.v", "`OP_SHL, `OP_ROL:          c = a3;",
                        "`OP_SHL:                   c = a3;",          "bit-sliced: ROL carry missing"),
    ("adder4.v",        "assign c3 = g[2] | (p[2] & g[1]) | (p[2] & p[1] & g[0])",
                        "assign c3 = g[2] | (p[2] & g[1]) | (p[1] & g[0])", "CLA c3 missing p[2] term"),
    ("adder4.v",        "assign G2[3] = G1[3] | (P1[3] & G1[1]);",
                        "assign G2[3] = G1[3] | (P1[3] & G1[0]);",     "KS prefix wired to wrong span"),
    ("alu4_checker.v",  "add3(res4(a), res4(y_p))",
                        "add3(res4(a), res4(b))",                      "checker[RES3]: residue of B used instead of adder operand"),
    ("alu4_checker.v",  "{4'b0000, ~ci_p}",
                        "{4'b0000, ci_p}",                             "checker[INV]: inverse carry-in not complemented"),
    ("alu4_checker.v",  "? (pa ^ pb ^ p_and) :",
                        "? (pa ^ pb) :",                       "checker[PAR]: OR parity misses AND term"),
    ("alu4_checker.v",  "(is_asr ? (pa ^ a[3]) : pa)",
                        "(is_asr ? pa : pa)",         "checker: ASR parity rule wrong"),
    ("alu4_checker.v",  "wire e_flag = (z != ~|r) | (n != r[3]);",
                        "wire e_flag = (z != ~|r) | (n != r[2]);",     "checker: N recomputed from wrong bit"),
]

def run(arch, rtl_dir, achk=1, lchk=1, dmr=False, dps=1):
    b = tempfile.mktemp(suffix=".vvp")
    files = [os.path.join(rtl_dir, f) for f in RTL]
    subprocess.run(["iverilog", "-g2005", "-I", rtl_dir, "-I", os.path.join(ROOT, "tb"),
                    f"-Ptb_alu4_exhaustive.ADDER_ARCH={arch}",
                    f"-Ptb_alu4_exhaustive.ARITH_CHK={achk}",
                    f"-Ptb_alu4_exhaustive.DP_STYLE={dps}",
                    f"-Ptb_alu4_exhaustive.LOGIC_CHK={lchk}", "-o", b,
                    os.path.join(ROOT, "tb", "tb_alu4_exhaustive.v")] + files
                   + (["-DDMR"] if dmr else []),
                   check=True, capture_output=True)
    out = subprocess.run(["vvp", "-n", b], capture_output=True, text=True).stdout
    os.remove(b)
    m = lambda k: int(re.search(k + r"\s*:\s*(\d+)", out).group(1))
    return ("RESULT: PASS" in out), m("functional fails"), m("err asserted")

def main():
    lines = []
    # architecture used for each mutant: adder mutants need their own adder
    for (fn, old, new, desc) in MUTANTS:
        arch = 1
        if "KS" in desc: arch = 2
        tmp = tempfile.mkdtemp()
        for f in os.listdir(os.path.join(ROOT, "rtl")):
            shutil.copy(os.path.join(ROOT, "rtl", f), tmp)
        src = open(os.path.join(tmp, fn)).read()
        assert old in src, f"pattern not found for mutant: {desc}"
        open(os.path.join(tmp, fn), "w").write(src.replace(old, new))
        achk = 0 if "RES3" in desc else 1
        # conventional-datapath mutants are run on DP_STYLE=0, all others on
        # the proposed bit-sliced datapath (DP_STYLE=1)
        dps = 0 if fn == "alu4_datapath.v" else 1
        passed, nf, ne = run(arch, tmp, achk, dps=dps)
        # design bug in the datapath: does a DMR core (two identical, equally
        # buggy copies) flag it at run time?  (common-mode failure study)
        dmr_txt = "      -"
        if fn in ("alu4_datapath.v", "adder4.v"):     # DMR uses the conventional datapath
            _, _, ne_dmr = run(arch, tmp, dmr=True)
            dmr_txt = f"{ne_dmr:7d}"
        shutil.rmtree(tmp)
        status = "SURVIVED" if passed else "KILLED"
        lines.append(f"{status:9s} | arch={arch} DP{dps} A{achk}L1 | func_fails={nf:5d} | "
                     f"SC err_asserted={ne:5d} | DMR err_asserted={dmr_txt} | {fn:16s} | {desc}")
        print(lines[-1], flush=True)
    killed = sum(l.startswith("KILLED") for l in lines)
    summ = f"\nMutants killed: {killed}/{len(lines)}"
    print(summ)
    os.makedirs(os.path.join(ROOT, "sim", "logs"), exist_ok=True)
    with open(os.path.join(ROOT, "sim", "logs", "mutation_test.log"), "w") as f:
        f.write("\n".join(lines) + summ + "\n")
    return 0 if killed == len(lines) else 1

if __name__ == "__main__":
    sys.exit(main())
