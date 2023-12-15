# Makefile
#
# Makefile for 65Tools readelf

project = readelf

include $(BUILD_BASE)/build/rules/global

objects = \
elf_file \
Memory \
readelf

target = readelf
target_version = 1

include $(BUILD_BASE)/build/rules/exec

test:
	../bin/readelf test/testfile
