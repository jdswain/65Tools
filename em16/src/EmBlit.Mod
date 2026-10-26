MODULE EmBlit; (* The SoC's blitter, rtl/blitter.v: copies or fills a
   rectangle of 4 bit pixels, combining source and destination through a
   logic operation, optionally leaving one source colour out.

   Registers (CONTROL, PAT_Y and PATTERN read back, the rest read $FF):

     $00-$02 SRC   source pixel address      $0C-$0D WIDTH  1..2047
     $04-$06 DST   destination pixel address $0E-$0F HEIGHT
     $08-$09 SRC_STRIDE, signed              $10 OP     low 4 bits
     $0A-$0B DST_STRIDE, signed              $11 COLOUR fill, transparent<<4
     $12 CONTROL   write: bit 0 start, 1 fill, 2 transparent, 3 pattern
                   read: bit 7 busy, bits 3-1 as written
     $13 PAT_Y     bits 2-0: the pattern row for the first line
     $20-$3F PATTERN  8 x 8 pixels, row r in bytes 4r..4r+3, the even pixel
                   of a byte in its low nibble

   With pattern set (it wins over fill) the source pixel is the pattern's,
   its column the destination pixel address MOD 8, its row PAT_Y for the
   first line and one more, MOD 8, for each line after; on the screen that
   is x MOD 8, and PAT_Y = top MOD 8 aligns it to y.

   A pixel address is twice the byte address, plus one for the high
   nibble. Each line is read whole before it is written, as the test
   bench's reference model (sim/tb_blitter.v) defines it; that model is
   what this does. OP bit n gives the result for source and destination
   bits: n = 2 * (1 - s) + (1 - d).

   It stays busy as long as on the board: a model fitted to the test
   bench's 409 timed blits (median error 6%) from the bursts and words
   each line reads and writes. The pixels change when it finishes. *)

  IMPORT EmSDRAM;

  VAR
    src, dst, srcStride, dstStride, width, height, op, colour: INTEGER;
    paty: INTEGER;
    fill, trans, patt, busy: BOOLEAN;
    pat: ARRAY 32 OF BYTE;
    endTime: LONGINT;
    line: ARRAY 2048 OF INTEGER;

  PROCEDURE GetPixel(p: INTEGER): INTEGER;
    VAR b, r: INTEGER;
  BEGIN p := AND(p, 0FFFFFFH); b := EmSDRAM.Peek(p DIV 2);
    IF ODD(p) THEN r := b DIV 16 ELSE r := b MOD 16 END;
    RETURN r
  END GetPixel;

  PROCEDURE SetPixel(p, v: INTEGER);
    VAR a, b: INTEGER;
  BEGIN p := AND(p, 0FFFFFFH); a := p DIV 2; b := EmSDRAM.Peek(a);
    IF ODD(p) THEN b := b MOD 16 + v * 16 ELSE b := AND(b, 0F0H) + v END;
    EmSDRAM.Poke(a, b); EmSDRAM.Invalidate(a)
  END SetPixel;

  PROCEDURE Rop(s, d: INTEGER): INTEGER;
    VAR r, b, sb, db: INTEGER;
  BEGIN r := 0;
    FOR b := 0 TO 3 DO
      sb := LSR(s, b) MOD 2; db := LSR(d, b) MOD 2;
      r := r + (LSR(op, (1 - sb) * 2 + (1 - db)) MOD 2) * ASL(1, b)
    END;
    RETURN r
  END Rop;

  PROCEDURE Signed16(v: INTEGER): INTEGER;
  BEGIN IF v >= 8000H THEN v := v - 10000H END; RETURN v
  END Signed16;

  PROCEDURE Ceil(a, b: INTEGER): INTEGER;
  BEGIN RETURN (a + b - 1) DIV b
  END Ceil;

  (* The cycles the blit takes on the board. *)
  PROCEDURE Cost(): LONGINT;
    VAR y, s, d, c: INTEGER; t: LONGINT;
  BEGIN t := 25;
    FOR y := 0 TO height - 1 DO
      s := AND(src + y * Signed16(srcStride), 0FFFFFFH); d := AND(dst + y * Signed16(dstStride), 0FFFFFFH);
      c := 43 * Ceil(AND(d, 31) + width, 32) + 14 * Ceil(AND(d, 7) + width, 8) - 21;
      IF ~fill & ~patt THEN c := c + 19 * Ceil(AND(s, 31) + width, 32) END;
      IF c < 1 THEN c := 1 END;
      t := t + c
    END;
    RETURN t
  END Cost;

  PROCEDURE Blit;
    VAR x, y, s, d, k, p: INTEGER;
  BEGIN
    FOR y := 0 TO height - 1 DO
      s := src + y * Signed16(srcStride); d := dst + y * Signed16(dstStride);
      FOR x := 0 TO width - 1 DO
        IF patt THEN p := pat[(paty + y) MOD 8 * 4 + AND(d + x, 7) DIV 2];
          IF ODD(d + x) THEN line[x] := p DIV 16 ELSE line[x] := p MOD 16 END
        ELSIF fill THEN line[x] := colour MOD 16
        ELSE line[x] := GetPixel(s + x)
        END
      END;
      k := colour DIV 16;
      FOR x := 0 TO width - 1 DO p := line[x];
        IF ~trans OR (p # k) THEN SetPixel(d + x, Rop(p, GetPixel(d + x))) END
      END
    END
  END Blit;

  PROCEDURE Tick*(now: LONGINT);
  BEGIN IF busy & (now >= endTime) THEN Blit; busy := FALSE END
  END Tick;

  PROCEDURE Busy*(): BOOLEAN;
  BEGIN RETURN busy
  END Busy;

  PROCEDURE Byte(VAR r: INTEGER; n, v: INTEGER);    (* byte n of register r *)
    VAR m: INTEGER;
  BEGIN m := ASL(0FFH, 8 * n); r := ORA(AND(r, -1 - m), ASL(v, 8 * n))
  END Byte;

  PROCEDURE Read*(reg: INTEGER; now: LONGINT): INTEGER;
    VAR r: INTEGER;
  BEGIN Tick(now); reg := AND(reg, 3FH);
    IF reg = 12H THEN r := 0;
      IF busy THEN r := 80H END; IF patt THEN r := r + 8 END;
      IF trans THEN r := r + 4 END; IF fill THEN r := r + 2 END
    ELSIF reg = 13H THEN r := paty
    ELSIF reg >= 20H THEN r := pat[reg - 20H]
    ELSE r := 0FFH
    END;
    RETURN r
  END Read;

  PROCEDURE Write*(reg, v: INTEGER; now: LONGINT);
  BEGIN Tick(now); reg := AND(reg, 3FH);
    IF ~busy & (reg >= 20H) THEN pat[reg - 20H] := v
    ELSIF ~busy THEN
      CASE reg OF
        0, 1, 2: Byte(src, reg, v)
      | 4, 5, 6: Byte(dst, reg - 4, v)
      | 8, 9: Byte(srcStride, reg - 8, v)
      | 0AH, 0BH: Byte(dstStride, reg - 0AH, v)
      | 0CH: Byte(width, 0, v)
      | 0DH: Byte(width, 1, AND(v, 7))
      | 0EH, 0FH: Byte(height, reg - 0EH, v)
      | 10H: op := v
      | 11H: colour := v
      | 13H: paty := AND(v, 7)
      | 12H:
          fill := ODD(v DIV 2); trans := ODD(v DIV 4); patt := ODD(v DIV 8);
          IF ODD(v) & (width # 0) & (height # 0) THEN busy := TRUE; endTime := now + Cost() END
      ELSE
      END
    END
  END Write;

  PROCEDURE Reset*;
  BEGIN src := 0; dst := 0; srcStride := 0; dstStride := 0; width := 0; height := 0;
    op := 3; colour := 0; paty := 0; fill := FALSE; trans := FALSE; patt := FALSE; busy := FALSE
  END Reset;

BEGIN Reset
END EmBlit.
