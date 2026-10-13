MODULE Graphics;

TYPE
	 Display* = POINTER TO DisplayDesc;
	 Context* = POINTER TO ContextDesc;

	 DisplayDesc* = RECORD
		  fbaddr : INTEGER; (* Probably needs to be LONGINT *)
		  fbw, fbh : INTEGER;		  

		  run : PROCEDURE (c : Context; l : INTEGER; s, e : INTEGER; color : INTEGER);
	 END;
	 
	 ContextDesc* = RECORD
		  display : Display;
		  x, y : INTEGER;
		  fgcolor : INTEGER;
		  bgcolor : INTEGER;
		  clip_x, clip_y, clip_w, clip_h : INTEGER;

		  push* : PROCEDURE () : Context;
     	  pop* : PROCEDURE () : Context;
										   
		  moveto* : PROCEDURE (c : Context; x, y : INTEGER);
		  lineto* : PROCEDURE (c : Context; x, y : INTEGER);

          move* : PROCEDURE (c : Context; dx, dy : INTEGER);							  
		  line* : PROCEDURE (c : Context; dx, dy : INTEGER);

		  stringSize* : PROCEDURE (c : Context, var w, h : INTEGER);
		  drawString* : PROCEDURE (c : Context, s : STRING);
	 END;							

PROCEDURE InitDisplay* (var d : Display; fbaddr: INTEGER; w, h: INTEGER)
BEGIN
	 d.fbaddr = fbaddr;
	 d.fbw = w;
	 d.fbh = h;
END Init;

PROCEDURE InitContext* (var c : Context; d : Display)
BEGIN
	 c.display = d;
END

PROCEDURE moveto(c: Context; x, y : INTEGER)
BEGIN
	 c.x = x;
	 x.y = y;
END moveto;


END Graphics.
