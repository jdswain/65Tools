#include "value.h"

#include "memory.h"
#include "buffered_file.h"

#include <string.h>

/*
 Scope
*/
void scope_push(void)
{
  struct Scope *parent = section->scope;
  section->scope = new struct Scope;
  section->scope->values = 0;
  section->scope->parent = parent;
}

void scope_pop(void)
{
  struct Scope *dead = section->scope; 
  section->scope = dead->parent;
  if (dead->values != 0 ) map_delete(dead->values);
  as_free(dead);
}

Value *scope_get_value(const char* name)
{
  return map_get(section->scope->values, name);
}

void scope_set_value(const char* name, Value *value)
{
  section->scope->values = map_set(section->scope->values, name, value);
}

void scope_set_anon_value(Value *value)
{
  section->scope->values = map_set_anon(section->scope->values, value);
}

int value_storage(ValueType type)
{
  switch (type) {
  case Void:
    return 0;
  case Char:
    return 1;
  case Short:
    return 2;
  case Int:
    return 4;
  case Long:
    return 8;
  case Float:
    return 4;
  case Double:
    return 8;
  case NearPointer:
    return 2;
  case FarPointer:
    return 4;
  case String:
    return 2; /* NearPointer? */
  case List:
  case Map:
  case Macro:
  case Func:
    break;
  }
  as_error("value_storage called on complex type");
  return 0;
}

void value_print(FILE *file, const Value *value)
{
  switch(value->value_type) {
  case Void:  fprintf(file, "void"); break;
  case NearPointer: fprintf(file, "%8x", (int)value->int_val); break;
  case FarPointer: fprintf(file, "%8x", (int)value->int_val); break;
    //case UChar: fprintf(file, "%2x", (unsigned char)value->int_val); break;
    //case UShort: fprintf(file, "%4x", (unsigned short)value->int_val); break;
    //case UInt: fprintf(file, "%4x", (unsigned int)value->int_val); break;
    //case ULong: fprintf(file, "%8lx", (unsigned long)value->int_val); break;
  case Char: fprintf(file, "%2x", (char)value->int_val); break;
  case Short: fprintf(file, "%4x", (short)value->int_val); break;
  case Int: fprintf(file, "%8x", (int)value->int_val); break;
  case Long: fprintf(file, "%8lx", (long)value->int_val); break;
  case Float: fprintf(file, "%8f", value->real_val); break;
  case Double: fprintf(file, "%8f", value->real_val); break;
  case String: fprintf(file, "%.8s", value->string_val); break;
  case List: fprintf(file, "[List]"); break;
  case Map: fprintf(file, "[map]"); break;
  case Macro: fprintf(file, "[Macro]"); break;
  case Func: fprintf(file, "[Func]"); break;
  };
}

Value *value_dup(const Value *value)
{
  Value *v = new Value;
  v->value_type = value->value_type;
  v->is_signed = value->is_signed;
  v->is_const = value->is_const;
  v->is_volatile = value->is_volatile;
  v->is_extern = value->is_extern;
  v->is_static = value->is_static;
  v->is_auto = value->is_auto;
  v->is_register = value->is_register;
  v->is_local = value->is_local; 
  switch (v->value_type) {
  case Void: break;
  case Float: v->real_val = value->real_val; break;
  case Double: v->real_val = value->real_val; break;
  case NearPointer: v->int_val = value->int_val; break;
  case FarPointer: v->int_val = value->int_val; break;
  case Char: v->int_val = value->int_val; break;
  case Short: v->int_val = value->int_val; break;
  case Int: v->int_val = value->int_val; break;
  case Long: v->int_val = value->int_val; break;
  case String: v->string_val = as_strdup(value->string_val); break;
  case List:
  case Map:
  case Macro:
    break;
  case Func: v->func_val = value->func_val; break;
  }
  return v;
}

Value *value_add(const Value *l, const Value *r)
{
  Value *result = new Value;
  result->value_type = Int;
  result->int_val = l->int_val + r->int_val;
  return result;
}

Value *value_sub(const Value *l, const Value *r)
{
  Value *result = new Value;
  result->value_type = Int;
  result->int_val = l->int_val - r->int_val;
  return result;
}

Value *value_mul(const Value *l, const Value *r)
{
  Value *result = new Value;
  result->value_type = Int;
  result->int_val = l->int_val * r->int_val;
  return result;

}

Value *value_div(const Value *l, const Value *r)
{
  Value *result = new Value;
  result->value_type = Int;
  result->int_val = l->int_val / r->int_val;
  return result;

}

Value *value_idiv(const Value *l, const Value *r)
{
  Value *result = new Value;
  result->value_type = Int;
  result->int_val = l->int_val / r->int_val;
  return result;
}

Value *value_mod(const Value *l, const Value *r)
{
  Value *result = new Value;
  result->value_type = Int;
  result->int_val = l->int_val % r->int_val;
  return result;
}

Value *value_and(const Value *l, const Value *r)
{
  Value *result = new Value;
  result->value_type = Int;
  result->int_val = l->int_val & r->int_val;
  return result;
}

Value *value_or(const Value *l, const Value *r)
{
  Value *result = new Value;
  result->value_type = Int;
  result->int_val = l->int_val / r->int_val;
  return result;
}

Value *value_not(const Value *l)
{
  Value *result = new Value;
  result->value_type = Int;
  result->int_val = !(l->int_val);
  return result;

}

Value *value_lowbyte(const Value *l)
{
  Value *result = new Value;
  result->value_type = Int;
  result->int_val = l->int_val & 0xff;
  return result;

}

Value *value_highbyte(const Value *l)
{
  Value *result = new Value;
  result->value_type = Int;
  result->int_val = (l->int_val >> 8) & 0xff;
  return result;

}

Value *value_bankbyte(const Value *l)
{
  Value *result = new Value;
  result->value_type = Int;
  result->int_val = (l->int_val >> 16) & 0xff;
  return result;

}

Value *value_neg(const Value *l)
{
  Value *result = new Value;
  result->value_type = Int;
  result->int_val = -l->int_val;
  return result;
}

Value *value_equal(const Value *l, const Value *r)
{
  Value *result = new Value;
  result->value_type = Int;
  result->int_val = l->int_val == r->int_val;
  return result;
}

Value *value_notequal(const Value *l, const Value *r)
{
  Value *result = new Value;
  result->value_type = Int;
  result->int_val = l->int_val != r->int_val;
  return result;
}

Value *value_greaterthan(const Value *l, const Value *r)
{
  Value *result = new Value;
  result->value_type = Int;
  result->int_val = l->int_val > r->int_val;
  return result;
}

Value *value_greaterthanequal(const Value *l, const Value *r)
{
  Value *result = new Value;
  result->value_type = Int;
  result->int_val = l->int_val >= r->int_val;
  return result;
}

Value *value_lessthan(const Value *l, const Value *r)
{
  Value *result = new Value;
  result->value_type = Int;
  result->int_val = l->int_val < r->int_val;
  return result;
}

Value *value_lessthanequal(const Value *l, const Value *r)
{
  Value *result = new Value;
  result->value_type = Int;
  result->int_val = l->int_val <= r->int_val;
  return result;
}

Value *value_leftshift(const Value *l, const Value *r)
{
  Value *result = new Value;
  result->value_type = Int;
  result->int_val = l->int_val << r->int_val;
  return result;
}

Value *value_rightshift(const Value *l, const Value *r)
{
  Value *result = new Value;
  result->value_type = Int;
  result->int_val = l->int_val >> r->int_val;
  return result;
}

void value_reset(Value *value)
{
  value->value_type = Void;
  value->is_signed = false;
  value->is_const = false;
  value->is_volatile = false;
  value->is_extern = false;
  value->is_static = false;
  value->is_auto = false;
  value->is_register = false;
  value->is_local = false;
  value->int_val = 0;
}

/* Avoid dependency on func here */
void func_delete(FuncDef *func) {
}

void value_delete(Value *value)
{
  switch(value->value_type) {
  case Void: break;
  case Float: break;
  case Double: break;
  case NearPointer: break;
  case FarPointer: break;
  case Char: break;
  case Short: break;
  case Int: break;
  case Long: break;
  case String: as_free(value->string_val); break;
  case List: /* ToDo */ break;
  case Map: map_delete(value->map_val); break;
  case Macro: macro_delete(value->macro_val); break;
  case Func: func_delete(value->func_val); break;
  };
  as_free(value);
}

/*
 List
*/

void list_add(void ***ptab, int *num_ptr, void *data)
{
  int num = *num_ptr;
  int num_alloc = 1;
  void **pp = *ptab;

  // Every power of two we double array size
  if ((num & (num - 1)) == 0) {
    if (num) num_alloc = num * 2;
    pp = (void**)as_realloc(pp, num_alloc * sizeof(void*));
    *ptab = pp;
  }
  pp[num++] = data;
  *num_ptr = num;
}

void list_reset(void ***ptab, int *n)
{
  void **tab = *ptab;
  if (tab != 0) {
    void **p;
    for (p = tab; *n; ++p, --*n)
      if (*p) as_free(*p);
    as_free(tab);
    *(void**)ptab = 0;
  }
}

/*
 Map
*/

MapNode* getParent(MapNode* n)
{
  return n == 0 ? 0 : n->parent;
}

MapNode* getGrandParent(MapNode* n)
{
  return getParent(getParent(n));
}

MapNode* getSibling(MapNode* n) {
  MapNode* p = getParent(n);

  // No parent means no sibling.
  if (p == 0) { return 0; }

  if (n == p->left) {
    return p->right;
  } else {
    return p->left;
  }
}

MapNode* getUncle(MapNode* n) {
  MapNode* p = getParent(n);

  // No parent means no uncle
  return getSibling(p);
}

void rotateLeft(MapNode* n) {
  MapNode* nnew = n->right;
  MapNode* p = getParent(n);
  // assert(nnew != 0);  // Since the leaves of a red-black tree are empty,
                            // they cannot become internal nodes.
  n->right = nnew->left;
  nnew->left = n;
  n->parent = nnew;
  // Handle other child/parent pointers.
  if (n->right != 0) {
    n->right->parent = n;
  }

  // Initially n could be the root.
  if (p != 0) {
    if (n == p->left) {
      p->left = nnew;
    } else if (n == p->right) {
      p->right = nnew;
    }
  }
  nnew->parent = p;
}

void rotateRight(MapNode* n) {
  MapNode* nnew = n->left;
  MapNode* p = getParent(n);
  // assert(nnew != 0);  // Since the leaves of a red-black tree are empty,
                            // they cannot become internal nodes.

  n->left = nnew->right;
  nnew->right = n;
  n->parent = nnew;

  // Handle other child/parent pointers.
  if (n->left != 0) {
    n->left->parent = n;
  }

  // Initially n could be the root.
  if (p != 0) {
    if (n == p->left) {
      p->left = nnew;
    } else if (n == p->right) {
      p->right = nnew;
    }
  }
  nnew->parent = p;
}

/*
 Insertion
*/

void insertRepairTree(MapNode* n)
{
  if (getParent(n) == 0) {
    n->color = BLACK;
  } else if (getParent(n)->color == BLACK) {
    return;
  } else if ((getUncle(n) != 0) && (getUncle(n)->color == RED)) {
    getParent(n)->color = BLACK;
    getUncle(n)->color = BLACK;
    getGrandParent(n)->color = RED;
    insertRepairTree(getGrandParent(n));
  } else if (getGrandParent(n) == 0) {
    return;
  } else  {
    MapNode* p = getParent(n);
    MapNode* g = getGrandParent(n);
  
    if ((n == p->right) && (p == g->left)) {
      rotateLeft(p);
      n = n->left;
    } else if ((n == p->left) && (p == g->right)) {
      rotateRight(p);
      n = n->right;
    }

    p = getParent(n);
    g = getGrandParent(n);

    if (n == p->left) {
      rotateRight(g);
    } else {
      rotateLeft(g);
    }
    p->color = BLACK;
    g->color = RED;
  }
}

void insertRecurse(MapNode* root, MapNode* n) {
  // Recursively descend the tree until a leaf is found.
  if (root != 0) {
    if (strncmp(n->key, root->key, MAX_LABEL) < 0) {
      if (root->left != 0) {
        insertRecurse(root->left, n);
        return;
      } else {
        root->left = n;
      }
    } else { // n->key >= root->key
      if (root->right != 0) {
        insertRecurse(root->right, n);
        return;
      } else {
        root->right = n;
      }
    }
  }

  // Insert new Node n.
  n->parent = root;
  // n->left = 0;
  // n->right = 0;
  // n->color = RED;
}

MapNode* insert(MapNode* root, MapNode* n) {
  insertRecurse(root, n);
  insertRepairTree(n);

  // Find the new root to return.
  root = n;
  while (getParent(root) != 0) {
    root = getParent(root);
  }
  return root;
}

MapNode *map_find(MapNode *map, const char *key)
{
  if (map != 0) {
    int r = strncmp(map->key, key, MAX_LABEL);
    if (r > 0) return map_find(map->left, key);
    else if (r == 0) return map;
    else return map_find(map->right, key);
  }
  return 0;
}

/*
 Public
*/

MapNode *map_set(MapNode *map, const char *key, Value *value)
{
  MapNode* nnew = map_find(map, key);
  if (nnew == 0) {
    nnew = (MapNode *)as_mallocz(sizeof(struct MapNode));
    nnew->key = key;
    if (map) map = insert(map, nnew); else map = nnew;
  } else {
    value_delete(nnew->value);
  }
  nnew->value = value;
  return map;
}

MapNode *map_set_anon(MapNode *map, Value *value)
{
  MapNode *nnew = (MapNode *)as_mallocz(sizeof(struct MapNode));
  char *key = (char *)as_malloc(10);
  sprintf(key, "anon%d", map_count(map));
  nnew->key = key;
  nnew->value = value;
  if (map) map = insert(map, nnew); else map = nnew;
  return map;
}

Value *map_get(MapNode *map, const char *key)
{
  MapNode *node = map_find(map, key);
  if (node != 0) { return node->value; }
  return 0;
}

int map_count(MapNode *map)
{
  if (map == 0) return 0;
  return 1 + map_count(map->left) + map_count(map->right);
}

void map_delete(MapNode *map)
{
  if (map->left != 0) map_delete(map->left);
  if (map->right != 0) map_delete(map->right);
  value_delete(map->value);
  as_free(map);
}

void buf_add(unsigned char **pbuf, ELF_Word *num_ptr, unsigned char *data, ELF_Word size)
{
  int num = *num_ptr;
  int num_alloc = 1;
  unsigned char *pp = *pbuf;
  int i;
  
  // Every power of two we double array size
  if ((num & (num - 1)) == 0) {
    if (num) num_alloc = num * 2;
    while (num_alloc < (num + size)) num_alloc = num_alloc * 2;
    pp = (unsigned char *)as_realloc(pp, num_alloc * sizeof(unsigned char));
    *pbuf = pp;
  }
  for (i = 0; i < size; i++)
    pp[num++] = data[i];
  *num_ptr = num;
}

void buf_add_char(unsigned char **pbuf, ELF_Word *num_ptr, char data)
{
  unsigned char *buf = (unsigned char *)&data;
  buf_add(pbuf, num_ptr, buf, 1);
}

void buf_add_short(unsigned char **pbuf, ELF_Word *num_ptr, short data)
{
  unsigned char *buf = (unsigned char *)&data;
  buf_add(pbuf, num_ptr, buf, 2);
}

void buf_add_int(unsigned char **pbuf, ELF_Word *num_ptr, int data)
{
  unsigned char *buf = (unsigned char *)&data;
  buf_add(pbuf, num_ptr, buf, 4);
}

void buf_add_long(unsigned char **pbuf, ELF_Word *num_ptr, long data)
{
  unsigned char *buf = (unsigned char *)&data;
  buf_add(pbuf, num_ptr, buf, 8);
}

void buf_add_string(unsigned char **pbuf, ELF_Word *num_ptr, char* data)
{
  unsigned char *buf = (unsigned char *)&data;
  buf_add(pbuf, num_ptr, buf, strlen(data) + 1);
}


void buf_reset(unsigned char **pbuf, ELF_Word *num_ptr)
{
  unsigned char *buf = *pbuf;
  if (buf != 0) {
    as_free(buf);
    *pbuf = 0;
    *num_ptr = 0;
  }
}

void macro_delete(MacroDef *macro)
{
  macro->num_instrs = 0;
  as_free(macro->instrs);
  as_free(macro);
}



