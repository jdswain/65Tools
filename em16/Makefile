# Makefile
#
# Makefile for Em16

project = em16
target = em16
target_version = 1

include $(BUILD_BASE)/build/rules/global

src_objects = \
emu816 \
wdc816 \
mem816 \
UART_6551 \
R6501 \
Video \
memory \
main \

objects = \
$(src_objects) \

test_objects = \
$(src_objects) \
test_main

LINKFLAGS += -lutil
CPPFLAGS += `sdl2-config --cflags --libs`
LINKFLAGS += `sdl2-config --cflags --libs`


include $(BUILD_BASE)/build/rules/exec

mem:
	command time -f "%M" ../bin/asd test/wozmon.s -o test.o
