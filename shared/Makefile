# Makefile
#
# Makefile for 65Tools shared source

project = shared
target = lib65

include $(BUILD_BASE)/build/rules/global


src_objects = \
codegen \
memory \
buffered_file \
elf_file \
cpu \

objects = \
$(src_objects) \

dep_objects = \
gen_02 \
gen_C02 \
gen_RC02 \
gen_816 \
gen_RC19 \

include $(BUILD_BASE)/build/rules/lib

