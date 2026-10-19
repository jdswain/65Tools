MODULE GraphicsWindow;
IMPORT Out, UIGraphics, UIText, UIKit, Ohlfs9;

CONST
    ScreenW = 640;
    ScreenH = 480;      (* framebuffer is 640 x 480 *)
    MenuH   = 14;       (* menu-bar height at the bottom of the screen *)

VAR
	 x, y, w, h: INTEGER;
     dx: INTEGER;
     s: ARRAY 32 OF CHAR;
BEGIN
  UIGraphics.InitGraphics;

  (* Menu bar occupies the last MenuH rows of the screen:
     black rule, dark-gray rule, then the light-gray bar to the bottom edge. *)
  UIGraphics.DrawLine(0, ScreenH-MenuH,   ScreenW-1, ScreenH-MenuH,   1, UIKit.Black);
  UIGraphics.DrawLine(0, ScreenH-MenuH+1, ScreenW-1, ScreenH-MenuH+1, 1, UIKit.DarkGray);
  UIGraphics.FillRect(0, ScreenH-MenuH+2, ScreenW, MenuH-2, UIKit.LightGray);

  (* Desktop fills everything above the menu bar *)
  UIGraphics.FillRect(0, 0, ScreenW, ScreenH-MenuH, UIKit.DarkGray);

  (* Window sized to fill the taller screen (20px margins, clear of the menu bar) *)
  x:=20; y:=20; w:=ScreenW-40; h:=ScreenH-MenuH-y-20;

  UIGraphics.DrawLine(x, y, x+w, y, 1, UIKit.Black);
  UIGraphics.DrawLine(x+w, y, x+w, y+h, 1, UIKit.Black);
  UIGraphics.DrawLine(x+w, y+h, x, y+h, 1, UIKit.Black);
  UIGraphics.DrawLine(x, y+h, x, y, 1, UIKit.Black);
  UIGraphics.DrawLine(x+1, y+h-14, x+w-1, y+h-14, 1, UIKit.Black);

  UIGraphics.DrawLine(x+1, y+h-13, x+1, y+h-1, 1, UIKit.White);
  UIGraphics.DrawLine(x+1, y+h-1, x+w-1, y+h-1, 1, UIKit.White);

  UIGraphics.DrawLine(x+2, y+h-13, x+w-1, y+h-13, 1, UIKit.DarkGray);
  UIGraphics.DrawLine(x+w-1, y+h-13, x+w-1, y+h-2, 1, UIKit.DarkGray);

  (* Title bar (bottom of the window) and window body *)
  UIGraphics.FillRect(x+2, y+h-12, w-3, 11, UIKit.LightGray);
  UIGraphics.FillRect(x+1, y+1, w-1, h-15, UIKit.LightGray);

  (* Title text in the title bar *)
  s := "Terminal";
  dx := UIText.DrawString(Ohlfs9.T, s, x+5, y+h-10, 0);

END GraphicsWindow.
