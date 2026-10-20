MODULE View; (* A rectangle of the screen that draws itself and handles
   events (model: View). Control, ScrollView, Window and Dialog extend
   it. Coordinates are the screen's, in pixels. *)

  IMPORT EventManager;

  TYPE
    View* = POINTER TO ViewDesc;
    ViewDesc* = RECORD
      x*, y*, w*, h*: INTEGER
    END;

  PROCEDURE (v: View) Draw*;
  BEGIN
  END Draw;

  (* TRUE if the view used the event *)
  PROCEDURE (v: View) Handle*(VAR e: EventManager.Event): BOOLEAN;
  BEGIN RETURN FALSE
  END Handle;

  PROCEDURE (v: View) SetBounds*(x, y, w, h: INTEGER);
  BEGIN v.x := x; v.y := y; v.w := w; v.h := h
  END SetBounds;

  PROCEDURE (v: View) Contains*(x, y: INTEGER): BOOLEAN;
  BEGIN RETURN (x >= v.x) & (x < v.x + v.w) & (y >= v.y) & (y < v.y + v.h)
  END Contains;

END View.
