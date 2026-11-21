MODULE EmHarte; (* EmCore against the SingleStepTests (TomHarte) vectors,
   as ../../Verilog65C816/tb_harte.v runs cpu_65c816.v against them:

     em16 -harte dir [opcode.mode ...]

   dir holds the vectors as harte_run.py of the Verilog repository
   converts them (harte/bin/NN.e.hex, NN.n.hex: a byte a line, in hex).
   For each test the registers and memory are set, the instruction queue
   empty, and one instruction runs, a cycle at a time with memory that is
   always ready (fills bring a word), until it has begun (left the fetch
   state, or moved PC) and is back at the next fetch (or in WAI or STP);
   its deferred execute is run (EmCore.Settle), and the registers and the
   memory the vector lists are compared, as tb_harte does. As it does,
   the bytes the vector set or listed and those written are cleared
   after each test: the vectors do not list the byte after a WDM, which
   must read 0. As for the Verilog core, MVN and MVP (44, 54) are
   expected to fail: the vectors stop a block move part of the way
   through.

     em16 -bench file [-c832]

   runs a test image of the Verilog repository as its tb_cpu.v does
   (test832_gen.py's, with --irq-only): 128K of memory, banks 0 and 1,
   always ready and read a word at a time; a write to $00F000 ends it,
   0 PASS and else FAIL with the check's number, $00F001 prints its
   byte, $00F002 drives the IRQ line (not 0: asserted), $00F006/7 are a
   failure's detail. The NMI and ABORT of tb_cpu ($00F003, $00F005)
   are not there, as EmCore has neither. tb_cpu counts the 4 cycles of
   its reset too; EmCore's bus cycles drift from the core's by one now
   and then, so the counts differ by 3 or 4. *)

  IMPORT Files, EmHost, EmCore, EmW816;

  TYPE
    Names* = ARRAY 64, 16 OF CHAR;
    Regs = RECORD pc, s, p, a, x, y, dbr, d, pbr, e: INTEGER END;

  VAR
    mem: ARRAY 1000000H OF BYTE;
    r: Files.Rider; f: Files.File;
    shown: INTEGER;
    time: LONGINT;
    (* the bytes written by a test, to clear after it *)
    wlog: ARRAY 256 OF INTEGER; wn: INTEGER;
    (* the bench: the result written (-1: none yet), when, the detail, the IRQ line *)
    result, detail: INTEGER; resultAt: LONGINT; irq: BOOLEAN;
    (* -harte816: the vector's cycles; the cycles run, and the first that
       differs (-1: none) with what it was *)
    ecy: INTEGER;
    eAddr, eKind, eData: ARRAY 8192 OF INTEGER;
    ncy, bad, gAddr, gKind, gData: INTEGER;

  PROCEDURE Read(a: INTEGER): INTEGER;
  BEGIN RETURN mem[AND(a, 0FFFFFFH)]
  END Read;

  PROCEDURE Write(a, d: INTEGER);
  BEGIN mem[AND(a, 0FFFFFFH)] := d;
    IF wn < 256 THEN wlog[wn] := AND(a, 0FFFFFFH) END; INC(wn)
  END Write;

  PROCEDURE Fetch(a: INTEGER; at: LONGINT; VAR w: ARRAY OF INTEGER; VAR n: INTEGER): INTEGER;
    VAR i: INTEGER;
  BEGIN n := 4 - a MOD 4; FOR i := 0 TO n - 1 DO w[i] := mem[AND(a + i, 0FFFFFFH)] END; RETURN 1
  END Fetch;

  PROCEDURE Wait(c: INTEGER);
  BEGIN time := time + c
  END Wait;

  PROCEDURE Clock(): LONGINT;
  BEGIN RETURN time
  END Clock;

  PROCEDURE NoIrq(): BOOLEAN;
  BEGIN RETURN FALSE
  END NoIrq;

  (* the bench's memory: a bus cycle each *)
  PROCEDURE BRead(a: INTEGER): INTEGER;
  BEGIN time := time + 1; RETURN mem[AND(a, 1FFFFH)]
  END BRead;

  PROCEDURE BWrite(a, d: INTEGER);
  BEGIN time := time + 1; mem[AND(a, 1FFFFH)] := d;
    IF a = 0F000H THEN IF result < 0 THEN result := d; resultAt := time END
    ELSIF a = 0F001H THEN EmHost.Ch(EmHost.out, CHR(d))
    ELSIF a = 0F002H THEN irq := d # 0
    ELSIF a = 0F006H THEN detail := AND(detail, 0FF00H) + d
    ELSIF a = 0F007H THEN detail := AND(detail, 0FFH) + d * 256
    END
  END BWrite;

  PROCEDURE BFetch(a: INTEGER; at: LONGINT; VAR w: ARRAY OF INTEGER; VAR n: INTEGER): INTEGER;
    VAR i: INTEGER;
  BEGIN n := 4 - a MOD 4; FOR i := 0 TO n - 1 DO w[i] := mem[AND(a + i, 1FFFFH)] END; RETURN 1
  END BFetch;

  PROCEDURE BIrq(): BOOLEAN;
  BEGIN RETURN irq
  END BIrq;

  (* the next byte of the file: two hex digits and a line end *)
  PROCEDURE Byte(): INTEGER;
    VAR b: BYTE; v, n, c: INTEGER;
  BEGIN v := 0; n := 0;
    REPEAT Files.ReadByte(r, b); c := b;
      IF (c >= ORD("0")) & (c <= ORD("9")) THEN v := v * 16 + c - ORD("0"); INC(n)
      ELSIF (c >= ORD("A")) & (c <= ORD("F")) THEN v := v * 16 + c - ORD("A") + 10; INC(n)
      ELSIF (c >= ORD("a")) & (c <= ORD("f")) THEN v := v * 16 + c - ORD("a") + 10; INC(n)
      END
    UNTIL (n = 2) OR r.eof;
    RETURN v
  END Byte;

  PROCEDURE B16(): INTEGER;
    VAR l: INTEGER;
  BEGIN l := Byte(); RETURN l + Byte() * 256
  END B16;

  PROCEDURE B24(): INTEGER;
    VAR l: INTEGER;
  BEGIN l := B16(); RETURN l + Byte() * 10000H
  END B24;

  PROCEDURE GetRegs(VAR g: Regs);
  BEGIN
    g.pc := B16(); g.s := B16(); g.p := Byte(); g.a := B16(); g.x := B16();
    g.y := B16(); g.dbr := Byte(); g.d := B16(); g.pbr := Byte(); g.e := Byte()
  END GetRegs;

  PROCEDURE Out(s: ARRAY OF CHAR);
  BEGIN EmHost.Str(EmHost.out, s)
  END Out;

  PROCEDURE Hex(x, n: INTEGER);
  BEGIN EmHost.Hex(EmHost.out, x, n)
  END Hex;

  PROCEDURE ShowRegs(what: ARRAY OF CHAR; pc, s, a, x, y, d, dbr, pbr, p, e: INTEGER);
  BEGIN Out(what); Out(" pc="); Hex(pc, 4); Out(" s="); Hex(s, 4); Out(" a="); Hex(a, 4);
    Out(" x="); Hex(x, 4); Out(" y="); Hex(y, 4); Out(" d="); Hex(d, 4); Out(" dbr="); Hex(dbr, 2);
    Out(" pbr="); Hex(pbr, 2); Out(" p="); Hex(p, 2); Out(" e="); Hex(e, 1); EmHost.Ln(EmHost.out)
  END ShowRegs;

  (* One file of vectors; the number of failures. *)
  PROCEDURE RunFile(name: ARRAY OF CHAR; VAR pass, fail: INTEGER);
    VAR n, t, i, ni, nf, a, v, cyc, s, x, y: INTEGER; ini, fin: Regs; ok, started: BOOLEAN;
      fa, fv: ARRAY 64 OF INTEGER; ia: ARRAY 256 OF INTEGER;
  BEGIN pass := 0; fail := 0;
    f := Files.Old(name);
    IF f = NIL THEN Out("cannot open "); Out(name); EmHost.Ln(EmHost.out)
    ELSE
      Files.Set(r, f, 0);
      n := B16(); n := n + B16() * 10000H;
      FOR t := 0 TO n - 1 DO
        GetRegs(ini); GetRegs(fin);
        ni := B16(); nf := B16();
        FOR i := 0 TO ni - 1 DO a := B24(); v := Byte(); mem[a] := v; IF i < 256 THEN ia[i] := a END END;
        FOR i := 0 TO nf - 1 DO a := B24(); v := Byte(); IF i < 64 THEN fa[i] := a; fv[i] := v END END;
        (* the chip's view of the state: S in page 1 and 8 bit index
           registers in emulation mode, 8 bit index registers when x = 1 *)
        s := ini.s; x := ini.x; y := ini.y;
        IF ini.e # 0 THEN s := 100H + AND(s, 0FFH); x := AND(x, 0FFH); y := AND(y, 0FFH)
        ELSIF ODD(ini.p DIV 16) THEN x := AND(x, 0FFH); y := AND(y, 0FFH)
        END;
        EmCore.SetState(ini.pc, s, ini.p, ini.a, x, y, ini.dbr, ini.d, ini.pbr, ini.e);
        (* begun once the state leaves the fetch or PC moves (an implied
           opcode stays there): the queue starts empty *)
        cyc := 0; started := FALSE; wn := 0;
        REPEAT EmCore.Step(0); INC(cyc);
          IF ~EmCore.AtFetch() OR (EmCore.PC # ini.pc) THEN started := TRUE END
        UNTIL started & (EmCore.AtFetch() OR (EmCore.state = 19) OR (EmCore.state = 20)) OR (cyc >= 200);
        EmCore.Settle;
        ok := (cyc < 200) & (EmCore.PC = fin.pc) & (EmCore.S = fin.s) & (EmCore.A = fin.a)
          & (EmCore.X = fin.x) & (EmCore.Y = fin.y) & (EmCore.D = fin.d) & (EmCore.DBR = fin.dbr)
          & (EmCore.PBR = fin.pbr) & (EmCore.GetP() = fin.p) & (EmCore.fE = fin.e);
        FOR i := 0 TO nf - 1 DO
          IF (i < 64) & (mem[fa[i]] # fv[i]) THEN ok := FALSE END
        END;
        IF ok THEN INC(pass)
        ELSE INC(fail);
          IF shown < 3 THEN INC(shown);
            Out("MISMATCH "); Out(name); Out(" test "); EmHost.Int(EmHost.out, t); EmHost.Ln(EmHost.out);
            ShowRegs("  exp", fin.pc, fin.s, fin.a, fin.x, fin.y, fin.d, fin.dbr, fin.pbr, fin.p, fin.e);
            ShowRegs("  got", EmCore.PC, EmCore.S, EmCore.A, EmCore.X, EmCore.Y, EmCore.D,
              EmCore.DBR, EmCore.PBR, EmCore.GetP(), EmCore.fE);
            FOR i := 0 TO nf - 1 DO
              IF (i < 64) & (mem[fa[i]] # fv[i]) THEN
                Out("  mem "); Hex(fa[i], 6); Out(" exp "); Hex(fv[i], 2); Out(" got "); Hex(mem[fa[i]], 2);
                EmHost.Ln(EmHost.out)
              END
            END
          END
        END;
        FOR i := 0 TO ni - 1 DO IF i < 256 THEN mem[ia[i]] := 0 END END;
        FOR i := 0 TO nf - 1 DO IF i < 64 THEN mem[fa[i]] := 0 END END;
        FOR i := 0 TO wn - 1 DO IF i < 256 THEN mem[wlog[i]] := 0 END END
      END
    END
  END RunFile;

  (* em16 -bench: the image, a byte a line in hex, run to its result *)
  PROCEDURE Bench*(name: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    f := Files.Old(name);
    IF f = NIL THEN Out("cannot open "); Out(name); EmHost.Ln(EmHost.out)
    ELSE
      Files.Set(r, f, 0);
      FOR i := 0 TO 1FFFFH DO mem[i] := Byte() END;
      EmCore.SetBus(BRead, BWrite, BFetch, Wait, Clock, BIrq); EmCore.Reset;
      time := 0; result := -1; detail := 0; irq := FALSE;
      REPEAT EmCore.Step(time) UNTIL (result >= 0) OR EmCore.stopped OR (time > 4000000);
      IF result = 0 THEN Out("PASS  ("); EmHost.Int(EmHost.out, resultAt); Out(" cycles)")
      ELSIF result > 0 THEN Out("FAIL: test "); EmHost.Int(EmHost.out, result);
        Out("  detail "); EmHost.Int(EmHost.out, detail);
        Out("  ("); EmHost.Int(EmHost.out, resultAt); Out(" cycles)")
      ELSE Out("TIMEOUT: no result written (PC "); Hex(EmCore.PBR * 10000H + EmCore.PC, 6); Out(")")
      END;
      EmHost.Ln(EmHost.out)
    END
  END Bench;

  PROCEDURE Append(s: ARRAY OF CHAR; VAR d: ARRAY OF CHAR);
    VAR i, j: INTEGER;
  BEGIN i := 0; WHILE d[i] # 0X DO INC(i) END; j := 0;
    WHILE (j < LEN(s)) & (s[j] # 0X) DO d[i] := s[j]; INC(i); INC(j) END; d[i] := 0X
  END Append;

  (* All 512 files, or those named ("a9.n"); a line per file with
     failures, then the totals. *)
  PROCEDURE Run*(dir: ARRAY OF CHAR; VAR names: Names; n: INTEGER);
    VAR name, file: ARRAY 512 OF CHAR; op, m, pass, fail, tp, tf, k: INTEGER; hex: ARRAY 17 OF CHAR;
  BEGIN
    EmCore.SetBus(Read, Write, Fetch, Wait, Clock, NoIrq); time := 0;
    FOR k := 0 TO 15 DO IF k < 10 THEN hex[k] := CHR(ORD("0") + k) ELSE hex[k] := CHR(ORD("a") + k - 10) END END;
    tp := 0; tf := 0; shown := 0;
    op := 0; k := 0;
    WHILE ((n = 0) & (op < 256)) OR ((n > 0) & (k < n)) DO
      FOR m := 0 TO 1 DO
        IF n = 0 THEN
          name[0] := hex[op DIV 16]; name[1] := hex[op MOD 16]; name[2] := ".";
          IF m = 0 THEN name[3] := "n" ELSE name[3] := "e" END; name[4] := 0X
        ELSIF m = 0 THEN name[0] := 0X; Append(names[k], name)
        END;
        IF (n = 0) OR (m = 0) THEN
          file[0] := 0X; Append(dir, file); Append("/", file); Append(name, file); Append(".hex", file);
          RunFile(file, pass, fail); tp := tp + pass; tf := tf + fail;
          IF fail > 0 THEN
            Out("=== "); Out(name); Out(": "); EmHost.Int(EmHost.out, pass); Out(" pass, ");
            EmHost.Int(EmHost.out, fail); Out(" fail ==="); EmHost.Ln(EmHost.out)
          END
        END
      END;
      INC(op); INC(k)
    END;
    EmHost.Int(EmHost.out, tp); Out(" passed, "); EmHost.Int(EmHost.out, tf); Out(" failed");
    EmHost.Ln(EmHost.out)
  END Run;

  (* --- em16 -harte816: EmW816, the chip, against the vectors with their
     bus cycles, as tools/harte816.py converts them (NN.m.bin, its
     header). Each cycle is checked as it is made: its address and its
     byte where the vector has them, its kind (VDA, VPA, VPB, a write,
     MLB); then the cycles' count, the registers and the memory. --- *)

  PROCEDURE U8(): INTEGER;
    VAR b: BYTE;
  BEGIN Files.ReadByte(r, b); RETURN b
  END U8;

  PROCEDURE U16(): INTEGER;
    VAR l: INTEGER;
  BEGIN l := U8(); RETURN l + U8() * 256
  END U16;

  PROCEDURE U32(): INTEGER;
    VAR l: INTEGER;
  BEGIN l := U16(); RETURN l + U16() * 10000H
  END U32;

  PROCEDURE GetRegs816(VAR g: Regs);
  BEGIN
    g.pc := U16(); g.s := U16(); g.p := U8(); g.a := U16(); g.x := U16();
    g.y := U16(); g.dbr := U8(); g.d := U16(); g.pbr := U8(); g.e := U8()
  END GetRegs816;

  (* a cycle's kind as the vectors write it *)
  PROCEDURE Kind(k: INTEGER);
  BEGIN
    IF ODD(k) THEN Out("d") ELSE Out("-") END;
    IF ODD(k DIV 2) THEN Out("p") ELSE Out("-") END;
    IF ODD(k DIV 4) THEN Out("v") ELSE Out("-") END;
    IF ODD(k DIV 8) THEN Out("w") ELSE Out("r") END;
    IF ODD(k DIV 16) THEN Out("l") ELSE Out("-") END
  END Kind;

  PROCEDURE ChipBus(a, k, d: INTEGER): INTEGER;
    VAR v: INTEGER;
  BEGIN
    IF ODD(k DIV EmW816.wr) THEN v := d;
      IF ODD(k) THEN mem[a] := d; IF wn < 256 THEN wlog[wn] := a END; INC(wn) END
    ELSE v := mem[a]
    END;
    IF (bad < 0) & ((ncy >= ecy) OR ~ODD(eKind[ncy] DIV 64) & (a # eAddr[ncy]) OR (k # AND(eKind[ncy], 31))
        OR ~ODD(eKind[ncy] DIV 32) & (v # eData[ncy])) THEN
      bad := ncy; gAddr := a; gKind := k; gData := v
    END;
    INC(ncy); RETURN v
  END ChipBus;

  PROCEDURE RunFile816(name: ARRAY OF CHAR; VAR pass, fail: INTEGER);
    VAR n, t, i, ni, nf, a, v, s, x, y, steps: INTEGER; ini, fin: Regs; ok: BOOLEAN;
      fa, fv: ARRAY 64 OF INTEGER; ia: ARRAY 256 OF INTEGER;
  BEGIN pass := 0; fail := 0;
    f := Files.Old(name);
    IF f = NIL THEN Out("cannot open "); Out(name); EmHost.Ln(EmHost.out)
    ELSE
      Files.Set(r, f, 0);
      n := U32();
      FOR t := 0 TO n - 1 DO
        GetRegs816(ini); GetRegs816(fin);
        ni := U16(); nf := U16();
        FOR i := 0 TO ni - 1 DO v := U32(); a := AND(v, 0FFFFFFH); mem[a] := LSR(v, 24); IF i < 256 THEN ia[i] := a END END;
        FOR i := 0 TO nf - 1 DO v := U32(); IF i < 64 THEN fa[i] := AND(v, 0FFFFFFH); fv[i] := LSR(v, 24) END END;
        ecy := U16();
        FOR i := 0 TO ecy - 1 DO v := U32();
          IF i < LEN(eAddr) THEN eAddr[i] := AND(v, 0FFFFFFH); eKind[i] := LSR(v, 24); eData[i] := U8()
          ELSE v := U8()
          END
        END;
        s := ini.s; x := ini.x; y := ini.y;
        IF ini.e # 0 THEN s := 100H + AND(s, 0FFH); x := AND(x, 0FFH); y := AND(y, 0FFH)
        ELSIF ODD(ini.p DIV 16) THEN x := AND(x, 0FFH); y := AND(y, 0FFH)
        END;
        EmW816.SetState(ini.pc, s, ini.p, ini.a, x, y, ini.dbr, ini.d, ini.pbr, ini.e);
        ncy := 0; bad := -1; wn := 0; steps := 0;
        REPEAT EmW816.Step; INC(steps)
        UNTIL (ncy >= ecy) OR EmW816.stopped OR EmW816.waiting OR (steps > 10000);
        (* WAI's and STP's vectors end with the halted chip: an entry with
           no address and neither a read nor a write, not a bus cycle *)
        WHILE (EmW816.stopped OR EmW816.waiting) & (ncy < ecy) & (ncy < LEN(eKind)) & ODD(eKind[ncy] DIV 64) DO
          INC(ncy)
        END;
        ok := (bad < 0) & (ncy = ecy) & (EmW816.PC = fin.pc) & (EmW816.S = fin.s) & (EmW816.A = fin.a)
          & (EmW816.X = fin.x) & (EmW816.Y = fin.y) & (EmW816.D = fin.d) & (EmW816.DBR = fin.dbr)
          & (EmW816.PBR = fin.pbr) & (EmW816.GetP() = fin.p) & (EmW816.fE = fin.e);
        FOR i := 0 TO nf - 1 DO
          IF (i < 64) & (mem[fa[i]] # fv[i]) THEN ok := FALSE END
        END;
        IF ok THEN INC(pass)
        ELSE INC(fail);
          IF fail <= shown THEN
            Out("MISMATCH "); Out(name); Out(" test "); EmHost.Int(EmHost.out, t);
            Out(": "); EmHost.Int(EmHost.out, ncy); Out(" cycles, expected "); EmHost.Int(EmHost.out, ecy);
            EmHost.Ln(EmHost.out);
            ShowRegs("  ini", ini.pc, ini.s, ini.a, ini.x, ini.y, ini.d, ini.dbr, ini.pbr, ini.p, ini.e);
            ShowRegs("  exp", fin.pc, fin.s, fin.a, fin.x, fin.y, fin.d, fin.dbr, fin.pbr, fin.p, fin.e);
            ShowRegs("  got", EmW816.PC, EmW816.S, EmW816.A, EmW816.X, EmW816.Y, EmW816.D,
              EmW816.DBR, EmW816.PBR, EmW816.GetP(), EmW816.fE);
            IF bad >= 0 THEN
              FOR i := 0 TO bad DO
                IF (i < ecy) & (i < LEN(eAddr)) THEN
                  Out("  cycle "); EmHost.Int(EmHost.out, i); Out(" exp "); Hex(eAddr[i], 6); Out(" ");
                  Kind(eKind[i]); Out(" ");
                  IF ODD(eKind[i] DIV 32) THEN Out("--") ELSE Hex(eData[i], 2) END;
                  EmHost.Ln(EmHost.out)
                END
              END;
              Out("  cycle "); EmHost.Int(EmHost.out, bad); Out(" got "); Hex(gAddr, 6); Out(" ");
              Kind(gKind); Out(" "); Hex(gData, 2); EmHost.Ln(EmHost.out)
            END;
            FOR i := 0 TO nf - 1 DO
              IF (i < 64) & (mem[fa[i]] # fv[i]) THEN
                Out("  mem "); Hex(fa[i], 6); Out(" exp "); Hex(fv[i], 2); Out(" got "); Hex(mem[fa[i]], 2);
                EmHost.Ln(EmHost.out)
              END
            END
          END
        END;
        FOR i := 0 TO ni - 1 DO IF i < 256 THEN mem[ia[i]] := 0 END END;
        FOR i := 0 TO nf - 1 DO IF i < 64 THEN mem[fa[i]] := 0 END END;
        FOR i := 0 TO wn - 1 DO IF i < 256 THEN mem[wlog[i]] := 0 END END
      END
    END
  END RunFile816;

  (* All 512 files, or those named; a line per file with failures (its
     first show failures in full), then the totals. *)
  PROCEDURE Run816*(dir: ARRAY OF CHAR; VAR names: Names; n, show: INTEGER);
    VAR name, file: ARRAY 512 OF CHAR; op, m, pass, fail, tp, tf, k: INTEGER; hex: ARRAY 17 OF CHAR;
  BEGIN
    EmW816.SetBus(ChipBus, NoIrq);
    FOR k := 0 TO 15 DO IF k < 10 THEN hex[k] := CHR(ORD("0") + k) ELSE hex[k] := CHR(ORD("a") + k - 10) END END;
    tp := 0; tf := 0; shown := show;
    op := 0; k := 0;
    WHILE ((n = 0) & (op < 256)) OR ((n > 0) & (k < n)) DO
      FOR m := 0 TO 1 DO
        IF n = 0 THEN
          name[0] := hex[op DIV 16]; name[1] := hex[op MOD 16]; name[2] := ".";
          IF m = 0 THEN name[3] := "n" ELSE name[3] := "e" END; name[4] := 0X
        ELSIF m = 0 THEN name[0] := 0X; Append(names[k], name)
        END;
        IF (n = 0) OR (m = 0) THEN
          file[0] := 0X; Append(dir, file); Append("/", file); Append(name, file); Append(".bin", file);
          RunFile816(file, pass, fail); tp := tp + pass; tf := tf + fail;
          IF fail > 0 THEN
            Out("=== "); Out(name); Out(": "); EmHost.Int(EmHost.out, pass); Out(" pass, ");
            EmHost.Int(EmHost.out, fail); Out(" fail ==="); EmHost.Ln(EmHost.out)
          END
        END
      END;
      INC(op); INC(k)
    END;
    EmHost.Int(EmHost.out, tp); Out(" passed, "); EmHost.Int(EmHost.out, tf); Out(" failed");
    EmHost.Ln(EmHost.out)
  END Run816;

END EmHarte.
