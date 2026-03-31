MODULE Terminal;
  IMPORT UIGraphics, UIMenuBar, UIWindow, UIText, UIKit, Helve12,
         EventManager, ADBManager, UIMouse;

  CONST
    lineHeight = 14;
    contentLeft = 23;
    contentRight = 617;
    contentTop = 346;
    contentBottom = 29;
    charWidth = 6;

  VAR
    menubar: UIMenuBar.UIMenuBar;
    window: UIWindow.UIWindow;
    ev: EventManager.Event;
    curX, curY: INTEGER;
    dx: INTEGER;
    running: BOOLEAN;
    mouseX, mouseY: INTEGER;

  PROCEDURE NewLine;
  BEGIN
    curX := contentLeft;
    curY := curY - lineHeight;
    IF curY < contentBottom THEN
      curY := contentTop
    END
  END NewLine;

BEGIN
  UIGraphics.InitGraphics;
  menubar := UIMenuBar.New();
  window := UIWindow.New("Terminal", 20, 20, 600, 350);
  UIMenuBar.Draw(menubar);
  UIWindow.Draw(window);

  ADBManager.Init;
  (* Flush accumulated mouse deltas from before app start *)
  ADBManager.Poll;
  WHILE EventManager.HasEvent() DO EventManager.NextEvent(ev) END;
  ADBManager.Poll;
  WHILE EventManager.HasEvent() DO EventManager.NextEvent(ev) END;
  mouseX := 320; mouseY := 200;
  UIMouse.Init(mouseX, mouseY);
  curX := contentLeft;
  curY := contentTop;
  running := TRUE;

  WHILE running DO
    ADBManager.Poll;
    WHILE EventManager.HasEvent() DO
      EventManager.NextEvent(ev);
      IF ev.kind = EventManager.EvKeyDown THEN
        IF ev.ch = 27 THEN
          running := FALSE
        ELSIF ev.ch = 13 THEN
          NewLine
        ELSIF ev.ch = 8 THEN
          curX := curX - charWidth;
          IF curX < contentLeft THEN curX := contentLeft END;
          UIGraphics.FillRect(curX, curY - 2, charWidth, lineHeight, UIKit.White)
        ELSIF ev.ch > 31 THEN
          dx := UIText.DrawChar(Helve12.T, ev.ch, curX, curY, UIKit.Black);
          curX := curX + dx;
          IF curX > contentRight THEN
            NewLine
          END
        END
      ELSIF ev.kind = EventManager.EvMouseMove THEN
        mouseX := mouseX + ev.dx;
        mouseY := mouseY - ev.dy;
        IF mouseX < 0 THEN mouseX := 0
        ELSIF mouseX > 629 THEN mouseX := 629
        END;
        IF mouseY < 13 THEN mouseY := 13
        ELSIF mouseY > 399 THEN mouseY := 399
        END;
        UIMouse.MoveTo(mouseX, mouseY)
      END
    END
  END
END Terminal.
