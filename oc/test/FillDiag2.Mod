MODULE FillDiag2;
  IMPORT SYSTEM, Graphics, Out;
VAR w, bank, addr: INTEGER;
BEGIN
  Graphics.FillRect(0, 0, 640, 480, 1);

  (* Row 409: flat offset 65440=$FFA0 in bank 2, wraps after 96 bytes *)

  (* Bank 2, addr $FFA0 = row 409 byte 0 *)
  bank := 2; addr := -96;
  SYSTEM.GET(bank, addr, w);
  Out.String("B2 FFA0: "); Out.Int(w, 0); Out.Ln;

  (* Bank 2, addr $FFFF = row 409 byte 95 *)
  addr := -1;
  SYSTEM.GET(bank, addr, w);
  Out.String("B2 FFFF: "); Out.Int(w, 0); Out.Ln;

  (* Bank 3, addr $0000 = row 409 byte 96 (SHOULD be $55, may be 0) *)
  bank := 3; addr := 0;
  SYSTEM.GET(bank, addr, w);
  Out.String("B3 0000: "); Out.Int(w, 0); Out.Ln;

  (* Bank 3, addr $003F = row 409 byte 159 *)
  addr := 63;
  SYSTEM.GET(bank, addr, w);
  Out.String("B3 003F: "); Out.Int(w, 0); Out.Ln;

  (* Bank 3, addr $0040 = row 410 byte 0 *)
  addr := 64;
  SYSTEM.GET(bank, addr, w);
  Out.String("B3 0040: "); Out.Int(w, 0); Out.Ln;

  Out.Int(99, 0); Out.Ln
END FillDiag2.
