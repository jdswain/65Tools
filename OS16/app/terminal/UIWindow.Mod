MODULE UIWindow;
  IMPORT UIGraphics, UIText, UIKit, Ohlfs9;

  TYPE
    UIWindow* = POINTER TO UIWindowDesc;
    UIWindowDesc* = RECORD
      title: ARRAY 32 OF CHAR;
      x, y, w, h: INTEGER;
      hasFocus: BOOLEAN;
      resizeable: BOOLEAN
    END;

  PROCEDURE New*(title: ARRAY OF CHAR; x, y, w, h: INTEGER): UIWindow;
    VAR win: UIWindow; i: INTEGER;
  BEGIN
    NEW(win);
    i := 0;
    WHILE (i < LEN(title)) & (i < 31) & (title[i] # 0X) DO
      win.title[i] := title[i]; INC(i)
    END;
    win.title[i] := 0X;
    win.x := x; win.y := y; win.w := w; win.h := h;
    win.hasFocus := TRUE; win.resizeable := TRUE;
    RETURN win
  END New;

  PROCEDURE Draw*(self: UIWindow);
    VAR dx: INTEGER;
  BEGIN
    (* Window border *)
    UIGraphics.DrawLine(self.x, self.y, self.x + self.w, self.y, 1, UIKit.Black);
    UIGraphics.DrawLine(self.x + self.w, self.y, self.x + self.w, self.y + self.h, 1, UIKit.Black);
    UIGraphics.DrawLine(self.x + self.w, self.y + self.h, self.x, self.y + self.h, 1, UIKit.Black);
    UIGraphics.DrawLine(self.x, self.y + self.h, self.x, self.y, 1, UIKit.Black);
    (* Title bar separator *)
    UIGraphics.DrawLine(self.x + 1, self.y + self.h - 14, self.x + self.w - 1, self.y + self.h - 14, 1, UIKit.Black);
    (* Title bar 3D effect *)
    UIGraphics.DrawLine(self.x + 1, self.y + self.h - 13, self.x + 1, self.y + self.h - 1, 1, UIKit.White);
    UIGraphics.DrawLine(self.x + 1, self.y + self.h - 1, self.x + self.w - 1, self.y + self.h - 1, 1, UIKit.White);
    UIGraphics.DrawLine(self.x + 2, self.y + self.h - 13, self.x + self.w - 1, self.y + self.h - 13, 1, UIKit.DarkGray);
    UIGraphics.DrawLine(self.x + self.w - 1, self.y + self.h - 13, self.x + self.w - 1, self.y + self.h - 2, 1, UIKit.DarkGray);
    (* Fills *)
    UIGraphics.FillRect(self.x + 2, self.y + self.h - 12, self.w - 3, 11, UIKit.Black);
    UIGraphics.FillRect(self.x + 1, self.y + 1 + 6, self.w - 1, self.h - 21, UIKit.White);
    UIGraphics.FillRect(self.x + 1, self.y + 1, self.w - 1, 4, UIKit.LightGray);

	UIGraphics.DrawLine(self.x + 1, self.y + 1 + 4, self.x + self.w - 1, self.y + 1 + 4, 1, UIKit.White);
    UIGraphics.DrawLine(self.x + 1, self.y + 1 + 5, self.x + self.w - 1, self.y + 1 + 5, 1, UIKit.DarkGray);

	UIGraphics.DrawLine(self.x + 1 + 20, self.y + 1, self.x + 1 + 20, self.y + 1 + 4, 1, UIKit.DarkGray);
	UIGraphics.DrawLine(self.x + 1 + 21, self.y + 1, self.x + 1 + 21, self.y + 1 + 4, 1, UIKit.White);

	UIGraphics.DrawLine(self.x + self.w - 1 - 21, self.y + 1, self.x + self.w - 1 - 21, self.y + 1 + 4, 1, UIKit.DarkGray);
	UIGraphics.DrawLine(self.x + self.w - 1 - 20, self.y + 1, self.x + self.w - 1 - 20, self.y + 1 + 4, 1, UIKit.White);
	
    (* Title text *)
    dx := UIText.DrawString(Ohlfs9.T, self.title, self.x + 5, self.y + self.h - 10, UIKit.White)
  END Draw;

  PROCEDURE SetBounds*(self: UIWindow; x, y, w, h: INTEGER);
  BEGIN self.x := x; self.y := y; self.w := w; self.h := h
  END SetBounds;

END UIWindow.
