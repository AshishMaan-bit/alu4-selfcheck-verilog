#!/usr/bin/env python3
"""
crossval_iverilog.py - independent cross-validation of the bit-parallel
fault simulator (gatesim.py) against Icarus Verilog.

Part A (fault-free): for every netlist, the Python simulation must reproduce
  the gate-level Icarus vector dump sim/vectors/gate_<variant>.txt on all
  8192 vectors and all 13 output bits (r, c, v, z, n, err, err_vec).

Part B (faulty): for a random sample of stuck-at faults per netlist, the
  fault is inserted into the Yosys JSON netlist (the driving gate is
  disconnected and every reader of the net is tied to 0/1), Yosys writes a
  new gate-level Verilog netlist, Icarus simulates it with the exhaustive
  testbench, and the three counts printed by the testbench
      functional fails / err asserted / undetected fails
  must equal the counts predicted by the Python fault simulator
      corrupt_vecs     / detected+alarm / sdc_vecs.

Output: fault/crossval_report.txt
"""
import copy, json, os, random, re, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
from gatesim import Netlist, MASK  # noqa: E402

FUNC = ["r", "c", "v", "z", "n"]
FAULTS_PER_VARIANT = int(os.environ.get("XV_FAULTS", "6"))


def module_name(v):
    return "alu4_base_core" if v.startswith("base") else ("alu4_dmr_core" if v.startswith("dmr") else "alu4_sc_core")


def bitval(ints, i):
    return [(x >> i) & 1 for x in ints]


def part_a(variant, nl, log):
    out = nl.simulate()
    lines = [l for l in open(os.path.join(ROOT, "sim", "vectors", f"gate_{variant}.txt")) if not l.startswith("#")]
    assert len(lines) == 8192
    bad = 0
    for i, l in enumerate(lines):
        lhs, rhs = l.split("|")
        op, a, b, cin = lhs.split()
        idx = int(op, 16) << 9 | int(a, 16) << 5 | int(b, 16) << 1 | int(cin)
        r, c, v, z, n, err, ev = rhs.split()
        py_r = sum(((out["r"][k] >> idx) & 1) << k for k in range(4))
        py_ev = sum(((out["err_vec"][k] >> idx) & 1) << k for k in range(4))
        py = (py_r, *[(out[p][0] >> idx) & 1 for p in ("c", "v", "z", "n", "err")], py_ev)
        iv = (int(r, 16), int(c), int(v), int(z), int(n), int(err), int(ev, 2))
        bad += py != iv
    log(f"A  {variant:28s} vectors=8192 mismatches={bad}")
    return bad == 0


def inject(json_path, bit, sa, dst):
    d = json.load(open(json_path))
    mname = [m for m in d["modules"] if d["modules"][m].get("attributes", {}).get("top")] or list(d["modules"])
    m = d["modules"][mname[0]]
    const = "1" if sa else "0"
    newbit = 1 + max(b for c in m["cells"].values() for bits in c["connections"].values() for b in bits if isinstance(b, int))
    is_pi = any(bit in p["bits"] for p in m["ports"].values() if p["direction"] == "input")
    for c in m["cells"].values():
        for pin, bits in c["connections"].items():
            if c["port_directions"][pin] == "output":
                c["connections"][pin] = [newbit if x == bit else x for x in bits]
            else:
                c["connections"][pin] = [const if x == bit else x for x in bits]
    for p in m["ports"].values():
        if p["direction"] == "output":
            p["bits"] = [const if x == bit else x for x in p["bits"]]
    if not is_pi:   # a PI keeps its name; readers were already tied off
        for nn in m["netnames"].values():
            nn["bits"] = [const if x == bit else x for x in nn["bits"]]
    json.dump(d, open(dst, "w"))


def run_iverilog(variant, json_faulty, tmp):
    v_out = os.path.join(tmp, "faulty.v")
    subprocess.run(["yosys", "-q", "-p", f"read_json {json_faulty}; write_verilog -noattr {v_out}"],
                   check=True, capture_output=True)
    vvp = os.path.join(tmp, "f.vvp")
    subprocess.run(["iverilog", "-g2005", "-I", os.path.join(ROOT, "rtl"), "-I", os.path.join(ROOT, "tb"),
                    f"-DGATE={module_name(variant)}", "-o", vvp,
                    os.path.join(ROOT, "tb", "tb_alu4_exhaustive.v"), v_out], check=True, capture_output=True)
    out = subprocess.run(["vvp", "-n", vvp], capture_output=True, text=True).stdout
    g = lambda k: int(re.search(k + r"\s*:\s*(\d+)", out).group(1))
    return g("functional fails"), g("err asserted"), g("undetected fails")


def part_b(variant, nl, rng, log):
    jpath = os.path.join(ROOT, "synth", "out", variant, "netlist.json")
    gold = nl.simulate()
    sites = nl.fault_sites()
    ok = True
    with tempfile.TemporaryDirectory() as tmp:
        for (bit, cell, net) in rng.sample(sites, min(FAULTS_PER_VARIANT, len(sites))):
            sa = rng.randint(0, 1)
            out = nl.simulate((bit, sa))
            diff = 0
            for p in FUNC:
                for g, f in zip(gold[p], out[p]):
                    diff |= g ^ f
            err = out["err"][0]
            py = (bin(diff).count("1"), bin(err).count("1"), bin(diff & ~err & MASK).count("1"))
            fj = os.path.join(tmp, "faulty.json")
            inject(jpath, bit, sa, fj)
            iv = run_iverilog(variant, fj, tmp)
            same = py == iv
            ok &= same
            log(f"B  {variant:28s} SA{sa} {net[-34:]:34s} python(corrupt,err,sdc)={py} "
                f"iverilog={iv} {'OK' if same else 'MISMATCH'}")
    return ok


def main():
    rng = random.Random(2026)
    lines = []

    def log(s):
        print(s, flush=True)
        lines.append(s)

    variants = sorted(os.listdir(os.path.join(ROOT, "synth", "out")))
    a_ok = b_ok = True
    for v in variants:
        nl = Netlist(os.path.join(ROOT, "synth", "out", v, "netlist.json"))
        a_ok &= part_a(v, nl, log)
    for v in variants:
        nl = Netlist(os.path.join(ROOT, "synth", "out", v, "netlist.json"))
        b_ok &= part_b(v, nl, rng, log)
    log(f"\nPart A (fault-free, {len(variants)} netlists x 8192 vectors): {'ALL MATCH' if a_ok else 'MISMATCH'}")
    log(f"Part B ({len(variants)} netlists x {FAULTS_PER_VARIANT} random faults): {'ALL MATCH' if b_ok else 'MISMATCH'}")
    open(os.path.join(ROOT, "fault", "crossval_report.txt"), "w").write("\n".join(lines) + "\n")
    return 0 if (a_ok and b_ok) else 1


if __name__ == "__main__":
    sys.exit(main())
