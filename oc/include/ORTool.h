// ORTool.h - Oberon Tool for decoding symbol and object files

#ifndef ORTOOL_H
#define ORTOOL_H

#include "Oberon.h"
#include "Texts.h"
#include "Files.h"
#include "ORB.h"

// Main functions
void ORTool_DecSym(void);    // Decode symbol file
void ORTool_DecObj(void);    // Decode object file
void ORTool_Init(void);      // Initialize module

#endif // ORTOOL_H
