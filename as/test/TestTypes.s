; Oberon types, constants and names for the symbol file: .type (arrays
; and records, with their type descriptors), LONGINT, open arrays,
; exported constants, and labels spelled like a mnemonic or DIV.
    cpu="816"
    longa=on
    longi=on

    .type Vec = ARRAY 5 OF INTEGER
    .type Dec = RECORD
        sgn, exp: INTEGER
        sig: ARRAY 29 OF CHAR
    END
    .type Form = RECORD style: INTEGER, digits: INTEGER END
    .proc Add(VAR Vec, Vec)
    .proc Div(Form, Vec, VAR Dec)
    .proc Scan(ARRAY OF CHAR, VAR LONGINT): REAL
    .proc Long(LONGINT): LONGINT

Small* = $10
Negative* = -3
Big* = $12345

    section "text"
Add*:   rtl
Div*:   rtl
Scan*:  rtl
Long*:  rtl
