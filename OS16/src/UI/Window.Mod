MODULE Window; (* A window: a frame with a title bar (model: Window, a
   View). *)
  IMPORT Graphics, FontManager, UIKit, View, Ohlfs9;

  TYPE
    Window* = POINTER TO WindowDesc;
    WindowDesc* = RECORD (View.ViewDesc)
      title: ARRAY 32 OF CHAR;
      hasFocus: BOOLEAN;
      resizeable: BOOLEAN
    END;

  PROCEDURE New*(title: ARRAY OF CHAR; x, y, w, h: INTEGER): Window;
    VAR win: Window; i: INTEGER;
  BEGIN
    NEW(win);
    i := 0;
    WHILE (i < LEN(title)) & (i < 31) & (title[i] # 0X) DO
      win.title[i] := title[i]; INC(i)
    END;
    win.title[i] := 0X;
    win.SetBounds(x, y, w, h);
    win.hasFocus := TRUE; win.resizeable := TRUE;
    RETURN win
  END New;

  PROCEDURE (self: Window) Draw* OVERRIDE;
    VAR dx: INTEGER;
  BEGIN
    (* Window border *)
    Graphics.DrawLine(self.x, self.y, self.x + self.w, self.y, 1, UIKit.Black);
    Graphics.DrawLine(self.x + self.w, self.y, self.x + self.w, self.y + self.h, 1, UIKit.Black);
    Graphics.DrawLine(self.x + self.w, self.y + self.h, self.x, self.y + self.h, 1, UIKit.Black);
    Graphics.DrawLine(self.x, self.y + self.h, self.x, self.y, 1, UIKit.Black);
    (* Title bar separator *)
    Graphics.DrawLine(self.x + 1, self.y + self.h - 14, self.x + self.w - 1, self.y + self.h - 14, 1, UIKit.Black);
    (* Title bar 3D effect *)
    Graphics.DrawLine(self.x + 1, self.y + self.h - 13, self.x + 1, self.y + self.h - 1, 1, UIKit.White);
    Graphics.DrawLine(self.x + 1, self.y + self.h - 1, self.x + self.w - 1, self.y + self.h - 1, 1, UIKit.White);
    Graphics.DrawLine(self.x + 2, self.y + self.h - 13, self.x + self.w - 1, self.y + self.h - 13, 1, UIKit.DarkGray);
    Graphics.DrawLine(self.x + self.w - 1, self.y + self.h - 13, self.x + self.w - 1, self.y + self.h - 2, 1, UIKit.DarkGray);
    (* Fills *)
    Graphics.FillRect(self.x + 2, self.y + self.h - 12, self.w - 3, 11, UIKit.Black);
    Graphics.FillRect(self.x + 1, self.y + 1 + 6, self.w - 1, self.h - 21, UIKit.White);
    Graphics.FillRect(self.x + 1, self.y + 1, self.w - 1, 4, UIKit.LightGray);

	Graphics.DrawLine(self.x + 1, self.y + 1 + 4, self.x + self.w - 1, self.y + 1 + 4, 1, UIKit.White);
    Graphics.DrawLine(self.x + 1, self.y + 1 + 5, self.x + self.w - 1, self.y + 1 + 5, 1, UIKit.DarkGray);

	Graphics.DrawLine(self.x + 1 + 20, self.y + 1, self.x + 1 + 20, self.y + 1 + 4, 1, UIKit.DarkGray);
	Graphics.DrawLine(self.x + 1 + 21, self.y + 1, self.x + 1 + 21, self.y + 1 + 4, 1, UIKit.White);

	Graphics.DrawLine(self.x + self.w - 1 - 21, self.y + 1, self.x + self.w - 1 - 21, self.y + 1 + 4, 1, UIKit.DarkGray);
	Graphics.DrawLine(self.x + self.w - 1 - 20, self.y + 1, self.x + self.w - 1 - 20, self.y + 1 + 4, 1, UIKit.White);
	
    (* Title text *)
    dx := FontManager.DrawString(Ohlfs9.T, self.title, self.x + 5, self.y + self.h - 10, UIKit.White)
  END Draw;

END Window.
