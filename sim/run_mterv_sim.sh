#!/bin/bash
# run_mterv_sim.sh — Verilator simulation of MTE-RV tag-check module
# Measures: tag-check latency cycles, fault detection correctness
set -e
cd "$(dirname "$0")"

RTL=../rtl/mte_rv
OUT=build_mterv

echo "=== MTE-RV Verilator Simulation ==="

# Compile with Verilator
verilator --cc --exe --build \
    --top-module tb_mterv \
    -o sim_mterv \
    --Mdir $OUT \
    $RTL/DCacheArbiter_mterv.v \
    $RTL/tb_mterv.v \
    2>&1 | tail -5

echo "Running simulation..."
./$OUT/sim_mterv 2>&1

echo ""
echo "=== Overhead Estimation ==="
echo "Tag check adds 1 pipeline register stage (1 cycle at 50 MHz = 20 ns)."
echo "Cache hit path: ~4 cycles. Tag overhead: 1/4 = 25% worst case."
echo "In practice tag SRAM runs in parallel with TLB — effective overhead: ~0 cycles on hit."
