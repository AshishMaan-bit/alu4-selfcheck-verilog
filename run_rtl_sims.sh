#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# run_rtl_sims.sh : all RTL simulations with Icarus Verilog (logs: sim/logs)
#   * exhaustive test (8192 vectors) of every configuration and adder:
#       base (unprotected), DMR, 4 checker configs on the conventional
#       datapath, 2 checker configs on the bit-sliced datapath
#   * RTL fault-injection demo (force/release), VCD in sim/waves/
#   * clocked top-level test with error latch/counter, VCD in sim/waves/
# ---------------------------------------------------------------------------
set -e
cd "$(dirname "$0")"
mkdir -p sim/build sim/logs sim/vectors sim/waves
RTL="rtl/adder4.v rtl/alu4_datapath.v rtl/alu4_datapath_bs.v rtl/alu4_checker.v \
     rtl/alu4_sc_core.v rtl/alu4_dmr_core.v rtl/alu4_base_core.v rtl/alu4_sc_top.v"
IV="iverilog -g2005 -Wall -Irtl -Itb"
T=tb_alu4_exhaustive
ANAMES=(rca cla ks)
# name : DP_STYLE ARITH_CHK LOGIC_CHK
CONFIGS="sc_res3dup:0:0:0 sc_res3par:0:0:1 sc_invdup:0:1:0 sc_invpar:0:1:1 sc_res3par_bs:1:0:1 sc_invpar_bs:1:1:1"
: > sim/logs/rtl_exhaustive_summary.log
for A in 0 1 2; do
  for CFG in $CONFIGS; do
    IFS=: read -r NM DS AC LC <<< "$CFG"
    N="${NM}_${ANAMES[$A]}"
    $IV -P$T.ADDER_ARCH=$A -P$T.DP_STYLE=$DS -P$T.ARITH_CHK=$AC -P$T.LOGIC_CHK=$LC \
        -DVEC_FILE="\"sim/vectors/rtl_${N}.txt\"" -o sim/build/$N.vvp tb/$T.v $RTL
    vvp -n sim/build/$N.vvp > sim/logs/rtl_exhaustive_$N.log
    printf "%-20s %s\n" "$N" "$(grep RESULT sim/logs/rtl_exhaustive_$N.log)" | tee -a sim/logs/rtl_exhaustive_summary.log
  done
  N="dmr_${ANAMES[$A]}"
  $IV -DDMR -P$T.ADDER_ARCH=$A -DVEC_FILE="\"sim/vectors/rtl_${N}.txt\"" \
      -o sim/build/$N.vvp tb/$T.v $RTL
  vvp -n sim/build/$N.vvp > sim/logs/rtl_exhaustive_$N.log
  printf "%-20s %s\n" "$N" "$(grep RESULT sim/logs/rtl_exhaustive_$N.log)" | tee -a sim/logs/rtl_exhaustive_summary.log
done
$IV -o sim/build/tb_fault_demo.vvp tb/tb_alu4_fault_demo.v $RTL
vvp -n sim/build/tb_fault_demo.vvp | grep -v "^VCD" > sim/logs/rtl_fault_demo.log
tail -10 sim/logs/rtl_fault_demo.log
$IV -o sim/build/tb_top.vvp tb/tb_alu4_top.v $RTL
vvp -n sim/build/tb_top.vvp | grep -v "^VCD" | tee sim/logs/rtl_top.log
