/* ORB.h - Symbol Table Management Header */
/* Original: NW 25.6.2014 / AP 4.3.2020 / 8.3.2019 in Oberon-07 */

#ifndef ORB_H
#define ORB_H

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include "ORS.h"
#include "Files.h"

/* Constants */
#define versionkey 1
#define maxTypTab 64

/* Class values */
#define Head 0
#define Const 1
#define Var 2
#define Par 3
#define Fld 4
#define Typ 5
#define SProc 6
#define SFunc 7
#define Mod 8

/* Class values with ORB_ prefix */
#define ORB_Head 0
#define ORB_Const 1
#define ORB_Var 2
#define ORB_Par 3
#define ORB_Fld 4
#define ORB_Typ 5
#define ORB_SProc 6
#define ORB_SFunc 7
#define ORB_Mod 8

/* Form values */
#define Byte 1
#define Bool 2
#define Char 3
#define Int 4
#define Real 5
#define Set 6
#define Pointer 7
#define NilTyp 8
#define NoTyp 9
#define Proc 10
#define String 11
#define Array 12
#define Record 13

/* Form values with ORB_ prefix */
#define ORB_Byte 1
#define ORB_Bool 2
#define ORB_Char 3
#define ORB_Int 4
#define ORB_Real 5
#define ORB_Set 6
#define ORB_Pointer 7
#define ORB_NilTyp 8
#define ORB_NoTyp 9
#define ORB_Proc 10
#define ORB_String 11
#define ORB_Array 12
#define ORB_Record 13

/* Forward declarations */
typedef struct ORB_Object* ObjectPtr;
typedef struct ORB_Module* ModulePtr;
typedef struct ORB_Type* TypePtr;

/* Type definitions */
typedef struct ORB_Object {
    uint8_t class;
    uint8_t exno;
    BOOLEAN expo;          /* exported */
    BOOLEAN rdo;           /* read-only */
    INTEGER lev;
    ObjectPtr next;
    ObjectPtr dsc;
    TypePtr type;
    Ident name;
    LONGINT val;
} ORB_Object;

typedef struct ORB_Module {
    ORB_Object base;        /* Module extends Object */
    Ident orgname;
} ORB_Module;

typedef struct ORB_Type {
    int form;
    int ref;           /* only used for import/export */
    int mno;
    int nofpar;        /* for procedures, extension level for records */
    int32_t len;       /* for arrays, len < 0 => open array; for records: adr of descriptor */
    ObjectPtr dsc;
    ObjectPtr typobj;
    TypePtr base;      /* for arrays, records, pointers */
    int32_t size;      /* in bytes; always multiple of 4, except for Byte, Bool and Char */
} ORB_Type;

/* Global variables */
extern ObjectPtr topScope;
extern ObjectPtr universe;
extern ObjectPtr systemScope;  /* renamed from system */
extern TypePtr byteType;
extern TypePtr boolType;
extern TypePtr charType;
extern TypePtr intType;
extern TypePtr realType;
extern TypePtr setType;
extern TypePtr nilType;
extern TypePtr noType;
extern TypePtr strType;

/* Function prototypes */
void NewObj(ObjectPtr *obj, const char *id, int class);
ObjectPtr thisObj(void);
ObjectPtr thisimport(ObjectPtr mod);
ObjectPtr thisfield(TypePtr rec);
void OpenScope(void);
void CloseScope(void);
void MakeFileName(char *FName, const char *name, const char *ext);
void Import(char *modid, char *modid1);
void Export(const char *modid, BOOLEAN *newSF, int32_t *key);
void ORB_Init(void);  /* renamed from Init */
void ORB_Initialize(void);  /* Module initialization */

/* File operations are now provided by Files.h */

#endif /* ORB_H */
