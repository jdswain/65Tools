MODULE TestGraphics;
  IMPORT UIGraphics, Out;
VAR c: INTEGER;
BEGIN
  (* Test 1: FillRect aligned to byte boundaries *)
  (* x=4, w=8 => left_col=2, right_col=5, all full bytes *)
  UIGraphics.FillRect(4, 10, 8, 2, 15);
  c := UIGraphics.GetPixel(4, 10);
  Out.Int(c, 0); Out.Ln;
  c := UIGraphics.GetPixel(7, 10);
  Out.Int(c, 0); Out.Ln;
  c := UIGraphics.GetPixel(8, 11);
  Out.Int(c, 0); Out.Ln;
  c := UIGraphics.GetPixel(11, 11);
  Out.Int(c, 0); Out.Ln;
  (* Outside should be 0 *)
  c := UIGraphics.GetPixel(3, 10);
  Out.Int(c, 0); Out.Ln;
  c := UIGraphics.GetPixel(12, 10);
  Out.Int(c, 0); Out.Ln;

  (* Test 2: FillRect with partial left and right edges *)
  (* x=1, w=5 => pixels 1..5, left_col=0 pos=1, right_col=2 pos=1 *)
  UIGraphics.FillRect(1, 20, 5, 1, 7);
  c := UIGraphics.GetPixel(1, 20);
  Out.Int(c, 0); Out.Ln;
  c := UIGraphics.GetPixel(3, 20);
  Out.Int(c, 0); Out.Ln;
  c := UIGraphics.GetPixel(5, 20);
  Out.Int(c, 0); Out.Ln;
  (* Pixel 0 should be untouched *)
  c := UIGraphics.GetPixel(0, 20);
  Out.Int(c, 0); Out.Ln;
  (* Pixel 6 should be untouched *)
  c := UIGraphics.GetPixel(6, 20);
  Out.Int(c, 0); Out.Ln;

  (* Test 3: Single-pixel FillRect (same byte, single pixel) *)
  UIGraphics.FillRect(5, 30, 1, 1, 8);
  c := UIGraphics.GetPixel(5, 30);
  Out.Int(c, 0); Out.Ln;
  c := UIGraphics.GetPixel(4, 30);
  Out.Int(c, 0); Out.Ln;
  c := UIGraphics.GetPixel(6, 30);
  Out.Int(c, 0); Out.Ln;

  (* Test 4: FillRect within single byte *)
  (* x=1, w=2 => pixels 1..2, left_col=0 pos=1, right_col=1 pos=0 *)
  UIGraphics.FillRect(1, 40, 2, 1, 15);
  c := UIGraphics.GetPixel(0, 40);
  Out.Int(c, 0); Out.Ln;
  c := UIGraphics.GetPixel(1, 40);
  Out.Int(c, 0); Out.Ln;
  c := UIGraphics.GetPixel(2, 40);
  Out.Int(c, 0); Out.Ln;
  c := UIGraphics.GetPixel(3, 40);
  Out.Int(c, 0); Out.Ln;

  Out.Int(99, 0); Out.Ln
END TestGraphics.
