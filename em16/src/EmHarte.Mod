MODULE EmHarte; (* EmCore against the SingleStepTests (TomHarte) vectors,
   as ../../Verilog65C816/tb_harte.v runs cpu_65c816.v against them:

     em16 -harte dir [opcode.mode ...]

   dir holds the vectors as harte_run.py of the Verilog repository
   converts them (harte/bin/NN.e.hex, NN.n.hex: a byte a line, in hex).
   For each test the registers and memory are set, one instruction runs
   to the next fetch (or into WAI or STP), and the registers and the
   memory the vector lists are compared. As for the Verilog core, MVN and
   MVP (44, 54) are expected to fail: the vectors stop a block move part
   of the way through. *)

  IMPORT Files, EmHost, EmCore;

  TYPE
    Names* = ARRAY 64, 16 OF CHAR;
    Regs = RECORD pc, s, p, a, x, y, dbr, d, pbr, e: INTEGER END;

  VAR
    mem: ARRAY 1000000H OF BYTE;
    r: Files.Rider; f: Files.File;
    shown: INTEGER;

  PROCEDURE Read(a: INTEGER): INTEGER;
  BEGIN RETURN mem[AND(a, 0FFFFFFH)]
  END Read;

  PROCEDURE Write(a, d: INTEGER);
  BEGIN mem[AND(a, 0FFFFFFH)] := d
  END Write;

  PROCEDURE Idle;
  END Idle;

  PROCEDURE NoIrq(): BOOLEAN;
  BEGIN RETURN FALSE
  END NoIrq;

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
    VAR n, t, i, ni, nf, a, v, cyc, s, x, y: INTEGER; ini, fin: Regs; ok: BOOLEAN;
      fa, fv: ARRAY 64 OF INTEGER;
  BEGIN pass := 0; fail := 0;
    f := Files.Old(name);
    IF f = NIL THEN Out("cannot open "); Out(name); EmHost.Ln(EmHost.out)
    ELSE
      Files.Set(r, f, 0);
      n := B16(); n := n + B16() * 10000H;
      FOR t := 0 TO n - 1 DO
        GetRegs(ini); GetRegs(fin);
        ni := B16(); nf := B16();
        FOR i := 0 TO ni - 1 DO a := B24(); v := Byte(); mem[a] := v END;
        FOR i := 0 TO nf - 1 DO a := B24(); v := Byte(); IF i < 64 THEN fa[i] := a; fv[i] := v END END;
        (* the chip's view of the state: S in page 1 and 8 bit index
           registers in emulation mode, 8 bit index registers when x = 1 *)
        s := ini.s; x := ini.x; y := ini.y;
        IF ini.e # 0 THEN s := 100H + AND(s, 0FFH); x := AND(x, 0FFH); y := AND(y, 0FFH)
        ELSIF ODD(ini.p DIV 16) THEN x := AND(x, 0FFH); y := AND(y, 0FFH)
        END;
        EmCore.SetState(ini.pc, s, ini.p, ini.a, x, y, ini.dbr, ini.d, ini.pbr, ini.e);
        cyc := 0;
        REPEAT EmCore.Step(0); INC(cyc)
        UNTIL EmCore.AtFetch() OR (EmCore.state = 19) OR (EmCore.state = 20) OR (cyc >= 200);
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
        END
      END
    END
  END RunFile;

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
    EmCore.SetBus(Read, Read, Write, Idle, NoIrq);
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

END EmHarte.
