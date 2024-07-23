# Makefile
#
# Makefile for 65Tools Oberon Compiler

project = oc
target = oc
target_version = 1

CFLAGS += -std=c11

include $(BUILD_BASE)/build/rules/global

src_objects = \
ocs \
ocp \
ocb \
ocg \

objects = \
$(src_objects) \

dep_objects = \

test_objects = \
$(src_objects) \
test_main

include $(BUILD_BASE)/build/rules/exec

test:
	../bin/oc test/Module.Mod

assemble:
	../bin/as test/a.asm -o ret

exec:
	../bin/em16 -t ret | more 
