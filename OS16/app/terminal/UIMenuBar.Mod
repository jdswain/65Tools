MODULE UIMenuBar;
  IMPORT UIGraphics, UIKit;

  CONST height* = 14;

  TYPE
    UIMenuBar* = POINTER TO UIMenuBarDesc;
    UIMenuBarDesc* = RECORD END;

  PROCEDURE New*(): UIMenuBar;
    VAR m: UIMenuBar;
  BEGIN NEW(m); RETURN m
  END New;

  PROCEDURE Draw*(self: UIMenuBar);
  BEGIN
    UIGraphics.FillRect(0, 399 - height + 3, 640, 12, UIKit.LightGray);
    UIGraphics.DrawLine(0, 399 - height + 2, 639, 399 - height + 2, 1, UIKit.DarkGray);
    UIGraphics.DrawLine(0, 399 - height + 1, 639, 399 - height + 1, 1, UIKit.Black);
    UIGraphics.FillRect(0, 0, 640, 399 - height, UIKit.DarkGray)
  END Draw;

END UIMenuBar.
