#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# run_gate_sims.sh : post-synthesis (gate-level) exhaustive simulation of all
# 36 netlists in synth/out/ with the same testbench used for RTL.
# ---------------------------------------------------------------------------
set -e
cd "$(dirname "$0")"
mkdir -p sim/build sim/logs sim/vectors
: > sim/logs/gate_exhaustive_summary.log
for d in synth/out/*/; do
  N=$(basename "$d")
  case "$N" in base_*) M=alu4_base_core;; dmr_*) M=alu4_dmr_core;; *) M=alu4_sc_core;; esac
  iverilog -g2005 -Irtl -Itb -DGATE=$M -DVEC_FILE="\"sim/vectors/gate_${N}.txt\"" \
      -o sim/build/gate_$N.vvp tb/tb_alu4_exhaustive.v "$d/netlist.v"
  vvp -n sim/build/gate_$N.vvp > sim/logs/gate_exhaustive_$N.log
  printf "%-24s %s\n" "$N" "$(grep RESULT sim/logs/gate_exhaustive_$N.log)" | tee -a sim/logs/gate_exhaustive_summary.log
done
