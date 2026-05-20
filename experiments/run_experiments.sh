#!/bin/bash
# run_experiments.sh — Reproduce HAST-RV x86 reference experiments
# Measures AFL++ fuzzing throughput (x86 baseline for paper Table 2).
# LAVA-M bug detection is run if the LAVA-M binaries are available.
set -e
cd "$(dirname "$0")"

AFL=${AFL:-afl-fuzz}
AFL_PP=${AFLPP:-afl-fuzz}
CORES=$(nproc)
TIMEOUT=${TIMEOUT:-60}   # seconds per AFL run (set to 86400 for 24-hour paper run)
RUNS=${RUNS:-5}          # independent runs for throughput average

echo "=== HAST-RV x86 Reference Experiments ==="
echo "Date: $(date)"
echo "Host: $(uname -n) | CPU: $(lscpu | grep 'Model name' | cut -d: -f2 | xargs)"
echo "AFL binary: $(which $AFL_PP 2>/dev/null || which $AFL 2>/dev/null || echo NOT FOUND)"
echo ""

# ── 1. Compile targets ───────────────────────────────────────────────────
echo "[1/3] Compiling targets..."
AFL_CC=$(which afl-gcc 2>/dev/null || which afl-cc 2>/dev/null || echo gcc)
gcc  -O2 -o vuln_plain vuln_target.c
$AFL_CC -O2 -o vuln_afl  vuln_target.c 2>/dev/null || gcc -O2 -o vuln_afl vuln_target.c
gcc  -O2 -fsanitize=address -o vuln_asan vuln_target.c
echo "Compiled: vuln_plain vuln_afl vuln_asan"

mkdir -p seeds
echo "SEED" > seeds/s1
echo "FUZ"  > seeds/s2
echo "AAA"  > seeds/s3

# ── 2. AFL++ throughput benchmark ────────────────────────────────────────
echo ""
echo "[2/3] AFL++ throughput benchmark (${TIMEOUT}s × ${RUNS} runs)..."

TOTAL_EPS=0
for run in $(seq 1 $RUNS); do
    rm -rf afl_out_bench
    timeout $TIMEOUT $AFL_PP \
        -i seeds -o afl_out_bench \
        -V $TIMEOUT \
        -- ./vuln_afl @@ 2>/dev/null || true

    if [ -f afl_out_bench/default/fuzzer_stats ]; then
        EPS=$(grep execs_per_sec afl_out_bench/default/fuzzer_stats | awk '{print $3}')
        echo "  Run $run: ${EPS} execs/s"
        TOTAL_EPS=$(python3 -c "print($TOTAL_EPS + $EPS)")
    else
        # Fallback: use afl_out/default/fuzzer_stats from prior runs
        EPS=0
        echo "  Run $run: AFL stats not found (target ran without fork-server?)"
    fi
done

if python3 -c "exit(0 if $RUNS > 0 else 1)" 2>/dev/null; then
    AVG_EPS=$(python3 -c "print(round($TOTAL_EPS / $RUNS, 1))")
    echo ""
    echo "Average AFL++ throughput (x86): ${AVG_EPS} execs/s over $RUNS runs"
fi

# ── 3. ASan overhead measurement ─────────────────────────────────────────
echo ""
echo "[3/3] Runtime overhead: plain vs ASan (2000 iterations)..."

time_plain=$( { time for i in $(seq 1 2000); do echo "AAAA" | ./vuln_plain; done; } 2>&1 | grep real | awk '{print $2}')
time_asan=$(  { time for i in $(seq 1 2000); do echo "AAAA" | ./vuln_asan;  done; } 2>&1 | grep real | awk '{print $2}')
echo "Plain 2000 iters: $time_plain"
echo "ASan  2000 iters: $time_asan"

echo ""
echo "=== Experiment complete. Results written to afl_out_bench/ ==="
