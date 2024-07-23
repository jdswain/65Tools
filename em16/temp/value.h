#ifndef VALUE_H
#define VALUE_H

#include "elf.h"
#include "elf_file.h"

#include <stdbool.h>
#include <stdio.h>

#define MAX_LABEL 32

struct MapNode;
typedef struct MapNode MapNode;

struct Op;
typedef struct Op Op;

extern elf_section_t *section; /* The active section */

/* Macro */

struct MacroDef {
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

/* Scope */

struct Scope {
  struct Scope *parent;
  MapNode *values;
};
typedef struct Scope Scope;

void scope_push(void);
void scope_pop(void);

/* 
 Value

 A value is a variant type.
*/
typedef enum {
  /* SimpleTypes */
  Void,
  NearPointer,
  FarPointer,
  Char,
  Short,
  Int,
  Long,
  Float,
  Double,

  /* asm Types */
  String,
  List,
  Map,
  Macro,
  Func,
} ValueType;

int value_storage_size(ValueType type);

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

struct Value {
  ValueType value_type;
  StorageType storage_type;
  int addr; /* Stack offset for local, address for global */
  elf_section_t *section;
  bool is_signed;
  bool is_const;
  bool is_volatile;
  bool is_extern;
  bool is_static;
  bool is_auto;
  bool is_register;
  bool is_local;  /* For asm */
  union {
    bool bool_val;
    long int_val;
    double real_val;
    char *string_val;
    MapNode *map_val;
    MacroDef *macro_val;
    FuncDef *func_val;
  };
};
typedef struct Value Value;

/* Function */
struct IInstrStore {
  IInstrType instr;
  Value *a, *b, *c;
};

struct FuncDef {
  char *name;
  ValueType return_type;
  // Param Spec
  int param_size; /* ToDo: derive from param spec */
  int local_size;
  int nextReg;
  
  /* ICode buffer */
  int buf_len;
  struct IInstrStore *buf;
};

/*
scope_get_value returns a pointer to the value object.
The value pointer will be valid for an entire pass so can 
be used to refer to the value rather than looking it up 
by name.
*/
Value *scope_get_value(const char* name);
void scope_set_value(const char* name, Value *value);
void scope_set_anon_value(Value *value); /* Anonymous values */

int value_storage(ValueType type);
void value_print(FILE *file, const Value *value);
Value *value_dup(const Value *value);
Value *value_add(const Value *l, const Value *r);
Value *value_sub(const Value *l, const Value *r);
Value *value_mul(const Value *l, const Value *r);
Value *value_div(const Value *l, const Value *r);
Value *value_idiv(const Value *l, const Value *r);
Value *value_mod(const Value *l, const Value *r);
Value *value_and(const Value *l, const Value *r);
Value *value_or(const Value *l, const Value *r);
Value *value_not(const Value *l);
Value *value_lowbyte(const Value *l);
Value *value_highbyte(const Value *l);
Value *value_bankbyte(const Value *l);
Value *value_neg(const Value *l);
Value *value_equal(const Value *l, const Value *r);
Value *value_notequal(const Value *l, const Value *r);
Value *value_greaterthan(const Value *l, const Value *r);
Value *value_greaterthanequal(const Value *l, const Value *r);
Value *value_lessthan(const Value *l, const Value *r);
Value *value_lessthanequal(const Value *l, const Value *r);
Value *value_leftshift(const Value *l, const Value *r);
Value *value_rightshift(const Value *l, const Value *r);
void value_reset(Value *value);
void value_delete(Value *value);

/* 
 DynArray

 A dynamic array is an expandable array. It forms the basis
 for the List and Map types.

 Storage is more efficient than a linked list but insertion
 takes longer as memory has to be moved.
*/

/*
 List

 A list is a DynArray of values.
*/

void list_add(void ***ptab, int *num_ptr, void *data);
void list_reset(void ***ptab, int *n);

/* Map

 A Map is an stores string keys and Value values.

 Internally the data is maintained in sorted order. A 
 search is used for finding values. 
*/

enum color_t { RED = 0, BLACK };

struct MapNode {
  struct MapNode *parent;
  struct MapNode *left;
  struct MapNode *right;
  enum color_t color;
  const char *key;
  Value *value;
};

/*
 map_set - set a value in the map

 If the map does not yet exist then it will be created and
 the root node returned.

 If the key exists then a duplicate will not be created but 
 the value will be updated.
*/
MapNode *map_set(MapNode *map, const char *key, Value *value);

/*
Anonymous version of map_set
*/
MapNode *map_set_anon(MapNode *map, Value *value);

/*
 map_get - returns the value mapped to key
*/
Value *map_get(MapNode *map, const char *key);

/* 
   map_count - count the entries in the map
*/
int map_count(MapNode *map);

/*
 map_delete - free the memory of a map

 After calling map_delete the map pointer is invalid.
*/

void map_delete(MapNode *map);

/*
  Byte Buffer
*/

void buf_add_char(unsigned char **pbuf, ELF_Word *num_ptr, char data);
void buf_add_short(unsigned char **pbuf, ELF_Word *num_ptr, short data);
void buf_add_int(unsigned char **pbuf, ELF_Word *num_ptr, int data);
void buf_add_long(unsigned char **pbuf, ELF_Word *num_ptr, long data);
void buf_add_string(unsigned char **pbuf, ELF_Word *num_ptr, char* data);
void buf_reset(unsigned char **pbuf, ELF_Word *num_ptr);

#endif
