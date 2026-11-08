MODULE EmSDRAM; (* The SoC's 8 MB of SDRAM, the cache in front of it, and
   the controller's sharing of it with the display and refresh.

   The memory is $00_0000-$7F_FFFF; the framebuffer at $70_0000 is part
   of it and lives in EmVideo, for the display. Peek and Poke reach it
   without taking time; the CPU's accesses go through ReadCost, FetchCost
   and WriteCost, which give the cycles the cache takes, as its state
   machine (rtl/cache.v) and the controller's (rtl/sdram_burst.v) do.

   The cache is direct mapped, 256 lines of 16 bytes, write-through
   without allocation, and holds the last word a data read read: a read
   in the held word takes 1 cycle; a hit 2 (look up, check); a miss waits
   until the write buffer is empty and the port free, asks the controller
   for the line (a burst of four words), and answers 3 cycles after the
   burst: 16 cycles with the port free and the row open. A fill of the
   CPU's instruction queue (FetchCost) is a read that leaves the held word
   alone. A store goes into a write buffer of 4 words, merging into the
   newest if it is the same word and not yet on its way, in 2 cycles; into
   a full buffer it waits for the oldest to leave, 4 or more. The buffer
   drains a word at a time whenever the port is free, a write transaction
   each (8 cycles from one to the next with the row open). BufferEmpty
   says when the last store has gone (wr_busy falls): the blitter and the
   DMA engine start no earlier.

   The controller serves, whenever it is idle, a refresh that is due,
   then the display, then the cache. The display reads each of the 768
   lines shown at the start of the line before (1344 pixels at 64.8 MHz:
   840 cycles at 40.5 MHz) in bursts of four words, 32 a line in graphics
   and 16 in text (latched at the frame's first line, as rtl/video.v
   does), and after each burst drops its request for a cycle, so that a
   waiting access of the cache goes in between. A burst is 10 cycles, a
   write 7, with the row open; 2 more when the bank has no row open
   (after a refresh) and 3 when it has another. A refresh is due every
   FREQ / 133 kHz + 1 cycles and takes 6, closing every row. The core
   starts once the controller has initialised (FREQ / 5000 + 36 cycles
   after reset), by when the display's and the refresh's counters have
   been running; their phases follow from that, as measured in tb_soc
   (the line pulse 2 cycles after its pixel, at 40.5 MHz). The bursts of
   other masters (the blitter's, the DMA engine's) on the controller's
   port 2, which outrank the cache's, are not modelled.

   Writes by the blitter drop the lines they touch, as there. *)

  IMPORT EmHost, EmVideo;

  CONST
    size* = 800000H;
    lines = 806; shown = 768;
    burstLen = 10; writeLen = 7; refreshBusy = 6;

  VAR
    ram: ARRAY size OF BYTE;
    tags: ARRAY 256 OF INTEGER;     (* line DIV 256 + 1 of each line, 0: empty *)
    held: INTEGER;                  (* word (address DIV 4) of the held word, -1: none *)
    nodisplay: BOOLEAN;             (* the display fetches nothing: NoDisplay *)
    (* the write buffer: its words, oldest first from wbHead, and the cycle each leaves for the port *)
    wbWord: ARRAY 4 OF INTEGER;
    wbDrain: ARRAY 4 OF LONGINT;
    wbHead, wbN: INTEGER;
    portFree: LONGINT;              (* the first cycle the cache's port is free (m_busy low) *)
    writeFree: LONGINT;             (* ... after its last write *)
    (* the controller *)
    cfree: LONGINT;                 (* the cycle it is next idle, nothing granted from then on *)
    openRow: ARRAY 4 OF INTEGER;    (* the row open in each bank, -1 none *)
    refPeriod, refPhase: INTEGER;
    nextRef: LONGINT;               (* a refresh due from this cycle on *)
    (* the display: a line pulse each 1344 pixels, lineQ + lineR / 64.8 MHz cycles *)
    t0, lineQ, lineR: LONGINT;      (* the cycle the core starts, from reset *)
    vline: LONGINT;                 (* the next line pulse's number, from reset *)
    vpulse: LONGINT;                (* ... its cycle *)
    vnext: LONGINT;                 (* ... when its fetch asks, -1 for a line with none *)
    vleft: INTEGER;                 (* bursts left of the line being fetched *)
    vreq: LONGINT;                  (* when it next asks *)
    vaddr: INTEGER;                 (* the word its next burst reads *)
    vtext: BOOLEAN;                 (* the frame's text mode *)

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

  (* The display fetches nothing, for comparing with an RTL simulation
     built without one (soc.v's USE_VIDEO = 0) *)
  PROCEDURE NoDisplay*;
  BEGIN nodisplay := TRUE
  END NoDisplay;

  (* --- the controller --- *)

  (* The extra cycles of a transaction on word w: none with its row open,
     2 if the bank has none, 3 if another; w's row is open after it. *)
  PROCEDURE Row(w: INTEGER): INTEGER;
    VAR bank, row, r: INTEGER;
  BEGIN bank := w DIV 256 MOD 4; row := w DIV 1024;
    IF openRow[bank] = row THEN r := 0 ELSIF openRow[bank] < 0 THEN r := 2 ELSE r := 3 END;
    openRow[bank] := row;
    RETURN r
  END Row;

  (* The cycle (from the core's start) of line pulse n, counted from reset *)
  PROCEDURE Pulse(n: LONGINT): LONGINT;
  BEGIN RETURN n * lineQ + n * lineR DIV 64800000 + 2 - t0
  END Pulse;

  (* When the fetch of line pulse vline asks: the frame's first line at
     the last line of the frame before, each line shown after it at the
     line before it; -1 for the pulses with no fetch. *)
  PROCEDURE NextPulse;
    VAR y: INTEGER;
  BEGIN y := vline MOD lines; vpulse := Pulse(vline);
    IF nodisplay OR (y >= shown - 1) & (y # lines - 1) THEN vnext := -1 ELSE vnext := vpulse + 1 END
  END NextPulse;

  (* The fetch of line pulse vline starts *)
  PROCEDURE StartLine;
    VAR y, line: INTEGER;
  BEGIN y := vline MOD lines;
    IF y = lines - 1 THEN line := 0; vtext := EmVideo.text # 0 ELSE line := y + 1 END;
    IF vtext THEN vleft := 16; vaddr := (EmVideo.base + line DIV 16 * EmVideo.textBpr) DIV 4
    ELSE vleft := 32; vaddr := (EmVideo.base + line * EmVideo.bpr) DIV 4
    END;
    vreq := vnext
  END StartLine;

  (* The display's line pulses up to cycle c *)
  PROCEDURE Lines(c: LONGINT);
  BEGIN
    WHILE vpulse <= c DO
      IF vnext >= 0 THEN StartLine END;
      INC(vline); NextPulse
    END
  END Lines;

  (* The cycle the controller grants the cache a transaction it asks for
     from cycle r: once idle, with no refresh due and the display not
     asking; the refreshes and the display's bursts before it, done. *)
  PROCEDURE Grant(r: LONGINT): LONGINT;
    VAR c, e, v: LONGINT; done: BOOLEAN;
  BEGIN done := FALSE;
    REPEAT c := cfree; Lines(c);
      IF c < r THEN
        IF vleft > 0 THEN v := vreq ELSE v := vnext END;
        e := r;
        IF nextRef < e THEN e := nextRef END;
        IF (v >= 0) & (v < e) THEN e := v END;
        IF e > c THEN c := e; Lines(c) END
      END;
      IF nextRef <= c THEN                          (* refresh *)
        cfree := c + refreshBusy; nextRef := nextRef + refPeriod;
        openRow[0] := -1; openRow[1] := -1; openRow[2] := -1; openRow[3] := -1
      ELSIF (vleft > 0) & (vreq <= c) THEN          (* the display's burst *)
        cfree := c + burstLen + Row(vaddr); vreq := cfree + 1; vaddr := vaddr + 4; DEC(vleft)
      ELSIF r <= c THEN done := TRUE
      ELSE cfree := c                               (* idle until the next event *)
      END
    UNTIL done;
    RETURN c
  END Grant;

  (* The cache's transaction on word w, asked for from cycle r: the cycle
     after it, the port free again. *)
  PROCEDURE Transact(w: INTEGER; r: LONGINT; wr: BOOLEAN): LONGINT;
    VAR g: LONGINT;
  BEGIN g := Grant(r);
    IF wr THEN cfree := g + writeLen + Row(w) ELSE cfree := g + burstLen + Row(w) END;
    RETURN cfree
  END Transact;

  (* --- the cache --- *)

  (* A read by the CPU starting at cycle now: its cycles. *)
  PROCEDURE Read(a: INTEGER; now: LONGINT; ifetch: BOOLEAN): INTEGER;
    VAR word, line, idx, r: INTEGER; w, e: LONGINT;
  BEGIN word := a DIV 4;
    IF word = held THEN r := 1
    ELSE line := a DIV 16; idx := line MOD 256;
      IF tags[idx] = line DIV 256 + 1 THEN r := 2
      ELSE (* S_WAIT from now + 2, until the buffer is empty and the port free; the request the cycle after *)
        w := now + 2; IF portFree > w THEN w := portFree END;
        e := Transact(line * 4, w + 1, FALSE); portFree := e;
        r := e + 3 - now;                           (* fill done, serve, ack *)
        tags[idx] := line DIV 256 + 1;
        IF (held >= 0) & (held DIV 4 MOD 256 = idx) THEN held := -1 END
      END;
      IF ~ifetch THEN held := word END
    END;
    RETURN r
  END Read;

  PROCEDURE ReadCost*(a: INTEGER; now: LONGINT): INTEGER;
  BEGIN RETURN Read(a, now, FALSE)
  END ReadCost;

  (* A fill of the CPU's instruction queue: a read that leaves the held word *)
  PROCEDURE FetchCost*(a: INTEGER; now: LONGINT): INTEGER;
  BEGIN RETURN Read(a, now, TRUE)
  END FetchCost;

  (* Forget the buffer's words that have left by cycle c *)
  PROCEDURE Buffered(c: LONGINT);
  BEGIN
    WHILE (wbN > 0) & (wbDrain[wbHead] < c) DO wbHead := (wbHead + 1) MOD 4; DEC(wbN) END
  END Buffered;

  (* Word w into the buffer, there from cycle c: it leaves once the port is free. *)
  PROCEDURE Push(w: INTEGER; c: LONGINT);
    VAR i: INTEGER; d: LONGINT;
  BEGIN i := (wbHead + wbN) MOD 4; INC(wbN);
    d := c; IF portFree > d THEN d := portFree END;
    wbWord[i] := w; wbDrain[i] := d;
    portFree := Transact(w, d + 1, TRUE); writeFree := portFree
  END Push;

  (* A store by the CPU starting at cycle now: its cycles. *)
  PROCEDURE WriteCost*(a: INTEGER; now: LONGINT): INTEGER;
    VAR word, last, r: INTEGER; c, w: LONGINT;
  BEGIN word := a DIV 4; c := now + 1;               (* S_CHECK *)
    IF word = held THEN held := -1 END;
    Buffered(c); last := (wbHead + wbN - 1) MOD 4;
    IF (wbN > 0) & (wbWord[last] = word) & (wbDrain[last] > c) THEN r := 2     (* merged *)
    ELSIF wbN < 4 THEN Push(word, c + 1); r := 2
    ELSE (* full: S_WAIT until the oldest has left; the ack a cycle later *)
      IF wbWord[last] = word THEN w := c + 1
      ELSE w := wbDrain[wbHead] + 1; IF w < c + 1 THEN w := c + 1 END;
        Buffered(w); Push(word, w + 1)
      END;
      r := w + 2 - now
    END;
    RETURN r
  END WriteCost;

  (* The cycle from which the CPU's last store has left the buffer *)
  PROCEDURE BufferEmpty*(): LONGINT;
  BEGIN RETURN writeFree
  END BufferEmpty;

  (* Another master has written the byte at a. *)
  PROCEDURE Invalidate*(a: INTEGER);
    VAR line: INTEGER;
  BEGIN line := a DIV 16;
    IF tags[line MOD 256] = line DIV 256 + 1 THEN tags[line MOD 256] := 0 END;
    IF a DIV 4 = held THEN held := -1 END
  END Invalidate;

  PROCEDURE Reset*;
    VAR i: INTEGER; hz: LONGINT;
  BEGIN FOR i := 0 TO 255 DO tags[i] := 0 END; held := -1;
    wbHead := 0; wbN := 0; portFree := 0; writeFree := 0;
    FOR i := 0 TO 3 DO openRow[i] := -1 END;
    hz := EmHost.hz; IF hz < 1000000 THEN hz := 25200000 END; t0 := hz DIV 5000 + 36;
    lineQ := 1344 * hz DIV 64800000; lineR := 1344 * hz MOD 64800000;
    refPeriod := hz DIV 133000 + 1; refPhase := refPeriod - t0 MOD refPeriod;
    (* the controller comes out of its initialisation 2 cycles after the
       core's start, with a refresh due *)
    cfree := 2; nextRef := refPhase - refPeriod;
    (* the display: the line pulse before the core's start asked for its
       line, which nothing has served *)
    vline := 0; WHILE Pulse(vline + 1) <= 0 DO INC(vline) END;
    vtext := FALSE; vleft := 0; NextPulse;
    IF vnext >= 0 THEN StartLine; vreq := 0 END;
    INC(vline); NextPulse
  END Reset;

BEGIN nodisplay := FALSE; Reset
END EmSDRAM.
