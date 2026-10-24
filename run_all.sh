#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# run_all.sh : reproduces every result of the project from the sources
#   tools: Icarus Verilog 12, Yosys 0.33 (+ABC), Verilator 5, Python 3 with
#          matplotlib, Graphviz (dot)
# ---------------------------------------------------------------------------
set -e
cd "$(dirname "$0")"
echo "== 1. lint";                    ./run_lint.sh | tail -1
echo "== 2. RTL simulation";          ./run_rtl_sims.sh
echo "== 3. testbench mutation test"; python3 scripts/mutation_test.py | tail -1
echo "== 4. synthesis (54 netlists)"; python3 scripts/run_synth.py > synth/synthesis_log.txt; tail -3 synth/synthesis_log.txt
echo "== 5. gate-level simulation";   ./run_gate_sims.sh > /dev/null
echo "   PASS: $(grep -c PASS sim/logs/gate_exhaustive_summary.log) / $(wc -l < sim/logs/gate_exhaustive_summary.log)"
echo "== 6. fault campaign";          python3 scripts/fault_campaign.py > fault/campaign_log.txt; tail -3 fault/campaign_log.txt
echo "== 7. cross-validation";        python3 scripts/crossval_iverilog.py | tail -2
echo "== 8. figures";                 python3 scripts/make_figures.py 2>/dev/null | head -1
echo "done."
