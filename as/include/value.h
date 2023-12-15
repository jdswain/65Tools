#ifndef VALUE_H
#define VALUE_H

#include "elf.h"
#include "elf_file.h"

#include <stdbool.h>
#include <stdio.h>

#define MAX_LABEL 32

void value_init(void);

struct MapNode;
typedef struct MapNode MapNode;

struct DSymNode;
typedef struct DSymNode DSymNode;

struct Op;
typedef struct Op Op;

struct Item;
typedef struct Item Item;

extern elf_section_t *section; /* The active section */

/* Macro */

struct MacroDef {
  int num_params;
  Op **instrs;
  int num_instrs;
};
typedef struct MacroDef MacroDef;

void macro_delete(MacroDef *macro);

typedef enum {
  ADD,
  SUB,
  MUL,
  DIV,
  MOD,
  ROL,
  ROR,
  NEG,
  AND,
  OR,
  XOR,
  LAN,
  LOR,
  SHL,
  SHR,
  
  CAL,
  PAR,
  RET,

  BC,
  BN,
  BO,
  BZ,
  BA,
  
  MOV
} IInstrType;

/* 
 Object

 A value is a variant type.
*/
typedef enum {
  Const,
  Var,
  Par,
  Fld,
  Typ,
  SProc,
  SFunc,
  Macro,
  /* Internal */
  Reg
} Mode;

typedef enum {
  /* Oberon type forms */
  ByteForm,
  BoolForm,
  CharForm,
  IntForm,
  RealForm,
  PointerForm,
  NilTypeForm,
  NoTypeForm,
  ProcForm,
  ModForm,
  StringForm,
  ArrayForm,
  RecordForm,
  SetForm,
  /* Assembler type forms */
  MapForm,
  MacroForm,
} Form;
	
int value_storage_size(Form type);

struct FuncDef;
typedef struct FuncDef FuncDef;

typedef enum {
  SymVar, /* A local or global variable */
  SymA, /* Used as a temporary */
  SymX,
  SymY,
  SymReg, /* A register, addr is index */
  SymInt, /* A constant */
  SymFloat, /* A constant */
  SymLoc, /* A code location */
} StorageType;

struct Type;

typedef struct Object {
  int ref_count;
  struct Type *type;
  Mode mode;
  int level;
  struct Object *parent;
  struct MapNode *desc; /* children */
  //  StorageType storage_type;
  int addr; /* Stack offset for local, address for global */
  elf_section_t *section;
  bool exported;
  int exno;
  bool readonly;
  bool is_local;  /* For asm only */
  union {
    bool bool_val;
    long int_val;
    double real_val;
    char *string_val;
    MapNode *map_val;
    MacroDef *macro_val;
    FuncDef *func_val;
  };
} Object;

/* Oberon basic types, initialised in value_init */
extern struct Type *typeByte;
extern struct Type *typeBool;
extern struct Type *typeChar;
extern struct Type *typeInt;
extern struct Type *typeReal;
extern struct Type *typeSet;
extern struct Type *typeNilType;
extern struct Type *typeNoType;
extern struct Type *typeString;
extern struct Type *typeProc;
extern struct Type *typeMod;

/* Assembler basic types, initialised in value_init */
extern struct Type *typeMap;
extern struct Type *typeMacro;

extern Object objectZero;
extern Object objectFalse;
extern Object objectTrue;

extern Object* global_scope;

/* Function */
struct IInstrStore {
  IInstrType instr;
  Object *a, *b, *c;
};

/* Types */
typedef struct Type {
  int ref_count;
  Form form;
  int ref; /* Used for import/export */
  int mno;
  int nofpar; /* Number of params for procedures, extension level for records */
  int len; /* For arrays, len < 0 = open array; for records: adr of descriptor */
  Object **desc; /* Count is nofpar */
  Object *typobj;
  struct Type *base; /* For arrays, records, pointers */
  long size; /* In bytes, always multiple of 2, except for byte, bool, char */
} Type;

Type *type_new(void);
Type *type_retain(Type *self);
void type_release(Type *self);

extern Object *scope;
extern int current_level;
void scope_push_object(Object *object);
void scope_pop(void);

/*
scope_get_object returns a pointer to the value object.
The value pointer will be valid for an entire pass so can 
be used to refer to the value rather than looking it up 
by name.

Only returns objects in the current scope.
*/
Object *scope_get_object(const char* name);

/*
Searches up the scope tree to find the object.
*/
Object *scope_find_object(const char* name);
void scope_add_object(const char *name, Object *object);

Object *object_new(Mode mode, Type *type);
Object *object_retain(Object *object);
Object *object_copy(Object *object);
void object_set(Object *to, Object *from);
void object_reset(Object *value);
void object_release(Object *value);

void object_string(char *buffer, const Object *value);
void object_print(FILE *file, const Object *value);
Object *object_add(const Object *l, const Object *r);
Object *object_sub(const Object *l, const Object *r);
Object *object_mul(const Object *l, const Object *r);
Object *object_div(const Object *l, const Object *r);
Object *object_idiv(const Object *l, const Object *r);
Object *object_mod(const Object *l, const Object *r);
Object *object_and(const Object *l, const Object *r);
Object *object_or(const Object *l, const Object *r);
Object *object_not(const Object *l);
Object *object_lowbyte(const Object *l);
Object *object_highbyte(const Object *l);
Object *object_bankbyte(const Object *l);
Object *object_neg(const Object *l);
Object *object_equal(const Object *l, const Object *r);
Object *object_notequal(const Object *l, const Object *r);
Object *object_greaterthan(const Object *l, const Object *r);
Object *object_greaterthanequal(const Object *l, const Object *r);
Object *object_lessthan(const Object *l, const Object *r);
Object *object_lessthanequal(const Object *l, const Object *r);
Object *object_leftshift(const Object *l, const Object *r);
Object *object_rightshift(const Object *l, const Object *r);

void object_list_add(Object ***ptab, int *num_ptr, Object *data);
void object_list_reset(Object ***ptab, int *n);

/* 
 DynArray

 A dynamic array is an expandable array. It forms the basis
 for the List and Map types.

 Storage is more efficient than a linked list but insertion
 takes longer as memory has to be moved.
*/

/*
 List

 A list is a DynArray of objects.
*/

void list_add(void ***ptab, int *num_ptr, void *data);
void list_reset(void ***ptab, int *n);

/* Map

 A Map is an stores string keys and object values.

 Internally the data is maintained in sorted order. A 
 search is used for finding objects. 
*/

enum color_t { RED = 0, BLACK };

struct MapNode {
  struct MapNode *parent;
  struct MapNode *left;
  struct MapNode *right;
  enum color_t color;
  const char *key;
  Object *value;
};

/*
 map_set - set a value in the map

 If the map does not yet exist then it will be created and
 the root node returned.

 If the key exists then a duplicate will not be created but 
 the value will be updated.
*/
MapNode *map_set(MapNode *map, const char *key, Object *value);

/*
Anonymous version of map_set
*/
MapNode *map_set_anon(MapNode *map, Object *value);

/*
 map_get - returns the value mapped to key
*/
Object *map_get(MapNode *map, const char *key);

/* 
   map_count - count the entries in the map
*/
int map_count(MapNode *map);

/*
 map_delete - free the memory of a map

 After calling map_delete the map pointer is invalid.
*/

void map_delete(MapNode *map);
void object_bmap_delete(MapNode *map);

void map_print(MapNode *map); /* Debug only */

/*
  Byte Buffer
*/

void buf_add_char(unsigned char **pbuf, ELF_Word *num_ptr, const char data);
void buf_add_short(unsigned char **pbuf, ELF_Word *num_ptr, const short data);
void buf_add_int(unsigned char **pbuf, ELF_Word *num_ptr, const int data);
void buf_add_long(unsigned char **pbuf, ELF_Word *num_ptr, const long data);
void buf_add_string(unsigned char **pbuf, ELF_Word *num_ptr, const char* data);
void buf_reset(unsigned char **pbuf, ELF_Word *num_ptr);

/*
dsym_table - a list of strings ordered by address.

This is used to build a symbol table for the debugger.
*/

struct DSymNode {
  struct DSymNode *parent;
  struct DSymNode *left;
  struct DSymNode *right;
  enum color_t color;
  long key;
  char symType;
  const char *value;
};

DSymNode *dsym_add(DSymNode *dsym, long addr, char symType,  const char* value);
DSymNode *dsym_find(DSymNode *root, long addr);

Object *thisImport(Object *mod, char *name);

#endif
