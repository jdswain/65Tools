/* test_orp.c - Test program for the ORP parser module */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ORS.h"
#include "ORB.h"
#include "ORP.h"

int main(int argc, char *argv[]) {
    const char *filename;
    bool forceNewSF = false;
    
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <source.Mod> [/s]\n", argv[0]);
        fprintf(stderr, "  /s  Force new symbol file\n");
        return 1;
    }
    
    filename = argv[1];
    
    /* Check for /s option */
    if (argc > 2 && strcmp(argv[2], "/s") == 0) {
        forceNewSF = true;
    }
    
    /* Initialize parser */
    ORB_Init();
    
    /* Compile the file */
    ORP_Compile(filename, forceNewSF);
    
    return ORS_errcnt > 0 ? 1 : 0;
}
