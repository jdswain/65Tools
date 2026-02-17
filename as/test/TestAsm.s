	cpu="816"
	longa=on
	longi=on

Twice*:
	asl a
	rtl

Thrice*:
	sta $00
	asl a
	clc
	adc $00
	rtl

_init:
	rtl
