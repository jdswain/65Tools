#include "value.h"

#include "memory.h"
//#include "func.h"
#include "buffered_file.h"
#include "oberongen.h"

#include <string.h>

/*
 Scope
*/
void scope_push(void)
{
  struct Scope *parent = section->scope;
  section->scope = as_malloc(sizeof(struct Scope));
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

Object *scope_get_value(const char* name)
{
  return map_get(section->scope->values, name);
}

void scope_set_value(const char* name, Object *value)
{
  section->scope->values = map_set(section->scope->values, name, value);
}

void scope_set_anon_value(Object *value)
{
  section->scope->values = map_set_anon(section->scope->values, value);
}

Object *object_new(const char *name, Form form)
{
  Object *obj = scope_get_value(name);
  if (obj == 0) {
	obj = as_mallocz(sizeof(Object));
	obj->form = form;
	obj->readonly = false;
	scope_set_value(name, obj);
  } else {
	as_error("Multiple definition");
  }
  return obj;
}

int object_storage(Form form)
{
  switch (form) {
  case ByteForm: return 1;
  case BoolForm: return 1;
  case CharForm: return 1;
  case IntForm: return 2;
  case RealForm: return 4;
  case PointerForm: return 4;
  case NilTypeForm: return 0;
  case NoTypeForm: return 0;
  case StringForm: return 4; // Pointer

  case ProcForm:
  case ArrayForm:
  case RecordForm:
  case List:
  case Map:
  case Macro:
  case Func:
    break;
  }
  as_error("value_storage called on complex type");
  return 0;
}

void object_print(FILE *file, const Object *value)
{
  switch(value->type->form) {
  case ByteForm: fprintf(file, "%2x", (char)value->int_val); break;
  case BoolForm: fprintf(file, "%2x", (char)value->int_val); break;
  case CharForm: fprintf(file, "%2x", (char)value->int_val); break;
  case IntForm: fprintf(file, "%4x", (int)value->int_val); break;
  case RealForm: fprintf(file, "%8f", value->real_val); break;
  case PointerForm: fprintf(file, "%8x", (int)value->int_val); break;
  case NilTypeForm: fprintf(file, "nil"); break;
  case NoTypeForm: fprintf(file, "void"); break;
  case ProcForm: fprintf(file, "[Proc]"); break;
  case StringForm: fprintf(file, "%.8s", value->string_val); break;
  case ArrayForm: fprintf(file, "[Array]"); break;
  case RecordForm: fprintf(file, "[Record]"); break;

  /* asm Types */
  case List: fprintf(file, "[List]"); break;
  case Map: fprintf(file, "[map]"); break;
  case Macro: fprintf(file, "[Macro]"); break;
  case Func: fprintf(file, "[Func]"); break;
  };
}

Object *value_dup(const Object *value)
{
  Object *v = as_mallocz(sizeof(Object));
  v->form = value->form;
  v->readonly = value->readonly;
  v->exported = value->exported;
  v->is_local = value->is_local; 
  switch (v->form) {
  case ByteForm: v->int_val = value->int_val; break;
  case BoolForm: v->int_val = value->int_val; break;
  case CharForm: v->int_val = value->int_val; break;
  case IntForm: v->int_val = value->int_val; break;
  case RealForm: v->real_val = value->real_val; break;
  case PointerForm: v->int_val = value->int_val; break;
  case NilTypeForm: v->int_val = value->int_val; break;
  case NoTypeForm: v->int_val = value->int_val; break;
  case ProcForm: v->func_val = value->func_val; break;
  case StringForm: v->string_val = as_strdup(value->string_val); break;
  case ArrayForm:
  case RecordForm:

  /* asm Types */
  case List:
  case Map:
  case Macro:
  case Func:
	break;
  }
  return v;
}

Object *value_add(const Object *l, const Object *r)
{
  Object *result = as_mallocz(sizeof(Object));
  result->form = IntForm;
  result->int_val = l->int_val + r->int_val;
  return result;
}

Object *value_sub(const Object *l, const Object *r)
{
  Object *result = as_mallocz(sizeof(Object));
  result->form = IntForm;
  result->int_val = l->int_val - r->int_val;
  return result;
}

Object *value_mul(const Object *l, const Object *r)
{
  Object *result = as_mallocz(sizeof(Object));
  result->form = IntForm;
  result->int_val = l->int_val * r->int_val;
  return result;

}

Object *value_div(const Object *l, const Object *r)
{
  Object *result = as_mallocz(sizeof(Object));
  result->form = IntForm;
  result->int_val = l->int_val / r->int_val;
  return result;

}

Object *value_idiv(const Object *l, const Object *r)
{
  Object *result = as_mallocz(sizeof(Object));
  result->form = IntForm;
  result->int_val = l->int_val / r->int_val;
  return result;
}

Object *value_mod(const Object *l, const Object *r)
{
  Object *result = as_mallocz(sizeof(Object));
  result->form = IntForm;
  result->int_val = l->int_val % r->int_val;
  return result;
}

Object *value_and(const Object *l, const Object *r)
{
  Object *result = as_mallocz(sizeof(Object));
  result->form = IntForm;
  result->int_val = l->int_val & r->int_val;
  return result;
}

Object *value_or(const Object *l, const Object *r)
{
  Object *result = as_mallocz(sizeof(Object));
  result->form = IntForm;
  result->int_val = l->int_val | r->int_val;
  return result;
}

Object *value_not(const Object *l)
{
  Object *result = as_mallocz(sizeof(Object));
  result->form = IntForm;
  result->int_val = !(l->int_val);
  return result;

}

Object *value_lowbyte(const Object *l)
{
  Object *result = as_mallocz(sizeof(Object));
  result->form = IntForm;
  result->int_val = l->int_val & 0xff;
  return result;

}

Object *value_highbyte(const Object *l)
{
  Object *result = as_mallocz(sizeof(Object));
  result->form = IntForm;
  result->int_val = (l->int_val >> 8) & 0xff;
  return result;

}

Object *value_bankbyte(const Object *l)
{
  Object *result = as_mallocz(sizeof(Object));
  result->form = IntForm;
  result->int_val = (l->int_val >> 16) & 0xff;
  return result;

}

Object *value_neg(const Object *l)
{
  Object *result = as_mallocz(sizeof(Object));
  result->form = IntForm;
  result->int_val = -l->int_val;
  return result;
}

Object *value_equal(const Object *l, const Object *r)
{
  Object *result = as_mallocz(sizeof(Object));
  result->form = IntForm;
  result->int_val = l->int_val == r->int_val;
  return result;
}

Object *value_notequal(const Object *l, const Object *r)
{
  Object *result = as_mallocz(sizeof(Object));
  result->form = IntForm;
  result->int_val = l->int_val != r->int_val;
  return result;
}

Object *value_greaterthan(const Object *l, const Object *r)
{
  Object *result = as_mallocz(sizeof(Object));
  result->form = IntForm;
  result->int_val = l->int_val > r->int_val;
  return result;
}

Object *value_greaterthanequal(const Object *l, const Object *r)
{
  Object *result = as_mallocz(sizeof(Object));
  result->form = IntForm;
  result->int_val = l->int_val >= r->int_val;
  return result;
}

Object *value_lessthan(const Object *l, const Object *r)
{
  Object *result = as_mallocz(sizeof(Object));
  result->form = IntForm;
  result->int_val = l->int_val < r->int_val;
  return result;
}

Object *value_lessthanequal(const Object *l, const Object *r)
{
  Object *result = as_mallocz(sizeof(Object));
  result->form = IntForm;
  result->int_val = l->int_val <= r->int_val;
  return result;
}

Object *value_leftshift(const Object *l, const Object *r)
{
  Object *result = as_mallocz(sizeof(Object));
  result->form = IntForm;
  result->int_val = l->int_val << r->int_val;
  return result;
}

Object *value_rightshift(const Object *l, const Object *r)
{
  Object *result = as_mallocz(sizeof(Object));
  result->form = IntForm;
  result->int_val = l->int_val >> r->int_val;
  return result;
}

void value_reset(Object *value)
{
  value->form = NoTypeForm;
  value->readonly = false;
  value->exported = false;
  value->is_local = false;
  value->int_val = 0;
}

void value_delete(Object *value)
{
  switch(value->form) {
  case ByteForm: break;
  case BoolForm: break;
  case CharForm: break;
  case IntForm: break;
  case RealForm: break;
  case PointerForm: break;
  case NilTypeForm: break;
  case NoTypeForm: break;
  case ProcForm: break;
  case StringForm: as_free(value->string_val); break;
  case ArrayForm: break;
  case RecordForm: break;
  case List: /* ToDo */ break;
  case Map: map_delete(value->map_val); break;
  case Macro: macro_delete(value->macro_val); break;
  case Func: break;
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
    pp = as_realloc(pp, num_alloc * sizeof(void*));
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

MapNode *map_set(MapNode *map, const char *key, Object *value)
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

MapNode *map_set_anon(MapNode *map, Object *value)
{
  MapNode *nnew = (MapNode *)as_mallocz(sizeof(struct MapNode));
  char *key = as_malloc(10);
  sprintf(key, "anon%d", map_count(map));
  nnew->key = key;
  nnew->value = value;
  if (map) map = insert(map, nnew); else map = nnew;
  return map;
}

Object *map_get(MapNode *map, const char *key)
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
    pp = as_realloc(pp, num_alloc * sizeof(unsigned char));
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

void insertDSymRecurse(DSymNode* root, DSymNode* n) {
  // Recursively descend the tree until a leaf is found.
  if (root != 0) {
    if (n->key < root->key) {
      if (root->left != 0) {
        insertDSymRecurse(root->left, n);
        return;
      } else {
        root->left = n;
      }
    } else { // n->key >= root->key
      if (root->right != 0) {
        insertDSymRecurse(root->right, n);
        return;
      } else {
        root->right = n;
      }
    }
  }
  n->parent = root;
}

DSymNode *dsym_add(DSymNode *dsym, long addr, char symType,  const char* value)
{
  DSymNode* nnew = as_mallocz(sizeof(DSymNode));
  nnew->key = addr;
  nnew->symType = symType;
  nnew->value = value;
  if (dsym == 0 ) return nnew;
  insertDSymRecurse(dsym, nnew);
  return dsym;
}

DSymNode *dsym_find(DSymNode *root, long addr)
{
  if (root == 0) return root;
  if (root->key == addr) return root;
  else if (root->key > addr) return dsym_find(root->left, addr);
  else /* if (root->key < addr) */ return dsym_find(root->right, addr);
}

/* Objects */

Object *thisImport(Object *mod, char *name)
{
  Object *obj = 0;
  if (mod->readonly) {
	obj = map_get(mod->desc, name);
  }
  return obj;
}

Object *thisField(Type *rec)
{
}

void makeFilename(void)
{
}

void thisModule(void)
{
}

void xread(void)
{
}

void inType(void)
{
}

void import(void)
{
}

void write(void)
{
}

void outType(void)
{
}

void export(void)
{
}

Item *makeItem(Object *y, long curlev)
{
  Item *item = as_malloc(sizeof(Item));
  /*
  item->mode = y->class;
  item->type = y->type;
  item->a = y->int_val;
  item->readonly = y->readonly;
  if (y->class = ClassPar) {
	x->b = 0;
  } else if ((y->class == ClassConst) && (y->type->form == FormString)) {
	x->b = y.lev; /* len * 
  } else {
	x->r = y->lev;
  }
  if ((y->lev > 0) && (y->lev != curlev) && (y->class != ClassConst)) {
	as_error("Not accessible");
  }
*/
  return item;
}
