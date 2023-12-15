

const char* names_816[256] = {
  "BRK", "ORA", "COP", "ORA", "TSB", "ORA", "ASL", "ORA", "PHP", "ORA", "ASL", "PHD", "TSB", "ORA", "ASL", "ORA",
  "BPL", "ORA", "ORA", "ORA", "TRB", "ORA", "ASL", "ORA", "CLC", "ORA", "INC", "TCS", "TRB", "ORA", "ASL", "ORA",
  "JSR", "AND", "JSL", "AND", "BIT", "AND", "ROL", "AND", "PLP", "AND", "ROL", "PLD", "BIT", "AND", "ROL", "AND",
  "BMI", "AND", "AND", "AND", "BIT", "AND", "ROL", "AND", "SEC", "AND", "DEC", "TSC", "BIT", "AND", "ROL", "AND",
  "RTI", "EOR", "WDM", "EOR", "MVP", "EOR", "LSR", "EOR", "PHA", "EOR", "LSR", "PHK", "JMP", "EOR", "LSR", "EOR",
  "BVC", "EOR", "EOR", "EOR", "MVN", "EOR", "LSR", "EOR", "CLI", "EOR", "PHY", "TCD", "JMP", "EOR", "LSR", "EOR",
  "RTS", "ADC", "PER", "ADC", "STZ", "ADC", "ROR", "ADC", "PLA", "ADC", "ROR", "RTL", "JMP", "ADC", "ROR", "ADC",
  "BVS", "ADC", "ADC", "ADC", "STZ", "ADC", "ROR", "ADC", "SEI", "ADC", "PLY", "TDC", "JMP", "ADC", "ROR", "ADC",
  "BRA", "STA", "BRL", "STA", "STY", "STA", "STX", "STA", "DEY", "BIT", "TXA", "PHB", "STY", "STA", "STX", "STA",
  "BCC", "STA", "STA", "STA", "STY", "STA", "STX", "STA", "TYA", "STA", "TXS", "TXY", "STZ", "STA", "STZ", "STA", 
  "LDY", "LDA", "LDX", "LDA", "LDY", "LDA", "LDX", "LDA", "TAY", "LDA", "TAX", "PLB", "LDY", "ADC", "LDX", "LDA",
  "BCS", "LDA", "LDA", "LDY", "LDA", "LDY", "LDX", "LDA", "CLV", "LDA", "TSX", "TYX", "LDY", "LDA", "LDX", "LDA",
  "CPY", "CMP", "REP", "CMP", "CPY", "CMP", "DEC", "CMP", "INY", "CMP", "DEX", "WAI", "CPY", "CMP", "DEC", "CMP",
  "BNE", "CMP", "CMP", "CMP", "PEI", "CMP", "DEC", "CMP", "CLD", "CMP", "PHX", "STP", "JML", "CMP", "DEC", "CMP",
  "CPX", "SBC", "SEP", "SBC", "CPX", "SBC", "INC", "SBC", "INX", "SBC", "NOP", "XBA", "CPX", "SBC", "INC", "SBC",
  "BEQ", "SBC", "SBC", "SBC", "PEA", "SBC", "INC", "SBC", "SED", "SBC", "PLX", "XCE", "JSR", "SBC", "INC", "SBC",
};

char modes_816[256] = {/* 0      1       2       3       4       5       6       7       8        9       a       b       c       d       e       f         */
		       si    , dpiix , si    , sr    , dp    , dp    , dp    , dpil  , s     , im    , ac    , s     , ab    , ab    , ab    , al    , /* 0 */
		       pcr   , dpiiy , dpi   , sriiy , dp    , dpix  , dpix  , dpiliy, imp   , aiy   , ac    , imp   , ab    , aix   , aix   , alix  , /* 1 */
		       ab    , dpiix , al    , sr    , dp    , dp    , dp    , dpil  , s     , imp   , ac    , s     , ab    , ab    , ab    , al    , /* 2 */
		       pcr   , dpiiy , dpi   , sriiy , dpix  , dpix  , dpix  , dpiliy, imp   , aiy   , ac    , imp   , aix   , aix   , aix   , alix  , /* 3 */
		       s     , dpiix , si    , sr    , bm    , dp    , dp    , dpil  , s     , imp   , ac    , s     , ab    , ab    , ab    , al    , /* 4 */
		       pcr   , dpiiy , dpi   , sriiy , bm    , dpix  , dpix  , dpiliy, imp   , aiy   , s     , imp   , al    , aix   , aix   , alix  , /* 5 */
		       s     , dpiix , pcrl  , sr    , dp    , dp    , dp    , dpil  , s     , im    , ac    , s     , ai    , ab    , ab    , al    , /* 6 */
		       pcr   , dpiiy , dpi   , sriiy , dpiix , dpix  , dpix  , dpiliy, imp   , aiy   , s     , imp   , aii   , aix   , aix   , alix  , /* 7 */
		       pcr   , dpiix , pcrl  , sr    , dp    , dp    , dp    , dpil  , imp   , im    , imp   , s     , ab    , ab    , ab    , al    , /* 8 */
		       pcr   , dpiiy , dpi   , sriiy , dpix  , dpix  , dpiy  , dpiliy, imp   , aiy   , imp   , imp   , ab    , aix   , aix   , alix  , /* 9 */
		       imp   , dpiix , im    , sr    , dp    , dp    , dp    , dpil  , imp   , im    , imp   , s     , ab    , ab    , ab    , al    , /* a */
		       pcr   , dpiiy , dpi   , sriiy , dpix  , dpix  , dpiy  , dpiliy, imp   , aiy   , imp   , imp   , aix   , aix   , aiy   , alix  , /* b */
		       imp   , dpiix , imp   , sr    , dp    , dp    , dp    , dpil  , imp   , im    , imp   , imp   , ab    , ab    , ab    , al    , /* c */
		       pcr   , dpiiy , dpi   , sriiy , sdpi  , dpix  , dpix  , dpiliy, imp   , aiy   , s     , imp   , ail   , aix   , aix   , alix  , /* d */
		       imp   , dpiix , imp   , sr    , dp    , dp    , dp    , dpil  , imp   , im    , imp   , imp   , ab    , ab    , ab    , al    , /* e */
		       pcr   , dpiiy , dpi   , sriiy , ab    , dpix  , dpix  , dpiliy, imp   , aiy   , s     , imp   , aii   , aix   , aix   , alix  , /* f */
};

