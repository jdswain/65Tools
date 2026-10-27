; Oberon types, constants and names for the symbol file: .type (arrays
; and records, with their type descriptors, and procedure types), LONGINT,
; open arrays, exported constants, and labels spelled like a mnemonic or
; DIV.
    cpu="816"
    longa=on
    longi=on

    .type Vec = ARRAY 5 OF INTEGER
    .type Dec = RECORD
        sgn, exp: INTEGER
        sig: ARRAY 29 OF CHAR
    END
    .type Form = RECORD style: INTEGER, digits: INTEGER END
    .type Handler = PROCEDURE (INTEGER, VAR Vec)
    .type Func = PROCEDURE (REAL): REAL
    .proc Add(VAR Vec, Vec)
    .proc Div(Form, Vec, VAR Dec)
    .proc Scan(ARRAY OF CHAR, VAR LONGINT): REAL
    .proc Long(LONGINT): LONGINT
    .proc Install(Handler): Handler
    .proc Each(PROCEDURE (INTEGER), Func)

Small* = $10
Negative* = -3
Big* = $12345

    section "text"
Add*:   rtl
Div*:   rtl
Scan*:  rtl
Long*:  rtl
Install*: rtl
Each*:  rtl
