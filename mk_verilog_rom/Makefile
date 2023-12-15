include $(POCO_BASE)/build/rules/global

objects = ROM

target = rom
target_libs = 

INCLUDE += -I$(PROJECT_BASE)/include

include $(POCO_BASE)/build/rules/exec

run:
	bin/Linux/x86_64/rom

debug:
	gdb bin/Linux/x86_64/romd
