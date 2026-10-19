MODULE GraphicsWindow;
IMPORT Out, Graphics, FontManager, UIKit, Ohlfs9;

CONST
    ScreenW = 640;
    ScreenH = 480;      (* framebuffer is 640 x 480 *)
    MenuH   = 14;       (* menu-bar height at the bottom of the screen *)

VAR
	 x, y, w, h: INTEGER;
     dx: INTEGER;
     s: ARRAY 32 OF CHAR;
BEGIN
  Graphics.InitGraphics;

  (* Menu bar occupies the last MenuH rows of the screen:
     black rule, dark-gray rule, then the light-gray bar to the bottom edge. *)
  Graphics.DrawLine(0, ScreenH-MenuH,   ScreenW-1, ScreenH-MenuH,   1, UIKit.Black);
  Graphics.DrawLine(0, ScreenH-MenuH+1, ScreenW-1, ScreenH-MenuH+1, 1, UIKit.DarkGray);
  Graphics.FillRect(0, ScreenH-MenuH+2, ScreenW, MenuH-2, UIKit.LightGray);

  (* Desktop fills everything above the menu bar *)
  Graphics.FillRect(0, 0, ScreenW, ScreenH-MenuH, UIKit.DarkGray);

  (* Window sized to fill the taller screen (20px margins, clear of the menu bar) *)
  x:=20; y:=20; w:=ScreenW-40; h:=ScreenH-MenuH-y-20;

  Graphics.DrawLine(x, y, x+w, y, 1, UIKit.Black);
  Graphics.DrawLine(x+w, y, x+w, y+h, 1, UIKit.Black);
  Graphics.DrawLine(x+w, y+h, x, y+h, 1, UIKit.Black);
  Graphics.DrawLine(x, y+h, x, y, 1, UIKit.Black);
  Graphics.DrawLine(x+1, y+h-14, x+w-1, y+h-14, 1, UIKit.Black);

  Graphics.DrawLine(x+1, y+h-13, x+1, y+h-1, 1, UIKit.White);
  Graphics.DrawLine(x+1, y+h-1, x+w-1, y+h-1, 1, UIKit.White);

  Graphics.DrawLine(x+2, y+h-13, x+w-1, y+h-13, 1, UIKit.DarkGray);
  Graphics.DrawLine(x+w-1, y+h-13, x+w-1, y+h-2, 1, UIKit.DarkGray);

  (* Title bar (bottom of the window) and window body *)
  Graphics.FillRect(x+2, y+h-12, w-3, 11, UIKit.LightGray);
  Graphics.FillRect(x+1, y+1, w-1, h-15, UIKit.LightGray);

  (* Title text in the title bar *)
  s := "Terminal";
  dx := FontManager.DrawString(Ohlfs9.T, s, x+5, y+h-10, 0);

END GraphicsWindow.
