# Build the vpatt-v4l2 module out of tree.
#
# On the target (kernel headers installed):
#     make && sudo make install
#
# Cross-building from the host, e.g.:
#     make KDIR=/path/to/linux-xlnx ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-

obj-m += vpatt-v4l2.o

KDIR ?= /lib/modules/$(shell uname -r)/build
PWD  := $(CURDIR)

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean

install: all
	$(MAKE) -C $(KDIR) M=$(PWD) modules_install
	depmod -a

.PHONY: all clean install
