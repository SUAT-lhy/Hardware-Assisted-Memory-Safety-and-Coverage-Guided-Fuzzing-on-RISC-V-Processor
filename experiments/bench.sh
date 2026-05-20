#!/bin/bash
echo "=== Plain binary (2000 runs) ==="
{ time for i in $(seq 1 2000); do ~/hast_rv/bin/vuln_plain ~/hast_rv/seeds/s1 >/dev/null 2>&1; done; } 2>&1
echo "=== AFL-instrumented (2000 runs) ==="
{ time for i in $(seq 1 2000); do ~/hast_rv/bin/vuln_afl ~/hast_rv/seeds/s1 >/dev/null 2>&1; done; } 2>&1
echo "=== ASan binary (2000 runs) ==="
{ time for i in $(seq 1 2000); do ~/hast_rv/bin/vuln_asan ~/hast_rv/seeds/s1 >/dev/null 2>&1; done; } 2>&1
echo "BENCH_DONE"
