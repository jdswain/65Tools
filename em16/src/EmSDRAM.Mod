MODULE EmSDRAM; (* The SoC's 8 MB of SDRAM and the cache in front of it.

   The memory is $00_0000-$7F_FFFF; the framebuffer at $70_0000 is part
   of it and lives in EmVideo, for the display. Peek and Poke reach it
   without taking time; the CPU's accesses go through ReadCost and
   WriteCost, which give the cycles the cache would take.

   The cache (rtl/cache.v) is direct mapped, 256 lines of 16 bytes,
   write-through without allocation, and holds the last word read. Its
   time here follows its state machine, as traced in the RTL simulation:
   a byte of the held word takes 1 cycle; any other access 3 (look up,
   check, acknowledge). A store is posted, and the write port is then
   busy for 10 cycles; a store or a miss arriving meanwhile waits for it.
   A miss fills its line from the port in 15 cycles more, 18 in all.

   The SDRAM controller (rtl/sdram_burst.v) serves the display first. It
   reads each of the 768 lines shown, at the start of the line before
   (1344 pixels at 64.8 MHz, 523 of these cycles), in bursts that hold
   the port for about 137 cycles (69 in text mode, which reads half as
   much): the share of a line that 640 x 480's took, 210 of 800, as the
   SoC leaves the CPU a slot between its bursts and is little slower at
   1024 x 768 (in simulation, by some 2%); and it refreshes every 190
   cycles, for 6. A fill or a store waits for these; a store is still
   acknowledged at once, but the next waits for it to finish. Which rows
   are open, which would add a cycle or two, is not modelled.

   Writes by the blitter drop the lines they touch, as there. *)

  IMPORT EmVideo;

  CONST
    size* = 800000H;
    hitHeld = 1; hit = 3; fill = 15; portBusy = 10;
    lineTime = 523; lines = 806; shown = 768; fetchGraphics = 137; fetchText = 69;
    refreshTime = 190; refreshBusy = 6;
    (* On the board the core starts once the SDRAM is initialised, 5088
       cycles after reset, by when the display and refresh have been
       running: the frame began 5073 cycles before the core's time 0,
       and a refresh is due at 54 + 190k. *)
    framePhase = 5073; refreshPhase = 54;

  VAR
    ram: ARRAY size OF BYTE;
    tags: ARRAY 256 OF INTEGER;     (* line DIV 256 + 1 of each line, 0: empty *)
    held: INTEGER;                  (* word (address DIV 4) of the held word, -1: none *)
    portFree: LONGINT;              (* the first cycle the SDRAM port is free *)

  PROCEDURE Peek*(a: INTEGER): INTEGER;
    VAR r: INTEGER;
  BEGIN
    IF (a >= EmVideo.base) & (a < EmVideo.base + EmVideo.size) THEN r := EmVideo.mem[a - EmVideo.base]
    ELSIF (a >= 0) & (a < size) THEN r := ram[a]
    ELSE r := 0FFH
    END;
    RETURN r
  END Peek;

  PROCEDURE Poke*(a, v: INTEGER);
  BEGIN
    IF (a >= EmVideo.base) & (a < EmVideo.base + EmVideo.size) THEN EmVideo.SetByte(a - EmVideo.base, v)
    ELSIF (a >= 0) & (a < size) THEN ram[a] := v
    END
  END Poke;

  (* The first cycle from t on that the display and refresh leave the
     port to the CPU. *)
  PROCEDURE Free(t: LONGINT): LONGINT;
    VAR s, off, len: LONGINT; again: BOOLEAN;
  BEGIN
    IF EmVideo.text # 0 THEN len := fetchText ELSE len := fetchGraphics END;
    REPEAT again := FALSE;
      s := (t + framePhase) MOD (lineTime * lines); off := s MOD lineTime;
      IF (s DIV lineTime < shown) & (off < len) THEN t := t + len - off; again := TRUE END;
      off := (t - refreshPhase) MOD refreshTime;
      IF off < refreshBusy THEN t := t + refreshBusy - off; again := TRUE END
    UNTIL ~again;
    RETURN t
  END Free;

  (* The cycles of a read by the CPU starting at cycle now. *)
  PROCEDURE ReadCost*(a: INTEGER; now: LONGINT): INTEGER;
    VAR word, line, idx, r: INTEGER; c, issue: LONGINT;
  BEGIN word := a DIV 4;
    IF word = held THEN c := hitHeld
    ELSE line := a DIV 16; idx := line MOD 256;
      IF tags[idx] = line DIV 256 + 1 THEN c := hit
      ELSE issue := now + 2;                          (* once the last store is done *)
        IF portFree > issue THEN issue := portFree END;
        c := Free(issue) + fill - now + 1;
        tags[idx] := line DIV 256 + 1
      END;
      held := word
    END;
    r := c; RETURN r
  END ReadCost;

  (* A store is posted once the cache has finished the last one: the
     cycles of a hit, or more if it has not. *)
  PROCEDURE WriteCost*(a: INTEGER; now: LONGINT): INTEGER;
    VAR r: INTEGER; issue: LONGINT;
  BEGIN issue := now + 1;
    IF portFree > issue THEN issue := portFree END;
    portFree := Free(issue + 1) + portBusy;
    IF a DIV 4 = held THEN held := -1 END;
    r := issue + 2 - now; RETURN r
  END WriteCost;

  (* Another master has written the byte at a. *)
  PROCEDURE Invalidate*(a: INTEGER);
    VAR line: INTEGER;
  BEGIN line := a DIV 16;
    IF tags[line MOD 256] = line DIV 256 + 1 THEN tags[line MOD 256] := 0 END;
    IF a DIV 4 = held THEN held := -1 END
  END Invalidate;

  PROCEDURE Reset*;
    VAR i: INTEGER;
  BEGIN FOR i := 0 TO 255 DO tags[i] := 0 END; held := -1; portFree := 0
  END Reset;

BEGIN Reset
END EmSDRAM.
