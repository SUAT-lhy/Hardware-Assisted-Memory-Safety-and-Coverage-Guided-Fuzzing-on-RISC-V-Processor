# HAST-RV: Hardware-Assisted Memory Safety and Coverage-Guided Fuzzing on RISC-V

> Implementation artifacts for the CIVS 2026 paper (Springer LNCS)

---

## Overview

**HAST-RV** (Hardware-Assisted Security Testing for RISC-V) extends the open-source **MEISHA V100** RISC-V SoC (RV64GC, quad-core Rocket, Xilinx VC707 FPGA) with two lightweight microarchitectural modules:

| Module | File | Lines | Purpose |
|--------|------|-------|---------|
| MTE-RV | `rtl/mte_rv/DCacheArbiter_mterv.v` | 31 added to DCacheArbiter | Lock-and-key memory tagging via Sv39 unused bits [63:60] |
| HLCT | `rtl/hlct/hlct_top.v` + `axi4lite_bram.v` | 148 + 80 | Passive Commit-stage coverage probe to 64 KB BRAM |

---

## Repository Structure

```
.
|- rtl/
|  |- mte_rv/
|  |  |- DCacheArbiter_mterv.v   # MTE-RV tag-check logic (31 lines added to LSU)
|  |  +- tb_mterv.v              # Icarus Verilog testbench
|  +- hlct/
|     |- hlct_top.v              # HLCT top: XOR hash FSM + AXI4-Lite slave (148 lines)
|     |- axi4lite_bram.v         # 64 KB dual-port BRAM with AXI4-Lite port B (80 lines)
|     +- tb_hlct.v               # Testbench: hash correctness + AXI read-back
|- sw/
|  |- linux/
|  |  +- 0001-riscv-mterv-trap-handler.patch   # Linux RISC-V kernel patch
|  |- glibc/
|  |  +- 0001-glibc-mterv-malloc-tag.patch      # glibc malloc colour injection
|  |- hlct_module/
|  |  |- hlct_mod.c              # /dev/hlct_bram kernel module
|  |  +- Makefile
|  +- afl_driver/
|     |- afl_hlct_driver.c       # AFL++ driver (mmap BRAM -> __afl_area_ptr)
|     +- Makefile
|- sim/
|  |- run_mterv_sim.sh           # Simulate MTE-RV with iverilog
|  +- run_hlct_sim.sh            # Simulate HLCT with iverilog
+- experiments/
   |- vuln_target.c              # Minimal fuzzing target (3 code paths)
   |- bench.sh                   # 2000-iteration overhead benchmark
   |- run_afl.sh                 # AFL++ launch script
   |- run_experiments.sh         # Full x86 experiment suite
   |- run_lavam.sh               # LAVA-M bug-detection experiment
   +- results/
      |- afl_run1_stats.txt      # AFL++ run 1 (65 s): 5,221 execs/s
      |- afl_run2_stats.txt      # AFL++ run 2 (65 s): 5,901 execs/s
      +- afl_run3_stats.txt      # AFL++ run 3 (65 s): 5,801 execs/s
```

---

## RTL Simulation Results

Both modules verified with Icarus Verilog 10.3 on AWS z1d.2xlarge:

### MTE-RV tag-check (6/6 PASS)

```
PASS test 1: addr=5000000000000000 fault=0   correct colour, no fault
PASS test 2: addr=7000000000000000 fault=1   wrong colour -> load access fault (cause=5)
PASS test 3: addr=3000000000000010 fault=0   correct colour, granule 1
PASS test 4: addr=0000000000000000 fault=1   use-after-free (colour 0 != stored 5)
PASS test 5: addr=a000000000000020 fault=0   correct colour, store
PASS test 6: addr=b000000000000020 fault=1   wrong colour -> store access fault (cause=7)
ALL TESTS PASSED
```

### HLCT coverage tracking (3/3 PASS)

```
PASS: hash[0x0800]=0x01   PC 0->0x1000:   H = 0 ^ (0x1000>>1) = 0x0800
PASS: hash[0x0000]=0x01   PC 0x1000->0x2000: H = 0x1000 ^ 0x1000 = 0x0000
PASS: hash[0x3000]=0x01   PC 0x2000->0x2000: H = 0x2000 ^ 0x1000 = 0x3000
ALL TESTS PASSED
```

### How to run simulations

```bash
sudo apt-get install iverilog
cd sim
bash run_mterv_sim.sh    # MTE-RV tag-check correctness
bash run_hlct_sim.sh     # HLCT coverage hash + AXI read-back
```

---

## x86 Reference Experiments

Run on AWS z1d.2xlarge (Intel Xeon Platinum 8151, 3.40 GHz, 8 cores, AFL++ v2.59d).

| Metric | Value | Method |
|--------|-------|--------|
| AFL++ throughput (x86) | 5,641 execs/s avg (3 runs: 5,221 / 5,901 / 5,801) | vuln_target, 60-65 s each |
| ASan overhead (x86) | ~1,198% | 2,000 iter: plain 1.035 s vs ASan 12.397 s |

> **Note on FPGA numbers:** The paper's RISC-V FPGA metrics (HLCT: 4,312 execs/s, 6.9x over SW AFL; MTE-RV overhead: 2.1%) come from execution on the MEISHA V100 prototype (Xilinx VC707, 50 MHz). The x86 measurements above validate the software components and serve as a cross-platform reference point.

### How to reproduce x86 experiments

```bash
cd experiments
sudo apt-get install afl++
gcc -O2 -o vuln_plain vuln_target.c
afl-gcc -O2 -o vuln_afl vuln_target.c
gcc -O2 -fsanitize=address -o vuln_asan vuln_target.c
mkdir -p seeds && echo SEED > seeds/s1 && printf FUZ > seeds/s2 && echo AAAA > seeds/s3
bash run_experiments.sh
```

---

## Software Components

### Linux kernel patch (`sw/linux/`)

Modifies `arch/riscv/kernel/traps.c`: detects MTE-RV tag-mismatch faults and delivers `SIGSEGV` with `si_code = SEGV_MTEAERR`. Applies to Linux 6.1 RISC-V.

### glibc patch (`sw/glibc/`)

Instruments `malloc.c`: assigns random 4-bit colour at every `malloc()`, writes colour to tag shadow memory; zeroes tag at `free()` to catch use-after-free. Applies to glibc 2.37.

### HLCT kernel module (`sw/hlct_module/`)

Exposes the HLCT BRAM physical range (AXI4-Lite base 0x7000_0000) as character device `/dev/hlct_bram` for unprivileged `mmap()`.

Build for RISC-V:
```bash
cd sw/hlct_module
make KDIR=/path/to/riscv-linux cross
```

### AFL++ driver (`sw/afl_driver/`)

Replaces AFL++'s LLVM instrumentation shared memory with a direct `mmap()` of `/dev/hlct_bram`, setting `__afl_area_ptr` to the hardware coverage map. Falls back to software SHM on x86 hosts.

Build:
```bash
cd sw/afl_driver
make               # x86 native (for testing SW fallback)
make riscv         # RISC-V cross-compile
```

---

## Hardware Platform

- **Processor**: MEISHA V100 - open-source RV64GC SoC (4x Rocket cores, 5-stage in-order pipeline)
- **FPGA**: Xilinx VC707 (Virtex-7 XC7VX485T), 50 MHz
- **Memory**: 512 KB on-chip IRAM + 1 GB DDR3 SDRAM
- Platform source: [MEISHA V100 GitHub](https://github.com/SUAT-lhy/MEISHAV100---FPGA-verification-on-VC707)

---

## References

- ARM MTE: ARM DDI 0600A (2019)
- LAVA-M benchmark: Dolan-Gavitt et al., IEEE S&P 2016
- AFL++: Fioraldi et al., USENIX WOOT 2020
- TIMBER-V: Weiser et al., NDSS 2019
- kAFL: Schumilo et al., USENIX Security 2017

---

*Submitted to CIVS 2026 (Springer LNCS). Supported by the Guangdong Science and Technology Programme and the SUAT Research Fund.*
