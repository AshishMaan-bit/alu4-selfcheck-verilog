#!/usr/bin/env bash
# run_lint.sh : Verilator -Wall lint of every module / parameter combination
set -e
cd "$(dirname "$0")"
mkdir -p sim/logs
RTL="rtl/adder4.v rtl/alu4_datapath.v rtl/alu4_datapath_bs.v rtl/alu4_checker.v \
     rtl/alu4_sc_core.v rtl/alu4_dmr_core.v rtl/alu4_base_core.v rtl/alu4_sc_top.v"
LOG=sim/logs/lint_verilator.log; : > $LOG
lint() {  # $1 top, rest = -G overrides
  T=$1; shift
  if verilator --lint-only -Wall -Irtl --top-module $T "$@" $RTL > /tmp/lint_$$.txt 2>&1; then rc=0; else rc=1; fi
  echo "top=$T $* : rc=$rc warnings=$(grep -c Warning /tmp/lint_$$.txt || true)" | tee -a $LOG
}
for A in 0 1 2; do
  lint alu4_base_core -GADDER_ARCH=$A -GDP_STYLE=0
  lint alu4_base_core -GADDER_ARCH=$A -GDP_STYLE=1
  lint alu4_dmr_core  -GADDER_ARCH=$A
  for D in 0 1; do for AC in 0 1; do for LC in 0 1; do
    lint alu4_sc_core -GADDER_ARCH=$A -GDP_STYLE=$D -GARITH_CHK=$AC -GLOGIC_CHK=$LC
  done; done; done
  lint alu4_sc_top -GADDER_ARCH=$A
done
rm -f /tmp/lint_$$.txt
echo "lint runs with warnings: $(grep -vc 'warnings=0' $LOG || true)"
