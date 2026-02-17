MODULE GraphicsWindow;
IMPORT Graphics, Out;

CONST
	 Black = 0;
     DarkGray = 1;
     LightGray = 2;
     White = 3;

VAR x, y, w, h: INTEGER;

BEGIN
  Graphics.InitGraphics;

  (* Menubar *)
  h:=14;
  Graphics.FillRect(0, 479-h+3, 640, 12, LightGray); 
  Graphics.DrawLine(0, 479-h+2, 639, 479-h+2, 1, DarkGray); 
  Graphics.DrawLine(0, 479-h+1, 639, 479-h+1, 1, Black); 
  Graphics.FillRect(0, 0, 640, 480-h, DarkGray); 
  
  (* Window *)

  x:=20; y:=20; w:=600; h:=430;

  Graphics.DrawLine(x, y, x+w, y, 1, Black);
  Graphics.DrawLine(x+w, y, x+w, y+h, 1, Black);
  Graphics.DrawLine(x+w, y+h, x, y+h, 1, Black);
  Graphics.DrawLine(x, y+h, x, y, 1, Black);
  Graphics.DrawLine(x+1, y+h-14, x+w-1, y+h-14, 1, Black); 

  Graphics.DrawLine(x+1, y+h-13, x+1, y+h-1, 1, White);
  Graphics.DrawLine(x+1, y+h-1, x+w-1, y+h-1, 1, White);
  
  Graphics.DrawLine(x+2, y+h-13, x+w-1, y+h-13, 1, DarkGray);
  Graphics.DrawLine(x+w-1, y+h-13, x+w-1, y+h-2, 1, DarkGray);

  Graphics.FillRect(x+2, y+h-12, w-3, 11, LightGray);
  Graphics.FillRect(x+1, y+1, w-1, h-15, LightGray);

END GraphicsWindow.
