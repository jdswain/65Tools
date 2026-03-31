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
 L28_MCU \
 R6501 \
 WD1793 \
 VIA_6522 \
 ADB_Controller \
 Video \
 LCD_ST7586S \
 memory \
 main

objects = \
$(src_objects)

test_objects = \
$(src_objects) \
test_main

CPPFLAGS += -std=c++17

# Platform-specific flags
ifeq ($(HOST_OSNAME),Darwin)
  LINKFLAGS += -framework Cocoa
else
  CPPFLAGS += `sdl2-config --cflags`
  LINKFLAGS += -lutil `sdl2-config --libs`
endif

include $(BUILD_BASE)/build/rules/exec
