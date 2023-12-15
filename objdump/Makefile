# Makefile
#
# Makefile for 65-objdump

project = objdump

include $(BUILD_BASE)/build/rules/global

src_objects = \
objdump \
memory \
value \
buffered_file \
elf_file \
dis \

objects = \
$(src_objects) \
objdump

target = objdump
target_version = 1

include $(BUILD_BASE)/build/rules/exec

elf:
	readelf -h -S test.o

