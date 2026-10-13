MODULE ASH; (* Host interface of the 65xx assembler.

   The few things the assembler needs from its environment besides files:
   console text, the process exit status and path name handling. Keeping
   them here leaves one module to adapt when the assembler is moved to
   another system. *)

  IMPORT Out;

  CONST PathLen* = 256;

  TYPE Path* = ARRAY PathLen OF CHAR;

  (* --- console --- *)

  PROCEDURE Ch*(ch: CHAR);
  BEGIN Out.Write(ch)
  END Ch;

  PROCEDURE Str*(s: ARRAY OF CHAR);
  BEGIN Out.WriteString(s)
  END Str;

  PROCEDURE Ln*;
  BEGIN Out.Ln
  END Ln;

  (* x as decimal digits *)
  PROCEDURE IntStr*(x: LONGINT; VAR s: ARRAY OF CHAR);
    VAR d: ARRAY 24 OF CHAR; i, j: INTEGER; neg: BOOLEAN;
  BEGIN neg := x < 0; i := 0; j := 0;
    IF neg THEN x := -x END;
    REPEAT d[i] := CHR(x MOD 10 + 30H); x := x DIV 10; INC(i) UNTIL x = 0;
    IF neg THEN s[0] := "-"; j := 1 END;
    WHILE (i > 0) & (j < LEN(s) - 1) DO DEC(i); s[j] := d[i]; INC(j) END;
    s[j] := 0X
  END IntStr;

  (* the low n hexadecimal digits of x *)
  PROCEDURE HexStr*(x: LONGINT; n: INTEGER; upper: BOOLEAN; VAR s: ARRAY OF CHAR);
    VAR i, d: INTEGER;
  BEGIN
    IF n > LEN(s) - 1 THEN n := LEN(s) - 1 END;
    i := n; s[i] := 0X;
    WHILE i > 0 DO
      DEC(i); d := x MOD 10H; x := x DIV 10H;
      IF d < 10 THEN s[i] := CHR(d + 30H)
      ELSIF upper THEN s[i] := CHR(d + 37H)
      ELSE s[i] := CHR(d + 57H)
      END
    END
  END HexStr;

  (* number of hexadecimal digits needed for the address x, at least n *)
  PROCEDURE HexDigits*(x: LONGINT; n: INTEGER): INTEGER;
    VAR lim: LONGINT; i: INTEGER;
  BEGIN
    IF x < 0 THEN n := 8
    ELSE lim := 1; i := 0;
      WHILE i < n DO lim := lim * 10H; INC(i) END;
      WHILE (n < 8) & (x >= lim) DO lim := lim * 100H; INC(n, 2) END
    END;
    RETURN n
  END HexDigits;

  PROCEDURE Int*(x: LONGINT);
    VAR s: ARRAY 24 OF CHAR;
  BEGIN IntStr(x, s); Out.WriteString(s)
  END Int;

  PROCEDURE Hex*(x: LONGINT; n: INTEGER);
    VAR s: ARRAY 12 OF CHAR;
  BEGIN HexStr(x, n, FALSE, s); Out.WriteString(s)
  END Hex;

  (* --- process --- *)

  (* End the program with the given status. The body is supplied by the
     host (ASH_rt.c); an empty exported body is a weak stub the C
     definition overrides. *)
  PROCEDURE Exit*(code: INTEGER);
  BEGIN
  END Exit;

  (* --- strings and path names --- *)

  PROCEDURE Length*(s: ARRAY OF CHAR): INTEGER;
    VAR i: INTEGER;
  BEGIN i := 0;
    WHILE (i < LEN(s)) & (s[i] # 0X) DO INC(i) END;
    RETURN i
  END Length;

  PROCEDURE Copy*(src: ARRAY OF CHAR; VAR dst: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN i := 0;
    WHILE (i < LEN(dst) - 1) & (i < LEN(src)) & (src[i] # 0X) DO dst[i] := src[i]; INC(i) END;
    dst[i] := 0X
  END Copy;

  PROCEDURE Append*(src: ARRAY OF CHAR; VAR dst: ARRAY OF CHAR);
    VAR i, j: INTEGER;
  BEGIN j := Length(dst); i := 0;
    WHILE (j < LEN(dst) - 1) & (i < LEN(src)) & (src[i] # 0X) DO dst[j] := src[i]; INC(i); INC(j) END;
    dst[j] := 0X
  END Append;

  PROCEDURE Cap*(ch: CHAR): CHAR;
  BEGIN
    IF (ch >= "a") & (ch <= "z") THEN ch := CHR(ORD(ch) - 20H) END;
    RETURN ch
  END Cap;

  (* equality that ignores the case of letters *)
  PROCEDURE Same*(a, b: ARRAY OF CHAR): BOOLEAN;
    VAR i: INTEGER; eq: BOOLEAN;
  BEGIN i := 0;
    WHILE (i < LEN(a)) & (i < LEN(b)) & (a[i] # 0X) & (Cap(a[i]) = Cap(b[i])) DO INC(i) END;
    IF i = LEN(a) THEN eq := (i = LEN(b)) OR (b[i] = 0X)
    ELSIF i = LEN(b) THEN eq := a[i] = 0X
    ELSE eq := (a[i] = 0X) & (b[i] = 0X)
    END;
    RETURN eq
  END Same;

  (* index of the last "/" of path, -1 if there is none *)
  PROCEDURE LastSlash(path: ARRAY OF CHAR): INTEGER;
    VAR i: INTEGER;
  BEGIN i := Length(path) - 1;
    WHILE (i >= 0) & (path[i] # "/") & (path[i] # 5CX) DO DEC(i) END;
    RETURN i
  END LastSlash;

  (* index of the "." that starts the extension, -1 if there is none *)
  PROCEDURE ExtPos(path: ARRAY OF CHAR): INTEGER;
    VAR i, slash: INTEGER;
  BEGIN slash := LastSlash(path); i := Length(path) - 1;
    WHILE (i > slash + 1) & (path[i] # ".") DO DEC(i) END;
    IF i <= slash + 1 THEN i := -1 END;   (* no dot, or a leading dot *)
    RETURN i
  END ExtPos;

  (* the directory part of path including its final "/"; empty if none *)
  PROCEDURE Dir*(path: ARRAY OF CHAR; VAR dir: ARRAY OF CHAR);
    VAR i, n: INTEGER;
  BEGIN n := LastSlash(path) + 1; i := 0;
    WHILE (i < n) & (i < LEN(dir) - 1) DO dir[i] := path[i]; INC(i) END;
    dir[i] := 0X
  END Dir;

  (* the extension of path including the "."; empty if none *)
  PROCEDURE Ext*(path: ARRAY OF CHAR; VAR ext: ARRAY OF CHAR);
    VAR i, j: INTEGER;
  BEGIN i := ExtPos(path); j := 0;
    IF i >= 0 THEN
      WHILE (path[i] # 0X) & (j < LEN(ext) - 1) DO ext[j] := path[i]; INC(i); INC(j) END
    END;
    ext[j] := 0X
  END Ext;

  (* the file name of path without directory and extension *)
  PROCEDURE Base*(path: ARRAY OF CHAR; VAR name: ARRAY OF CHAR);
    VAR i, j, end: INTEGER;
  BEGIN i := LastSlash(path) + 1; end := ExtPos(path); j := 0;
    IF end < 0 THEN end := Length(path) END;
    WHILE (i < end) & (j < LEN(name) - 1) DO name[j] := path[i]; INC(i); INC(j) END;
    name[j] := 0X
  END Base;

  (* path with its extension replaced by ext *)
  PROCEDURE SetExt*(path, ext: ARRAY OF CHAR; VAR res: ARRAY OF CHAR);
    VAR i, end: INTEGER;
  BEGIN end := ExtPos(path); i := 0;
    IF end < 0 THEN end := Length(path) END;
    WHILE (i < end) & (i < LEN(res) - 1) DO res[i] := path[i]; INC(i) END;
    res[i] := 0X;
    Append(ext, res)
  END SetExt;

  (* TRUE if name is to be looked up as given: "/x", "./x" or "../x" *)
  PROCEDURE Rooted*(name: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN (name[0] = "/") OR (name[0] = ".") & ((name[1] = "/") OR (name[1] = ".") & (name[2] = "/"))
  END Rooted;

END ASH.
