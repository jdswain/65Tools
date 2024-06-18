# Makefile
#
# Makefile for 65Tools Oberon Compiler

project = oc

include $(BUILD_BASE)/build/rules/global

src_objects = \
ocs \
ocp \
ocb \
ocg \
buffered_file \
memory \

objects = \
$(src_objects) \

dep_objects = \

test_objects = \
$(src_objects) \
test_main

target = oc
target_version = 1

include $(BUILD_BASE)/build/rules/exec

