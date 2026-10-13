MODULE ASS; (* Scanner of the 65xx assembler.

   Port of as/src/scanner.c and shared/src/buffered_file.c, shaped after
   the Oberon compiler's scanner ORS: Get delivers the next symbol, with
   its attributes in ival, rval, id and str, and Mark reports an error at
   the position of that symbol.

   Unlike Oberon, assembler source is line oriented, so the end of a line
   is a symbol (eol). Source files nest (include), and the scanner tells
   the parser which part of the source text each eol closes, so that the
   listing can show the text beside the code generated from it. *)

  IMPORT Files, ASC, ASH;

  CONST IdLen* = 32; StrLen* = 256;
    KwLen = 12;
    NKW = 184;        (* size of the keyword table *)
    maxDepth = 8;     (* nesting of include files *)
    maxPaths = 6;     (* include directories *)
    maxErrors = 50;   (* messages printed before the rest are only counted *)
    LF = 0AX; CR = 0DX;

    (* lexical symbols *)
    null = 0;
    times* = 1; slash* = 2; div* = 3; mod* = 4; and* = 5; land* = 6;
    plus* = 7; minus* = 8; bar* = 9; lor* = 10;
    eql* = 11; neq* = 12; lss* = 13; leq* = 14; gtr* = 15; geq* = 16;
    lshift* = 17; rshift* = 18;
    period* = 19; comma* = 20; colon* = 21; hash* = 22; caret* = 23;
    not* = 24; tilde* = 25; lparen* = 26; rparen* = 27; lbrak* = 28;
    rbrak* = 29; lbrace* = 30; rbrace* = 31;
    becomes* = 32;
    opbecomes* = 33;  (* "+=" and the like; the operator symbol is in op *)
    int* = 34; real* = 35; string* = 36; ident* = 37;
    eol* = 38;        (* end of line *)
    eot* = 39;        (* end of text *)

    (* keywords; like the mnemonics they are recognised in any case *)
    regA* = 41; regX* = 42; regY* = 43; regS* = 44;
    if* = 45; else* = 46; let* = 47; var* = 48; macro* = 49; end* = 50;
    for* = 51; while* = 52; repeat* = 53; until* = 54;

    (* directives *)
    align* = 60; byte* = 61; data* = 62; double* = 63; error* = 64;
    errorif* = 65; fill* = 66; float* = 67; function* = 68; global* = 69;
    heading* = 70; import* = 71; inclist* = 72; include* = 73; insert* = 74;
    list* = 75; long* = 76; message* = 77; messagenow* = 78; page* = 79;
    pl* = 80; pw* = 81; section* = 82; segment* = 83; subheading* = 84;
    text* = 85; title* = 86; top* = 87; word* = 88;

    (* instructions: instr + the mnemonic number of ASC *)
    instr* = 100;

  TYPE Ident* = ARRAY IdLen OF CHAR;
    KwName = ARRAY KwLen OF CHAR;

    Source* = POINTER TO SourceDesc;
    SourceDesc* = RECORD
      name*: ASH.Path;
      isFile*: BOOLEAN;      (* FALSE: the text of a command line definition *)
      F: Files.File; R: Files.Rider;
      text: ARRAY StrLen OF CHAR;
      pos: LONGINT;          (* offset of ch in the source *)
      lineBeg: LONGINT;      (* offset of the first line no eol was delivered for *)
      line, col: INTEGER;    (* position of ch *)
      atEnd: BOOLEAN;        (* text exhausted; ch is the line end closing it *)
      ch: CHAR;              (* lookahead, saved while an included file is read *)
      prev: Source
    END;

  VAR ival*: LONGINT;        (* results of Get *)
    rval*: REAL;
    id*: Ident;
    str*: ARRAY StrLen OF CHAR;
    slen*: INTEGER;          (* length of str, which may contain 0X *)
    op*: INTEGER;
    errcnt*, warncnt*: INTEGER;

    (* position of the symbol last delivered *)
    src*: Source;
    line*, col*: INTEGER;

    (* source text closed by the eol last delivered: [listFrom, listTo) *)
    listSrc*: Source;
    listFrom*, listTo*: LONGINT;

    ch: CHAR;                (* lookahead *)
    cur: Source;             (* innermost open source, NIL at the end *)
    depth: INTEGER;
    ahead: INTEGER;          (* symbol to deliver next, or null *)
    k: INTEGER;
    keyTab: ARRAY NKW OF RECORD sym: INTEGER; id: KwName END;
    paths: ARRAY maxPaths OF ASH.Path;
    nofPaths: INTEGER;

  (* --- messages --- *)

  PROCEDURE Position(s: Source; line, col: INTEGER);
  BEGIN
    IF s # NIL THEN
      ASH.Str(s.name);
      IF s.isFile THEN
        ASH.Ch(":"); ASH.Int(line);
        IF col > 0 THEN ASH.Ch(":"); ASH.Int(col) END
      END;
      ASH.Str(": ")
    END
  END Position;

  PROCEDURE Report(s: Source; line, col: INTEGER; kind, msg, arg: ARRAY OF CHAR);
  BEGIN Position(s, line, col); ASH.Str(kind); ASH.Str(msg); ASH.Str(arg); ASH.Ln
  END Report;

  (* Report an error at source line `line` of s. The message is msg
     followed by arg. *)
  PROCEDURE Error*(s: Source; line: INTEGER; msg, arg: ARRAY OF CHAR);
  BEGIN
    IF errcnt < maxErrors THEN Report(s, line, 0, "Error: ", msg, arg)
    ELSIF errcnt = maxErrors THEN ASH.Str("Too many errors"); ASH.Ln
    END;
    INC(errcnt)
  END Error;

  PROCEDURE Warn*(s: Source; line: INTEGER; msg, arg: ARRAY OF CHAR);
  BEGIN Report(s, line, 0, "Warning: ", msg, arg); INC(warncnt)
  END Warn;

  (* Report an error at the symbol last delivered. *)
  PROCEDURE MarkS*(msg, arg: ARRAY OF CHAR);
  BEGIN
    IF errcnt < maxErrors THEN Report(src, line, col, "Error: ", msg, arg)
    ELSIF errcnt = maxErrors THEN ASH.Str("Too many errors"); ASH.Ln
    END;
    INC(errcnt)
  END MarkS;

  PROCEDURE Mark*(msg: ARRAY OF CHAR);
  BEGIN MarkS(msg, "")
  END Mark;

  (* --- characters --- *)

  PROCEDURE Read;
    VAR b: BYTE; eof: BOOLEAN;
  BEGIN
    IF cur = NIL THEN ch := 0X
    ELSIF cur.atEnd THEN  (*resume the including source*)
      IF cur.isFile THEN Files.Close(cur.F) END;
      cur := cur.prev; DEC(depth);
      IF cur # NIL THEN ch := cur.ch ELSE ch := 0X END
    ELSE
      IF ch = LF THEN INC(cur.line); cur.col := 0 END;
      REPEAT
        cur.pos := cur.pos + 1;
        IF cur.isFile THEN Files.ReadByte(cur.R, b); eof := cur.R.eof
        ELSE b := ORD(cur.text[cur.pos]); eof := b = 0
        END
      UNTIL eof OR (b # ORD(CR));
      INC(cur.col);
      (* every source ends with a line end, whether its text does or not *)
      IF eof THEN cur.atEnd := TRUE; ch := LF ELSE ch := CHR(b) END
    END
  END Read;

  PROCEDURE Push(s: Source);
  BEGIN
    s.pos := -1; s.lineBeg := 0; s.line := 1; s.col := 0; s.atEnd := FALSE;
    s.prev := cur;
    IF cur # NIL THEN cur.ch := ch END;
    cur := s; INC(depth); ch := 0X; Read
  END Push;

  (* --- symbols --- *)

  PROCEDURE Lower(ch: CHAR): CHAR;
  BEGIN
    IF (ch >= "A") & (ch <= "Z") THEN ch := CHR(ORD(ch) + 20H) END;
    RETURN ch
  END Lower;

  PROCEDURE IsDigit(ch: CHAR): BOOLEAN;
  BEGIN RETURN (ch >= "0") & (ch <= "9")
  END IsDigit;

  PROCEDURE IsLetter(ch: CHAR): BOOLEAN;
  BEGIN RETURN (ch >= "A") & (ch <= "Z") OR (ch >= "a") & (ch <= "z") OR (ch = "_")
  END IsLetter;

  (* value of the hexadecimal digit ch, -1 if it is none *)
  PROCEDURE HexVal(ch: CHAR): INTEGER;
    VAR d: INTEGER;
  BEGIN
    IF IsDigit(ch) THEN d := ORD(ch) - 30H
    ELSIF (ch >= "A") & (ch <= "F") THEN d := ORD(ch) - 37H
    ELSIF (ch >= "a") & (ch <= "f") THEN d := ORD(ch) - 57H
    ELSE d := -1
    END;
    RETURN d
  END HexVal;

  PROCEDURE Identifier(VAR sym: INTEGER);
    VAR i, l, r, m: INTEGER; low: KwName; long: BOOLEAN;
  BEGIN i := 0; long := FALSE;
    REPEAT
      IF i < IdLen-1 THEN id[i] := ch; INC(i) ELSE long := TRUE END;
      Read
    UNTIL ~IsLetter(ch) & ~IsDigit(ch);
    id[i] := 0X; sym := ident;
    IF long THEN MarkS("identifier too long: ", id) END;
    IF i < KwLen THEN  (*search for a keyword, ignoring case*)
      l := 0;
      WHILE l <= i DO low[l] := Lower(id[l]); INC(l) END;
      l := 0; r := k;
      WHILE l < r DO
        m := (l + r) DIV 2;
        IF keyTab[m].id < low THEN l := m + 1 ELSE r := m END
      END;
      IF (r < k) & (keyTab[r].id = low) THEN sym := keyTab[r].sym END
    END
  END Identifier;

  PROCEDURE Put(c: CHAR);
  BEGIN
    IF slen < StrLen-1 THEN str[slen] := c; INC(slen)
    ELSIF slen = StrLen-1 THEN Mark("string too long"); INC(slen)
    END
  END Put;

  (* String constant. Escape sequences are translated here, so str holds
     the characters the string stands for. *)
  PROCEDURE String;
    VAR d, e: INTEGER;
  BEGIN slen := 0; Read;
    WHILE (ch # 22X) & (ch # LF) DO
      IF ch = 5CX THEN Read;
        IF ch = "n" THEN Put(0AX)
        ELSIF ch = "t" THEN Put(9X)
        ELSIF ch = "b" THEN Put(8X)
        ELSIF ch = "r" THEN Put(0DX)
        ELSIF ch = "a" THEN Put(7X)
        ELSIF ch = "f" THEN Put(0CX)
        ELSIF ch = "v" THEN Put(0BX)
        ELSIF ch = "0" THEN Put(0X)
        ELSIF ch = "x" THEN Read; d := HexVal(ch);
          IF d < 0 THEN Mark("hex digit expected"); d := 0
          ELSE Read; e := HexVal(ch);
            IF e >= 0 THEN d := d * 10H + e ELSE Mark("hex digit expected") END
          END;
          Put(CHR(d))
        ELSIF ch # LF THEN Put(ch)  (* \" \' \\ *)
        END;
        IF ch # LF THEN Read END
      ELSE Put(ch); Read
      END
    END;
    IF slen >= StrLen THEN slen := StrLen-1 END;
    str[slen] := 0X;
    IF ch = 22X THEN Read ELSE Mark("string not terminated") END
  END String;

  (* 'c': the character code; more characters form a multi-byte value *)
  PROCEDURE CharConst;
  BEGIN ival := 0; Read;
    WHILE (ch # "'") & (ch # LF) DO ival := ival * 100H + ORD(ch); Read END;
    IF ch = "'" THEN Read ELSE Mark("character constant not terminated") END
  END CharConst;

  PROCEDURE Hex;
    VAR d: INTEGER;
  BEGIN ival := 0; d := HexVal(ch);
    IF d < 0 THEN Mark("hex digit expected") END;
    WHILE d >= 0 DO ival := ival * 10H + d; Read; d := HexVal(ch) END
  END Hex;

  PROCEDURE Binary;
  BEGIN ival := 0;
    REPEAT ival := ival * 2 + ORD(ch) - 30H; Read UNTIL (ch # "0") & (ch # "1")
  END Binary;

  PROCEDURE Ten(e: INTEGER): REAL;
    VAR x, t: REAL;
  BEGIN x := 1.0; t := 10.0;
    WHILE e > 0 DO
      IF ODD(e) THEN x := t * x END;
      t := t * t; e := e DIV 2
    END;
    RETURN x
  END Ten;

  PROCEDURE Number(VAR sym: INTEGER);
    CONST maxExp = 38;
    VAR x: REAL; e, s, d: INTEGER; negE: BOOLEAN;
  BEGIN ival := 0; x := 0.0; sym := int;
    REPEAT d := ORD(ch) - 30H;
      ival := ival * 8 + ival * 2 + d; x := x * 10.0 + FLT(d); Read
    UNTIL ~IsDigit(ch);
    IF ch = "." THEN Read;
      IF ~IsDigit(ch) THEN ahead := period  (*not a fraction*)
      ELSE sym := real; e := 0;
        REPEAT x := x * 10.0 + FLT(ORD(ch) - 30H); DEC(e); Read UNTIL ~IsDigit(ch);
        IF (ch = "E") OR (ch = "e") THEN Read; s := 0;
          negE := ch = "-";
          IF (ch = "-") OR (ch = "+") THEN Read END;
          IF IsDigit(ch) THEN
            REPEAT s := s * 10 + ORD(ch) - 30H; Read UNTIL ~IsDigit(ch) OR (s > 1000);
            IF negE THEN e := e - s ELSE e := e + s END
          ELSE Mark("digit expected")
          END
        END;
        IF e < 0 THEN
          IF e >= -maxExp THEN x := x / Ten(-e) ELSE x := 0.0 END
        ELSIF e > 0 THEN
          IF e <= maxExp THEN x := Ten(e) * x ELSE x := 0.0; Mark("number too large") END
        END;
        rval := x
      END
    END
  END Number;

  PROCEDURE LineComment;
  BEGIN
    WHILE ch # LF DO Read END  (*the line end is a symbol of its own*)
  END LineComment;

  (* Oberon comment, which may be nested and may span lines *)
  PROCEDURE Comment;
  BEGIN Read;
    REPEAT
      WHILE (cur # NIL) & (ch # "*") DO
        IF ch = "(" THEN Read;
          IF ch = "*" THEN Comment END
        ELSE Read
        END
      END;
      WHILE ch = "*" DO Read END
    UNTIL (ch = ")") OR (cur = NIL);
    IF cur # NIL THEN Read ELSE Mark("comment not terminated") END
  END Comment;

  PROCEDURE CComment;
    VAR done: BOOLEAN;
  BEGIN Read; done := FALSE;
    WHILE ~done & (cur # NIL) DO
      IF ch = "*" THEN Read;
        IF ch = "/" THEN Read; done := TRUE END
      ELSE Read
      END
    END;
    IF ~done THEN Mark("comment not terminated") END
  END CComment;

  (* ch = LF: deliver eol and note which source text it closes *)
  PROCEDURE EndLine;
  BEGIN
    listSrc := cur; listFrom := cur.lineBeg;
    IF cur.atEnd THEN listTo := cur.pos ELSE listTo := cur.pos + 1 END;
    cur.lineBeg := listTo;
    Read
  END EndLine;

  (* "x=" is the compound assignment of operator o, otherwise it is o *)
  PROCEDURE Operator(o: INTEGER; VAR sym: INTEGER);
  BEGIN
    IF ch = "=" THEN Read; sym := opbecomes; op := o ELSE sym := o END
  END Operator;

  PROCEDURE Get*(VAR sym: INTEGER);
  BEGIN
    IF ahead # null THEN sym := ahead; ahead := null
    ELSE
      REPEAT
        WHILE (cur # NIL) & (ch # LF) & (ch <= " ") DO Read END;
        IF cur = NIL THEN sym := eot
        ELSE src := cur; line := cur.line; col := cur.col;
          IF ch = LF THEN EndLine; sym := eol
          ELSIF IsLetter(ch) THEN Identifier(sym)
          ELSIF IsDigit(ch) THEN Number(sym)
          ELSIF ch = 22X THEN String; sym := string
          ELSIF ch = "'" THEN CharConst; sym := int
          ELSIF ch = "$" THEN Read; Hex; sym := int
          ELSIF ch = "%" THEN Read;
            IF (ch = "0") OR (ch = "1") THEN Binary; sym := int ELSE Operator(mod, sym) END
          ELSIF ch = ";" THEN LineComment; sym := null
          ELSIF ch = "*" THEN
            IF cur.col = 1 THEN LineComment; sym := null ELSE Read; Operator(times, sym) END
          ELSIF ch = "/" THEN Read;
            IF ch = "/" THEN LineComment; sym := null
            ELSIF ch = "*" THEN CComment; sym := null
            ELSE Operator(slash, sym)
            END
          ELSIF ch = "(" THEN Read;
            IF ch = "*" THEN Comment; sym := null ELSE sym := lparen END
          ELSIF ch = "+" THEN Read; Operator(plus, sym)
          ELSIF ch = "-" THEN Read; Operator(minus, sym)
          ELSIF ch = "&" THEN Read;
            IF ch = "&" THEN Read; sym := land ELSE Operator(and, sym) END
          ELSIF ch = "|" THEN Read;
            IF ch = "|" THEN Read; sym := lor ELSE Operator(bar, sym) END
          ELSIF ch = "<" THEN Read;
            IF ch = "=" THEN Read; sym := leq
            ELSIF ch = "<" THEN Read; Operator(lshift, sym)
            ELSE sym := lss
            END
          ELSIF ch = ">" THEN Read;
            IF ch = "=" THEN Read; sym := geq
            ELSIF ch = ">" THEN Read; Operator(rshift, sym)
            ELSE sym := gtr
            END
          ELSIF ch = "=" THEN Read;
            IF ch = "=" THEN Read; sym := eql ELSE sym := becomes END
          ELSIF ch = ":" THEN Read;
            IF ch = "=" THEN Read; sym := becomes ELSE sym := colon END
          ELSIF ch = "!" THEN Read;
            IF ch = "=" THEN Read; sym := neq ELSE sym := not END
          ELSE
            IF ch = ")" THEN sym := rparen
            ELSIF ch = "," THEN sym := comma
            ELSIF ch = "." THEN sym := period
            ELSIF ch = "#" THEN sym := hash
            ELSIF ch = "[" THEN sym := lbrak
            ELSIF ch = "]" THEN sym := rbrak
            ELSIF ch = "^" THEN sym := caret
            ELSIF ch = "{" THEN sym := lbrace
            ELSIF ch = "}" THEN sym := rbrace
            ELSIF ch = "~" THEN sym := tilde
            ELSE Mark("illegal character"); sym := null
            END;
            Read
          END
        END
      UNTIL sym # null
    END
  END Get;

  PROCEDURE IsInstr*(sym: INTEGER): BOOLEAN;
  BEGIN RETURN sym >= instr
  END IsInstr;

  PROCEDURE IsDirective*(sym: INTEGER): BOOLEAN;
  BEGIN RETURN (sym >= align) & (sym <= word)
  END IsDirective;

  (* A name for symbol sym, for messages. *)
  PROCEDURE SymName*(sym: INTEGER; VAR s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    IF sym >= regA THEN i := 0;
      WHILE (i < k) & (keyTab[i].sym # sym) DO INC(i) END;
      IF i < k THEN ASH.Copy(keyTab[i].id, s) ELSE s := "?" END
    ELSIF sym = int THEN s := "number"
    ELSIF sym = real THEN s := "real number"
    ELSIF sym = string THEN s := "string"
    ELSIF sym = ident THEN ASH.Copy(id, s)
    ELSIF sym = eol THEN s := "end of line"
    ELSIF sym = eot THEN s := "end of file"
    ELSE
      CASE sym OF
        times: s := "*" | slash: s := "/" | div: s := "div" | mod: s := "mod"
      | and: s := "&" | land: s := "&&" | plus: s := "+" | minus: s := "-"
      | bar: s := "|" | lor: s := "||" | eql: s := "==" | neq: s := "!="
      | lss: s := "<" | leq: s := "<=" | gtr: s := ">" | geq: s := ">="
      | lshift: s := "<<" | rshift: s := ">>" | period: s := "."
      | comma: s := "," | colon: s := ":" | hash: s := "#" | caret: s := "^"
      | not: s := "!" | tilde: s := "~" | lparen: s := "(" | rparen: s := ")"
      | lbrak: s := "[" | rbrak: s := "]" | lbrace: s := "{" | rbrace: s := "}"
      | becomes: s := "=" | opbecomes: s := "op="
      END
    END
  END SymName;

  (* --- sources --- *)

  PROCEDURE Reset;
  BEGIN
    WHILE cur # NIL DO
      IF cur.isFile THEN Files.Close(cur.F) END;
      cur := cur.prev
    END;
    depth := 0; ahead := null; ch := 0X; src := NIL; line := 0; col := 0;
    listSrc := NIL; listFrom := 0; listTo := 0
  END Reset;

  PROCEDURE OpenFile(name: ARRAY OF CHAR): Source;
    VAR s: Source; F: Files.File;
  BEGIN s := NIL; F := Files.Old(name);
    IF F # NIL THEN
      NEW(s); ASH.Copy(name, s.name); s.isFile := TRUE; s.F := F;
      Files.Set(s.R, F, 0)
    END;
    RETURN s
  END OpenFile;

  (* Start scanning file `name`. FALSE if it cannot be read. *)
  PROCEDURE Open*(name: ARRAY OF CHAR): BOOLEAN;
    VAR s: Source;
  BEGIN Reset; s := OpenFile(name);
    IF s # NIL THEN Push(s) END;
    RETURN s # NIL
  END Open;

  (* Start scanning `text`, a definition given on the command line. *)
  PROCEDURE OpenText*(text: ARRAY OF CHAR);
    VAR s: Source;
  BEGIN Reset;
    NEW(s); s.name := "command line"; s.isFile := FALSE; ASH.Copy(text, s.text);
    Push(s)
  END OpenText;

  (* Add a directory to those searched for include files. *)
  PROCEDURE AddPath*(dir: ARRAY OF CHAR);
    VAR n: INTEGER;
  BEGIN
    IF nofPaths < maxPaths THEN
      ASH.Copy(dir, paths[nofPaths]); n := ASH.Length(dir);
      IF (n > 0) & (dir[n-1] # "/") THEN ASH.Append("/", paths[nofPaths]) END;
      INC(nofPaths)
    ELSE ASH.Str("Too many include paths"); ASH.Ln
    END
  END AddPath;

  (* Open the file `name` for reading: as given if it names a place,
     otherwise beside the file `from`, in the include directories and
     in the current directory, in that order. *)
  PROCEDURE Locate*(name, from: ARRAY OF CHAR; VAR path: ARRAY OF CHAR): Files.File;
    VAR F: Files.File; i: INTEGER;
  BEGIN
    IF ASH.Rooted(name) THEN ASH.Copy(name, path); F := Files.Old(path)
    ELSE
      ASH.Dir(from, path); ASH.Append(name, path); F := Files.Old(path);
      i := 0;
      WHILE (F = NIL) & (i < nofPaths) DO
        ASH.Copy(paths[i], path); ASH.Append(name, path); F := Files.Old(path); INC(i)
      END;
      IF F = NIL THEN ASH.Copy(name, path); F := Files.Old(path) END
    END;
    RETURN F
  END Locate;

  (* Continue scanning with the text of file `name`; at its end the
     scanner resumes after the symbol last delivered. *)
  PROCEDURE Include*(name: ARRAY OF CHAR): BOOLEAN;
    VAR s: Source; F: Files.File; path: ASH.Path; from: ASH.Path;
  BEGIN s := NIL;
    IF depth >= maxDepth THEN Mark("includes nested too deeply")
    ELSE
      IF cur # NIL THEN from := cur.name ELSE from[0] := 0X END;
      F := Locate(name, from, path);
      IF F # NIL THEN
        NEW(s); ASH.Copy(path, s.name); s.isFile := TRUE; s.F := F;
        Files.Set(s.R, F, 0);
        Push(s)
      END
    END;
    RETURN s # NIL
  END Include;

  PROCEDURE Init*;
  BEGIN Reset; errcnt := 0; warncnt := 0
  END Init;

  (* --- keywords --- *)

  (* The table is kept sorted for the binary search of Identifier. *)
  PROCEDURE Enter(sym: INTEGER; name: ARRAY OF CHAR);
    VAR i: INTEGER; kw: KwName;
  BEGIN ASH.Copy(name, kw); i := k;
    WHILE (i > 0) & (kw < keyTab[i-1].id) DO keyTab[i] := keyTab[i-1]; DEC(i) END;
    keyTab[i].sym := sym; keyTab[i].id := kw;
    INC(k)
  END Enter;

  PROCEDURE EnterKeywords;
    VAR i: INTEGER; m: ASC.Mnemonic;
  BEGIN k := 0;
    Enter(regA, "a"); Enter(regX, "x"); Enter(regY, "y"); Enter(regS, "s");
    Enter(div, "div"); Enter(mod, "mod");
    Enter(if, "if"); Enter(else, "else"); Enter(let, "let"); Enter(var, "var");
    Enter(macro, "macro"); Enter(end, "end");
    Enter(for, "for"); Enter(while, "while"); Enter(repeat, "repeat");
    Enter(until, "until");
    Enter(align, "align"); Enter(byte, "byte"); Enter(data, "data");
    Enter(double, "double"); Enter(error, "error"); Enter(errorif, "errorif");
    Enter(fill, "fill"); Enter(float, "float"); Enter(function, "function");
    Enter(global, "global"); Enter(heading, "heading"); Enter(import, "import");
    Enter(inclist, "inclist"); Enter(include, "include"); Enter(insert, "insert");
    Enter(list, "list"); Enter(long, "long"); Enter(message, "message");
    Enter(messagenow, "messagenow"); Enter(page, "page"); Enter(pl, "pl");
    Enter(pw, "pw"); Enter(section, "section"); Enter(segment, "segment");
    Enter(subheading, "subheading"); Enter(text, "text"); Enter(title, "title");
    Enter(top, "top"); Enter(word, "word");
    FOR i := 0 TO ASC.nofInstr - 1 DO ASC.Name(i, m); Enter(instr + i, m) END
  END EnterKeywords;

BEGIN cur := NIL; nofPaths := 0; EnterKeywords; Init
END ASS.
