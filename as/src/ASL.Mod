MODULE ASL; (* Listing of the 65xx assembler.

   Writes the listing file: every source line beside the address and the
   bytes generated from it, followed by the table of symbols. Port of the
   listing parts of as/src/interp.c and as/src/as.c.

   The text of a line is not kept in memory while the program is
   assembled; it is read again from the source file when it is listed. *)

  IMPORT Files, ASH, ASS, ASB, ASG;

  CONST BytesPerLine = 6;
    Columns = 4; NameWidth = 20;   (* of the symbol table *)
    LF = 0AX; CR = 0DX; FF = 0CX;

  VAR
    isOpen: BOOLEAN;
    F: Files.File; R: Files.Rider;
    (* the source file being quoted *)
    src: ASS.Source; srcF: Files.File; srcR: Files.Rider;
    (* the text of the line being listed *)
    textSrc: ASS.Source; textFrom, textTo: LONGINT;

  PROCEDURE Ch(ch: CHAR);
  BEGIN Files.WriteByte(R, ORD(ch))
  END Ch;

  PROCEDURE Str(s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN i := 0;
    WHILE (i < LEN(s)) & (s[i] # 0X) DO Files.WriteByte(R, ORD(s[i])); INC(i) END
  END Str;

  PROCEDURE Hex(x: LONGINT; n: INTEGER);
    VAR s: ARRAY 12 OF CHAR;
  BEGIN ASH.HexStr(x, n, FALSE, s); Str(s)
  END Hex;

  PROCEDURE Spaces(n: INTEGER);
  BEGIN
    WHILE n > 0 DO Ch(" "); DEC(n) END
  END Spaces;

  PROCEDURE IsOpen*(): BOOLEAN;
  BEGIN RETURN isOpen
  END IsOpen;

  PROCEDURE Open*(name: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    F := Files.New(name); isOpen := F # NIL;
    IF isOpen THEN Files.Set(R, F, 0) END;
    src := NIL; srcF := NIL;
    RETURN isOpen
  END Open;

  PROCEDURE Close*;
  BEGIN
    IF isOpen THEN Files.Register(F); Files.Close(F); isOpen := FALSE END;
    IF srcF # NIL THEN Files.Close(srcF); srcF := NIL END;
    src := NIL
  END Close;

  (* Position the source reader at offset pos of file s. *)
  PROCEDURE Seek(s: ASS.Source; pos: LONGINT);
  BEGIN
    IF s # src THEN
      IF srcF # NIL THEN Files.Close(srcF) END;
      src := s; srcF := Files.Old(s.name)
    END;
    IF srcF # NIL THEN Files.Set(srcR, srcF, pos) END
  END Seek;

  (* Copy one line of source text, which starts at pos, to the listing;
     pos is advanced past it. *)
  PROCEDURE CopyLine(VAR pos: LONGINT; to: LONGINT);
    VAR b: BYTE; done: BOOLEAN;
  BEGIN done := FALSE;
    WHILE ~done & (pos < to) DO
      Files.ReadByte(srcR, b); pos := pos + 1;
      IF srcR.eof THEN done := TRUE
      ELSIF b = ORD(LF) THEN done := TRUE
      ELSIF b # ORD(CR) THEN Files.WriteByte(R, b)
      END
    END
  END CopyLine;

  (* The source text [from, to) of file s is what the next Line lists.
     (A procedure of its own: with the text as parameters of Line, the
     call needs more registers than the 65C816 compiler has.) *)
  PROCEDURE Text*(s: ASS.Source; from, to: LONGINT);
  BEGIN textSrc := s; textFrom := from; textTo := to
  END Text;

  (* List the source text given to Text beside the n bytes at offset
     start of section sect, which are at address addr. exec is FALSE
     for text that conditional assembly left out. *)
  PROCEDURE Line*(sect: ASG.Section; addr, start, n: LONGINT; exec: BOOLEAN);
    VAR pos, i, from, to: LONGINT; j, digits: INTEGER; hasText: BOOLEAN; s: ASS.Source;
  BEGIN s := textSrc; from := textFrom; to := textTo;
    IF isOpen THEN
      IF ~exec THEN n := 0 END;
      hasText := (s # NIL) & s.isFile & (from < to);
      IF hasText THEN Seek(s, from); hasText := srcF # NIL END;
      pos := from; i := 0;
      digits := ASH.HexDigits(addr + n, 4);
      IF hasText OR (n > 0) THEN
      REPEAT
        IF i < n THEN Hex(addr + i, digits) ELSE Hex(addr + n, digits) END;
        Str(": ");
        IF ~exec THEN Str("XX"); Spaces(BytesPerLine * 3 - 2)
        ELSE j := 0;
          WHILE j < BytesPerLine DO
            IF (i + j < n) & (sect.type # ASG.Nobits) THEN Hex(ASG.Get(sect, start + i + j), 2); Ch(" ")
            ELSE Spaces(3)
            END;
            INC(j)
          END
        END;
        IF hasText & (pos < to) THEN CopyLine(pos, to) END;
        Ch(LF);
        i := i + BytesPerLine
      UNTIL (i >= n) & ~(hasText & (pos < to))
      END
    END
  END Line;

  (* Start a new page, headed by the title and the subheading. *)
  PROCEDURE Page*(title, subheading: ARRAY OF CHAR);
  BEGIN
    IF isOpen THEN
      Ch(FF);
      IF title[0] # 0X THEN Str(title); Ch(LF) END;
      IF subheading[0] # 0X THEN Str(subheading); Ch(LF) END
    END
  END Page;

  PROCEDURE Symbol(obj: ASB.Object);
    VAR n, i: INTEGER; s: ARRAY 24 OF CHAR;
  BEGIN
    Str(obj.name); n := ASH.Length(obj.name);
    IF obj.expo THEN Ch("*"); INC(n) END;
    Spaces(NameWidth - n); Ch(" ");
    IF obj.val.form = ASB.Int THEN
      Hex(obj.val.i, ASH.HexDigits(obj.val.i, 4)); Spaces(10 - ASH.HexDigits(obj.val.i, 4))
    ELSIF obj.val.form = ASB.Str THEN
      Ch(22X); i := 0;
      WHILE (i < 7) & (i < obj.val.s.len) & (obj.val.s.s[i] >= " ") DO Ch(obj.val.s.s[i]); INC(i) END;
      Ch(22X); Spaces(8 - i)
    ELSE (*real*)
      ASH.IntStr(FLOOR(obj.val.r), s); Str(s); Str(".");
      Spaces(9 - ASH.Length(s))
    END
  END Symbol;

  PROCEDURE Listed(obj: ASB.Object): BOOLEAN;
  BEGIN RETURN (obj.val.form = ASB.Int) OR (obj.val.form = ASB.Real) OR (obj.val.form = ASB.Str)
  END Listed;

  (* Append the table of the program's symbols, in alphabetical order
     running down the columns. *)
  PROCEDURE Symbols*;
    VAR list, obj, row, p: ASB.Object; n, count, rows, r, c, i: INTEGER;
  BEGIN
    IF isOpen THEN
      (* unlink what is not listed: modules and symbols never defined *)
      list := ASB.Sorted(ASB.Top(), n);
      WHILE (list # NIL) & ~Listed(list) DO list := list.link END;
      count := 0; obj := list;
      WHILE obj # NIL DO INC(count);
        WHILE (obj.link # NIL) & ~Listed(obj.link) DO obj.link := obj.link.link END;
        obj := obj.link
      END;
      Ch(LF); Str("Symbols:"); Ch(LF);
      rows := (count + Columns - 1) DIV Columns;
      row := list;
      FOR r := 0 TO rows - 1 DO
        p := row; c := 0;
        WHILE (p # NIL) & (c < Columns) DO
          Symbol(p); INC(c);
          i := 0;
          WHILE (p # NIL) & (i < rows) DO p := p.link; INC(i) END
        END;
        Ch(LF);
        row := row.link
      END
    END
  END Symbols;

BEGIN isOpen := FALSE; src := NIL; srcF := NIL; textSrc := NIL
END ASL.
