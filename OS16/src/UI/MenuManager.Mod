MODULE MenuManager; (* The menu bar along the foot of the screen (model:
   MenuManager). Draws the bar; menus are not yet written. *)
  IMPORT Graphics, UIKit;

  CONST height* = 14;

  TYPE
    MenuBar* = POINTER TO MenuBarDesc;
    MenuBarDesc* = RECORD END;

  PROCEDURE New*(): MenuBar;
    VAR m: MenuBar;
  BEGIN NEW(m); RETURN m
  END New;

  PROCEDURE Draw*(self: MenuBar);
  BEGIN
    Graphics.FillRect(0, 399 - height + 3, 640, 12, UIKit.LightGray);
    Graphics.DrawLine(0, 399 - height + 2, 639, 399 - height + 2, 1, UIKit.DarkGray);
    Graphics.DrawLine(0, 399 - height + 1, 639, 399 - height + 1, 1, UIKit.Black);
    Graphics.FillRect(0, 0, 640, 399 - height, UIKit.DarkGray)
  END Draw;

END MenuManager.
