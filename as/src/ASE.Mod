MODULE ASE; (* The assembler's environment: its arguments and its console.
   Here POSIX's Env and Out; a system the assembler is moved to gives its
   own (OS16's takes the arguments from the command's parameters and
   writes to the terminal). *)

  IMPORT Env, Out;

  PROCEDURE ArgCount*(): INTEGER;
  BEGIN RETURN Env.ArgCount()
  END ArgCount;

  PROCEDURE Arg*(i: INTEGER; VAR s: ARRAY OF CHAR);
  BEGIN Env.Arg(i, s)
  END Arg;

  PROCEDURE Write*(ch: CHAR);
  BEGIN Out.Write(ch)
  END Write;

  PROCEDURE WriteString*(s: ARRAY OF CHAR);
  BEGIN Out.WriteString(s)
  END WriteString;

  PROCEDURE Ln*;
  BEGIN Out.Ln
  END Ln;

END ASE.
