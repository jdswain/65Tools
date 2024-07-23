# Makefile
#
# Makefile for 65Tools assembler

project = as
target = as
target_version = 1

include $(BUILD_BASE)/build/rules/global

src_objects = \
as \
scanner \
parser \
interp \

objects = \
$(src_objects) \
$(target)

dep_objects = \

test_objects = \
$(src_objects) \
test_main

include $(BUILD_BASE)/build/rules/exec

elf:
	readelf -hs -S test.o

link:
	ld -o prog.tim -of tim prog

mem:
	command time -f "%M" ../bin/asd test/wozmon.s -o test.o

test:
	../bin/asd test/first.mod
