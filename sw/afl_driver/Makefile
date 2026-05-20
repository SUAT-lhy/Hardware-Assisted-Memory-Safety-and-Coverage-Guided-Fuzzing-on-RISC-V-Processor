CC_NATIVE  = gcc
CC_RISCV   = riscv64-unknown-linux-gnu-gcc
CFLAGS     = -O2 -Wall -fPIC

# Native x86 build (for testing with software fallback)
all: afl_hlct_driver.o afl_hlct_driver_x86.so

afl_hlct_driver.o: afl_hlct_driver.c
	$(CC_NATIVE) $(CFLAGS) -c -o $@ $<

afl_hlct_driver_x86.so: afl_hlct_driver.c
	$(CC_NATIVE) $(CFLAGS) -shared -o $@ $<

# RISC-V cross-compile
riscv: afl_hlct_driver_riscv.o

afl_hlct_driver_riscv.o: afl_hlct_driver.c
	$(CC_RISCV) $(CFLAGS) -c -o $@ $<

clean:
	rm -f *.o *.so
