#!/usr/bin/env python3
"""
fault_campaign.py - exhaustive single stuck-at fault-injection campaign.

For every synthesised netlist in synth/out/<variant>/netlist.json:
  * fault list  : stuck-at-0 and stuck-at-1 on every net bit (13 primary-input
                  bits + every gate output), i.e. the classical stem fault set
  * stimulus    : all 8192 input vectors (exhaustive), bit-parallel
  * per fault   : diff = vectors whose {r,c,v,z,n} differ from the fault-free
                  netlist; det = diff & err; sdc = diff & ~err;
                  alarm = err & ~diff
  * class       : SDC        - at least one vector silently corrupted
                  DETECTED   - output corrupted on some vector, and EVERY
                               corrupted vector is flagged (fault-secure)
                  ALARM_ONLY - outputs never wrong, err raised (safe, e.g.
                               a fault inside the checker)
                  SILENT     - no observable effect (redundant / masked)

Before the campaign every fault-free netlist is checked against the Python
reference model (must match on all 8192 vectors, err never asserted).

Outputs:
  fault/results/<variant>_faults.csv   one row per fault
  fault/results/summary.csv            one row per variant
"""
import csv, os, re, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
from gatesim import Netlist, MASK, NVEC, op_masks, reference_outputs  # noqa: E402

FUNC = ["r", "c", "v", "z", "n"]
OPNAMES = ["ADD", "ADC", "SUB", "SBB", "INC", "DEC", "AND", "OR",
           "XOR", "NOR", "NOT", "SHL", "SHR", "ASR", "ROL", "ROR"]
OPCLASS = {**{o: "arith" for o in range(6)}, 6: "logic", 7: "logic", 9: "logic",
           **{o: "parity" for o in (8, 10, 11, 12, 13, 14, 15)}}


def popcount(x):
    return bin(x).count("1")


def location(cell_name):
    if cell_name == "PI":
        return "input"
    for tag in ("u_dp2", "u_chk", "u_dp"):
        if re.search(r"(^|[\\.])" + tag + r"\.", cell_name):
            return {"u_dp": "datapath", "u_dp2": "datapath2", "u_chk": "checker"}[tag]
    return "glue"           # top-level logic, e.g. the DMR comparator


def run_variant(name, ref, opm):
    nl = Netlist(os.path.join(ROOT, "synth", "out", name, "netlist.json"))
    gold = nl.simulate()
    # ---- sanity: fault-free netlist == reference model, no false alarm
    for p in FUNC:
        if gold[p] != ref[p]:
            raise SystemExit(f"{name}: fault-free netlist differs from reference on '{p}'")
    if gold["err"][0] != 0:
        raise SystemExit(f"{name}: false alarm in fault-free netlist")

    rows = []
    for bit, cell, net in nl.fault_sites():
        for sa in (0, 1):
            out = nl.simulate((bit, sa))
            diff = 0
            for p in FUNC:
                for g, f in zip(gold[p], out[p]):
                    diff |= g ^ f
            err = out["err"][0]
            sdc, det, alarm = diff & ~err & MASK, diff & err, err & ~diff & MASK
            cls = "SDC" if sdc else ("DETECTED" if diff else ("ALARM_ONLY" if err else "SILENT"))
            sdc_ops = [OPNAMES[o] for o in range(16) if sdc & opm[o]]
            rows.append({"net": net, "location": location(cell), "stuck_at": sa, "class": cls,
                         "corrupt_vecs": popcount(diff), "detected_vecs": popcount(det),
                         "sdc_vecs": popcount(sdc), "alarm_vecs": popcount(alarm),
                         "sdc_ops": " ".join(sdc_ops)})
    return nl, rows


def summarise(name, nl, rows):
    st = nl.stats()
    n = len(rows)
    eff = [r for r in rows if r["corrupt_vecs"] > 0]
    sdc = [r for r in rows if r["class"] == "SDC"]
    det = [r for r in rows if r["class"] == "DETECTED"]
    tot_corrupt = sum(r["corrupt_vecs"] for r in rows)
    tot_sdc = sum(r["sdc_vecs"] for r in rows)
    by_cls = {"arith": 0, "logic": 0, "parity": 0}
    for r in sdc:
        for o in r["sdc_ops"].split():
            by_cls[OPCLASS[OPNAMES.index(o)]] += 1
    intern = [r for r in rows if r["location"] != "input"]
    int_eff = [r for r in intern if r["corrupt_vecs"] > 0]
    int_sdc = [r for r in intern if r["class"] == "SDC"]
    int_corrupt = sum(r["corrupt_vecs"] for r in intern)
    int_sdcv = sum(r["sdc_vecs"] for r in intern)
    design, arch, flow = name.rsplit("_", 2)
    return {
        "variant": name, "design": design, "adder": arch, "flow": flow,
        "cells": st["cells"], "transistors": st["transistors"], "depth": st["depth"],
        "faults": n, "effective_faults": len(eff),
        "detected_faults": len(det), "sdc_faults": len(sdc),
        "alarm_only_faults": sum(r["class"] == "ALARM_ONLY" for r in rows),
        "silent_faults": sum(r["class"] == "SILENT" for r in rows),
        # fault-secure coverage: effective faults that never cause an SDC
        "fault_secure_cov_pct": round(100.0 * (len(eff) - len(sdc)) / len(eff), 3) if eff else 100.0,
        # fraction of corrupted (fault, vector) pairs that were flagged
        "error_detection_pct": round(100.0 * (tot_corrupt - tot_sdc) / tot_corrupt, 3) if tot_corrupt else 100.0,
        # probability that a random op under a random fault is silently wrong
        "sdc_probability_pct": round(100.0 * tot_sdc / (n * NVEC), 4),
        # same metrics restricted to faults INSIDE the ALU (primary-input stem
        # faults excluded: they are common-mode for every CED scheme and are
        # normally covered by operand-bus parity upstream)
        "int_faults": len(intern),
        "int_effective_faults": len(int_eff),
        "int_sdc_faults": len(int_sdc),
        "int_fault_secure_cov_pct": round(100.0 * (len(int_eff) - len(int_sdc)) / len(int_eff), 3) if int_eff else 100.0,
        "int_error_detection_pct": round(100.0 * (int_corrupt - int_sdcv) / int_corrupt, 3) if int_corrupt else 100.0,
        "int_sdc_probability_pct": round(100.0 * int_sdcv / (len(intern) * NVEC), 4),
        "sdc_fault_op_arith": by_cls["arith"], "sdc_fault_op_logic": by_cls["logic"],
        "sdc_fault_op_parity": by_cls["parity"],
        "sdc_faults_datapath": sum(r["location"].startswith("datapath") for r in sdc),
        "sdc_faults_checker": sum(r["location"] == "checker" for r in sdc),
        "sdc_faults_input": sum(r["location"] == "input" for r in sdc),
        "sdc_faults_glue": sum(r["location"] == "glue" for r in sdc),
    }


def main():
    outdir = os.path.join(ROOT, "fault", "results")
    os.makedirs(outdir, exist_ok=True)
    ref, opm = reference_outputs(), op_masks()
    variants = sorted(os.listdir(os.path.join(ROOT, "synth", "out")))
    if len(sys.argv) > 1:
        variants = [v for v in variants if any(k in v for k in sys.argv[1:])]
    summary = []
    for v in variants:
        t0 = time.time()
        nl, rows = run_variant(v, ref, opm)
        with open(os.path.join(outdir, f"{v}_faults.csv"), "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0]))
            w.writeheader(); w.writerows(rows)
        s = summarise(v, nl, rows)
        summary.append(s)
        print(f"{v:24s} faults={s['faults']:4d} eff={s['effective_faults']:4d} "
              f"SDC={s['sdc_faults']:4d} FSC={s['fault_secure_cov_pct']:7.3f}% "
              f"det={s['error_detection_pct']:7.3f}% Psdc={s['sdc_probability_pct']:.4f}% | internal: "
              f"SDC={s['int_sdc_faults']:3d} FSC={s['int_fault_secure_cov_pct']:7.3f}% "
              f"det={s['int_error_detection_pct']:7.3f}% "
              f"({time.time() - t0:.1f}s)", flush=True)
    if len(sys.argv) == 1:
        with open(os.path.join(outdir, "summary.csv"), "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(summary[0]))
            w.writeheader(); w.writerows(summary)


if __name__ == "__main__":
    main()
