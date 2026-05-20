#!/bin/bash
# run_hlct_sim.sh — Verilator simulation of HLCT coverage tracking module
# Verifies: AFL-compatible hash generation, BRAM increment, AXI4-Lite read-back
set -e
cd "$(dirname "$0")"

RTL=../rtl/hlct
OUT=build_hlct

echo "=== HLCT Verilator Simulation ==="

verilator --cc --exe --build \
    --top-module tb_hlct \
    -o sim_hlct \
    --Mdir $OUT \
    $RTL/hlct_top.v \
    $RTL/axi4lite_bram.v \
    $RTL/tb_hlct.v \
    2>&1 | tail -5

echo "Running simulation..."
./$OUT/sim_hlct 2>&1

echo ""
echo "=== HLCT Throughput Estimate ==="
echo "Hash FSM: 2 cycles per commit (read + write)."
echo "At 50 MHz: max 25M edge records/s."
echo "Branch frequency for typical C code: ~1 branch per 5 instructions."
echo "RISC-V Rocket at 50 MHz, IPC~0.8: ~10M insn/s → ~2M branches/s."
echo "HLCT never saturates the 25M cap — pipeline stall = 0."
