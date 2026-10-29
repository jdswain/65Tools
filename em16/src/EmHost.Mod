MODULE EmHost; (* The host side of em16: standard output and error, the
   terminal, the clock, disk images and the display windows.

   The procedures without a body here are weak stubs; EmHost_rt.c (and
   EmCocoa.m for the windows) define them, as ASH_rt.c does for as.
   Everything else is written in Oberon on top of them: the formatting
   of numbers and the "sticky" hex of C++'s cout, which em16's messages
   relied on and its test scripts read. *)

  CONST
    out* = 0; err* = 1;     (* the two streams *)
    bufLen = 512;

  TYPE
    Stream = RECORD
      buf: ARRAY bufLen OF CHAR;
      n: INTEGER
    END;

  VAR
    s: ARRAY 2 OF Stream;
    coutHex*: BOOLEAN;      (* cout << hex has been written: integers go out in hex *)
    adb*: INTEGER;          (* where the window's keys and mouse go: 0 the VIA, 1 the SoC *)
    pace*: INTEGER;         (* 1: the SoC kept to real time once at rest (set by the window) *)

  (* --- the C side --- *)

  PROCEDURE Init*;                                   (* signals *)
  END Init;

  PROCEDURE Write*(stream: INTEGER; VAR buf: ARRAY OF CHAR; n: INTEGER);
  END Write;

  PROCEDURE Flush*;                                  (* fflush(stdout) *)
  END Flush;

  PROCEDURE PutChar*(ch: INTEGER);                   (* putchar and fflush *)
  END PutChar;

  PROCEDURE IsTTY*(): INTEGER;                       (* stdin is a terminal *)
  BEGIN RETURN 0
  END IsTTY;

  PROCEDURE NonBlock*;                               (* stdin O_NONBLOCK *)
  END NonBlock;

  PROCEDURE RawMode*;                                (* stdin raw, once *)
  END RawMode;

  PROCEDURE ReadIn*(): INTEGER;                      (* a byte of stdin, -1: none *)
  BEGIN RETURN -1
  END ReadIn;

  PROCEDURE Exit*(code: INTEGER);
  END Exit;

  PROCEDURE ClockStart*;
  END ClockStart;

  (* Kept to real time: a sleep while cycles at hz a second are ahead of
     the clock since the first call. *)
  PROCEDURE Pace*(cycles, hz: LONGINT);
  END Pace;

  (* The closing statistics: "Executed n in s Secs", the frequency. *)
  PROCEDURE Report*(cycles: LONGINT; hex: INTEGER);
  END Report;

  PROCEDURE SetADB*(n: INTEGER);
  BEGIN adb := n
  END SetADB;

  (* The path of this program. *)
  PROCEDURE ExePath*(VAR s: ARRAY OF CHAR);
  END ExePath;

  PROCEDURE FileExists*(name: ARRAY OF CHAR): INTEGER;
  BEGIN RETURN 0
  END FileExists;

  (* Disk images, by number: 0 and 1 the floppy drives, 2 the SCSI disk,
     3 the SD card.
     Open returns 0 failed, 1 read-write, 2 read-only. *)
  PROCEDURE DiskOpen*(drive: INTEGER; name: ARRAY OF CHAR): INTEGER;
  BEGIN RETURN 0
  END DiskOpen;

  PROCEDURE DiskRead*(drive, offset: INTEGER; VAR buf: ARRAY OF BYTE): INTEGER;
  BEGIN RETURN 0
  END DiskRead;

  PROCEDURE DiskWrite*(drive, offset: INTEGER; VAR buf: ARRAY OF BYTE);
  END DiskWrite;

  PROCEDURE DiskSize*(drive: INTEGER): INTEGER;      (* in bytes, 0: none *)
  BEGIN RETURN 0
  END DiskSize;

  (* Run the CPU (Em16.CpuThread) on a second thread and the window of
     the video display or the LCD on this one, until it is closed. *)
  PROCEDURE RunVideo*;
  END RunVideo;

  PROCEDURE RunLCD*;
  END RunLCD;

  PROCEDURE StopDisplay*;
  END StopDisplay;

  (* The RA8889's built-in 8x16 font, 4096 bytes. *)
  PROCEDURE Font*(VAR f: ARRAY OF BYTE);
  END Font;

  (* --- output --- *)

  PROCEDURE Drain*(stream: INTEGER);
  BEGIN
    IF s[stream].n > 0 THEN Write(stream, s[stream].buf, s[stream].n); s[stream].n := 0 END
  END Drain;

  PROCEDURE Ch*(stream: INTEGER; ch: CHAR);
  BEGIN
    IF s[stream].n = bufLen THEN Drain(stream) END;
    s[stream].buf[s[stream].n] := ch; INC(s[stream].n)
  END Ch;

  PROCEDURE Str*(stream: INTEGER; str: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN i := 0;
    WHILE (i < LEN(str)) & (str[i] # 0X) DO Ch(stream, str[i]); INC(i) END
  END Str;

  (* A line end. Standard error is written through at once, as cerr was;
     standard output when the line ends, which keeps the order of the C++
     version as long as the two go to different places. *)
  PROCEDURE Ln*(stream: INTEGER);
  BEGIN Ch(stream, 0AX); Drain(stream)
  END Ln;

  (* Decimal, at least w wide, padded with blanks (or zeros if zero). *)
  PROCEDURE IntPad*(stream: INTEGER; x: LONGINT; w: INTEGER; zero: BOOLEAN);
    VAR d: ARRAY 24 OF CHAR; i, k: INTEGER; neg: BOOLEAN;
  BEGIN neg := x < 0; i := 0;
    IF neg THEN x := -x END;
    REPEAT d[i] := CHR(ORD("0") + x MOD 10); x := x DIV 10; INC(i) UNTIL x = 0;
    k := i; IF neg THEN INC(k) END;
    IF zero & neg THEN Ch(stream, "-") END;
    WHILE k < w DO
      IF zero THEN Ch(stream, "0") ELSE Ch(stream, " ") END; INC(k)
    END;
    IF ~zero & neg THEN Ch(stream, "-") END;
    WHILE i > 0 DO DEC(i); Ch(stream, d[i]) END
  END IntPad;

  PROCEDURE Int*(stream: INTEGER; x: LONGINT);
  BEGIN IntPad(stream, x, 0, FALSE)
  END Int;

  (* Hexadecimal of the low 32 bits, at least w digits, zero padded. *)
  PROCEDURE HexPad*(stream: INTEGER; x: LONGINT; w: INTEGER; upper: BOOLEAN);
    VAR d: ARRAY 16 OF CHAR; i, v: INTEGER; m: LONGINT;
  BEGIN i := 0;
    m := 65536; m := m * 65536; x := x MOD m;
    REPEAT v := x MOD 16; x := x DIV 16;
      IF v < 10 THEN d[i] := CHR(ORD("0") + v)
      ELSIF upper THEN d[i] := CHR(ORD("A") + v - 10)
      ELSE d[i] := CHR(ORD("a") + v - 10)
      END;
      INC(i)
    UNTIL x = 0;
    WHILE w > i DO Ch(stream, "0"); DEC(w) END;
    WHILE i > 0 DO DEC(i); Ch(stream, d[i]) END
  END HexPad;

  (* printf's %0wX *)
  PROCEDURE Hex*(stream: INTEGER; x: LONGINT; w: INTEGER);
  BEGIN HexPad(stream, x, w, TRUE)
  END Hex;

  (* em16's toHex: exactly n upper case digits, the low ones. *)
  PROCEDURE ToHex*(stream: INTEGER; x: LONGINT; n: INTEGER);
    VAR d: ARRAY 16 OF CHAR; i, v: INTEGER;
  BEGIN
    FOR i := 0 TO n - 1 DO v := x MOD 16; x := x DIV 16;
      IF v < 10 THEN d[i] := CHR(ORD("0") + v) ELSE d[i] := CHR(ORD("A") + v - 10) END
    END;
    i := n;
    WHILE i > 0 DO DEC(i); Ch(stream, d[i]) END
  END ToHex;

  (* An integer written to cout: in lower case hex once cout << hex has
     been written, in decimal before. *)
  PROCEDURE Cout*(x: LONGINT);
  BEGIN
    IF coutHex THEN HexPad(out, x, 0, FALSE) ELSE Int(out, x) END
  END Cout;

  (* cout << hex << x *)
  PROCEDURE CoutHex*(x: LONGINT);
  BEGIN coutHex := TRUE; HexPad(out, x, 0, FALSE)
  END CoutHex;

  (* The C side calls this before the process ends. *)
  PROCEDURE DrainAll*;
  BEGIN Drain(out); Drain(err)
  END DrainAll;

BEGIN s[out].n := 0; s[err].n := 0; coutHex := FALSE; adb := 0; pace := 0
END EmHost.
