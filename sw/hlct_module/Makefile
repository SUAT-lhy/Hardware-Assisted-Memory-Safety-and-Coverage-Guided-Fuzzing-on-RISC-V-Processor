obj-m += hlct_mod.o

KDIR ?= /lib/modules/$(shell uname -r)/build

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean

# Cross-compile for RISC-V Linux
cross:
	$(MAKE) -C $(KDIR) M=$(PWD) \
		ARCH=riscv \
		CROSS_COMPILE=riscv64-unknown-linux-gnu- \
		modules
