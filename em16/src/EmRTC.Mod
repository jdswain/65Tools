MODULE EmRTC; (* The 65-16 rev B's real-time clock, a DS12C887 (the PC AT's
   MC146818 with its crystal, its cell and a century byte), on the external
   bus at select 7, $0870-$087F, mirrored every 128 bytes; only A0 is
   decoded (Verilog65C816 docs/Hardware.md, "Real-time clock"):

     $0870 (A0 = 0)  write: the register's index (AS); read: nobody
                     drives the bus, $FF
     $0871 (A0 = 1)  the register at the index, read or written

   Its 128 bytes: 00 seconds, 01 their alarm, 02 minutes, 03 their alarm,
   04 hours (12-hour mode: 1-12, bit 7 PM), 05 their alarm, 06 the day of
   the week (1-7, Sunday 1), 07 the date, 08 the month, 09 the year (0-99),
   in binary or BCD as B.DM says; 0A register A (7 UIP, read only; 6-4 DV,
   010 the only pattern that keeps time, 11x the divider held, the first
   update 500 ms after 010 is written; 3-0 RS, the periodic rate); 0B
   register B (7 SET, updates stopped; 6 PIE, 5 AIE, 4 UIE, 3 SQWE, 2 DM
   binary, 1 24-hour, 0 DSE); 0C register C, read only and cleared by a
   read (7 IRQF, 6 PF, 5 AF, 4 UF); 0D register D (7 VRT: the cell good,
   always here); 0E-7F the NV RAM, 32 of it the century (DM's form too).

   The time is kept in the registers as they were written, as the chip
   keeps it: a change of DM or 24/12 does not convert them. Each update
   (a second of the SoC's clock, EmHost.hz, so the guest's times agree
   with each other, paced or not) decodes them as B says, adds a second
   (the date, the month, the year and the century carried, leap years
   from the year, 2000 a leap year) and encodes them back, unless SET;
   then UF, and AF if the seconds, minutes and hours match their alarms
   (an alarm byte of C0-FF matches any). UIP is 1 from 244 us before an
   update to 2 ms after it. PF comes every period of RS (none for 0;
   1 and 2 as 8 and 9, 256 and 128 Hz; else 2^(RS-1) / 32768 s) while the
   divider runs. The interrupt, the open-drain /IRQ on the cards' IRQ#,
   is IRQF: PF and PIE, AF and AIE, or UF and UIE. DSE's daylight saving
   and the square wave are not done (SQW is not connected).

   A reset (/RES) clears PIE, AIE, UIE, SQWE and the flags; the time and
   the RAM are kept. At start-up the chip is as OS16 leaves it, running
   (A 20H), binary and 24-hour (B 06H), at the host's time in UTC; or at
   -rtctime's (SetTime, for a test); or as -rtc's file has it (Load), its
   time carried on by the host's seconds since it was saved, and a file
   not there yet a new module: the oscillator off (A 00H), B 00H, the time
   and the RAM 0. The file, the 128 bytes and the host's time at the
   save, 8 bytes, is written after each write to a register. With
   -nortc (Absent) there is no chip, as on a rev A board: select 7 reads
   $FF and takes no writes (a test's machine, whose files have no date). *)

  IMPORT Files, EmHost;

  CONST
    Uip = 80H; Set = 80H; Pie = 40H; Aie = 20H; Uie = 10H; Sqwe = 08H; Dm = 04H; H24 = 02H;
    Irqf = 80H; Pf = 40H; Af = 20H; Uf = 10H;
    Century = 32H;
    Size = 128;

  VAR
    r: ARRAY Size OF INTEGER;  (* the registers and the RAM; r[0CH] the flags *)
    index: INTEGER;
    hz: LONGINT;
    nextUpdate, lastUpdate, nextPeriodic: LONGINT;   (* cycles; -1 none *)
    file: ARRAY 256 OF CHAR;   (* -rtc's, "" none *)
    present*: BOOLEAN;      (* the chip is there: FALSE after -nortc *)

  (* --- the calendar --- *)

  PROCEDURE Leap(y: INTEGER): BOOLEAN;
  BEGIN RETURN (y MOD 4 = 0) & ((y MOD 100 # 0) OR (y MOD 400 = 0))
  END Leap;

  PROCEDURE MonthDays(y, m: INTEGER): INTEGER;
    VAR n: INTEGER;
  BEGIN
    IF m = 2 THEN IF Leap(y) THEN n := 29 ELSE n := 28 END
    ELSIF (m = 4) OR (m = 6) OR (m = 9) OR (m = 11) THEN n := 30
    ELSE n := 31
    END;
    RETURN n
  END MonthDays;

  PROCEDURE YearDays(y: INTEGER): INTEGER;
    VAR n: INTEGER;
  BEGIN IF Leap(y) THEN n := 366 ELSE n := 365 END;
    RETURN n
  END YearDays;

  (* The leap years 1 .. y *)
  PROCEDURE Leaps(y: INTEGER): INTEGER;
  BEGIN RETURN y DIV 4 - y DIV 100 + y DIV 400
  END Leaps;

  (* Days from 1970-01-01 to y-m-d, y 1970 on *)
  PROCEDURE Days(y, m, d: INTEGER): INTEGER;
    VAR n, i: INTEGER;
  BEGIN n := (y - 1970) * 365 + Leaps(y - 1) - Leaps(1969);
    FOR i := 1 TO m - 1 DO n := n + MonthDays(y, i) END;
    RETURN n + d - 1
  END Days;

  (* --- the registers' forms --- *)

  PROCEDURE Enc(v: INTEGER): INTEGER;   (* as B.DM says *)
  BEGIN IF AND(r[0BH], Dm) = 0 THEN v := v DIV 10 * 16 + v MOD 10 END;
    RETURN v
  END Enc;

  PROCEDURE Dec(b: INTEGER): INTEGER;
  BEGIN IF AND(r[0BH], Dm) = 0 THEN b := b DIV 16 * 10 + b MOD 16 END;
    RETURN b
  END Dec;

  PROCEDURE EncHour(h: INTEGER): INTEGER;
    VAR v: INTEGER;
  BEGIN
    IF AND(r[0BH], H24) # 0 THEN v := Enc(h)
    ELSE v := h MOD 12; IF v = 0 THEN v := 12 END; v := Enc(v); IF h >= 12 THEN v := v + 80H END
    END;
    RETURN v
  END EncHour;

  PROCEDURE DecHour(b: INTEGER): INTEGER;
    VAR h: INTEGER;
  BEGIN
    IF AND(r[0BH], H24) # 0 THEN h := Dec(b)
    ELSE h := Dec(AND(b, 7FH)); IF h = 12 THEN h := 0 END; IF AND(b, 80H) # 0 THEN h := h + 12 END
    END;
    RETURN h
  END DecHour;

  (* The time the registers say, in seconds from 1970 *)
  PROCEDURE Time(): LONGINT;
    VAR y, m, d, c: INTEGER; t: LONGINT;
  BEGIN c := Dec(r[Century]); IF (c < 19) OR (c > 99) THEN c := 20 END;
    y := c * 100 + Dec(r[9]); IF y < 1970 THEN y := 1970 END;
    m := Dec(r[8]); IF (m < 1) OR (m > 12) THEN m := 1 END;
    d := Dec(r[7]);
    t := Days(y, m, d); t := t * 86400 + DecHour(r[4]) * 3600 + Dec(r[2]) * 60 + Dec(r[0]);
    RETURN t
  END Time;

  (* The registers made time t, seconds from 1970 *)
  PROCEDURE PutTime(t: LONGINT);
    VAR days, s, y, m: INTEGER;
  BEGIN days := t DIV 86400; s := t MOD 86400;
    r[6] := Enc((days + 4) MOD 7 + 1);   (* 1970-01-01 a Thursday, Sunday 1 *)
    y := 1970; WHILE days >= YearDays(y) DO days := days - YearDays(y); INC(y) END;
    m := 1; WHILE days >= MonthDays(y, m) DO days := days - MonthDays(y, m); INC(m) END;
    r[Century] := Enc(y DIV 100); r[9] := Enc(y MOD 100); r[8] := Enc(m); r[7] := Enc(days + 1);
    r[4] := EncHour(s DIV 3600); r[2] := Enc(s DIV 60 MOD 60); r[0] := Enc(s MOD 60)
  END PutTime;

  (* --- time --- *)

  PROCEDURE Running(): BOOLEAN;   (* DV = 010 *)
  BEGIN RETURN AND(r[0AH], 70H) = 20H
  END Running;

  PROCEDURE Period(): LONGINT;    (* RS's in cycles, 0 none *)
    VAR rs: INTEGER; p: LONGINT;
  BEGIN rs := AND(r[0AH], 0FH); p := 0;
    IF rs # 0 THEN IF rs < 3 THEN rs := rs + 7 END;
      p := hz; WHILE rs > 1 DO p := p * 2; DEC(rs) END; p := p DIV 32768
    END;
    RETURN p
  END Period;

  PROCEDURE Alarm(k: INTEGER): BOOLEAN;   (* register k matches its alarm, k + 1 *)
  BEGIN RETURN (AND(r[k + 1], 0C0H) = 0C0H) OR (r[k + 1] = r[k])
  END Alarm;

  PROCEDURE Tick*(now: LONGINT);
    VAR p: LONGINT;
  BEGIN
    IF Running() THEN
      WHILE (nextUpdate >= 0) & (now >= nextUpdate) DO
        IF AND(r[0BH], Set) = 0 THEN PutTime(Time() + 1);
          r[0CH] := ORA(r[0CH], Uf);
          IF Alarm(0) & Alarm(2) & Alarm(4) THEN r[0CH] := ORA(r[0CH], Af) END
        END;
        lastUpdate := nextUpdate; nextUpdate := nextUpdate + hz
      END;
      p := Period();
      IF p = 0 THEN nextPeriodic := -1
      ELSE IF nextPeriodic < 0 THEN nextPeriodic := now + p END;
        WHILE now >= nextPeriodic DO r[0CH] := ORA(r[0CH], Pf); nextPeriodic := nextPeriodic + p END
      END
    END
  END Tick;

  (* IRQF, the /IRQ pulled down *)
  PROCEDURE Irq*(): BOOLEAN;
  BEGIN RETURN present & ((AND(r[0CH], Pf) # 0) & (AND(r[0BH], Pie) # 0) OR (AND(r[0CH], Af) # 0) & (AND(r[0BH], Aie) # 0)
    OR (AND(r[0CH], Uf) # 0) & (AND(r[0BH], Uie) # 0))
  END Irq;

  (* --- the file --- *)

  PROCEDURE Save;
    VAR f: Files.File; w: Files.Rider; i: INTEGER; t: LONGINT;
  BEGIN
    IF file # "" THEN f := Files.New(file);
      IF f # NIL THEN Files.Set(w, f, 0);
        FOR i := 0 TO Size - 1 DO Files.WriteByte(w, r[i]) END;
        t := EmHost.UnixTime(); FOR i := 0 TO 7 DO Files.WriteByte(w, t MOD 256); t := t DIV 256 END;
        Files.Register(f); Files.Close(f)
      END
    END
  END Save;

  (* -rtc name: the chip as name has it, or a new module if it is not
     there; kept in it from now on *)
  PROCEDURE Load*(name: ARRAY OF CHAR);
    VAR f: Files.File; rd: Files.Rider; i: INTEGER; b: BYTE; t, u: LONGINT;
  BEGIN present := TRUE; file := name; f := Files.Old(name);
    IF (f # NIL) & (Files.Length(f) >= Size + 8) THEN Files.Set(rd, f, 0);
      FOR i := 0 TO Size - 1 DO Files.ReadByte(rd, b); r[i] := b END;
      t := 0; FOR i := 0 TO 7 DO Files.ReadByte(rd, b); u := b; t := t + ASL(u, 8 * i) END;
      Files.Close(f);
      r[0CH] := 0; r[0DH] := 80H; r[0AH] := AND(r[0AH], 7FH);
      IF Running() & (AND(r[0BH], Set) = 0) & (EmHost.UnixTime() > t) THEN PutTime(Time() + EmHost.UnixTime() - t) END
    ELSE
      FOR i := 0 TO Size - 1 DO r[i] := 0 END; r[0DH] := 80H
    END
  END Load;

  (* s[at .. at+n-1] as a number; ok FALSE if they are not digits *)
  PROCEDURE N(s: ARRAY OF CHAR; at, n: INTEGER; VAR ok: BOOLEAN): INTEGER;
    VAR v, k: INTEGER;
  BEGIN v := 0;
    FOR k := at TO at + n - 1 DO
      IF (s[k] >= "0") & (s[k] <= "9") THEN v := v * 10 + ORD(s[k]) - ORD("0") ELSE ok := FALSE END
    END;
    RETURN v
  END N;

  (* -rtctime YYYYMMDDhhmmss: the chip running, binary, 24-hour, at that
     time (UTC): FALSE if s is not one *)
  PROCEDURE SetTime*(s: ARRAY OF CHAR): BOOLEAN;
    VAR i, y, mo, d, h, mi, se: INTEGER; ok: BOOLEAN; t: LONGINT;

  BEGIN present := TRUE; ok := TRUE; i := 0; WHILE (i < LEN(s)) & (s[i] # 0X) DO INC(i) END;
    IF i # 14 THEN ok := FALSE
    ELSE y := N(s, 0, 4, ok); mo := N(s, 4, 2, ok); d := N(s, 6, 2, ok); h := N(s, 8, 2, ok); mi := N(s, 10, 2, ok); se := N(s, 12, 2, ok);
      ok := ok & (y >= 1970) & (y <= 9999) & (mo >= 1) & (mo <= 12) & (d >= 1) & (d <= MonthDays(y, mo))
        & (h < 24) & (mi < 60) & (se < 60);
      IF ok THEN r[0AH] := 20H; r[0BH] := Dm + H24;
        t := Days(y, mo, d); PutTime(t * 86400 + h * 3600 + mi * 60 + se)
      END
    END;
    RETURN ok
  END SetTime;

  (* -nortc: no chip *)
  PROCEDURE Absent*;
  BEGIN present := FALSE; file := ""
  END Absent;

  (* --- the bus --- *)

  PROCEDURE Read*(a: INTEGER; now: LONGINT): INTEGER;
    VAR v: INTEGER;
  BEGIN Tick(now); v := 0FFH;
    IF ~present THEN
    ELSIF ODD(a) THEN
      IF index = 0AH THEN v := r[0AH];
        IF Running() & (AND(r[0BH], Set) = 0) & ((nextUpdate >= 0) & (now >= nextUpdate - hz DIV 4096)
            OR (lastUpdate >= 0) & (now < lastUpdate + hz DIV 500)) THEN v := v + Uip
        END
      ELSIF index = 0CH THEN v := r[0CH]; IF Irq() THEN v := v + Irqf END; r[0CH] := 0
      ELSIF index = 0DH THEN v := 80H
      ELSE v := r[index]
      END
    END;
    RETURN v
  END Read;

  PROCEDURE Write*(a, v: INTEGER; now: LONGINT);
    VAR was: BOOLEAN;
  BEGIN Tick(now); v := AND(v, 0FFH);
    IF ~present THEN
    ELSIF ~ODD(a) THEN index := AND(v, 7FH)
    ELSIF index = 0AH THEN was := Running(); r[0AH] := AND(v, 7FH);
      IF Running() & ~was THEN nextUpdate := now + hz DIV 2; lastUpdate := -1 END;   (* the first update in 500 ms *)
      IF ~Running() THEN nextUpdate := -1 END;
      nextPeriodic := -1; Save
    ELSIF (index = 0CH) OR (index = 0DH) THEN   (* read only *)
    ELSE r[index] := v; Save
    END
  END Write;

  (* /RES: the interrupts' enables and the flags cleared; the time and
     the RAM kept *)
  PROCEDURE Reset*;
  BEGIN hz := EmHost.hz; index := 0;
    r[0BH] := AND(r[0BH], 0FFH - Pie - Aie - Uie - Sqwe); r[0CH] := 0;
    IF Running() THEN nextUpdate := hz ELSE nextUpdate := -1 END;
    lastUpdate := -1; nextPeriodic := -1
  END Reset;

  PROCEDURE Init;
    VAR i: INTEGER;
  BEGIN file := ""; present := TRUE; hz := EmHost.hz; FOR i := 0 TO Size - 1 DO r[i] := 0 END;
    r[0AH] := 20H; r[0BH] := Dm + H24; r[0DH] := 80H;
    PutTime(EmHost.UnixTime())
  END Init;

BEGIN Init
END EmRTC.
