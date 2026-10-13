/* ASH_rt.c - host side of ASH.Mod.

   Oberon has no way to set the process exit status, so ASH.Exit is an
   empty (weak) stub in ASH.Mod and this definition overrides it at link
   time, the same arrangement the runtime's Files/Out modules use. */

#include <stdio.h>
#include <stdlib.h>

void ASH__Exit(int code) {
  fflush(stdout);
  exit(code);
}
