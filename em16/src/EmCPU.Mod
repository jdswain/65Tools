MODULE EmCPU; (* The processor: the WDC 65C816, the Rockwell R65C02 and the
   L28's R65C19, after emu816 by Andrew John Jacobs.

   em16 is based on emu816, Copyright (C) 2016 Andrew John Jacobs, made
   available under the Creative Commons Attribution-NonCommercial-
   ShareAlike 4.0 International license
   (http://creativecommons.org/licenses/by-nc-sa/4.0/); this port is
   under the same license.

   The registers are integers: a, x, y, sp and dp hold 16 bits, and
   where the C++ wrote to the low byte of one (a.b) the high byte is kept.
   The flags are separate 0/1 integers, put together in GetP. Each
   instruction is an addressing mode, which fetches the operand bytes and
   returns the address of the operand, and an operation; the opcode
   tables at the end are generated from emu816.cpp (tools/gendispatch.py).

   The behaviour of em16 is kept, including where it differs from the
   chip (TCD sets no flags, JMP (a) leaves PBR 0, PEI pushes the word the
   pointer points to, TXS in native mode with 8 bit index registers puts
   the stack in page sp_page, (d,S),Y writes a line to standard output),
   and so is the trace, so that the two can be compared. *)

  IMPORT EmHost, EmSym, EmMem, EmVIA, EmL28;

  CONST
    wdc* = 0; rockwell* = 1; l28* = 2;
    crashLogSize = 64;

  TYPE
    TrapHandler* = PROCEDURE (n: INTEGER);
    CrashEntry = RECORD pc, a, x, y, sp, op: INTEGER END;

  VAR
    a, x, y, sp, dp, pc, pbr, dbr: INTEGER;
    e, fc, fz, fi, fd, fx, fm, fv, fn: INTEGER;
    spPage, iReg, wh, wl: INTEGER;
    stopped, interrupted, trace: BOOLEAN;
    cycles*: LONGINT;
    cpuType*: INTEGER;
    trap: TrapHandler;

    crashLog: ARRAY crashLogSize OF CrashEntry;
    crashIdx: INTEGER;

  (* --- the interface --- *)

  PROCEDURE SetCpuType*(t: INTEGER);
  BEGIN cpuType := t
  END SetCpuType;

  PROCEDURE SetStackPage*(addr: INTEGER);
  BEGIN spPage := addr
  END SetStackPage;

  PROCEDURE SetTrapHandler*(h: TrapHandler);
  BEGIN trap := h
  END SetTrapHandler;

  PROCEDURE GetA*(): INTEGER;
  BEGIN RETURN a
  END GetA;

  PROCEDURE SetA*(v: INTEGER);
  BEGIN a := AND(v, 0FFFFH)
  END SetA;

  PROCEDURE SetX*(v: INTEGER);
  BEGIN x := AND(v, 0FFFFH)
  END SetX;

  PROCEDURE GetPBR*(): INTEGER;
  BEGIN RETURN pbr
  END GetPBR;

  PROCEDURE GetPC*(): INTEGER;
  BEGIN RETURN pc
  END GetPC;

  PROCEDURE SetDP*(v: INTEGER);
  BEGIN dp := AND(v, 0FFFFH)
  END SetDP;

  PROCEDURE SetSP*(v: INTEGER);
  BEGIN sp := AND(v, 0FFFFH)
  END SetSP;

  PROCEDURE IsStopped*(): BOOLEAN;
  BEGIN RETURN stopped
  END IsStopped;

  PROCEDURE Stop*;
  BEGIN stopped := TRUE
  END Stop;

  (* Native mode, 16 bit registers, binary arithmetic. *)
  PROCEDURE SetNativeMode*;
  BEGIN e := 0; fm := 0; fx := 0; fd := 0
  END SetNativeMode;


  (* --- helpers --- *)

  PROCEDURE M8(): BOOLEAN;          (* 8 bit accumulator and memory *)
  BEGIN RETURN (e # 0) OR (fm # 0)
  END M8;

  PROCEDURE X8(): BOOLEAN;          (* 8 bit index registers *)
  BEGIN RETURN (e # 0) OR (fx # 0)
  END X8;

  PROCEDURE Lo(v: INTEGER): INTEGER;
  BEGIN RETURN AND(v, 0FFH)
  END Lo;

  PROCEDURE Hi(v: INTEGER): INTEGER;
  BEGIN RETURN AND(v DIV 256, 0FFH)
  END Hi;

  (* The 16 bit register r with its low byte replaced. *)
  PROCEDURE WithLo(r, v: INTEGER): INTEGER;
  BEGIN RETURN ORA(AND(r, 0FF00H), AND(v, 0FFH))
  END WithLo;

  PROCEDURE Bank(b: INTEGER): INTEGER;
  BEGIN RETURN b * 10000H
  END Bank;

  PROCEDURE Join(b, w: INTEGER): INTEGER;      (* bank and address *)
  BEGIN RETURN ORA(b * 10000H, w)
  END Join;

  PROCEDURE GetP*(): INTEGER;
  BEGIN RETURN fc + fz * 2 + fi * 4 + fd * 8 + fx * 16 + fm * 32 + fv * 64 + fn * 128
  END GetP;

  PROCEDURE SetP(b: INTEGER);
  BEGIN
    fc := AND(b, 1); fz := LSR(b, 1) MOD 2; fi := LSR(b, 2) MOD 2; fd := LSR(b, 3) MOD 2;
    fx := LSR(b, 4) MOD 2; fm := LSR(b, 5) MOD 2; fv := LSR(b, 6) MOD 2; fn := LSR(b, 7) MOD 2
  END SetP;

  PROCEDURE Bool(b: BOOLEAN): INTEGER;
    VAR r: INTEGER;
  BEGIN IF b THEN r := 1 ELSE r := 0 END; RETURN r
  END Bool;

  PROCEDURE NZB(v: INTEGER);
  BEGIN v := AND(v, 0FFH); fn := v DIV 128; fz := Bool(v = 0)
  END NZB;

  PROCEDURE NZW(v: INTEGER);
  BEGIN v := AND(v, 0FFFFH); fn := v DIV 8000H; fz := Bool(v = 0)
  END NZW;

  PROCEDURE GetByte(ea: INTEGER): INTEGER;
  BEGIN RETURN EmMem.GetByte(ea)
  END GetByte;

  PROCEDURE GetWord(ea: INTEGER): INTEGER;
  BEGIN RETURN EmMem.GetByte(ea) + EmMem.GetByte(ea + 1) * 256
  END GetWord;

  PROCEDURE GetAddr(ea: INTEGER): INTEGER;
  BEGIN RETURN GetWord(ea) + EmMem.GetByte(ea + 2) * 10000H
  END GetAddr;

  PROCEDURE SetByte(ea, v: INTEGER);
  BEGIN EmMem.SetByte(ea, AND(v, 0FFH))
  END SetByte;

  PROCEDURE SetWord(ea, v: INTEGER);
  BEGIN EmMem.SetByte(ea, AND(v, 0FFH)); EmMem.SetByte(ea + 1, AND(v DIV 256, 0FFH))
  END SetWord;

  PROCEDURE PushByte(v: INTEGER);
  BEGIN SetByte(sp, v);
    IF e # 0 THEN sp := WithLo(sp, sp - 1) ELSE sp := AND(sp - 1, 0FFFFH) END
  END PushByte;

  PROCEDURE PushWord(v: INTEGER);
  BEGIN PushByte(Hi(v)); PushByte(Lo(v))
  END PushWord;

  PROCEDURE PullByte(): INTEGER;
  BEGIN
    IF e # 0 THEN sp := WithLo(sp, sp + 1) ELSE sp := AND(sp + 1, 0FFFFH) END;
    RETURN GetByte(sp)
  END PullByte;

  PROCEDURE PullWord(): INTEGER;
    VAR l, h: INTEGER;
  BEGIN l := PullByte(); h := PullByte();
    RETURN l + h * 256
  END PullWord;

  (* Signed 8 and 16 bit values. *)
  PROCEDURE S8(v: INTEGER): INTEGER;
  BEGIN v := AND(v, 0FFH); IF v >= 80H THEN v := v - 100H END; RETURN v
  END S8;

  PROCEDURE S16(v: INTEGER): INTEGER;
  BEGIN v := AND(v, 0FFFFH); IF v >= 8000H THEN v := v - 10000H END; RETURN v
  END S16;

  (* --- the trace --- *)

  PROCEDURE ToHex(v, n: INTEGER);
  BEGIN EmHost.ToHex(EmHost.err, v, n)
  END ToHex;

  PROCEDURE ErrCh(ch: CHAR);
  BEGIN EmHost.Ch(EmHost.err, ch)
  END ErrCh;

  PROCEDURE ErrStr(s: ARRAY OF CHAR);
  BEGIN EmHost.Str(EmHost.err, s)
  END ErrStr;


  (* The program counter and the opcode. *)
  PROCEDURE Show;
  BEGIN EmSym.Word(Join(pbr, pc)); ErrCh(" "); ToHex(GetByte(Join(pbr, pc)), 2)
  END Show;

  (* The operand bytes. *)
  PROCEDURE Bytes(count: INTEGER);
    VAR i: INTEGER;
  BEGIN
    FOR i := 0 TO 2 DO
      IF count > i THEN ErrCh(" "); ToHex(GetByte(ORA(Bank(pbr), pc + i)), 2) ELSE ErrStr("   ") END
    END;
    ErrCh(" ")
  END Bytes;

  PROCEDURE Flag(f: INTEGER; ch: CHAR);
  BEGIN IF f # 0 THEN ErrCh(ch) ELSE ErrCh(".") END
  END Flag;

  PROCEDURE Reg(name: ARRAY OF CHAR; v: INTEGER; short: BOOLEAN);
  BEGIN ErrStr(name);
    IF short THEN ToHex(Hi(v), 2); ErrCh("[") ELSE ErrCh("["); ToHex(Hi(v), 2) END;
    ToHex(Lo(v), 2); ErrCh("]")
  END Reg;

  (* The mnemonic, the operand's address, the registers, the top of the
     stack and the start of the direct page. *)
  PROCEDURE Dump(mnem: ARRAY OF CHAR; ea: INTEGER);
    VAR i: INTEGER;
  BEGIN ErrStr(mnem); ErrStr(" {"); EmSym.Word(ea); ErrCh("}");
    ErrStr(" E="); ToHex(e, 1);
    ErrStr(" P="); Flag(fn, "N"); Flag(fv, "V"); Flag(fm, "M"); Flag(fx, "X");
    Flag(fd, "D"); Flag(fi, "I"); Flag(fz, "Z"); Flag(fc, "C");
    Reg(" A=", a, M8()); Reg(" X=", x, X8()); Reg(" Y=", y, X8());
    ErrStr(" DP="); ToHex(dp, 4);
    Reg(" SP=", sp, e # 0);
    ErrStr(" {");
    FOR i := 0 TO 3 DO ErrCh(" "); ToHex(GetWord(sp + 1 + 2 * i), 4) END;
    ErrStr(" }"); ErrStr(" DP="); ErrStr(" {");
    FOR i := 0 TO 7 DO ErrCh(" "); ToHex(EmMem.Peek(dp + i), 2) END;
    ErrStr(" }"); ErrStr(" DBR="); ToHex(dbr, 2);
    IF cpuType = l28 THEN ErrStr(" I="); ToHex(iReg, 4); ErrStr(" W="); ToHex(wh, 2); ToHex(wl, 2) END;
    EmHost.Ln(EmHost.err)
  END Dump;

  PROCEDURE T(mnem: ARRAY OF CHAR; ea: INTEGER);
  BEGIN IF trace THEN Dump(mnem, ea) END
  END T;

  (* Step over n operand bytes. *)
  PROCEDURE Skip(n: INTEGER);
  BEGIN
    IF trace THEN Bytes(n) END;
    pc := AND(pc + n, 0FFFFH)
  END Skip;

  (* --- addressing modes --- *)

  PROCEDURE Absl(): INTEGER;        (* a *)
    VAR ea: INTEGER;
  BEGIN ea := Join(dbr, GetWord(ORA(Bank(pbr), pc)));
    Skip(2); INC(cycles, 2); RETURN ea
  END Absl;

  PROCEDURE Absx(): INTEGER;        (* a,X *)
    VAR ea: INTEGER;
  BEGIN ea := Join(dbr, GetWord(ORA(Bank(pbr), pc)));
    IF X8() THEN ea := ea + Lo(x) ELSE ea := ea + x END;
    Skip(2); INC(cycles, 2); RETURN ea
  END Absx;

  PROCEDURE Absy(): INTEGER;        (* a,Y *)
    VAR ea: INTEGER;
  BEGIN ea := Join(dbr, GetWord(ORA(Bank(pbr), pc)));
    IF X8() THEN ea := ea + Lo(y) ELSE ea := ea + y END;
    Skip(2); INC(cycles, 2); RETURN ea
  END Absy;

  PROCEDURE Absi(): INTEGER;        (* (a) *)
    VAR ia: INTEGER;
  BEGIN ia := GetWord(ORA(Bank(pbr), pc));
    Skip(2); INC(cycles, 4); RETURN GetWord(ia)
  END Absi;

  PROCEDURE Abxi(): INTEGER;        (* (a,X) *)
    VAR ia: INTEGER;
  BEGIN ia := Join(pbr, GetWord(Join(pbr, pc))) + x;
    Skip(2); INC(cycles, 4); RETURN Join(pbr, GetWord(ia))
  END Abxi;

  PROCEDURE Alng(): INTEGER;        (* al *)
    VAR ea: INTEGER;
  BEGIN ea := GetAddr(Join(pbr, pc));
    Skip(3); INC(cycles, 3); RETURN ea
  END Alng;

  PROCEDURE Alnx(): INTEGER;        (* al,X *)
    VAR ea: INTEGER;
  BEGIN ea := GetAddr(Join(pbr, pc)) + x;
    Skip(3); INC(cycles, 3); RETURN ea
  END Alnx;

  PROCEDURE Abil(): INTEGER;        (* [a] *)
    VAR ia: INTEGER;
  BEGIN ia := GetWord(Join(pbr, pc));
    Skip(2); INC(cycles, 5); RETURN GetAddr(ia)
  END Abil;

  PROCEDURE Dpag(): INTEGER;        (* d *)
    VAR d: INTEGER;
  BEGIN d := GetByte(ORA(Bank(pbr), pc));
    Skip(1); INC(cycles, 1); RETURN AND(dp + d, 0FFFFH)
  END Dpag;

  (* In emulation mode with the low byte of D zero the index wraps in the
     direct page, as on the 6502; otherwise it does not. *)
  PROCEDURE Dpgx(): INTEGER;        (* d,X *)
    VAR d, ea: INTEGER;
  BEGIN d := GetByte(ORA(Bank(pbr), pc));
    Skip(1); INC(cycles, 1);
    IF (e # 0) & (Lo(dp) = 0) THEN ea := ORA(dp, AND(d + Lo(x), 0FFH))
    ELSE ea := AND(dp + d + x, 0FFFFH)
    END;
    RETURN ea
  END Dpgx;

  PROCEDURE Dpgy(): INTEGER;        (* d,Y *)
    VAR d, ea: INTEGER;
  BEGIN d := GetByte(ORA(Bank(pbr), pc));
    Skip(1); INC(cycles, 1);
    IF (e # 0) & (Lo(dp) = 0) THEN ea := ORA(dp, AND(d + Lo(y), 0FFH))
    ELSE ea := AND(dp + d + y, 0FFFFH)
    END;
    RETURN ea
  END Dpgy;

  PROCEDURE Dpgi(): INTEGER;        (* (d) *)
    VAR d: INTEGER;
  BEGIN d := GetByte(ORA(Bank(pbr), pc));
    Skip(1); INC(cycles, 3); RETURN ORA(Bank(dbr), GetWord(AND(dp + d, 0FFFFH)))
  END Dpgi;

  PROCEDURE Dpix(): INTEGER;        (* (d,X) *)
    VAR d, ea: INTEGER;
  BEGIN d := GetByte(Join(pbr, pc));
    Skip(1); INC(cycles, 3);
    IF (e # 0) & (Lo(dp) = 0) THEN ea := ORA(Bank(dbr), GetWord(ORA(dp, AND(d + Lo(x), 0FFH))))
    ELSE ea := ORA(Bank(dbr), GetWord(AND(dp + d + x, 0FFFFH)))
    END;
    RETURN ea
  END Dpix;

  PROCEDURE Dpiy(): INTEGER;        (* (d),Y *)
    VAR d: INTEGER;
  BEGIN d := GetByte(Join(pbr, pc));
    Skip(1); INC(cycles, 3); RETURN ORA(Bank(dbr), GetWord(dp + d) + y)
  END Dpiy;

  PROCEDURE Diix(): INTEGER;        (* (d),X *)
    VAR d: INTEGER;
  BEGIN d := GetByte(Join(pbr, pc));
    Skip(1); INC(cycles, 3); RETURN ORA(Bank(dbr), GetWord(dp + d) + x)
  END Diix;

  PROCEDURE Dpil(): INTEGER;        (* [d] *)
    VAR d: INTEGER;
  BEGIN d := GetByte(Join(pbr, pc));
    Skip(1); INC(cycles, 4); RETURN GetAddr(AND(dp + d, 0FFFFH))
  END Dpil;

  PROCEDURE Dily(): INTEGER;        (* [d],Y *)
    VAR d: INTEGER;
  BEGIN d := GetByte(Join(pbr, pc));
    Skip(1); INC(cycles, 4); RETURN GetAddr(AND(dp + d, 0FFFFH)) + y
  END Dily;

  PROCEDURE Impl(): INTEGER;        (* implied, stack *)
  BEGIN Skip(0); RETURN 0
  END Impl;

  PROCEDURE Acc(): INTEGER;         (* accumulator *)
  BEGIN Skip(0); RETURN 0
  END Acc;

  PROCEDURE Immb(): INTEGER;        (* #b *)
    VAR ea: INTEGER;
  BEGIN ea := ORA(Bank(pbr), pc); Skip(1); RETURN ea
  END Immb;

  PROCEDURE Immw(): INTEGER;        (* #w *)
    VAR ea: INTEGER;
  BEGIN ea := ORA(Bank(pbr), pc); Skip(2); INC(cycles); RETURN ea
  END Immw;

  PROCEDURE Immm(): INTEGER;        (* # as wide as A *)
    VAR ea, n: INTEGER;
  BEGIN ea := Join(pbr, pc);
    IF M8() THEN n := 1 ELSE n := 2 END;
    Skip(n); INC(cycles, n - 1); RETURN ea
  END Immm;

  PROCEDURE Immx(): INTEGER;        (* # as wide as X *)
    VAR ea, n: INTEGER;
  BEGIN ea := Join(pbr, pc);
    IF X8() THEN n := 1 ELSE n := 2 END;
    Skip(n); INC(cycles, n - 1); RETURN ea
  END Immx;

  PROCEDURE Lrel(): INTEGER;        (* rl *)
    VAR d: INTEGER;
  BEGIN d := GetWord(Join(pbr, pc));
    Skip(2); INC(cycles, 2); RETURN ORA(Bank(pbr), AND(pc + S16(d), 0FFFFH))
  END Lrel;

  PROCEDURE Rela(): INTEGER;        (* r *)
    VAR d: INTEGER;
  BEGIN d := GetByte(Join(pbr, pc));
    Skip(1); INC(cycles); RETURN ORA(Bank(pbr), AND(pc + S8(d), 0FFFFH))
  END Rela;

  PROCEDURE Srel(): INTEGER;        (* d,S *)
    VAR d, ea: INTEGER;
  BEGIN d := GetByte(Join(pbr, pc));
    Skip(1); INC(cycles);
    IF e # 0 THEN ea := AND(Lo(sp) + d, 0FFH) + Hi(sp) * 256
    ELSE ea := AND(sp + d, 0FFFFH)
    END;
    RETURN ea
  END Srel;

  PROCEDURE Sriy(): INTEGER;        (* (d,S),Y *)
    VAR d, ia: INTEGER;
  BEGIN d := GetByte(Join(pbr, pc));
    Skip(1); INC(cycles, 3);
    IF e # 0 THEN ia := GetWord(AND(Lo(sp) + d, 0FFH) + Hi(sp) * 256)
    ELSE ia := GetWord(sp + d)
    END;
    (* emu816 printed this, the displacement as a character *)
    EmHost.Str(EmHost.out, "disp = "); EmHost.Ch(EmHost.out, CHR(d));
    EmHost.Str(EmHost.out, ", addr = "); EmHost.CoutHex(sp + d);
    EmHost.Str(EmHost.out, ",ia = "); EmHost.Cout(ia); EmHost.Ln(EmHost.out); EmHost.Flush;
    RETURN ORA(Bank(dbr), AND(ia + y, 0FFFFH))
  END Sriy;

  (* --- operations --- *)

  (* Decimal arithmetic a digit at a time; c is the carry in and out. *)
  PROCEDURE BcdAdd(p, q: INTEGER; VAR c: INTEGER; digits: INTEGER): INTEGER;
    VAR i, d, r, sh: INTEGER;
  BEGIN r := 0; sh := 1;
    FOR i := 0 TO digits - 1 DO
      d := (p DIV sh) MOD 16 + (q DIV sh) MOD 16 + c;
      IF d > 9 THEN d := d + 6 END;
      c := Bool(d > 0FH);
      r := r + (d MOD 16) * sh; sh := sh * 16
    END;
    RETURN r
  END BcdAdd;

  (* c: 1 = no borrow *)
  PROCEDURE BcdSub(p, q: INTEGER; VAR c: INTEGER; digits: INTEGER): INTEGER;
    VAR i, d, r, sh: INTEGER;
  BEGIN r := 0; sh := 1;
    FOR i := 0 TO digits - 1 DO
      d := (p DIV sh) MOD 16 - (q DIV sh) MOD 16 - (1 - c);
      IF d < 0 THEN d := d + 10; c := 0 ELSE c := 1 END;
      r := r + (d MOD 16) * sh; sh := sh * 16
    END;
    RETURN r
  END BcdSub;

  (* The V flag of an addition of p and q giving r, sign bit s. *)
  PROCEDURE Overflow(p, q, r, s: INTEGER): INTEGER;
  BEGIN RETURN Bool((AND(EOR(p, q), s) = 0) & (AND(EOR(p, r), s) # 0))
  END Overflow;

  PROCEDURE Adc(ea: INTEGER);
    VAR data, t, c: INTEGER;
  BEGIN T("ADC", ea);
    IF M8() THEN data := GetByte(ea); t := Lo(a) + data + fc;
      IF fd # 0 THEN c := fc; t := BcdAdd(Lo(a), data, c, 2) + c * 100H END;
      fc := Bool(AND(t, 100H) # 0); fv := Overflow(Lo(a), data, t, 80H);
      a := WithLo(a, t); NZB(t); INC(cycles, 2)
    ELSE data := GetWord(ea); t := a + data + fc;
      IF fd # 0 THEN c := fc; t := BcdAdd(a, data, c, 4) + c * 10000H END;
      fc := Bool(AND(t, 10000H) # 0); fv := Overflow(a, data, t, 8000H);
      a := AND(t, 0FFFFH); NZW(a); INC(cycles, 2)
    END
  END Adc;

  PROCEDURE Sbc(ea: INTEGER);
    VAR data, t, c: INTEGER;
  BEGIN T("SBC", ea);
    IF M8() THEN data := 0FFH - GetByte(ea); t := Lo(a) + data + fc;
      IF fd # 0 THEN c := fc; t := BcdSub(Lo(a), 0FFH - data, c, 2) + c * 100H END;
      fc := Bool(AND(t, 100H) # 0); fv := Overflow(Lo(a), data, t, 80H);
      a := WithLo(a, t); NZB(t); INC(cycles, 2)
    ELSE data := 0FFFFH - GetWord(ea); t := a + data + fc;
      IF fd # 0 THEN c := fc; t := BcdSub(a, 0FFFFH - data, c, 4) + c * 10000H END;
      fc := Bool(AND(t, 10000H) # 0); fv := Overflow(a, data, t, 8000H);
      a := AND(t, 0FFFFH); NZW(a); INC(cycles, 3)
    END
  END Sbc;

  PROCEDURE Add(ea: INTEGER);
    VAR data, t: INTEGER;
  BEGIN T("ADD", ea);
    IF M8() THEN data := GetByte(ea); t := Lo(a) + data;
      fc := Bool(AND(t, 100H) # 0); fv := Overflow(Lo(a), data, t, 80H);
      a := WithLo(a, t); NZB(t)
    ELSE data := GetWord(ea); t := a + data;
      fc := Bool(AND(t, 10000H) # 0); fv := Overflow(a, data, t, 8000H);
      a := AND(t, 0FFFFH); NZW(a)
    END;
    INC(cycles, 2)
  END Add;

  PROCEDURE And(ea: INTEGER);
  BEGIN T("AND", ea);
    IF M8() THEN a := WithLo(a, AND(a, GetByte(ea))); NZB(a); INC(cycles, 2)
    ELSE a := AND(a, GetWord(ea)); NZW(a); INC(cycles, 3)
    END
  END And;

  PROCEDURE Ora(ea: INTEGER);
  BEGIN T("ORA", ea);
    IF M8() THEN a := WithLo(a, ORA(Lo(a), GetByte(ea))); NZB(a); INC(cycles, 2)
    ELSE a := ORA(a, GetWord(ea)); NZW(a); INC(cycles, 3)
    END
  END Ora;

  PROCEDURE Eor(ea: INTEGER);
  BEGIN T("EOR", ea);
    IF M8() THEN a := WithLo(a, EOR(Lo(a), GetByte(ea))); NZB(a); INC(cycles, 2)
    ELSE a := EOR(a, GetWord(ea)); NZW(a); INC(cycles, 3)
    END
  END Eor;

  PROCEDURE Asl(ea: INTEGER);
    VAR data: INTEGER;
  BEGIN T("ASL", ea);
    IF M8() THEN data := GetByte(ea); fc := data DIV 80H;
      data := AND(data * 2, 0FFH); NZB(data); SetByte(ea, data); INC(cycles, 4)
    ELSE data := GetWord(ea); fc := data DIV 8000H;
      data := AND(data * 2, 0FFFFH); NZW(data); SetWord(ea, data); INC(cycles, 5)
    END
  END Asl;

  PROCEDURE Asla(ea: INTEGER);
  BEGIN T("ASL", ea);
    IF M8() THEN fc := Lo(a) DIV 80H; a := WithLo(a, Lo(a) * 2); NZB(a)
    ELSE fc := a DIV 8000H; a := AND(a * 2, 0FFFFH); NZW(a)
    END;
    INC(cycles, 2)
  END Asla;

  PROCEDURE Asra(ea: INTEGER);
  BEGIN T("ASR", ea);
    IF M8() THEN fc := AND(a, 1); a := WithLo(a, Lo(a) DIV 2 + AND(a, 80H)); NZB(a)
    ELSE fc := AND(a, 1); a := a DIV 2 + AND(a, 8000H); NZW(a)
    END;
    INC(cycles, 2)
  END Asra;

  PROCEDURE Lsr(ea: INTEGER);
    VAR data: INTEGER;
  BEGIN T("LSR", ea);
    IF M8() THEN data := GetByte(ea); fc := AND(data, 1);
      data := data DIV 2; NZB(data); SetByte(ea, data); INC(cycles, 4)
    ELSE data := GetWord(ea); fc := AND(data, 1);
      data := data DIV 2; NZW(data); SetWord(ea, data); INC(cycles, 5)
    END
  END Lsr;

  PROCEDURE Lsra(ea: INTEGER);
  BEGIN T("LSR", ea);
    IF M8() THEN fc := AND(a, 1); a := WithLo(a, Lo(a) DIV 2); NZB(a)
    ELSE fc := AND(a, 1); a := a DIV 2; NZW(a)
    END;
    INC(cycles, 2)
  END Lsra;

  PROCEDURE Rol(ea: INTEGER);
    VAR data, c: INTEGER;
  BEGIN T("ROL", ea); c := fc;
    IF M8() THEN data := GetByte(ea); fc := data DIV 80H;
      data := AND(data * 2 + c, 0FFH); NZB(data); SetByte(ea, data); INC(cycles, 4)
    ELSE data := GetWord(ea); fc := data DIV 8000H;
      data := AND(data * 2 + c, 0FFFFH); NZW(data); SetWord(ea, data); INC(cycles, 5)
    END
  END Rol;

  PROCEDURE Rola(ea: INTEGER);
    VAR c: INTEGER;
  BEGIN T("ROL", ea); c := fc;
    IF M8() THEN fc := Lo(a) DIV 80H; a := WithLo(a, Lo(a) * 2 + c); NZB(a)
    ELSE fc := a DIV 8000H; a := AND(a * 2 + c, 0FFFFH); NZW(a)
    END;
    INC(cycles, 2)
  END Rola;

  PROCEDURE Ror(ea: INTEGER);
    VAR data, c: INTEGER;
  BEGIN T("ROR", ea); c := fc;
    IF M8() THEN data := GetByte(ea); fc := AND(data, 1);
      data := data DIV 2 + c * 80H; NZB(data); SetByte(ea, data); INC(cycles, 4)
    ELSE data := GetWord(ea); fc := AND(data, 1);
      data := data DIV 2 + c * 8000H; NZW(data); SetWord(ea, data); INC(cycles, 5)
    END
  END Ror;

  PROCEDURE Rora(ea: INTEGER);
    VAR c: INTEGER;
  BEGIN T("ROR", ea); c := fc;
    IF M8() THEN fc := AND(a, 1); a := WithLo(a, Lo(a) DIV 2 + c * 80H); NZB(a)
    ELSE fc := AND(a, 1); a := a DIV 2 + c * 8000H; NZW(a)
    END;
    INC(cycles, 2)
  END Rora;

  PROCEDURE Branch(mnem: ARRAY OF CHAR; cond: BOOLEAN; ea: INTEGER);
  BEGIN T(mnem, ea);
    IF cond THEN
      IF (e # 0) & (AND(EOR(pc, ea), 0FF00H) # 0) THEN INC(cycles) END;
      pc := AND(ea, 0FFFFH); INC(cycles, 3)
    ELSE INC(cycles, 2)
    END
  END Branch;

  PROCEDURE Bcc(ea: INTEGER); BEGIN Branch("BCC", fc = 0, ea) END Bcc;
  PROCEDURE Bcs(ea: INTEGER); BEGIN Branch("BCS", fc = 1, ea) END Bcs;
  PROCEDURE Beq(ea: INTEGER); BEGIN Branch("BEQ", fz = 1, ea) END Beq;
  PROCEDURE Bne(ea: INTEGER); BEGIN Branch("BNE", fz = 0, ea) END Bne;
  PROCEDURE Bmi(ea: INTEGER); BEGIN Branch("BMI", fn = 1, ea) END Bmi;
  PROCEDURE Bpl(ea: INTEGER); BEGIN Branch("BPL", fn = 0, ea) END Bpl;
  PROCEDURE Bvc(ea: INTEGER); BEGIN Branch("BVC", fv = 0, ea) END Bvc;
  PROCEDURE Bvs(ea: INTEGER); BEGIN Branch("BVS", fv = 1, ea) END Bvs;
  PROCEDURE Bra(ea: INTEGER); BEGIN Branch("BRA", TRUE, ea) END Bra;

  PROCEDURE Brl(ea: INTEGER);
  BEGIN T("BRL", ea); pc := AND(ea, 0FFFFH); INC(cycles, 3)
  END Brl;

  PROCEDURE Bit(ea: INTEGER);
    VAR data: INTEGER;
  BEGIN T("BIT", ea);
    IF M8() THEN data := GetByte(ea);
      fz := Bool(AND(Lo(a), data) = 0); fn := data DIV 80H; fv := LSR(data, 6) MOD 2; INC(cycles, 2)
    ELSE data := GetWord(ea);
      fz := Bool(AND(a, data) = 0); fn := data DIV 8000H; fv := LSR(data, 14) MOD 2; INC(cycles, 3)
    END
  END Bit;

  PROCEDURE Biti(ea: INTEGER);
  BEGIN T("BIT", ea);
    IF M8() THEN fz := Bool(AND(Lo(a), GetByte(ea)) = 0)
    ELSE fz := Bool(AND(a, GetWord(ea)) = 0)
    END;
    INC(cycles, 2)
  END Biti;

  (* An interrupt through vector v (emulation mode: ve). *)
  PROCEDURE Interrupt(v, ve, p: INTEGER);
  BEGIN
    IF e # 0 THEN PushWord(pc); PushByte(p); fi := 1; fd := 0; pbr := 0;
      pc := GetWord(ve); INC(cycles, 7)
    ELSE PushByte(pbr); PushWord(pc); PushByte(p); fi := 1; fd := 0; pbr := 0;
      pc := GetWord(v); INC(cycles, 8)
    END
  END Interrupt;

  (* BRK #0 to #15 are traps of the compiler's run time. *)
  PROCEDURE Brk(ea: INTEGER);
    VAR n: INTEGER;
  BEGIN T("BRK", ea); n := GetByte(ea);
    IF (n <= 15) & (trap # NIL) THEN trap(n); INC(cycles, 2)
    ELSIF e # 0 THEN Interrupt(0FFE6H, 0FFFEH, ORA(GetP(), 10H))
    ELSE Interrupt(0FFE6H, 0FFFEH, GetP())
    END
  END Brk;

  PROCEDURE Cop(ea: INTEGER);
  BEGIN T("COP", ea); Interrupt(0FFE4H, 0FFF4H, GetP())
  END Cop;

  PROCEDURE Clc(ea: INTEGER); BEGIN T("CLC", ea); fc := 0; INC(cycles, 2) END Clc;
  PROCEDURE Cld(ea: INTEGER); BEGIN T("CLD", ea); fd := 0; INC(cycles, 2) END Cld;
  PROCEDURE Cli(ea: INTEGER); BEGIN T("CLI", ea); fi := 0; INC(cycles, 2) END Cli;
  PROCEDURE Clv(ea: INTEGER); BEGIN T("CLD", ea); fv := 0; INC(cycles, 2) END Clv;
  PROCEDURE Sec(ea: INTEGER); BEGIN T("SEC", ea); fc := 1; INC(cycles, 2) END Sec;
  PROCEDURE Sed(ea: INTEGER); BEGIN T("SED", ea); fd := 1; INC(cycles, 2) END Sed;
  PROCEDURE Sei(ea: INTEGER); BEGIN T("SEI", ea); fi := 1; INC(cycles, 2) END Sei;

  PROCEDURE Compare(mnem: ARRAY OF CHAR; r: INTEGER; short: BOOLEAN; ea: INTEGER);
    VAR data: INTEGER;
  BEGIN T(mnem, ea);
    IF short THEN data := GetByte(ea); r := Lo(r);
      fc := Bool(r >= data); NZB(r - data); INC(cycles, 2)
    ELSE data := GetWord(ea);
      fc := Bool(r >= data); NZW(r - data); INC(cycles, 3)
    END
  END Compare;

  PROCEDURE Cmp(ea: INTEGER); BEGIN Compare("CMP", a, M8(), ea) END Cmp;
  PROCEDURE Cpx(ea: INTEGER); BEGIN Compare("CPX", x, X8(), ea) END Cpx;
  PROCEDURE Cpy(ea: INTEGER); BEGIN Compare("CPY", y, X8(), ea) END Cpy;

  PROCEDURE Dec(ea: INTEGER);
    VAR data: INTEGER;
  BEGIN T("DEC", ea);
    IF M8() THEN data := AND(GetByte(ea) - 1, 0FFH); SetByte(ea, data); NZB(data); INC(cycles, 4)
    ELSE data := AND(GetWord(ea) - 1, 0FFFFH); SetWord(ea, data); NZW(data); INC(cycles, 5)
    END
  END Dec;

  PROCEDURE Inc(ea: INTEGER);
    VAR data: INTEGER;
  BEGIN T("INC", ea);
    IF M8() THEN data := AND(GetByte(ea) + 1, 0FFH); SetByte(ea, data); NZB(data); INC(cycles, 4)
    ELSE data := AND(GetWord(ea) + 1, 0FFFFH); SetWord(ea, data); NZW(data); INC(cycles, 5)
    END
  END Inc;

  (* r := r + d, of the low byte only when short; the flags. *)
  PROCEDURE IncDec(VAR r: INTEGER; d: INTEGER; short: BOOLEAN);
  BEGIN
    IF short THEN r := WithLo(r, r + d); NZB(r) ELSE r := AND(r + d, 0FFFFH); NZW(r) END;
    INC(cycles, 2)
  END IncDec;

  PROCEDURE Deca(ea: INTEGER); BEGIN T("DEC", ea); IncDec(a, -1, M8()) END Deca;
  PROCEDURE Inca(ea: INTEGER); BEGIN T("INC", ea); IncDec(a, 1, M8()) END Inca;
  PROCEDURE Dex(ea: INTEGER); BEGIN T("DEX", ea); IncDec(x, -1, X8()) END Dex;
  PROCEDURE Dey(ea: INTEGER); BEGIN T("DEY", ea); IncDec(y, -1, X8()) END Dey;
  PROCEDURE Inx(ea: INTEGER); BEGIN T("INX", ea); IncDec(x, 1, X8()) END Inx;
  PROCEDURE Iny(ea: INTEGER); BEGIN T("INY", ea); IncDec(y, 1, X8()) END Iny;

  PROCEDURE Jmp(ea: INTEGER);
  BEGIN T("JMP", ea); pbr := AND(ea DIV 10000H, 0FFH); pc := AND(ea, 0FFFFH); INC(cycles)
  END Jmp;

  PROCEDURE Jsl(ea: INTEGER);
  BEGIN T("JSL", ea);
    PushByte(pbr); PushWord(pc - 1);
    pbr := AND(ea DIV 10000H, 0FFH); pc := AND(ea, 0FFFFH); INC(cycles, 5)
  END Jsl;

  PROCEDURE Jsr(ea: INTEGER);
  BEGIN T("JSR", ea); PushWord(pc - 1); pc := AND(ea, 0FFFFH); INC(cycles, 4)
  END Jsr;

  PROCEDURE Lda(ea: INTEGER);
  BEGIN T("LDA", ea);
    IF M8() THEN a := WithLo(a, GetByte(ea)); NZB(a); INC(cycles, 2)
    ELSE a := GetWord(ea); NZW(a); INC(cycles, 3)
    END
  END Lda;

  PROCEDURE Ldx(ea: INTEGER);
  BEGIN T("LDX", ea);
    IF X8() THEN x := GetByte(ea); NZB(x); INC(cycles, 2)
    ELSE x := GetWord(ea); NZW(x); INC(cycles, 3)
    END
  END Ldx;

  PROCEDURE Ldy(ea: INTEGER);
  BEGIN T("LDY", ea);
    IF X8() THEN y := GetByte(ea); NZB(y); INC(cycles, 2)
    ELSE y := GetWord(ea); NZW(y); INC(cycles, 3)
    END
  END Ldy;

  PROCEDURE Mvn(ea: INTEGER);
    VAR src, dst, b: INTEGER;
  BEGIN T("MVN", ea);
    src := GetByte(ea + 1); dst := GetByte(ea); dbr := dst;
    b := GetByte(Join(src, x)); SetByte(Join(dbr, y), b);
    x := AND(x + 1, 0FFFFH); y := AND(y + 1, 0FFFFH);
    a := AND(a - 1, 0FFFFH);
    IF a # 0FFFFH THEN pc := AND(pc - 3, 0FFFFH) END;
    INC(cycles, 7)
  END Mvn;

  PROCEDURE Mvp(ea: INTEGER);
    VAR src, dst, b: INTEGER;
  BEGIN T("MVP", ea);
    src := GetByte(ea + 1); dst := GetByte(ea); dbr := dst;
    b := GetByte(Join(src, x)); SetByte(Join(dbr, y), b);
    x := AND(x - 1, 0FFFFH); y := AND(y - 1, 0FFFFH);
    a := AND(a - 1, 0FFFFH);
    IF a # 0FFFFH THEN pc := AND(pc - 3, 0FFFFH) END;
    INC(cycles, 7)
  END Mvp;

  PROCEDURE Nop(ea: INTEGER); BEGIN T("NOP", ea); INC(cycles, 2) END Nop;

  PROCEDURE Pea(ea: INTEGER); BEGIN T("PEA", ea); PushWord(GetWord(ea)); INC(cycles, 5) END Pea;
  PROCEDURE Pei(ea: INTEGER); BEGIN T("PEI", ea); PushWord(GetWord(GetWord(ea))); INC(cycles, 6) END Pei;
  PROCEDURE Per(ea: INTEGER); BEGIN T("PER", ea); PushWord(AND(ea, 0FFFFH)); INC(cycles, 6) END Per;

  PROCEDURE Pha(ea: INTEGER);
  BEGIN T("PHA", ea);
    IF M8() THEN PushByte(Lo(a)); INC(cycles, 3) ELSE PushWord(a); INC(cycles, 4) END
  END Pha;

  PROCEDURE Phx(ea: INTEGER);
  BEGIN T("PHX", ea);
    IF X8() THEN PushByte(Lo(x)); INC(cycles, 3) ELSE PushWord(x); INC(cycles, 4) END
  END Phx;

  PROCEDURE Phy(ea: INTEGER);
  BEGIN T("PHY", ea);
    IF X8() THEN PushByte(Lo(y)); INC(cycles, 3) ELSE PushWord(y); INC(cycles, 4) END
  END Phy;

  PROCEDURE Phb(ea: INTEGER); BEGIN T("PHB", ea); PushByte(dbr); INC(cycles, 3) END Phb;
  PROCEDURE Phd(ea: INTEGER); BEGIN T("PHD", ea); PushWord(dp); INC(cycles, 4) END Phd;
  PROCEDURE Phk(ea: INTEGER); BEGIN T("PHK", ea); PushByte(pbr); INC(cycles, 3) END Phk;
  PROCEDURE Php(ea: INTEGER); BEGIN T("PHP", ea); PushByte(GetP()); INC(cycles, 3) END Php;

  PROCEDURE Pla(ea: INTEGER);
  BEGIN T("PLA", ea);
    IF M8() THEN a := WithLo(a, PullByte()); NZB(a); INC(cycles, 4)
    ELSE a := PullWord(); NZW(a); INC(cycles, 5)
    END
  END Pla;

  PROCEDURE Plx(ea: INTEGER);
  BEGIN T("PLX", ea);
    IF X8() THEN x := PullByte(); NZB(x); INC(cycles, 4) ELSE x := PullWord(); NZW(x); INC(cycles, 5) END
  END Plx;

  PROCEDURE Ply(ea: INTEGER);
  BEGIN T("PLY", ea);
    IF X8() THEN y := PullByte(); NZB(y); INC(cycles, 4) ELSE y := PullWord(); NZW(y); INC(cycles, 5) END
  END Ply;

  PROCEDURE Plb(ea: INTEGER); BEGIN T("PLB", ea); dbr := PullByte(); NZB(dbr); INC(cycles, 4) END Plb;
  PROCEDURE Plk(ea: INTEGER); BEGIN T("PLK", ea); dbr := PullByte(); NZB(dbr); INC(cycles, 4) END Plk;
  PROCEDURE Pld(ea: INTEGER); BEGIN T("PLD", ea); dp := PullWord(); NZW(dp); INC(cycles, 5) END Pld;

  PROCEDURE Plp(ea: INTEGER);
  BEGIN T("PLP", ea);
    IF e # 0 THEN SetP(ORA(PullByte(), 30H))
    ELSE SetP(PullByte());
      IF fx # 0 THEN x := Lo(x); y := Lo(y) END
    END;
    INC(cycles, 4)
  END Plp;

  PROCEDURE Rep(ea: INTEGER);
  BEGIN T("REP", ea);
    SetP(AND(GetP(), 0FFH - GetByte(ea)));
    IF e # 0 THEN fm := 1; fx := 1 END;
    INC(cycles, 3)
  END Rep;

  PROCEDURE Sep(ea: INTEGER);
  BEGIN T("SEP", ea);
    SetP(ORA(GetP(), GetByte(ea)));
    IF e # 0 THEN fm := 1; fx := 1 END;
    IF fx # 0 THEN x := Lo(x); y := Lo(y) END;
    INC(cycles, 3)
  END Sep;

  PROCEDURE Rti(ea: INTEGER);
  BEGIN T("RTI", ea);
    IF e # 0 THEN SetP(PullByte()); pc := PullWord(); INC(cycles, 6)
    ELSE SetP(PullByte()); pc := PullWord(); pbr := PullByte(); INC(cycles, 7)
    END
  END Rti;

  PROCEDURE Rtl(ea: INTEGER);
  BEGIN T("RTL", ea); pc := AND(PullWord() + 1, 0FFFFH); pbr := PullByte(); INC(cycles, 6)
  END Rtl;

  PROCEDURE Rts(ea: INTEGER);
  BEGIN T("RTS", ea); pc := AND(PullWord() + 1, 0FFFFH); INC(cycles, 6)
  END Rts;

  PROCEDURE Sta(ea: INTEGER);
  BEGIN T("STA", ea);
    IF M8() THEN SetByte(ea, a); INC(cycles, 2) ELSE SetWord(ea, a); INC(cycles, 3) END
  END Sta;

  PROCEDURE Stx(ea: INTEGER);
  BEGIN T("STX", ea);
    IF X8() THEN SetByte(ea, x); INC(cycles, 2) ELSE SetWord(ea, x); INC(cycles, 3) END
  END Stx;

  PROCEDURE Sty(ea: INTEGER);
  BEGIN T("STY", ea);
    IF X8() THEN SetByte(ea, y); INC(cycles, 2) ELSE SetWord(ea, y); INC(cycles, 3) END
  END Sty;

  PROCEDURE Stz(ea: INTEGER);
  BEGIN T("STZ", ea);
    IF M8() THEN SetByte(ea, 0); INC(cycles, 2) ELSE SetWord(ea, 0); INC(cycles, 3) END
  END Stz;

  (* STP and WAI wait here until an interrupt has happened. *)
  PROCEDURE Wait(mnem: ARRAY OF CHAR; ea: INTEGER);
  BEGIN T(mnem, ea);
    IF ~interrupted THEN pc := AND(pc - 1, 0FFFFH) ELSE interrupted := FALSE END;
    INC(cycles, 3)
  END Wait;

  PROCEDURE Stp(ea: INTEGER); BEGIN Wait("STP", ea) END Stp;
  PROCEDURE Wai(ea: INTEGER); BEGIN Wait("WAI", ea) END Wai;

  PROCEDURE Tax(ea: INTEGER);
  BEGIN T("TAX", ea);
    IF X8() THEN x := Lo(a); NZB(x) ELSE x := a; NZW(x) END; INC(cycles, 2)
  END Tax;

  PROCEDURE Tay(ea: INTEGER);
  BEGIN T("TAY", ea);
    IF X8() THEN y := Lo(a); NZB(y) ELSE y := a; NZW(y) END; INC(cycles, 2)
  END Tay;

  PROCEDURE Tcd(ea: INTEGER); BEGIN T("TCD", ea); dp := a; INC(cycles, 2) END Tcd;

  PROCEDURE Tdc(ea: INTEGER);
  BEGIN T("TDC", ea); a := dp; IF M8() THEN NZB(a) ELSE NZW(a) END; INC(cycles, 2)
  END Tdc;

  PROCEDURE Tcs(ea: INTEGER);
  BEGIN T("TCS", ea);
    IF e # 0 THEN sp := ORA(spPage, Lo(a)) ELSE sp := a END; INC(cycles, 2)
  END Tcs;

  PROCEDURE Tsc(ea: INTEGER);
  BEGIN T("TSC", ea); a := sp; IF M8() THEN NZB(a) ELSE NZW(a) END; INC(cycles, 2)
  END Tsc;

  PROCEDURE Tsx(ea: INTEGER);
  BEGIN T("TSX", ea);
    IF X8() THEN x := WithLo(x, sp); NZB(x) ELSE x := sp; NZW(x) END; INC(cycles, 2)
  END Tsx;

  PROCEDURE Txa(ea: INTEGER);
  BEGIN T("TXA", ea);
    IF M8() THEN a := WithLo(a, x); NZB(a) ELSE a := x; NZW(a) END; INC(cycles, 2)
  END Txa;

  PROCEDURE Txs(ea: INTEGER);
  BEGIN T("TXS", ea);
    IF X8() THEN sp := ORA(spPage, Lo(x)) ELSE sp := x END; INC(cycles, 2)
  END Txs;

  PROCEDURE Txy(ea: INTEGER);
  BEGIN T("TXY", ea); y := x; IF X8() THEN NZB(y) ELSE NZW(y) END; INC(cycles, 2)
  END Txy;

  PROCEDURE Tya(ea: INTEGER);
  BEGIN T("TYA", ea);
    IF M8() THEN a := WithLo(a, y); NZB(a) ELSE a := y; NZW(a) END; INC(cycles, 2)
  END Tya;

  PROCEDURE Tyx(ea: INTEGER);
  BEGIN T("TYX", ea); x := y; IF X8() THEN NZB(x) ELSE NZW(x) END; INC(cycles, 2)
  END Tyx;

  PROCEDURE Trb(ea: INTEGER);
    VAR data: INTEGER;
  BEGIN T("TRB", ea);
    IF M8() THEN data := GetByte(ea); SetByte(ea, AND(data, 0FFH - Lo(a)));
      fz := Bool(AND(Lo(a), data) = 0); INC(cycles, 4)
    ELSE data := GetWord(ea); SetWord(ea, AND(data, 0FFFFH - a));
      fz := Bool(AND(a, data) = 0); INC(cycles, 5)
    END
  END Trb;

  PROCEDURE Tsb(ea: INTEGER);
    VAR data: INTEGER;
  BEGIN T("TSB", ea);
    IF M8() THEN data := GetByte(ea); SetByte(ea, ORA(data, Lo(a)));
      fz := Bool(AND(Lo(a), data) = 0); INC(cycles, 4)
    ELSE data := GetWord(ea); SetWord(ea, ORA(data, a));
      fz := Bool(AND(a, data) = 0); INC(cycles, 5)
    END
  END Tsb;

  (* WDM 1 writes A as a character, 2 reads one, $FF stops. *)
  PROCEDURE Wdm(ea: INTEGER);
    VAR n, ch: INTEGER;
  BEGIN T("WDM", ea); n := GetByte(ea);
    IF n = 1 THEN EmHost.Ch(EmHost.out, CHR(Lo(a)))
    ELSIF n = 2 THEN
      EmHost.Drain(EmHost.out); EmHost.Flush;
      REPEAT ch := EmHost.ReadIn() UNTIL (ch < 0) OR (ch > 20H);
      IF ch >= 0 THEN a := WithLo(a, ch) END
    ELSIF n = 0FFH THEN stopped := TRUE
    END;
    INC(cycles, 3)
  END Wdm;

  PROCEDURE Xba(ea: INTEGER);
  BEGIN T("XBA", ea); a := Hi(a) + Lo(a) * 256; NZB(a); INC(cycles, 3)
  END Xba;

  PROCEDURE Xce(ea: INTEGER);
    VAR oe: INTEGER;
  BEGIN T("XCE", ea); oe := e; e := fc; fc := oe;
    IF e # 0 THEN fm := 1; fx := 1; sp := ORA(spPage, Lo(sp)) END;
    INC(cycles, 2)
  END Xce;

  (* --- Rockwell bit instructions --- *)

  PROCEDURE Bbs(bit, n, ea: INTEGER);
  BEGIN T("BBS", ea);
    IF ODD(LSR(GetByte(n), bit)) THEN
      IF (e # 0) & (AND(EOR(pc, ea), 0FF00H) # 0) THEN INC(cycles) END;
      pc := AND(ea, 0FFFFH); INC(cycles, 3)
    ELSE INC(cycles, 2)
    END
  END Bbs;

  PROCEDURE Bbr(bit, n, ea: INTEGER);
  BEGIN T("BBR", ea);
    IF ~ODD(LSR(GetByte(n), bit)) THEN
      IF (e # 0) & (AND(EOR(pc, ea), 0FF00H) # 0) THEN INC(cycles) END;
      pc := AND(ea, 0FFFFH); INC(cycles, 3)
    ELSE INC(cycles, 2)
    END
  END Bbr;

  PROCEDURE Rmb(bit, ea: INTEGER);
  BEGIN T("RMB", ea); SetByte(ea, AND(GetByte(ea), 0FFH - ASL(1, bit))); INC(cycles, 5)
  END Rmb;

  PROCEDURE Smb(bit, ea: INTEGER);
  BEGIN T("SMB", ea); SetByte(ea, ORA(GetByte(ea), ASL(1, bit))); INC(cycles, 5)
  END Smb;

  (* --- the R65C19's instructions --- *)

  PROCEDURE W(): INTEGER;              (* the W register, signed *)
  BEGIN RETURN S16(wh * 256 + wl)
  END W;

  PROCEDURE Mpy(ea: INTEGER);
    VAR prod: INTEGER;
  BEGIN T("MPY", ea);
    prod := AND(S8(a) * S8(y), 0FFFFH);
    a := WithLo(a, prod DIV 256); y := WithLo(y, prod);
    fn := prod DIV 8000H; fz := Bool(prod = 0); INC(cycles, 6)
  END Mpy;

  PROCEDURE Mpa(ea: INTEGER);
    VAR r: INTEGER;
  BEGIN T("MPA", ea);
    r := W() + S8(a) * S8(y);
    IF r > 32767 THEN r := 32767; fv := 1 ELSIF r < -32768 THEN r := -32768; fv := 1 END;
    r := AND(r, 0FFFFH); wh := r DIV 256; wl := AND(r, 0FFH);
    y := WithLo(y, 0); INC(cycles, 6)
  END Mpa;

  PROCEDURE Tip(ea: INTEGER); BEGIN T("TIP", ea); pc := iReg; INC(cycles, 2) END Tip;

  PROCEDURE Jsb(vector, ea: INTEGER);
  BEGIN T("JSB", ea); PushWord(pc); pc := GetWord(0FFE0H + vector * 2); INC(cycles, 6)
  END Jsb;

  PROCEDURE Jpi(ea: INTEGER);
    VAR ind: INTEGER;
  BEGIN T("JPI", ea); iReg := pc; ind := GetWord(iReg); iReg := AND(iReg + 2, 0FFFFH);
    pc := GetWord(ind); INC(cycles, 5)
  END Jpi;

  PROCEDURE Lab(ea: INTEGER);
  BEGIN T("LAB", ea);
    IF (Lo(a) >= 80H) & (Lo(a) # 80H) THEN a := WithLo(a, 100H - Lo(a)) END;
    NZB(a); INC(cycles, 3)
  END Lab;

  PROCEDURE Neg(ea: INTEGER);
  BEGIN T("NEG", ea);
    IF Lo(a) # 80H THEN a := WithLo(a, 100H - Lo(a)) END;
    NZB(a); INC(cycles, 2)
  END Neg;

  PROCEDURE Psh(ea: INTEGER);
  BEGIN T("PSH", ea); PushByte(Lo(a)); PushByte(Lo(x)); PushByte(Lo(y)); INC(cycles, 5)
  END Psh;

  PROCEDURE Phw(ea: INTEGER); BEGIN T("PHW", ea); PushByte(wh); PushByte(wl); INC(cycles, 4) END Phw;

  PROCEDURE Pul(ea: INTEGER);
  BEGIN T("PUL", ea);
    y := WithLo(y, PullByte()); x := WithLo(x, PullByte()); a := WithLo(a, PullByte());
    NZB(a); INC(cycles, 6)
  END Pul;

  PROCEDURE Plw(ea: INTEGER); BEGIN T("PLW", ea); wl := PullByte(); wh := PullByte(); INC(cycles, 5) END Plw;

  PROCEDURE Rnd(ea: INTEGER);
    VAR r: INTEGER;
  BEGIN T("RND", ea);
    r := (W() + 80H) DIV 256;
    IF r > 7FH THEN r := 7FH ELSIF r < -80H THEN r := -80H END;
    a := WithLo(a, r); NZB(a); INC(cycles, 2)
  END Rnd;

  PROCEDURE Clw(ea: INTEGER); BEGIN T("CLW", ea); wh := 0; wl := 0; fv := 0; INC(cycles, 2) END Clw;
  PROCEDURE Taw(ea: INTEGER); BEGIN T("TAW", ea); wh := Lo(a); wl := 0; INC(cycles, 2) END Taw;
  PROCEDURE Twa(ea: INTEGER); BEGIN T("TWA", ea); a := WithLo(a, wh); NZB(a); INC(cycles, 2) END Twa;

  PROCEDURE Nxt(ea: INTEGER);
  BEGIN T("NXT", ea); pc := GetWord(iReg); iReg := AND(iReg + 2, 0FFFFH); INC(cycles, 4)
  END Nxt;

  PROCEDURE Lii(ea: INTEGER); BEGIN T("LII", ea); iReg := GetWord(iReg); INC(cycles, 5) END Lii;

  PROCEDURE Lan(ea: INTEGER);
  BEGIN T("LAN", ea); a := WithLo(a, GetByte(iReg)); iReg := AND(iReg + 1, 0FFFFH); NZB(a); INC(cycles, 3)
  END Lan;

  PROCEDURE Sti(ea: INTEGER);
    VAR v, zp: INTEGER;
  BEGIN T("STI", ea); v := GetByte(ea); zp := GetByte(Join(pbr, pc)); pc := AND(pc + 1, 0FFFFH);
    SetByte(AND(dp + zp, 0FFFFH), v); INC(cycles, 4)
  END Sti;

  PROCEDURE Ini(ea: INTEGER); BEGIN T("INI", ea); iReg := AND(iReg + 1, 0FFFFH); INC(cycles, 3) END Ini;

  PROCEDURE Rba(ea: INTEGER);
    VAR mask, t: INTEGER;
  BEGIN T("RBA", ea); mask := GetByte(ea); t := Join(dbr, GetWord(Join(pbr, pc)));
    pc := AND(pc + 2, 0FFFFH); SetByte(t, AND(GetByte(t), 0FFH - mask)); INC(cycles, 6)
  END Rba;

  PROCEDURE Sba(ea: INTEGER);
    VAR mask, t: INTEGER;
  BEGIN T("SBA", ea); mask := GetByte(ea); t := Join(dbr, GetWord(Join(pbr, pc)));
    pc := AND(pc + 2, 0FFFFH); SetByte(t, ORA(GetByte(t), mask)); INC(cycles, 6)
  END Sba;

  PROCEDURE Phi(ea: INTEGER); BEGIN T("PHI", ea); PushWord(iReg); INC(cycles, 4) END Phi;

  PROCEDURE Exc(ea: INTEGER);
    VAR t: INTEGER;
  BEGIN T("EXC", ea); t := GetByte(ea); SetByte(ea, a); a := WithLo(a, t); NZB(a); INC(cycles, 5)
  END Exc;

  PROCEDURE Pli(ea: INTEGER); BEGIN T("PLI", ea); iReg := PullWord(); INC(cycles, 6) END Pli;

  (* BAR and BAS: branch if the bits of mask are all clear, or all set. *)
  PROCEDURE BitBranch(mnem: ARRAY OF CHAR; set: BOOLEAN; ea: INTEGER);
    VAR mask, addr, off, v: INTEGER;
  BEGIN T(mnem, ea); mask := GetByte(ea);
    addr := GetWord(Join(pbr, pc)); pc := AND(pc + 2, 0FFFFH);
    off := GetByte(Join(pbr, pc)); pc := AND(pc + 1, 0FFFFH);
    v := AND(GetByte(Join(dbr, addr)), mask);
    IF set & (v = mask) OR ~set & (v = 0) THEN pc := AND(pc + S8(off), 0FFFFH); INC(cycles, 6)
    ELSE INC(cycles, 5)
    END
  END BitBranch;

  PROCEDURE Bar(ea: INTEGER); BEGIN BitBranch("BAR", FALSE, ea) END Bar;
  PROCEDURE Bas(ea: INTEGER); BEGIN BitBranch("BAS", TRUE, ea) END Bas;

  PROCEDURE Lai(ea: INTEGER); BEGIN T("LAI", ea); a := WithLo(a, GetByte(iReg)); NZB(a); INC(cycles, 3) END Lai;

  PROCEDURE Pia(ea: INTEGER);
  BEGIN T("PIA", ea); iReg := PullWord(); a := WithLo(a, GetByte(iReg)); x := WithLo(x, a);
    iReg := AND(iReg + 1, 0FFFFH); NZB(a); INC(cycles, 6)
  END Pia;

  PROCEDURE JsrL28(ea: INTEGER);
  BEGIN T("JSR", ea); PushWord(pc); pc := AND(ea, 0FFFFH); INC(cycles, 4)
  END JsrL28;

  PROCEDURE RtsL28(ea: INTEGER);
  BEGIN T("RTS", ea); pc := PullWord(); INC(cycles, 6)
  END RtsL28;

  PROCEDURE BrkL28(ea: INTEGER);
  BEGIN T("BRK", ea); PushWord(pc); PushByte(ORA(GetP(), 10H)); fi := 1; fd := 0;
    pc := GetWord(0FFFEH); INC(cycles, 7)
  END BrkL28;

  (* --- the opcode tables, generated by tools/gendispatch.py --- *)

  PROCEDURE DispatchWDC(op: INTEGER);
    VAR n, ea: INTEGER;
  BEGIN
    CASE op OF
      00H: Brk(Immb())
    | 01H: Ora(Dpix())
    | 02H: Cop(Immb())
    | 03H: Ora(Srel())
    | 04H: Tsb(Dpag())
    | 05H: Ora(Dpag())
    | 06H: Asl(Dpag())
    | 07H: Ora(Dpil())
    | 08H: Php(Impl())
    | 09H: Ora(Immm())
    | 0AH: Asla(Acc())
    | 0BH: Phd(Impl())
    | 0CH: Tsb(Absl())
    | 0DH: Ora(Absl())
    | 0EH: Asl(Absl())
    | 0FH: Ora(Alng())
    | 10H: Bpl(Rela())
    | 11H: Ora(Dpiy())
    | 12H: Ora(Dpgi())
    | 13H: Ora(Sriy())
    | 14H: Trb(Dpag())
    | 15H: Ora(Dpgx())
    | 16H: Asl(Dpgx())
    | 17H: Ora(Dily())
    | 18H: Clc(Impl())
    | 19H: Ora(Absy())
    | 1AH: Inca(Acc())
    | 1BH: Tcs(Impl())
    | 1CH: Trb(Absl())
    | 1DH: Ora(Absx())
    | 1EH: Asl(Absx())
    | 1FH: Ora(Alnx())
    | 20H: Jsr(Absl())
    | 21H: And(Dpix())
    | 22H: Jsl(Alng())
    | 23H: And(Srel())
    | 24H: Bit(Dpag())
    | 25H: And(Dpag())
    | 26H: Rol(Dpag())
    | 27H: And(Dpil())
    | 28H: Plp(Impl())
    | 29H: And(Immm())
    | 2AH: Rola(Acc())
    | 2BH: Pld(Impl())
    | 2CH: Bit(Absl())
    | 2DH: And(Absl())
    | 2EH: Rol(Absl())
    | 2FH: And(Alng())
    | 30H: Bmi(Rela())
    | 31H: And(Dpiy())
    | 32H: And(Dpgi())
    | 33H: And(Sriy())
    | 34H: Bit(Dpgx())
    | 35H: And(Dpgx())
    | 36H: Rol(Dpgx())
    | 37H: And(Dily())
    | 38H: Sec(Impl())
    | 39H: And(Absy())
    | 3AH: Deca(Acc())
    | 3BH: Tsc(Impl())
    | 3CH: Bit(Absx())
    | 3DH: And(Absx())
    | 3EH: Rol(Absx())
    | 3FH: And(Alnx())
    | 40H: Rti(Impl())
    | 41H: Eor(Dpix())
    | 42H: Wdm(Immb())
    | 43H: Eor(Srel())
    | 44H: Mvp(Immw())
    | 45H: Eor(Dpag())
    | 46H: Lsr(Dpag())
    | 47H: Eor(Dpil())
    | 48H: Pha(Impl())
    | 49H: Eor(Immm())
    | 4AH: Lsra(Impl())
    | 4BH: Phk(Impl())
    | 4CH: Jmp(Absl())
    | 4DH: Eor(Absl())
    | 4EH: Lsr(Absl())
    | 4FH: Eor(Alng())
    | 50H: Bvc(Rela())
    | 51H: Eor(Dpiy())
    | 52H: Eor(Dpgi())
    | 53H: Eor(Sriy())
    | 54H: Mvn(Immw())
    | 55H: Eor(Dpgx())
    | 56H: Lsr(Dpgx())
    | 57H: Eor(Dily())
    | 58H: Cli(Impl())
    | 59H: Eor(Absy())
    | 5AH: Phy(Impl())
    | 5BH: Tcd(Impl())
    | 5CH: Jmp(Alng())
    | 5DH: Eor(Absx())
    | 5EH: Lsr(Absx())
    | 5FH: Eor(Alnx())
    | 60H: Rts(Impl())
    | 61H: Adc(Dpix())
    | 62H: Per(Lrel())
    | 63H: Adc(Srel())
    | 64H: Stz(Dpag())
    | 65H: Adc(Dpag())
    | 66H: Ror(Dpag())
    | 67H: Adc(Dpil())
    | 68H: Pla(Impl())
    | 69H: Adc(Immm())
    | 6AH: Rora(Impl())
    | 6BH: Rtl(Impl())
    | 6CH: Jmp(Absi())
    | 6DH: Adc(Absl())
    | 6EH: Ror(Absl())
    | 6FH: Adc(Alng())
    | 70H: Bvs(Rela())
    | 71H: Adc(Dpiy())
    | 72H: Adc(Dpgi())
    | 73H: Adc(Sriy())
    | 74H: Stz(Dpgx())
    | 75H: Adc(Dpgx())
    | 76H: Ror(Dpgx())
    | 77H: Adc(Dily())
    | 78H: Sei(Impl())
    | 79H: Adc(Absy())
    | 7AH: Ply(Impl())
    | 7BH: Tdc(Impl())
    | 7CH: Jmp(Abxi())
    | 7DH: Adc(Absx())
    | 7EH: Ror(Absx())
    | 7FH: Adc(Alnx())
    | 80H: Bra(Rela())
    | 81H: Sta(Dpix())
    | 82H: Brl(Lrel())
    | 83H: Sta(Srel())
    | 84H: Sty(Dpag())
    | 85H: Sta(Dpag())
    | 86H: Stx(Dpag())
    | 87H: Sta(Dpil())
    | 88H: Dey(Impl())
    | 89H: Biti(Immm())
    | 8AH: Txa(Impl())
    | 8BH: Phb(Impl())
    | 8CH: Sty(Absl())
    | 8DH: Sta(Absl())
    | 8EH: Stx(Absl())
    | 8FH: Sta(Alng())
    | 90H: Bcc(Rela())
    | 91H: Sta(Dpiy())
    | 92H: Sta(Dpgi())
    | 93H: Sta(Sriy())
    | 94H: Sty(Dpgx())
    | 95H: Sta(Dpgx())
    | 96H: Stx(Dpgy())
    | 97H: Sta(Dily())
    | 98H: Tya(Impl())
    | 99H: Sta(Absy())
    | 9AH: Txs(Impl())
    | 9BH: Txy(Impl())
    | 9CH: Stz(Absl())
    | 9DH: Sta(Absx())
    | 9EH: Stz(Absx())
    | 9FH: Sta(Alnx())
    | 0A0H: Ldy(Immx())
    | 0A1H: Lda(Dpix())
    | 0A2H: Ldx(Immx())
    | 0A3H: Lda(Srel())
    | 0A4H: Ldy(Dpag())
    | 0A5H: Lda(Dpag())
    | 0A6H: Ldx(Dpag())
    | 0A7H: Lda(Dpil())
    | 0A8H: Tay(Impl())
    | 0A9H: Lda(Immm())
    | 0AAH: Tax(Impl())
    | 0ABH: Plb(Impl())
    | 0ACH: Ldy(Absl())
    | 0ADH: Lda(Absl())
    | 0AEH: Ldx(Absl())
    | 0AFH: Lda(Alng())
    | 0B0H: Bcs(Rela())
    | 0B1H: Lda(Dpiy())
    | 0B2H: Lda(Dpgi())
    | 0B3H: Lda(Sriy())
    | 0B4H: Ldy(Dpgx())
    | 0B5H: Lda(Dpgx())
    | 0B6H: Ldx(Dpgy())
    | 0B7H: Lda(Dily())
    | 0B8H: Clv(Impl())
    | 0B9H: Lda(Absy())
    | 0BAH: Tsx(Impl())
    | 0BBH: Tyx(Impl())
    | 0BCH: Ldy(Absx())
    | 0BDH: Lda(Absx())
    | 0BEH: Ldx(Absy())
    | 0BFH: Lda(Alnx())
    | 0C0H: Cpy(Immx())
    | 0C1H: Cmp(Dpix())
    | 0C2H: Rep(Immb())
    | 0C3H: Cmp(Srel())
    | 0C4H: Cpy(Dpag())
    | 0C5H: Cmp(Dpag())
    | 0C6H: Dec(Dpag())
    | 0C7H: Cmp(Dpil())
    | 0C8H: Iny(Impl())
    | 0C9H: Cmp(Immm())
    | 0CAH: Dex(Impl())
    | 0CBH: Wai(Impl())
    | 0CCH: Cpy(Absl())
    | 0CDH: Cmp(Absl())
    | 0CEH: Dec(Absl())
    | 0CFH: Cmp(Alng())
    | 0D0H: Bne(Rela())
    | 0D1H: Cmp(Dpiy())
    | 0D2H: Cmp(Dpgi())
    | 0D3H: Cmp(Sriy())
    | 0D4H: Pei(Dpag())
    | 0D5H: Cmp(Dpgx())
    | 0D6H: Dec(Dpgx())
    | 0D7H: Cmp(Dily())
    | 0D8H: Cld(Impl())
    | 0D9H: Cmp(Absy())
    | 0DAH: Phx(Impl())
    | 0DBH: Stp(Impl())
    | 0DCH: Jmp(Abil())
    | 0DDH: Cmp(Absx())
    | 0DEH: Dec(Absx())
    | 0DFH: Cmp(Alnx())
    | 0E0H: Cpx(Immx())
    | 0E1H: Sbc(Dpix())
    | 0E2H: Sep(Immb())
    | 0E3H: Sbc(Srel())
    | 0E4H: Cpx(Dpag())
    | 0E5H: Sbc(Dpag())
    | 0E6H: Inc(Dpag())
    | 0E7H: Sbc(Dpil())
    | 0E8H: Inx(Impl())
    | 0E9H: Sbc(Immm())
    | 0EAH: Nop(Impl())
    | 0EBH: Xba(Impl())
    | 0ECH: Cpx(Absl())
    | 0EDH: Sbc(Absl())
    | 0EEH: Inc(Absl())
    | 0EFH: Sbc(Alng())
    | 0F0H: Beq(Rela())
    | 0F1H: Sbc(Dpiy())
    | 0F2H: Sbc(Dpgi())
    | 0F3H: Sbc(Sriy())
    | 0F4H: Pea(Immw())
    | 0F5H: Sbc(Dpgx())
    | 0F6H: Inc(Dpgx())
    | 0F7H: Sbc(Dily())
    | 0F8H: Sed(Impl())
    | 0F9H: Sbc(Absy())
    | 0FAH: Plx(Impl())
    | 0FBH: Xce(Impl())
    | 0FCH: Jsr(Abxi())
    | 0FDH: Sbc(Absx())
    | 0FEH: Inc(Absx())
    | 0FFH: Sbc(Alnx())
    END
  END DispatchWDC;

  PROCEDURE DispatchRockwell(op: INTEGER);
    VAR n, ea: INTEGER;
  BEGIN
    CASE op OF
      00H: Brk(Immb())
    | 01H: Ora(Dpix())
    | 02H: Cop(Immb())
    | 03H: Ora(Srel())
    | 04H: Tsb(Dpag())
    | 05H: Ora(Dpag())
    | 06H: Asl(Dpag())
    | 07H: Rmb(0, Dpag())
    | 08H: Php(Impl())
    | 09H: Ora(Immm())
    | 0AH: Asla(Acc())
    | 0BH: Phd(Impl())
    | 0CH: Tsb(Absl())
    | 0DH: Ora(Absl())
    | 0EH: Asl(Absl())
    | 0FH: n := Dpag(); ea := Rela(); Bbr(0, n, ea)
    | 10H: Bpl(Rela())
    | 11H: Ora(Dpiy())
    | 12H: Ora(Dpgi())
    | 13H: Ora(Sriy())
    | 14H: Trb(Dpag())
    | 15H: Ora(Dpgx())
    | 16H: Asl(Dpgx())
    | 17H: Rmb(1, Dpag())
    | 18H: Clc(Impl())
    | 19H: Ora(Absy())
    | 1AH: Inca(Acc())
    | 1BH: Tcs(Impl())
    | 1CH: Trb(Absl())
    | 1DH: Ora(Absx())
    | 1EH: Asl(Absx())
    | 1FH: n := Dpag(); ea := Rela(); Bbr(1, n, ea)
    | 20H: Jsr(Absl())
    | 21H: And(Dpix())
    | 22H: Jsl(Alng())
    | 23H: And(Srel())
    | 24H: Bit(Dpag())
    | 25H: And(Dpag())
    | 26H: Rol(Dpag())
    | 27H: Rmb(2, Dpag())
    | 28H: Plp(Impl())
    | 29H: And(Immm())
    | 2AH: Rola(Acc())
    | 2BH: Pld(Impl())
    | 2CH: Bit(Absl())
    | 2DH: And(Absl())
    | 2EH: Rol(Absl())
    | 2FH: n := Dpag(); ea := Rela(); Bbr(2, n, ea)
    | 30H: Bmi(Rela())
    | 31H: And(Dpiy())
    | 32H: And(Dpgi())
    | 33H: And(Sriy())
    | 34H: Bit(Dpgx())
    | 35H: And(Dpgx())
    | 36H: Rol(Dpgx())
    | 37H: Rmb(3, Dpag())
    | 38H: Sec(Impl())
    | 39H: And(Absy())
    | 3AH: Deca(Acc())
    | 3BH: Tsc(Impl())
    | 3CH: Bit(Absx())
    | 3DH: And(Absx())
    | 3EH: Rol(Absx())
    | 3FH: n := Dpag(); ea := Rela(); Bbr(3, n, ea)
    | 40H: Rti(Impl())
    | 41H: Eor(Dpix())
    | 42H: Wdm(Immb())
    | 43H: Eor(Srel())
    | 44H: Mvp(Immw())
    | 45H: Eor(Dpag())
    | 46H: Lsr(Dpag())
    | 47H: Rmb(4, Dpag())
    | 48H: Pha(Impl())
    | 49H: Eor(Immm())
    | 4AH: Lsra(Impl())
    | 4BH: Phk(Impl())
    | 4CH: Jmp(Absl())
    | 4DH: Eor(Absl())
    | 4EH: Lsr(Absl())
    | 4FH: n := Dpag(); ea := Rela(); Bbr(4, n, ea)
    | 50H: Bvc(Rela())
    | 51H: Eor(Dpiy())
    | 52H: Eor(Dpgi())
    | 53H: Eor(Sriy())
    | 54H: Mvn(Immw())
    | 55H: Eor(Dpgx())
    | 56H: Lsr(Dpgx())
    | 57H: Rmb(5, Dpag())
    | 58H: Cli(Impl())
    | 59H: Eor(Absy())
    | 5AH: Phy(Impl())
    | 5BH: Tcd(Impl())
    | 5CH: Jmp(Alng())
    | 5DH: Eor(Absx())
    | 5EH: Lsr(Absx())
    | 5FH: n := Dpag(); ea := Rela(); Bbr(5, n, ea)
    | 60H: Rts(Impl())
    | 61H: Adc(Dpix())
    | 62H: Per(Lrel())
    | 63H: Adc(Srel())
    | 64H: Stz(Dpag())
    | 65H: Adc(Dpag())
    | 66H: Ror(Dpag())
    | 67H: Rmb(6, Dpag())
    | 68H: Pla(Impl())
    | 69H: Adc(Immm())
    | 6AH: Rora(Impl())
    | 6BH: Rtl(Impl())
    | 6CH: Jmp(Absi())
    | 6DH: Adc(Absl())
    | 6EH: Ror(Absl())
    | 6FH: n := Dpag(); ea := Rela(); Bbr(6, n, ea)
    | 70H: Bvs(Rela())
    | 71H: Adc(Dpiy())
    | 72H: Adc(Dpgi())
    | 73H: Adc(Sriy())
    | 74H: Stz(Dpgx())
    | 75H: Adc(Dpgx())
    | 76H: Ror(Dpgx())
    | 77H: Rmb(7, Dpag())
    | 78H: Sei(Impl())
    | 79H: Adc(Absy())
    | 7AH: Ply(Impl())
    | 7BH: Tdc(Impl())
    | 7CH: Jmp(Abxi())
    | 7DH: Adc(Absx())
    | 7EH: Ror(Absx())
    | 7FH: n := Dpag(); ea := Rela(); Bbr(7, n, ea)
    | 80H: Bra(Rela())
    | 81H: Sta(Dpix())
    | 82H: Brl(Lrel())
    | 83H: Sta(Srel())
    | 84H: Sty(Dpag())
    | 85H: Sta(Dpag())
    | 86H: Stx(Dpag())
    | 87H: Smb(0, Dpag())
    | 88H: Dey(Impl())
    | 89H: Biti(Immm())
    | 8AH: Txa(Impl())
    | 8BH: Phb(Impl())
    | 8CH: Sty(Absl())
    | 8DH: Sta(Absl())
    | 8EH: Stx(Absl())
    | 8FH: n := Dpag(); ea := Rela(); Bbs(0, n, ea)
    | 90H: Bcc(Rela())
    | 91H: Sta(Dpiy())
    | 92H: Sta(Dpgi())
    | 93H: Sta(Sriy())
    | 94H: Sty(Dpgx())
    | 95H: Sta(Dpgx())
    | 96H: Stx(Dpgy())
    | 97H: Smb(1, Dpag())
    | 98H: Tya(Impl())
    | 99H: Sta(Absy())
    | 9AH: Txs(Impl())
    | 9BH: Txy(Impl())
    | 9CH: Stz(Absl())
    | 9DH: Sta(Absx())
    | 9EH: Stz(Absx())
    | 9FH: n := Dpag(); ea := Rela(); Bbs(1, n, ea)
    | 0A0H: Ldy(Immx())
    | 0A1H: Lda(Dpix())
    | 0A2H: Ldx(Immx())
    | 0A3H: Lda(Srel())
    | 0A4H: Ldy(Dpag())
    | 0A5H: Lda(Dpag())
    | 0A6H: Ldx(Dpag())
    | 0A7H: Smb(2, Dpag())
    | 0A8H: Tay(Impl())
    | 0A9H: Lda(Immm())
    | 0AAH: Tax(Impl())
    | 0ABH: Plb(Impl())
    | 0ACH: Ldy(Absl())
    | 0ADH: Lda(Absl())
    | 0AEH: Ldx(Absl())
    | 0AFH: n := Dpag(); ea := Rela(); Bbs(2, n, ea)
    | 0B0H: Bcs(Rela())
    | 0B1H: Lda(Dpiy())
    | 0B2H: Lda(Dpgi())
    | 0B3H: Lda(Sriy())
    | 0B4H: Ldy(Dpgx())
    | 0B5H: Lda(Dpgx())
    | 0B6H: Ldx(Dpgy())
    | 0B7H: Smb(3, Dpag())
    | 0B8H: Clv(Impl())
    | 0B9H: Lda(Absy())
    | 0BAH: Tsx(Impl())
    | 0BBH: Tyx(Impl())
    | 0BCH: Ldy(Absx())
    | 0BDH: Lda(Absx())
    | 0BEH: Ldx(Absy())
    | 0BFH: n := Dpag(); ea := Rela(); Bbs(3, n, ea)
    | 0C0H: Cpy(Immx())
    | 0C1H: Cmp(Dpix())
    | 0C2H: Rep(Immb())
    | 0C3H: Cmp(Srel())
    | 0C4H: Cpy(Dpag())
    | 0C5H: Cmp(Dpag())
    | 0C6H: Dec(Dpag())
    | 0C7H: Smb(4, Dpag())
    | 0C8H: Iny(Impl())
    | 0C9H: Cmp(Immm())
    | 0CAH: Dex(Impl())
    | 0CBH: Wai(Impl())
    | 0CCH: Cpy(Absl())
    | 0CDH: Cmp(Absl())
    | 0CEH: Dec(Absl())
    | 0CFH: n := Dpag(); ea := Rela(); Bbs(4, n, ea)
    | 0D0H: Bne(Rela())
    | 0D1H: Cmp(Dpiy())
    | 0D2H: Cmp(Dpgi())
    | 0D3H: Cmp(Sriy())
    | 0D4H: Pei(Dpag())
    | 0D5H: Cmp(Dpgx())
    | 0D6H: Dec(Dpgx())
    | 0D7H: Smb(5, Dpag())
    | 0D8H: Cld(Impl())
    | 0D9H: Cmp(Absy())
    | 0DAH: Phx(Impl())
    | 0DBH: Stp(Impl())
    | 0DCH: Jmp(Abil())
    | 0DDH: Cmp(Absx())
    | 0DEH: Dec(Absx())
    | 0DFH: n := Dpag(); ea := Rela(); Bbs(5, n, ea)
    | 0E0H: Cpx(Immx())
    | 0E1H: Sbc(Dpix())
    | 0E2H: Sep(Immb())
    | 0E3H: Sbc(Srel())
    | 0E4H: Cpx(Dpag())
    | 0E5H: Sbc(Dpag())
    | 0E6H: Inc(Dpag())
    | 0E7H: Smb(6, Dpag())
    | 0E8H: Inx(Impl())
    | 0E9H: Sbc(Immm())
    | 0EAH: Nop(Impl())
    | 0EBH: Xba(Impl())
    | 0ECH: Cpx(Absl())
    | 0EDH: Sbc(Absl())
    | 0EEH: Inc(Absl())
    | 0EFH: n := Dpag(); ea := Rela(); Bbs(6, n, ea)
    | 0F0H: Beq(Rela())
    | 0F1H: Sbc(Dpiy())
    | 0F2H: Sbc(Dpgi())
    | 0F3H: Sbc(Sriy())
    | 0F4H: Pea(Immw())
    | 0F5H: Sbc(Dpgx())
    | 0F6H: Inc(Dpgx())
    | 0F7H: Smb(7, Dpag())
    | 0F8H: Sed(Impl())
    | 0F9H: Sbc(Absy())
    | 0FAH: Plx(Impl())
    | 0FBH: Xce(Impl())
    | 0FCH: Jsr(Abxi())
    | 0FDH: Sbc(Absx())
    | 0FEH: Inc(Absx())
    | 0FFH: n := Dpag(); ea := Rela(); Bbs(7, n, ea)
    END
  END DispatchRockwell;

  PROCEDURE DispatchL28(op: INTEGER);
    VAR n, ea: INTEGER;
  BEGIN
    CASE op OF
      00H: BrkL28(Impl())
    | 01H: Ora(Dpgi())
    | 02H: Mpy(Impl())
    | 03H: Tip(Impl())
    | 04H: Nop(Impl())
    | 05H: Ora(Dpag())
    | 06H: Asl(Dpag())
    | 07H: Rmb(0, Dpag())
    | 08H: Php(Impl())
    | 09H: Ora(Immm())
    | 0AH: Asla(Acc())
    | 0BH: Jsb(0, Impl())
    | 0CH: Jpi(Impl())
    | 0DH: Ora(Absl())
    | 0EH: Asl(Absl())
    | 0FH: n := Dpag(); ea := Rela(); Bbr(0, n, ea)
    | 10H: Bpl(Rela())
    | 11H: Ora(Diix())
    | 12H: Mpa(Impl())
    | 13H: Lab(Acc())
    | 14H: Nop(Impl())
    | 15H: Ora(Dpgx())
    | 16H: Asl(Dpgx())
    | 17H: Rmb(1, Dpag())
    | 18H: Clc(Impl())
    | 19H: Ora(Absy())
    | 1AH: Neg(Acc())
    | 1BH: Jsb(1, Impl())
    | 1CH: Nop(Impl())
    | 1DH: Ora(Absx())
    | 1EH: Asl(Absx())
    | 1FH: n := Dpag(); ea := Rela(); Bbr(1, n, ea)
    | 20H: JsrL28(Absl())
    | 21H: And(Dpgi())
    | 22H: Psh(Impl())
    | 23H: Phw(Impl())
    | 24H: Bit(Dpag())
    | 25H: And(Dpag())
    | 26H: Rol(Dpag())
    | 27H: Rmb(2, Dpag())
    | 28H: Plp(Impl())
    | 29H: And(Immm())
    | 2AH: Rola(Acc())
    | 2BH: Jsb(2, Impl())
    | 2CH: Bit(Absl())
    | 2DH: And(Absl())
    | 2EH: Rol(Absl())
    | 2FH: n := Dpag(); ea := Rela(); Bbr(2, n, ea)
    | 30H: Bmi(Rela())
    | 31H: And(Diix())
    | 32H: Pul(Impl())
    | 33H: Plw(Impl())
    | 34H: Nop(Impl())
    | 35H: And(Dpgx())
    | 36H: Rol(Dpgx())
    | 37H: Rmb(3, Dpag())
    | 38H: Sec(Impl())
    | 39H: And(Absy())
    | 3AH: Asra(Acc())
    | 3BH: Jsb(3, Impl())
    | 3CH: Nop(Impl())
    | 3DH: And(Absx())
    | 3EH: Rol(Absx())
    | 3FH: n := Dpag(); ea := Rela(); Bbr(3, n, ea)
    | 40H: Rti(Impl())
    | 41H: Eor(Dpgi())
    | 42H: Rnd(Impl())
    | 43H: Nop(Impl())
    | 44H: Nop(Impl())
    | 45H: Eor(Dpag())
    | 46H: Lsr(Dpag())
    | 47H: Rmb(4, Dpag())
    | 48H: Pha(Impl())
    | 49H: Eor(Immm())
    | 4AH: Lsra(Impl())
    | 4BH: Jsb(4, Impl())
    | 4CH: Jmp(Absl())
    | 4DH: Eor(Absl())
    | 4EH: Lsr(Absl())
    | 4FH: n := Dpag(); ea := Rela(); Bbr(4, n, ea)
    | 50H: Bvc(Rela())
    | 51H: Eor(Diix())
    | 52H: Clw(Impl())
    | 53H: Nop(Impl())
    | 54H: Nop(Impl())
    | 55H: Eor(Dpgx())
    | 56H: Lsr(Dpgx())
    | 57H: Rmb(5, Dpag())
    | 58H: Cli(Impl())
    | 59H: Eor(Absy())
    | 5AH: Phy(Impl())
    | 5BH: Jsb(5, Impl())
    | 5CH: Nop(Impl())
    | 5DH: Eor(Absx())
    | 5EH: Lsr(Absx())
    | 5FH: n := Dpag(); ea := Rela(); Bbr(5, n, ea)
    | 60H: RtsL28(Impl())
    | 61H: Adc(Dpgi())
    | 62H: Taw(Impl())
    | 63H: Nop(Impl())
    | 64H: Add(Dpag())
    | 65H: Adc(Dpag())
    | 66H: Ror(Dpag())
    | 67H: Rmb(6, Dpag())
    | 68H: Pla(Impl())
    | 69H: Adc(Immm())
    | 6AH: Rora(Impl())
    | 6BH: Jsb(6, Impl())
    | 6CH: Jmp(Absi())
    | 6DH: Adc(Absl())
    | 6EH: Ror(Absl())
    | 6FH: n := Dpag(); ea := Rela(); Bbr(6, n, ea)
    | 70H: Bvs(Rela())
    | 71H: Adc(Diix())
    | 72H: Twa(Impl())
    | 73H: Nop(Impl())
    | 74H: Add(Dpgx())
    | 75H: Adc(Dpgx())
    | 76H: Ror(Dpgx())
    | 77H: Rmb(7, Dpag())
    | 78H: Sei(Impl())
    | 79H: Adc(Absy())
    | 7AH: Ply(Impl())
    | 7BH: Jsb(7, Impl())
    | 7CH: Jmp(Abxi())
    | 7DH: Adc(Absx())
    | 7EH: Ror(Absx())
    | 7FH: n := Dpag(); ea := Rela(); Bbr(7, n, ea)
    | 80H: Bra(Rela())
    | 81H: Sta(Dpgi())
    | 82H: Nop(Impl())
    | 83H: Nop(Impl())
    | 84H: Sty(Dpag())
    | 85H: Sta(Dpag())
    | 86H: Stx(Dpag())
    | 87H: Smb(0, Dpag())
    | 88H: Dey(Impl())
    | 89H: Add(Immm())
    | 8AH: Txa(Impl())
    | 8BH: Nxt(Impl())
    | 8CH: Sty(Absl())
    | 8DH: Sta(Absl())
    | 8EH: Stx(Absl())
    | 8FH: n := Dpag(); ea := Rela(); Bbs(0, n, ea)
    | 90H: Bcc(Rela())
    | 91H: Sta(Diix())
    | 92H: Nop(Impl())
    | 93H: Nop(Impl())
    | 94H: Sty(Dpgx())
    | 95H: Sta(Dpgx())
    | 96H: Stx(Dpgy())
    | 97H: Smb(1, Dpag())
    | 98H: Tya(Impl())
    | 99H: Sta(Absy())
    | 9AH: Txs(Impl())
    | 9BH: Lii(Impl())
    | 9CH: Nop(Impl())
    | 9DH: Sta(Absx())
    | 9EH: Nop(Impl())
    | 9FH: n := Dpag(); ea := Rela(); Bbs(1, n, ea)
    | 0A0H: Ldy(Immx())
    | 0A1H: Lda(Dpgi())
    | 0A2H: Ldx(Immx())
    | 0A3H: Nop(Impl())
    | 0A4H: Ldy(Dpag())
    | 0A5H: Lda(Dpag())
    | 0A6H: Ldx(Dpag())
    | 0A7H: Smb(2, Dpag())
    | 0A8H: Tay(Impl())
    | 0A9H: Lda(Immm())
    | 0AAH: Tax(Impl())
    | 0ABH: Lan(Impl())
    | 0ACH: Ldy(Absl())
    | 0ADH: Lda(Absl())
    | 0AEH: Ldx(Absl())
    | 0AFH: n := Dpag(); ea := Rela(); Bbs(2, n, ea)
    | 0B0H: Bcs(Rela())
    | 0B1H: Lda(Diix())
    | 0B2H: Sti(Immb())
    | 0B3H: Nop(Impl())
    | 0B4H: Ldy(Dpgx())
    | 0B5H: Lda(Dpgx())
    | 0B6H: Ldx(Dpgy())
    | 0B7H: Smb(3, Dpag())
    | 0B8H: Clv(Impl())
    | 0B9H: Lda(Absy())
    | 0BAH: Tsx(Impl())
    | 0BBH: Ini(Impl())
    | 0BCH: Ldy(Absx())
    | 0BDH: Lda(Absx())
    | 0BEH: Ldx(Absy())
    | 0BFH: n := Dpag(); ea := Rela(); Bbs(3, n, ea)
    | 0C0H: Cpy(Immx())
    | 0C1H: Cmp(Dpgi())
    | 0C2H: Rba(Immb())
    | 0C3H: Nop(Impl())
    | 0C4H: Cpy(Dpag())
    | 0C5H: Cmp(Dpag())
    | 0C6H: Dec(Dpag())
    | 0C7H: Smb(4, Dpag())
    | 0C8H: Iny(Impl())
    | 0C9H: Cmp(Immm())
    | 0CAH: Dex(Impl())
    | 0CBH: Phi(Impl())
    | 0CCH: Cpy(Absl())
    | 0CDH: Cmp(Absl())
    | 0CEH: Dec(Absl())
    | 0CFH: n := Dpag(); ea := Rela(); Bbs(4, n, ea)
    | 0D0H: Bne(Rela())
    | 0D1H: Cmp(Diix())
    | 0D2H: Sba(Immb())
    | 0D3H: Nop(Impl())
    | 0D4H: Exc(Dpgx())
    | 0D5H: Cmp(Dpgx())
    | 0D6H: Dec(Dpgx())
    | 0D7H: Smb(5, Dpag())
    | 0D8H: Cld(Impl())
    | 0D9H: Cmp(Absy())
    | 0DAH: Phx(Impl())
    | 0DBH: Pli(Impl())
    | 0DCH: Nop(Impl())
    | 0DDH: Cmp(Absx())
    | 0DEH: Dec(Absx())
    | 0DFH: n := Dpag(); ea := Rela(); Bbs(5, n, ea)
    | 0E0H: Cpx(Immx())
    | 0E1H: Sbc(Dpgi())
    | 0E2H: Bar(Immb())
    | 0E3H: Nop(Impl())
    | 0E4H: Cpx(Dpag())
    | 0E5H: Sbc(Dpag())
    | 0E6H: Inc(Dpag())
    | 0E7H: Smb(6, Dpag())
    | 0E8H: Inx(Impl())
    | 0E9H: Sbc(Immm())
    | 0EAH: Nop(Impl())
    | 0EBH: Lai(Impl())
    | 0ECH: Cpx(Absl())
    | 0EDH: Sbc(Absl())
    | 0EEH: Inc(Absl())
    | 0EFH: n := Dpag(); ea := Rela(); Bbs(6, n, ea)
    | 0F0H: Beq(Rela())
    | 0F1H: Sbc(Diix())
    | 0F2H: Bas(Immb())
    | 0F3H: Nop(Impl())
    | 0F4H: Nop(Impl())
    | 0F5H: Sbc(Dpgx())
    | 0F6H: Inc(Dpgx())
    | 0F7H: Smb(7, Dpag())
    | 0F8H: Sed(Impl())
    | 0F9H: Sbc(Absy())
    | 0FAH: Plx(Impl())
    | 0FBH: Pia(Impl())
    | 0FCH: Nop(Impl())
    | 0FDH: Sbc(Absx())
    | 0FEH: Inc(Absx())
    | 0FFH: n := Dpag(); ea := Rela(); Bbs(7, n, ea)
    END
  END DispatchL28;


  (* --- running --- *)

  PROCEDURE Reset*(tr: BOOLEAN);
  BEGIN
    e := 1; pbr := 0; dbr := 0; dp := 0; sp := spPage; a := 0; x := 0; y := 0;
    pc := GetWord(0FFFCH); SetP(34H);
    iReg := 0; wh := 0; wl := 0;
    IF cpuType = l28 THEN e := 1; fm := 1; fx := 1 END;
    stopped := FALSE; interrupted := FALSE; trace := tr
  END Reset;

  PROCEDURE Fetch(): INTEGER;
    VAR op: INTEGER;
  BEGIN op := GetByte(Join(pbr, pc)); pc := AND(pc + 1, 0FFFFH);
    RETURN op
  END Fetch;

  PROCEDURE StepWDC;
    VAR before: LONGINT;
  BEGIN
    IF (pbr = 0) & (pc = 0) THEN stopped := TRUE
    ELSE before := cycles;
      IF trace THEN Show END;
      DispatchWDC(Fetch());
      (* the VIA's timer, and its interrupt, native mode *)
      EmVIA.Tick(cycles - before);
      IF (fi = 0) & EmVIA.IrqPending() THEN
        PushByte(pbr); PushWord(pc); PushByte(GetP());
        fi := 1; fd := 0; pbr := 0; pc := GetWord(0FFEEH);
        interrupted := TRUE
      END
    END
  END StepWDC;

  PROCEDURE StepRockwell;
  BEGIN
    IF trace THEN Show END;
    DispatchRockwell(Fetch())
  END StepRockwell;

  (* The L28 keeps its last 64 instructions, and shows them when it ends
     up at address 0. *)
  PROCEDURE CrashReport;
    VAR i: INTEGER; c: CrashEntry;
  BEGIN
    EmHost.Ln(EmHost.err); ErrStr("[em16] Stopped: PC=$0000 SP=$"); EmHost.Hex(EmHost.err, sp, 4);
    ErrStr(" A=$"); EmHost.Hex(EmHost.err, Lo(a), 2); ErrStr(" X=$"); EmHost.Hex(EmHost.err, Lo(x), 2);
    ErrStr(" Y=$"); EmHost.Hex(EmHost.err, Lo(y), 2); EmHost.Ln(EmHost.err);
    ErrStr("[em16] Last "); EmHost.Int(EmHost.err, crashLogSize); ErrStr(" instructions:"); EmHost.Ln(EmHost.err);
    FOR i := 0 TO crashLogSize - 1 DO
      c := crashLog[AND(crashIdx + i, crashLogSize - 1)];
      IF (c.pc # 0) OR (c.op # 0) OR (i = crashLogSize - 1) THEN
        ErrStr("  PC=$"); EmHost.Hex(EmHost.err, c.pc, 4); ErrStr(" op=$"); EmHost.Hex(EmHost.err, c.op, 2);
        ErrStr(" A=$"); EmHost.Hex(EmHost.err, c.a, 2); ErrStr(" X=$"); EmHost.Hex(EmHost.err, c.x, 2);
        ErrStr(" Y=$"); EmHost.Hex(EmHost.err, c.y, 2); ErrStr(" SP=$"); EmHost.Hex(EmHost.err, c.sp, 4);
        EmHost.Ln(EmHost.err)
      END
    END
  END CrashReport;

  PROCEDURE StepL28;
    VAR before: LONGINT; k: INTEGER;
  BEGIN
    IF (pbr = 0) & (pc = 0) THEN CrashReport; stopped := TRUE
    ELSE
      k := AND(crashIdx, crashLogSize - 1);
      crashLog[k].pc := pc; crashLog[k].a := Lo(a); crashLog[k].x := Lo(x); crashLog[k].y := Lo(y);
      crashLog[k].sp := sp; crashLog[k].op := GetByte(Join(pbr, pc));
      INC(crashIdx);
      before := cycles;
      IF trace THEN Show END;
      DispatchL28(Fetch());
      EmL28.PollKeyboard;
      EmVIA.Tick(cycles - before);
      IF (fi = 0) & EmVIA.IrqPending() THEN
        PushWord(pc); PushByte(GetP()); fi := 1; fd := 0;
        pc := GetWord(0FFFEH); interrupted := TRUE
      END;
      IF (fi = 0) & EmL28.Irq0Pending() THEN
        PushWord(pc); PushByte(GetP()); fi := 1; fd := 0;
        pc := GetWord(0FFF0H); interrupted := TRUE
      END
    END
  END StepL28;

  PROCEDURE Step*;
  BEGIN
    IF cpuType = wdc THEN StepWDC
    ELSIF cpuType = rockwell THEN StepRockwell
    ELSE StepL28
    END
  END Step;

  PROCEDURE Run*;
  BEGIN
    WHILE ~stopped DO Step END
  END Run;

  (* Call the code at ea as with JSL, from a BRK #0 at $0080, so that its
     RTL stops the processor; run it. *)
  PROCEDURE JumpLong*(ea: INTEGER);
  BEGIN
    SetByte(80H, 0); SetByte(81H, 0);
    pbr := 0; pc := 80H;
    Jsl(ea); Run;
    stopped := FALSE
  END JumpLong;

  (* As JSL from where the processor is, for SYSTEM.EXEC. *)
  PROCEDURE ExecModule*(ea: INTEGER);
  BEGIN PushByte(pbr); PushWord(pc - 1); pbr := AND(ea DIV 10000H, 0FFH); pc := AND(ea, 0FFFFH)
  END ExecModule;

BEGIN
  cpuType := wdc; spPage := 0; cycles := 0; trap := NIL;
  crashIdx := 0; trace := FALSE; stopped := FALSE; interrupted := FALSE
END EmCPU.
