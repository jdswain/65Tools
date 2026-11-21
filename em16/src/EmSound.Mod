MODULE EmSound; (* The Mini816's speaker: PB7 drives it through a
   transistor, and CB2 (a header, the shift register's) may be a second
   voice. Each voice is a level, 1 or 0, from a time on (Set); a sample,
   48000 a second, is their sum averaged over its time, through a high
   pass (about 30 Hz) as the speaker passes it, so that a level held is
   silent. The samples go to the host's sound (EmHost.SoundStart, live)
   or to a WAV file (Record), in the board's time: Advance brings them up
   to it. Times are in the CPU's clocks, hz a second. *)

  IMPORT EmHost, Files;

  CONST
    rate* = 48000;
    amp = 12000;                          (* a voice's swing *)

  VAR
    on*: BOOLEAN;                         (* samples wanted: live or recorded *)
    live*: BOOLEAN;                       (* to the host's sound *)
    hz, at: LONGINT;                      (* the CPU's clock; the time sampled to *)
    part, sum: LONGINT;                   (* the current sample's time passed and its levels' integral, in clocks x rate *)
    level: ARRAY 2 OF INTEGER;
    voices: INTEGER;                      (* 1, or 2 with CB2 *)
    x1, y1: INTEGER;                      (* the high pass's last input, and output x 256 *)
    wav: Files.File; r: Files.Rider; count: LONGINT;

  PROCEDURE Word(v: LONGINT; n: INTEGER);       (* n bytes, little-endian *)
  BEGIN WHILE n > 0 DO Files.WriteByte(r, v MOD 100H); v := v DIV 100H; DEC(n) END
  END Word;

  PROCEDURE Tag(s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN FOR i := 0 TO 3 DO Files.WriteByte(r, ORD(s[i])) END
  END Tag;

  (* a WAV file's head, 16-bit mono, with n samples *)
  PROCEDURE Head(n: LONGINT);
  BEGIN Files.Set(r, wav, 0);
    Tag("RIFF"); Word(36 + n * 2, 4); Tag("WAVE"); Tag("fmt "); Word(16, 4);
    Word(1, 2); Word(1, 2); Word(rate, 4); Word(rate * 2, 4); Word(2, 2); Word(16, 2);
    Tag("data"); Word(n * 2, 4)
  END Head;

  (* a sample: s / hz the levels' mean *)
  PROCEDURE Emit(s: LONGINT);
    VAR x, y: INTEGER;
  BEGIN x := s * amp DIV hz;
    y1 := (x - x1) * 256 + y1 - y1 DIV 256; x1 := x; y := (y1 + 128) DIV 256;
    IF y > 32767 THEN y := 32767 ELSIF y < -32768 THEN y := -32768 END;
    IF live THEN EmHost.SoundPut(y) END;
    IF wav # NIL THEN Word(AND(y, 0FFFFH), 2); INC(count) END
  END Emit;

  (* the samples up to t *)
  PROCEDURE Advance*(t: LONGINT);
    VAR d, k: LONGINT; v: INTEGER;
  BEGIN
    IF t > at THEN d := (t - at) * rate; at := t; v := level[0] + level[1];
      WHILE part + d >= hz DO k := hz - part;
        Emit(sum + v * k);
        d := d - k; part := 0; sum := 0
      END;
      part := part + d; sum := sum + v * d
    END
  END Advance;

  (* voice n (0 PB7, 1 CB2) at level v from t *)
  PROCEDURE Set*(n, v: INTEGER; t: LONGINT);
  BEGIN
    IF on & (n < voices) & (v # level[n]) THEN Advance(t); level[n] := v END
  END Set;

  (* the clock, CB2 a voice too (cb2), the host's sound (play) *)
  PROCEDURE Start*(clock: LONGINT; cb2, play: BOOLEAN);
  BEGIN hz := clock;
    IF cb2 THEN voices := 2 ELSE voices := 1; level[1] := 0 END;
    x1 := (level[0] + level[1]) * amp;                (* at rest: no click *)
    IF play THEN live := EmHost.SoundStart(rate) # 0 END;
    on := live OR (wav # NIL)
  END Start;

  (* the samples to the WAV file name too; FALSE if it cannot be made *)
  PROCEDURE Record*(name: ARRAY OF CHAR): BOOLEAN;
  BEGIN wav := Files.New(name);
    IF wav # NIL THEN count := 0; Head(0) END;
    RETURN wav # NIL
  END Record;

  (* the WAV file finished: its sizes, then registered *)
  PROCEDURE Finish*;
  BEGIN
    IF wav # NIL THEN Head(count); Files.Register(wav); wav := NIL END
  END Finish;

BEGIN on := FALSE; live := FALSE; wav := NIL; hz := 7372800; at := 0; part := 0; sum := 0;
  level[0] := 1; level[1] := 1; voices := 1; x1 := 0; y1 := 0
END EmSound.
