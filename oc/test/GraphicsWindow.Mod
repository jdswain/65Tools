MODULE GraphicsWindow;
IMPORT Out, UIGraphics, UIText, UIKit, Ohlfs9;

VAR
	 x, y, w, h: INTEGER;
     fAddr, fBank: INTEGER;
     dx: INTEGER;
     s: ARRAY 32 OF CHAR;
BEGIN
  UIGraphics.InitGraphics;

  (* Menubar *)
  h:=14;
  UIGraphics.FillRect(0, 399-h+3, 640, 12, UIKit.LightGray);
  UIGraphics.DrawLine(0, 399-h+2, 639, 399-h+2, 1, UIKit.DarkGray);
  UIGraphics.DrawLine(0, 399-h+1, 639, 399-h+1, 1, UIKit.Black);
  UIGraphics.FillRect(0, 0, 640, 400-h, UIKit.DarkGray);

  (* Window *)

  x:=20; y:=20; w:=600; h:=350;

  UIGraphics.DrawLine(x, y, x+w, y, 1, UIKit.Black);
  UIGraphics.DrawLine(x+w, y, x+w, y+h, 1, UIKit.Black);
  UIGraphics.DrawLine(x+w, y+h, x, y+h, 1, UIKit.Black);
  UIGraphics.DrawLine(x, y+h, x, y, 1, UIKit.Black);
  UIGraphics.DrawLine(x+1, y+h-14, x+w-1, y+h-14, 1, UIKit.Black);

  UIGraphics.DrawLine(x+1, y+h-13, x+1, y+h-1, 1, UIKit.White);
  UIGraphics.DrawLine(x+1, y+h-1, x+w-1, y+h-1, 1, UIKit.White);

  UIGraphics.DrawLine(x+2, y+h-13, x+w-1, y+h-13, 1, UIKit.DarkGray);
  UIGraphics.DrawLine(x+w-1, y+h-13, x+w-1, y+h-2, 1, UIKit.DarkGray);

  UIGraphics.FillRect(x+2, y+h-12, w-3, 11, UIKit.LightGray);
  UIGraphics.FillRect(x+1, y+1, w-1, h-15, UIKit.LightGray);

  (* Text *)
  s := "Terminal";
  dx := UIText.DrawString(Ohlfs9.T, s, 25, 360, 0);

END GraphicsWindow.
