This is a collection of build tools for 6502 processors.

as is an assembler, it currently supports:
- MOS 6502
- WDC 65C02 and 65C816
- Rockwell 6502, 6501, 65C19 and later CPU's

as defaults to ELF output suitable for a future operating system. If the -o option specifies .hex as the extension then a binary file will be produced suitable for programming to a ROM, there are other options as well such as Intel Hex and TIM monitor format.
