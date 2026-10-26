MODULE ASI; (* Interpreter of the 65xx assembler.

   Port of as/src/interp.c and the symbol handling of as/src/as.c.

   The parser (ASP) does not generate code. It translates the source into
   a list of operations for a stack machine: push a constant or the value
   of a symbol, apply an operator, define a label, emit an instruction
   with the operands on the stack. The assembler then runs that program
   several times. An address that is not known when it is first used
   (a forward reference) takes the value it had in the previous pass, and
   the passes are repeated until no label moves any more; only then is a
   final pass run, which reports errors and writes the listing.

   Conditional assembly and macros are operations as well, so what an IF
   selects or a macro expands to may differ from pass to pass. *)

  IMPORT ASH, ASC, ASS, ASB, ASG, ASL;

  CONST
    (* operations *)
    pushInt = 0; pushReal = 1; pushStr = 2;
    pushVar* = 3;       (* push the value of a symbol *)
    popVar* = 4;        (* assign to a symbol, defining it if need be *)
    defVar* = 5;        (* define a symbol in the innermost scope *)
    label* = 6;         (* define a symbol as the location counter *)
    add* = 10; sub* = 11; mul* = 12; div* = 13; mod* = 14;
    and* = 15; or* = 16; land* = 17; lor* = 18; shl* = 19; shr* = 20;
    eql* = 21; neq* = 22; lss* = 23; leq* = 24; gtr* = 25; geq* = 26;
    neg* = 30; not* = 31; cpl* = 32; low* = 33; high* = 34; bank* = 35;
    instr = 40;
    ifBegin* = 41;      (* IF cond { *)
    elseCond* = 42;     (* } ELSE, before the condition of an ELSE IF *)
    elseIf* = 43;       (* ELSE IF cond { *)
    else* = 44;         (* ELSE { *)
    endIf* = 45;        (* the } that ends the statement *)
    scopeBegin = 46; scopeEnd* = 47;
    macroCall = 48;
    line = 49;          (* list source text *)
    (* directives; the operation counts its operands *)
    byte* = 50; word* = 51; long* = 52; float* = 53; text* = 54; fill* = 55;
    align* = 56; message* = 57; error* = 58; errorIf* = 59;
    title* = 60; subheading* = 61; page* = 62;
    (* a SECTION inside a block: leave the section, and arrive in the other *)
    suspend = 63; resume = 64;

    (* built-in variables *)
    sOrg = 1; sAddr = 2; sLongA = 3; sLongI = 4; sCpu = 5; sPass = 6;
    sDBReg = 7; sDPage = 8; sPBReg = 9; sEntry = 10; sFile = 11; sLine = 12;

    StackSize = 128;
    maxFrames = 64;     (* nesting of IF and blocks *)
    maxDepth = 32;      (* nesting of macro calls *)
    maxPasses = 12;
    maxFill = 1000000H;

  TYPE
    (* a symbol as it is written in the source *)
    Ref* = POINTER TO RefDesc;
    RefDesc* = RECORD
      name*: ASS.Ident;
      sub*: Ref;            (* "name.sub": a local label or an export *)
      local*: BOOLEAN;      (* ".name": local to the label before it *)
      expo*, rdo*: BOOLEAN; (* definition marked with "*" / made with LET *)
      special: INTEGER      (* number of the built-in variable, or 0 *)
    END;

    Macro* = POINTER TO MacroDesc;

    Op = POINTER TO OpDesc;
    Saved = POINTER TO SavedDesc;
    OpDesc = RECORD
      next: Op;
      code: INTEGER;
      a, b: INTEGER;        (* instr: mnemonic, mode; directive: count, modifier *)
      i, j: LONGINT;        (* pushInt: value; instr: modifier; line: from, to *)
      r: REAL;
      s: ASB.String;
      ref: Ref;
      obj: ASB.Object;      (* scope of a block or a macro call *)
      mac: Macro;
      sav: Saved;           (* suspend, resume: the blocks open at a SECTION *)
      src: ASS.Source; line: INTEGER
    END;

    MacroDesc* = RECORD
      name*: ASS.Ident;
      nofpar*: INTEGER;
      first, last: Op;
      next: Macro
    END;

    Frame = RECORD
      parent: BOOLEAN;      (* exec outside the statement *)
      taken: BOOLEAN;       (* a branch of the IF has been selected *)
      scope: BOOLEAN;       (* the frame opened a scope *)
      obj: ASB.Object       (* that scope *)
    END;

    (* The blocks that are open where a SECTION directive stands inside
       them. Each section has its own list of operations and is executed
       on its own, so the directive leaves this in the section it ends
       (suspend) and takes it up in the one it begins (resume): the rest of
       the block is then skipped or assembled there as it was here. *)
    SavedDesc = RECORD
      exec: BOOLEAN;
      n: INTEGER;
      frames: ARRAY maxFrames OF Frame
    END;

  VAR
    passNo: INTEGER;        (* 2, 3, ... and 0 in the final pass *)
    verbose: BOOLEAN;       (* report the passes *)

    (* the program: one list of operations for each section *)
    lists: ARRAY ASG.maxSections OF RECORD first, last: Op END;
    psect: ASG.Section;     (* section the parser is adding to *)
    open: INTEGER;          (* IF statements and blocks the parser is inside *)
    macros, defining: Macro;

    (* state of a pass *)
    final: BOOLEAN;
    stamp: INTEGER;         (* number of this pass, never reused *)
    changed: BOOLEAN;       (* a label is not where it was in the last pass *)
    stack: ARRAY StackSize OF ASB.Value;
    sp: INTEGER;
    frames: ARRAY maxFrames OF Frame;
    nofFrames: INTEGER;
    exec: BOOLEAN;          (* FALSE inside a branch that is not assembled *)
    depth: INTEGER;
    curLabel: ASB.Object;   (* the label local labels belong to *)
    lineAddr, lineStart: LONGINT;   (* where the code of the current line begins *)
    titleStr, subheadStr: ASB.String;
    here: Op;               (* the operation being executed, for messages *)

  (* --- building the program --- *)

  PROCEDURE NewOp(code: INTEGER): Op;
    VAR op: Op;
  BEGIN NEW(op); op.code := code; op.next := NIL; op.src := ASS.src; op.line := ASS.line;
    RETURN op
  END NewOp;

  PROCEDURE Append(op: Op);
    VAR n: INTEGER;
  BEGIN
    IF (defining # NIL) & (op.code # line) THEN
      IF defining.last = NIL THEN defining.first := op ELSE defining.last.next := op END;
      defining.last := op
    ELSE n := psect.no;
      IF lists[n].last = NIL THEN lists[n].first := op ELSE lists[n].last.next := op END;
      lists[n].last := op
    END
  END Append;

  PROCEDURE Put*(code: INTEGER);
  BEGIN
    IF defining = NIL THEN
      IF code = ifBegin THEN INC(open)
      ELSIF (code = endIf) OR (code = scopeEnd) THEN DEC(open)
      END
    END;
    Append(NewOp(code))
  END Put;

  (* A directive with n operands on the stack. *)
  PROCEDURE PutN*(code, n, modifier: INTEGER);
    VAR op: Op;
  BEGIN op := NewOp(code); op.a := n; op.b := modifier; Append(op)
  END PutN;

  PROCEDURE PushInt*(i: LONGINT);
    VAR op: Op;
  BEGIN op := NewOp(pushInt); op.i := i; Append(op)
  END PushInt;

  PROCEDURE PushReal*(r: REAL);
    VAR op: Op;
  BEGIN op := NewOp(pushReal); op.r := r; Append(op)
  END PushReal;

  PROCEDURE PushStr*(s: ARRAY OF CHAR; len: INTEGER);
    VAR op: Op;
  BEGIN op := NewOp(pushStr); op.s := ASB.NewString(s, len); Append(op)
  END PushStr;

  PROCEDURE NewRef*(name: ARRAY OF CHAR): Ref;
    VAR ref: Ref; s: INTEGER;
  BEGIN NEW(ref); ASH.Copy(name, ref.name);
    ref.sub := NIL; ref.local := FALSE; ref.expo := FALSE; ref.rdo := FALSE;
    IF ASH.Same(name, "org") THEN s := sOrg
    ELSIF ASH.Same(name, "addr") OR ASH.Same(name, "pc") THEN s := sAddr
    ELSIF ASH.Same(name, "longa") THEN s := sLongA
    ELSIF ASH.Same(name, "longi") THEN s := sLongI
    ELSIF ASH.Same(name, "cpu") THEN s := sCpu
    ELSIF ASH.Same(name, "pass") THEN s := sPass
    ELSIF ASH.Same(name, "dbreg") THEN s := sDBReg
    ELSIF ASH.Same(name, "dpage") THEN s := sDPage
    ELSIF ASH.Same(name, "pbreg") THEN s := sPBReg
    ELSIF ASH.Same(name, "entry") THEN s := sEntry
    ELSIF name = "__FILE__" THEN s := sFile
    ELSIF name = "__LINE__" THEN s := sLine
    ELSE s := 0
    END;
    ref.special := s;
    RETURN ref
  END NewRef;

  (* pushVar, popVar, defVar or label of the symbol ref *)
  PROCEDURE PutRef*(code: INTEGER; ref: Ref);
    VAR op: Op;
  BEGIN op := NewOp(code); op.ref := ref; Append(op)
  END PutRef;

  PROCEDURE Instr*(mnemonic, mode, modifier: INTEGER);
    VAR op: Op;
  BEGIN op := NewOp(instr); op.a := mnemonic; op.b := mode; op.i := modifier; Append(op)
  END Instr;

  (* The source text [from, to) of src goes to the listing here, beside
     the code of the operations since the last such text. *)
  PROCEDURE Line*(src: ASS.Source; from, to: LONGINT);
    VAR op: Op;
  BEGIN op := NewOp(line); op.src := src; op.i := from; op.j := to; Append(op)
  END Line;

  (* Open a block: the symbols defined up to its scopeEnd are local. *)
  PROCEDURE BeginScope*;
    VAR op: Op;
  BEGIN
    IF defining = NIL THEN INC(open) END;
    op := NewOp(scopeBegin); op.obj := ASB.NewScope(); Append(op)
  END BeginScope;

  PROCEDURE ThisMacro*(name: ARRAY OF CHAR): Macro;
    VAR m: Macro;
  BEGIN m := macros;
    WHILE (m # NIL) & (m.name # name) DO m := m.next END;
    RETURN m
  END ThisMacro;

  (* Define macro `name`. Until EndMacro, operations are added to its
     body instead of the program. *)
  PROCEDURE BeginMacro*(name: ARRAY OF CHAR): Macro;
    VAR m: Macro;
  BEGIN NEW(m); ASH.Copy(name, m.name); m.nofpar := 0; m.first := NIL; m.last := NIL;
    m.next := macros; macros := m; defining := m;
    RETURN m
  END BeginMacro;

  PROCEDURE SetParams*(m: Macro; n: INTEGER);
  BEGIN m.nofpar := n
  END SetParams;

  PROCEDURE EndMacro*;
  BEGIN defining := NIL
  END EndMacro;

  PROCEDURE InMacro*(): BOOLEAN;
  BEGIN RETURN defining # NIL
  END InMacro;

  (* Call macro m with its arguments on the stack. Each call has a scope
     of its own for the parameters and the labels of the body. *)
  PROCEDURE Call*(m: Macro);
    VAR op: Op;
  BEGIN op := NewOp(macroCall); op.mac := m; op.obj := ASB.NewScope(); Append(op)
  END Call;

  (* Continue in section `name`, creating it if it does not exist. *)
  PROCEDURE SetSection*(name: ARRAY OF CHAR; type, flags: INTEGER);
    VAR s: ASG.Section; sv: Saved; op: Op;
  BEGIN s := ASG.NewSection(name, type, flags);
    IF s = NIL THEN ASS.Mark("too many sections")
    ELSIF (s # psect) & (defining = NIL) THEN
      (* Inside a block its state goes along. A section that is taken up
         again is given the state too, even outside a block, because it
         may have been left inside one that was never closed there. *)
      NEW(sv); sv.exec := TRUE; sv.n := 0;
      IF open > 0 THEN op := NewOp(suspend); op.sav := sv; Append(op) END;
      psect := s;
      IF (open > 0) OR (lists[s.no].first # NIL) THEN
        op := NewOp(resume); op.sav := sv; Append(op)
      END
    ELSE psect := s
    END
  END SetSection;

  (* --- messages --- *)

  PROCEDURE Err(msg, arg: ARRAY OF CHAR);
  BEGIN
    IF final THEN ASS.Error(here.src, here.line, msg, arg) END
  END Err;

  (* --- the stack --- *)

  PROCEDURE Push(VAR v: ASB.Value);
  BEGIN
    IF sp < StackSize THEN stack[sp] := v; INC(sp)
    ELSE Err("expression too complex", "")
    END
  END Push;

  PROCEDURE PushI(i: LONGINT);
    VAR v: ASB.Value;
  BEGIN ASB.SetInt(v, i); Push(v)
  END PushI;

  PROCEDURE Pop(VAR v: ASB.Value);
  BEGIN
    IF sp > 0 THEN DEC(sp); v := stack[sp]; stack[sp].s := NIL
    ELSE ASB.SetInt(v, 0)
    END
  END Pop;

  (* Remove the top n values; they stay readable until the next Push. *)
  PROCEDURE Drop(n: INTEGER);
  BEGIN
    IF n > sp THEN sp := 0 ELSE sp := sp - n END
  END Drop;

  PROCEDURE True(VAR v: ASB.Value): BOOLEAN;
    VAR t: BOOLEAN;
  BEGIN
    IF v.form = ASB.Int THEN t := v.i # 0
    ELSIF v.form = ASB.Real THEN t := v.r # 0.0
    ELSIF v.form = ASB.Str THEN t := v.s.len > 0
    ELSE t := FALSE
    END;
    RETURN t
  END True;

  (* The integer v stands for. *)
  PROCEDURE IntOf(VAR v: ASB.Value): LONGINT;
    VAR i: LONGINT;
  BEGIN
    IF v.form = ASB.Int THEN i := v.i
    ELSIF v.form = ASB.Real THEN i := FLOOR(v.r)
    ELSIF (v.form = ASB.Str) & (v.s.len = 1) THEN i := ORD(v.s.s[0])
    ELSE i := 0;
      IF v.form = ASB.Str THEN Err("number expected, not a string", "") END
    END;
    RETURN i
  END IntOf;

  PROCEDURE RealOf(VAR v: ASB.Value): REAL;
    VAR r: REAL;
  BEGIN
    IF v.form = ASB.Real THEN r := v.r ELSE r := FLT(IntOf(v)) END;
    RETURN r
  END RealOf;

  (* --- operators --- *)

  PROCEDURE SameStr(a, b: ASB.String): BOOLEAN;
    VAR i: INTEGER;
  BEGIN i := 0;
    IF a.len = b.len THEN
      WHILE (i < a.len) & (a.s[i] = b.s[i]) DO INC(i) END
    END;
    RETURN (a.len = b.len) & (i = a.len)
  END SameStr;

  PROCEDURE Concat(a, b: ASB.String): ASB.String;
    VAR c: ASB.String; i: INTEGER;
  BEGIN c := ASB.NewString(a.s, a.len); i := 0;
    WHILE (i < b.len) & (c.len < ASS.StrLen - 1) DO c.s[c.len] := b.s[i]; INC(c.len); INC(i) END;
    c.s[c.len] := 0X;
    RETURN c
  END Concat;

  PROCEDURE Bool(b: BOOLEAN): LONGINT;
    VAR i: LONGINT;
  BEGIN
    IF b THEN i := 1 ELSE i := 0 END;
    RETURN i
  END Bool;

  (* Division and remainder truncate towards zero, as they do in C. *)
  PROCEDURE Quot(x, y: LONGINT): LONGINT;
    VAR q: LONGINT;
  BEGIN q := ABS(x) DIV ABS(y);
    IF (x < 0) # (y < 0) THEN q := -q END;
    RETURN q
  END Quot;

  PROCEDURE Shift(x, n: LONGINT; left: BOOLEAN): LONGINT;
  BEGIN
    IF n > 32 THEN n := 32 END;
    WHILE n > 0 DO
      IF left THEN x := x * 2 ELSE x := x DIV 2 END;
      DEC(n)
    END;
    RETURN x
  END Shift;

  PROCEDURE Binary(code: INTEGER);
    VAR x, y, z: ASB.Value; a, b, c: LONGINT; p, q: REAL; base: INTEGER;
  BEGIN Pop(y); Pop(x);
    IF (x.form = ASB.Str) & (y.form = ASB.Str) & ((code = eql) OR (code = neq) OR (code = add)) THEN
      IF code = add THEN ASB.SetStr(z, Concat(x.s, y.s))
      ELSE ASB.SetInt(z, Bool(SameStr(x.s, y.s) = (code = eql)))
      END
    ELSIF ((x.form = ASB.Real) OR (y.form = ASB.Real)) &
          ((code <= div) OR (code >= eql) & (code <= geq)) THEN
      p := RealOf(x); q := RealOf(y);
      IF code = add THEN ASB.SetReal(z, p + q)
      ELSIF code = sub THEN ASB.SetReal(z, p - q)
      ELSIF code = mul THEN ASB.SetReal(z, p * q)
      ELSIF code = div THEN
        IF q = 0.0 THEN Err("division by zero", ""); ASB.SetReal(z, 0.0) ELSE ASB.SetReal(z, p / q) END
      ELSIF code = eql THEN ASB.SetInt(z, Bool(p = q))
      ELSIF code = neq THEN ASB.SetInt(z, Bool(p # q))
      ELSIF code = lss THEN ASB.SetInt(z, Bool(p < q))
      ELSIF code = leq THEN ASB.SetInt(z, Bool(p <= q))
      ELSIF code = gtr THEN ASB.SetInt(z, Bool(p > q))
      ELSE ASB.SetInt(z, Bool(p >= q))
      END
    ELSE a := IntOf(x); b := IntOf(y); c := 0; base := ASB.Abs;
      IF (x.base # ASB.Abs) OR (y.base # ASB.Abs) THEN
        (* an address in a .816 module plus or minus a number stays one;
           the difference of two in the same place is a number *)
        IF (code = add) & (y.base = ASB.Abs) THEN base := x.base
        ELSIF (code = add) & (x.base = ASB.Abs) THEN base := y.base
        ELSIF (code = sub) & (y.base = ASB.Abs) THEN base := x.base
        ELSIF (code = sub) & (x.base = y.base) THEN base := ASB.Abs
        ELSIF (code >= eql) & (code <= geq) OR (code = land) OR (code = lor) THEN base := ASB.Abs
        ELSE base := ASB.Mixed
        END
      END;
      CASE code OF
        add: c := a + b
      | sub: c := a - b
      | mul: c := a * b
      | div: IF b = 0 THEN Err("division by zero", "") ELSE c := Quot(a, b) END
      | mod: IF b = 0 THEN Err("division by zero", "") ELSE c := a - Quot(a, b) * b END
      | and: c := AND(a, b)
      | or: c := ORA(a, b)
      | land: c := Bool((a # 0) & (b # 0))
      | lor: c := Bool((a # 0) OR (b # 0))
      | shl: c := Shift(a, b, TRUE)
      | shr: c := Shift(a, b, FALSE)
      | eql: c := Bool(a = b)
      | neq: c := Bool(a # b)
      | lss: c := Bool(a < b)
      | leq: c := Bool(a <= b)
      | gtr: c := Bool(a > b)
      | geq: c := Bool(a >= b)
      END;
      ASB.SetInt(z, c); z.base := base
    END;
    Push(z)
  END Binary;

  PROCEDURE Unary(code: INTEGER);
    VAR x: ASB.Value; a: LONGINT; base: INTEGER;
  BEGIN Pop(x);
    IF (x.base # ASB.Abs) & (code # not) THEN base := ASB.Mixed ELSE base := ASB.Abs END;
    IF (code = neg) & (x.form = ASB.Real) THEN ASB.SetReal(x, -x.r)
    ELSIF code = not THEN ASB.SetInt(x, Bool(~True(x)))
    ELSE a := IntOf(x);
      IF code = neg THEN a := -a
      ELSIF code = cpl THEN a := -a - 1
      ELSIF code = low THEN a := a MOD 100H
      ELSIF code = high THEN a := a DIV 100H MOD 100H
      ELSE (*bank*) a := a DIV 10000H MOD 100H
      END;
      ASB.SetInt(x, a); x.base := base
    END;
    Push(x)
  END Unary;

  (* --- symbols --- *)

  PROCEDURE PushSpecial(s: INTEGER);
    VAR v: ASB.Value; name: ARRAY 16 OF CHAR; sect: ASG.Section;
  BEGIN
    CASE s OF
      sOrg: sect := ASG.Current(); ASB.SetInt(v, sect.org)
    | sAddr: ASB.SetInt(v, ASG.Here()); v.base := ASG.Base()
    | sLongA: ASB.SetInt(v, Bool(ASG.LongA()))
    | sLongI: ASB.SetInt(v, Bool(ASG.LongI()))
    | sCpu: ASC.CpuName(ASC.Cpu(), name); ASB.SetStr(v, ASB.NewString(name, ASH.Length(name)))
    | sPass: ASB.SetInt(v, passNo)
    | sDBReg: ASB.SetInt(v, ASG.DBReg())
    | sDPage: ASB.SetInt(v, ASG.DPageReg())
    | sPBReg: ASB.SetInt(v, ASG.PBReg())
    | sEntry: ASB.SetInt(v, ASG.entry)
    | sFile: ASB.SetStr(v, ASB.NewString(here.src.name, ASH.Length(here.src.name)))
    | sLine: ASB.SetInt(v, here.line)
    END;
    Push(v)
  END PushSpecial;

  PROCEDURE SetCpu(VAR v: ASB.Value);
    VAR c: INTEGER;
  BEGIN c := 0;
    IF v.form # ASB.Str THEN Err("cpu must be set to a string", "")
    ELSIF ASH.Same(v.s.s, "6502") THEN c := ASC.c6502
    ELSIF ASH.Same(v.s.s, "65C02") THEN c := ASC.c65C02
    ELSIF ASH.Same(v.s.s, "R65C02") THEN c := ASC.cR65C02
    ELSIF ASH.Same(v.s.s, "R6501Q") THEN c := ASC.cR6501Q
    ELSIF ASH.Same(v.s.s, "65C816") OR ASH.Same(v.s.s, "816") THEN c := ASC.c65C816
    ELSIF ASH.Same(v.s.s, "C19") OR ASH.Same(v.s.s, "RC19") THEN c := ASC.cC19
    ELSE Err("unknown cpu: ", v.s.s)
    END;
    IF c # 0 THEN ASG.SetCpu(c) END
  END SetCpu;

  PROCEDURE SetSpecial(s: INTEGER; VAR v: ASB.Value);
  BEGIN
    CASE s OF
      sOrg, sAddr: ASG.SetAddr(IntOf(v))
    | sLongA: ASG.SetLongA(True(v))
    | sLongI: ASG.SetLongI(True(v))
    | sCpu: SetCpu(v)
    | sDBReg: ASG.SetDBReg(IntOf(v))
    | sDPage: ASG.SetDPageReg(IntOf(v))
    | sPBReg: ASG.SetPBReg(IntOf(v))
    | sEntry: ASG.SetEntry(IntOf(v))
    | sPass, sFile, sLine: Err(here.ref.name, " cannot be set")
    END
  END SetSpecial;

  PROCEDURE PushVar(ref: Ref);
    VAR obj: ASB.Object; sub: Ref; zero: ASB.Value;
  BEGIN
    IF ref.special # 0 THEN PushSpecial(ref.special)
    ELSE
      IF ref.local & (curLabel # NIL) THEN obj := ASB.ThisIn(curLabel, ref.name)
      ELSE obj := ASB.This(ref.name)
      END;
      sub := ref.sub;
      WHILE (obj # NIL) & (sub # NIL) DO obj := ASB.ThisIn(obj, sub.name); sub := sub.sub END;
      IF (obj # NIL) & (obj.val.form # ASB.Undef) & (obj.val.form # ASB.Mod) THEN Push(obj.val)
      ELSE (*not defined yet, or not at all: only the final pass can tell*)
        sub := ref;
        WHILE sub.sub # NIL DO sub := sub.sub END;
        IF ref.local THEN Err("undefined local symbol: ", ref.name)
        ELSE Err("undefined symbol: ", sub.name)
        END;
        ASB.SetInt(zero, 0); Push(zero)
      END
    END
  END PushVar;

  (* The object a definition of ref refers to. *)
  PROCEDURE Target(ref: Ref; innermost: BOOLEAN): ASB.Object;
    VAR obj: ASB.Object;
  BEGIN
    IF ref.local & (curLabel # NIL) THEN obj := ASB.NewIn(curLabel, ref.name)
    ELSE
      IF ref.local & final THEN
        ASS.Warn(here.src, here.line, "local symbol outside the range of a label: ", ref.name)
      END;
      IF innermost THEN obj := ASB.New(ref.name)
      ELSE obj := ASB.This(ref.name);
        IF obj = NIL THEN obj := ASB.New(ref.name) END
      END
    END;
    RETURN obj
  END Target;

  PROCEDURE Assign(ref: Ref; innermost: BOOLEAN);
    VAR obj: ASB.Object; v: ASB.Value;
  BEGIN Pop(v);
    IF ref.special # 0 THEN SetSpecial(ref.special, v)
    ELSE obj := Target(ref, innermost);
      IF obj.rdo & ((obj.stamp = stamp) OR (obj.stamp = ASB.Forever)) THEN
        Err(ref.name, " is a constant and cannot be changed")
      ELSIF obj.val.form = ASB.Mod THEN Err(ref.name, " is a module")
      ELSE
        obj.val := v; obj.stamp := stamp; obj.rdo := ref.rdo;
        IF ref.expo THEN obj.expo := TRUE END
      END
    END
  END Assign;

  PROCEDURE Label(ref: Ref);
    VAR obj: ASB.Object; a: LONGINT;
  BEGIN
    IF ref.special # 0 THEN Err(ref.name, " cannot be a label")
    ELSE obj := Target(ref, TRUE); a := ASG.Here();
      IF obj.stamp = stamp THEN Err("label defined twice: ", ref.name)
      ELSIF obj.val.form = ASB.Mod THEN Err(ref.name, " is a module")
      ELSE
        IF (obj.val.form # ASB.Int) OR (obj.val.i # a) OR (obj.val.base # ASG.Base()) THEN changed := TRUE END;
        ASB.SetInt(obj.val, a); obj.val.base := ASG.Base(); obj.stamp := stamp; obj.rdo := FALSE;
        obj.expo := ref.expo
      END;
      IF ~ref.local THEN curLabel := obj END
    END
  END Label;

  (* --- instructions and data --- *)

  PROCEDURE Instruction(op: Op);
    VAR n, b1, b2, b3: INTEGER; a1, a2, a3: LONGINT;
  BEGIN n := ASC.Operands(op.b); a1 := 0; a2 := 0; a3 := 0; b1 := ASB.Abs; b2 := ASB.Abs; b3 := ASB.Abs;
    IF n > sp THEN n := sp END;
    IF n >= 1 THEN a1 := IntOf(stack[sp - n]); b1 := stack[sp - n].base END;
    IF n >= 2 THEN a2 := IntOf(stack[sp - n + 1]); b2 := stack[sp - n + 1].base END;
    IF n >= 3 THEN a3 := IntOf(stack[sp - n + 2]); b3 := stack[sp - n + 2].base END;
    Drop(n);
    ASG.Instr(op.a, op.b, op.i, a1, a2, a3, b1 + 4 * b2 + 16 * b3, op.src, op.line)
  END Instruction;

  (* x as an IEEE 754 single, low byte first *)
  PROCEDURE Single(x: REAL);
    VAR e, hi, mid, lo, sign: INTEGER;
  BEGIN
    IF x = 0.0 THEN ASG.Long(0)
    ELSE sign := 0; e := 127;
      IF x < 0.0 THEN sign := 80H; x := -x END;
      WHILE (x >= 2.0) & (e < 254) DO x := x / 2.0; INC(e) END;
      WHILE (x < 1.0) & (e > 1) DO x := x * 2.0; DEC(e) END;
      (* the 23 bits of the fraction, in pieces of 7, 8 and 8 bits *)
      x := (x - 1.0) * 128.0; hi := FLOOR(x);
      x := (x - FLT(hi)) * 256.0; mid := FLOOR(x);
      x := (x - FLT(mid)) * 256.0; lo := FLOOR(x);
      ASG.Byte(lo); ASG.Byte(mid); ASG.Byte(e MOD 2 * 80H + hi MOD 80H); ASG.Byte(sign + e DIV 2)
    END
  END Single;

  (* BYTE, WORD, LONG and FLOAT: the n values on the stack, in order *)
  PROCEDURE Data(code, n: INTEGER);
    VAR k, i: INTEGER; v: ASB.Value;
  BEGIN
    IF n > sp THEN n := sp END;
    FOR k := sp - n TO sp - 1 DO
      v := stack[k];
      IF code = float THEN Single(RealOf(v))
      ELSIF v.form = ASB.Str THEN
        IF code = byte THEN
          FOR i := 0 TO v.s.len - 1 DO ASG.Byte(ORD(v.s.s[i])) END
        ELSE Err("number expected, not a string", "")
        END
      ELSIF v.base # ASB.Abs THEN
        IF (v.base = ASB.Mixed) OR (code = byte) THEN
          Err("not an address the loader can relocate", ""); ASG.Byte(0)
        ELSE ASG.Address(IntOf(v), v.base, code = word)
        END
      ELSIF code = byte THEN ASG.Byte(IntOf(v))
      ELSIF code = word THEN ASG.Word(IntOf(v))
      ELSE ASG.Long(IntOf(v))
      END
    END;
    Drop(n)
  END Data;

  (* One character of a TEXT; left counts those still to come. *)
  PROCEDURE TextByte(c: LONGINT; VAR left: LONGINT; bit7: BOOLEAN);
  BEGIN DEC(left);
    IF bit7 & (left = 0) THEN c := c MOD 80H + 80H END;
    ASG.Byte(c)
  END TextByte;

  (* TEXT: strings and character codes; a code above 0FFH is two
     characters, high byte first. The modifier adds a length byte in
     front (.l), a zero behind (.0), or sets bit 7 of the last character
     (.7). *)
  PROCEDURE Text(n, modifier: INTEGER);
    VAR k, i: INTEGER; left: LONGINT; v: ASB.Value; bit7: BOOLEAN;
  BEGIN
    IF n > sp THEN n := sp END;
    left := 0; bit7 := modifier = ASG.MBit7;
    FOR k := sp - n TO sp - 1 DO
      IF stack[k].form = ASB.Str THEN INC(left, stack[k].s.len)
      ELSIF IntOf(stack[k]) > 0FFH THEN INC(left, 2)
      ELSE INC(left)
      END
    END;
    IF modifier = ASG.MLong THEN ASG.Byte(left) END;
    FOR k := sp - n TO sp - 1 DO
      v := stack[k];
      IF v.form = ASB.Str THEN
        FOR i := 0 TO v.s.len - 1 DO TextByte(ORD(v.s.s[i]), left, bit7) END
      ELSE
        IF IntOf(v) > 0FFH THEN TextByte(IntOf(v) DIV 100H, left, bit7) END;
        TextByte(IntOf(v), left, bit7)
      END
    END;
    IF modifier = ASG.MZero THEN ASG.Byte(0) END;
    Drop(n)
  END Text;

  (* FILL count, value ...: count elements of the size the modifier
     names, taken in turn from the values; zeros if there are none. *)
  PROCEDURE Fill(n, modifier: INTEGER);
    VAR count, k, v: LONGINT; base, pat: INTEGER;
  BEGIN
    IF n > sp THEN n := sp END;
    IF n > 0 THEN
      base := sp - n; pat := n - 1; count := IntOf(stack[base]);
      IF (count < 0) OR (count > maxFill) THEN Err("bad length of fill", ""); count := 0 END;
      k := 0;
      WHILE k < count DO
        IF pat = 0 THEN v := 0 ELSE v := IntOf(stack[base + 1 + k MOD pat]) END;
        IF (modifier = ASG.MWord) OR (modifier = ASG.MAbs) THEN ASG.Word(v)
        ELSIF modifier = ASG.MLong THEN ASG.Long(v)
        ELSE ASG.Byte(v)
        END;
        INC(k)
      END
    END;
    Drop(n)
  END Fill;

  PROCEDURE Align;
    VAR v: ASB.Value; a: LONGINT;
  BEGIN Pop(v); a := IntOf(v);
    IF (a < 1) OR (a > 10000H) THEN Err("bad alignment", "")
    ELSE
      WHILE ASG.Here() MOD a # 0 DO ASG.Byte(0) END
    END
  END Align;

  (* The text of the n values on the stack: for a message, integers in
     hexadecimal; for an error, in decimal. *)
  PROCEDURE Compose(n: INTEGER; hex: BOOLEAN; VAR s: ARRAY OF CHAR);
    VAR k, d: INTEGER; x: LONGINT; num: ARRAY 24 OF CHAR; v: ASB.Value;
  BEGIN s[0] := 0X;
    IF n > sp THEN n := sp END;
    FOR k := sp - n TO sp - 1 DO
      v := stack[k];
      IF v.form = ASB.Str THEN ASH.Append(v.s.s, s)
      ELSIF v.form = ASB.Real THEN
        ASH.IntStr(FLOOR(v.r), num); ASH.Append(num, s); ASH.Append(".", s);
        ASH.IntStr(FLOOR((v.r - FLT(FLOOR(v.r))) * 1000.0) + 1000, num);
        num[0] := "0"; ASH.Append(num, s)   (*three decimals*)
      ELSIF hex THEN
        d := 1; x := v.i;
        IF x < 0 THEN d := 8 ELSE
          WHILE x >= 10H DO x := x DIV 10H; INC(d) END
        END;
        ASH.HexStr(v.i, d, FALSE, num); ASH.Append("$", s); ASH.Append(num, s)
      ELSE ASH.IntStr(v.i, num); ASH.Append(num, s)
      END
    END;
    Drop(n)
  END Compose;

  PROCEDURE Message(op: Op);
    VAR s: ASH.Path; cond: ASB.Value;
  BEGIN
    IF op.code = message THEN
      Compose(op.a, TRUE, s);
      IF final THEN ASH.Str(s); ASH.Ln END
    ELSE
      Compose(op.a, FALSE, s);
      IF op.code = errorIf THEN Pop(cond) ELSE ASB.SetInt(cond, 1) END;
      IF True(cond) THEN Err(s, "") END
    END
  END Message;

  PROCEDURE Heading(code: INTEGER);
    VAR v: ASB.Value;
  BEGIN Pop(v);
    IF v.form # ASB.Str THEN Err("string expected", "")
    ELSIF code = title THEN titleStr := v.s
    ELSE subheadStr := v.s
    END
  END Heading;

  PROCEDURE Page;
    VAR t, s: ASH.Path;
  BEGIN t[0] := 0X; s[0] := 0X;
    IF titleStr # NIL THEN ASH.Copy(titleStr.s, t) END;
    IF subheadStr # NIL THEN ASH.Copy(subheadStr.s, s) END;
    IF final THEN ASL.Page(t, s) END
  END Page;

  PROCEDURE ListLine(op: Op);
  BEGIN
    IF final THEN
      ASL.Text(op.src, op.i, op.j);
      ASL.Line(ASG.Current(), lineAddr, lineStart, ASG.Size() - lineStart, exec)
    END;
    lineAddr := ASG.Here(); lineStart := ASG.Size()
  END ListLine;

  (* --- execution --- *)

  PROCEDURE PushFrame(scope: BOOLEAN);
  BEGIN
    IF nofFrames < maxFrames THEN
      frames[nofFrames].parent := exec; frames[nofFrames].taken := FALSE;
      frames[nofFrames].scope := scope
    ELSIF nofFrames = maxFrames THEN Err("blocks nested too deeply", "")
    END;
    INC(nofFrames)
  END PushFrame;

  (* Execute the operations from op on. What is not assembled (exec is
     FALSE) is still walked: the statements that nest must be followed,
     and the listing shows the text. *)
  PROCEDURE Exec(op: Op);
    VAR v: ASB.Value; code, f, saved, i: INTEGER; opened: BOOLEAN; outer: ASB.Object;
  BEGIN
    WHILE op # NIL DO
      here := op; code := op.code;
      IF code = line THEN ListLine(op)
      ELSIF code = suspend THEN
        op.sav.exec := exec; op.sav.n := nofFrames; i := 0;
        WHILE (i < nofFrames) & (i < maxFrames) DO op.sav.frames[i] := frames[i]; INC(i) END
      ELSIF code = resume THEN
        ASB.ResetScopes; exec := op.sav.exec; nofFrames := op.sav.n; i := 0;
        WHILE (i < nofFrames) & (i < maxFrames) DO
          frames[i] := op.sav.frames[i];
          IF frames[i].scope & ~ASB.OpenScope(frames[i].obj) THEN frames[i].scope := FALSE END;
          INC(i)
        END
      ELSIF (code >= ifBegin) & (code <= scopeEnd) THEN
        f := nofFrames - 1;
        CASE code OF
          ifBegin: PushFrame(FALSE); f := nofFrames - 1;
            IF exec THEN Pop(v); exec := True(v);
              IF f < maxFrames THEN frames[f].taken := exec END
            END
        | elseCond:
            IF (f >= 0) & (f < maxFrames) THEN exec := frames[f].parent & ~frames[f].taken END
        | elseIf:
            IF exec THEN Pop(v); exec := True(v);
              IF (f >= 0) & (f < maxFrames) THEN frames[f].taken := exec END
            END
        | else:
            IF (f >= 0) & (f < maxFrames) THEN
              exec := frames[f].parent & ~frames[f].taken; frames[f].taken := TRUE
            END
        | endIf:
            IF f >= 0 THEN
              IF f < maxFrames THEN exec := frames[f].parent END;
              DEC(nofFrames)
            END
        | scopeBegin:
            opened := exec & ASB.OpenScope(op.obj);
            IF exec & ~opened THEN Err("blocks nested too deeply", "") END;
            PushFrame(opened);
            IF nofFrames <= maxFrames THEN frames[nofFrames - 1].obj := op.obj END
        | scopeEnd:
            IF f >= 0 THEN
              IF (f < maxFrames) & frames[f].scope THEN ASB.CloseScope END;
              DEC(nofFrames)
            END
        END
      ELSIF exec THEN
        CASE code OF
          pushInt: PushI(op.i)
        | pushReal: ASB.SetReal(v, op.r); Push(v)
        | pushStr: ASB.SetStr(v, op.s); Push(v)
        | pushVar: PushVar(op.ref)
        | popVar: Assign(op.ref, FALSE)
        | defVar: Assign(op.ref, TRUE)
        | label: Label(op.ref)
        | add, sub, mul, div, mod, and, or, land, lor, shl, shr,
          eql, neq, lss, leq, gtr, geq: Binary(code)
        | neg, not, cpl, low, high, bank: Unary(code)
        | instr: Instruction(op)
        | macroCall:
            IF depth >= maxDepth THEN Err("macro calls nested too deeply: ", op.mac.name); Drop(op.mac.nofpar)
            ELSIF ~ASB.OpenScope(op.obj) THEN Err("blocks nested too deeply", ""); Drop(op.mac.nofpar)
            ELSE
              (* local labels of the body belong to this call *)
              INC(depth); saved := nofFrames; outer := curLabel; curLabel := op.obj;
              Exec(op.mac.first);
              nofFrames := saved; exec := TRUE; DEC(depth); curLabel := outer;
              ASB.CloseScope
            END
        | byte, word, long, float: Data(code, op.a)
        | text: Text(op.a, op.b)
        | fill: Fill(op.a, op.b)
        | align: Align
        | message, error, errorIf: Message(op)
        | title, subheading: Heading(code)
        | page: Page
        END
      END;
      op := op.next
    END
  END Exec;

  (* Run the program once. *)
  PROCEDURE Pass(isFinal: BOOLEAN; VAR size: LONGINT);
    VAR s: ASG.Section;
  BEGIN
    final := isFinal; INC(stamp); changed := FALSE; size := 0;
    IF final THEN passNo := 0 ELSE INC(passNo) END;
    IF verbose THEN
      IF final THEN ASH.Str("Final pass") ELSE ASH.Str("Pass "); ASH.Int(passNo) END;
      ASH.Ln
    END;
    ASG.BeginPass(final);
    s := ASG.sections;
    WHILE s # NIL DO
      IF lists[s.no].first # NIL THEN
        ASG.BeginSection(s);
        ASB.ResetScopes; curLabel := NIL;
        sp := 0; nofFrames := 0; exec := TRUE; depth := 0;
        lineAddr := ASG.Here(); lineStart := 0;
        titleStr := NIL; subheadStr := NIL;
        Exec(lists[s.no].first);
        size := size + s.size
      END;
      s := s.next
    END;
    ASB.ResetScopes
  END Pass;

  (* Assemble the program that has been parsed. The listing goes to the
     file listName, unless that is empty. *)
  PROCEDURE Assemble*(listName: ARRAY OF CHAR);
    VAR size, lastSize: LONGINT; n: INTEGER; settled: BOOLEAN;
  BEGIN
    passNo := 1; lastSize := -1; n := 0;
    REPEAT
      Pass(FALSE, size); INC(n);
      settled := ~changed & (size = lastSize);
      lastSize := size
    UNTIL settled OR (n = maxPasses);
    IF ~settled THEN ASS.Error(NIL, 0, "the addresses of the labels do not settle", "")
    ELSE
      IF (listName[0] # 0X) & ~ASL.Open(listName) THEN
        ASS.Error(NIL, 0, "cannot write listing file ", listName)
      END;
      Pass(TRUE, size);
      IF changed THEN ASS.Error(NIL, 0, "a label moved in the final pass", "") END;
      ASL.Symbols; ASL.Close
    END
  END Assemble;

  PROCEDURE SetVerbose*(on: BOOLEAN);
  BEGIN verbose := on
  END SetVerbose;

  PROCEDURE Init*;
    VAR i: INTEGER;
  BEGIN
    FOR i := 0 TO ASG.maxSections - 1 DO lists[i].first := NIL; lists[i].last := NIL END;
    psect := ASG.text; macros := NIL; defining := NIL; open := 0;
    stamp := 0; passNo := 1; final := FALSE
  END Init;

BEGIN verbose := FALSE; Init
END ASI.
