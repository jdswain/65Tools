# Makefile
#
# Makefile for 65Tools assembler

project = as

include $(BUILD_BASE)/build/rules/global

src_objects = \
as \
scanner \
parser \
interp \
codegen \
memory \
buffered_file \
value \
elf_file \
cpu \
oberongen \

objects = \
$(src_objects) \
as

dep_objects = \
gen_02 \
gen_C02 \
gen_RC02 \
gen_816 \
gen_RC19 \

test_objects = \
$(src_objects) \
test_main

target = as
target_version = 1

include $(BUILD_BASE)/build/rules/exec

elf:
	readelf -hs -S test.o

link:
	ld -o prog.tim -of tim prog

mem:
	command time -f "%M" ../bin/asd test/wozmon.s -o test.o

test:
	../bin/asd test/first.mod
