#include "value.h"

#include "memory.h"
//#include "func.h"
#include "buffered_file.h"
#include "oberongen.h"

#include <string.h>

Object* global_scope;

Object objectZero;
Object objectFalse;
Object objectTrue;

/* Oberon basic types, initialised in oberongen_init */
Type *typeByte;
Type *typeBool;
Type *typeChar;
Type *typeInt;
Type *typeReal;
Type *typeSet;
Type *typeNilType;
Type *typeNoType;
Type *typeString;
Type *typeProc;
Type *typeMod;

/* Assembler types */
Type *typeMap;
Type *typeMacro;

Type *type_make(int ref, Form form, int size)
{
  Type *type = as_malloc(sizeof(Type));
  type->form = form;
  type->size = size;
  type->ref = ref;
  return type;
}

void value_init(void)
{
  typeByte = type_make(ByteForm, ByteForm, 1); 
  typeBool = type_make(BoolForm, BoolForm, 1);
  typeChar = type_make(CharForm, CharForm, 1);
  typeInt = type_make(IntForm, IntForm, 2);
  typeReal = type_make(RealForm, RealForm, 4);
  typeSet = type_make(SetForm, SetForm, 2);
  typeNilType = type_make(NilTypeForm, NilTypeForm, 0);
  typeNoType = type_make(NoTypeForm, NoTypeForm, 0); 
  typeString = type_make(StringForm, StringForm, 4); /* A constant string */
  typeProc = type_make(ProcForm, ProcForm, 4);
  typeMod = type_make(ModForm, ModForm, 4);

  typeMap = type_make(MapForm, MapForm, 0); 
  typeMacro = type_make(MacroForm, MacroForm, 0);

  objectZero.type = typeInt;
  objectZero.int_val = 0;
  objectFalse.type = typeBool;
  objectFalse.int_val = 0;
  objectTrue.type = typeBool;
  objectTrue.int_val = 1;
}

/* 
 Type
*/
Type *type_new(void)
{
  Type *self = as_mallocz(sizeof(struct Type));
  self->ref_count = 1;
  return self;
}

Type *type_retain(Type *self)
{
  self->ref_count++;
  return self;
}

void type_release(Type *self)
{
  self->ref_count--;
  if (self->ref_count == 0) {
	/* ToDo: free sub objects */
	as_free(self);
  }
}

Object *scope;
int current_level;

void scope_push_object(Object *object)
{
  if (object->parent == scope) {
	scope = object;
	current_level++;
  } else {
	as_error("Attempt to push object that is not in current scope");
  }
}

void scope_pop()
{
  if (scope->parent != 0) {
	scope = scope->parent;
	current_level--;
  } else {
	as_error("Internal error: scope end without begin");
  }
}

Object *scope_get_object(const char* name)
{
  return map_get(scope->desc, name);
}

Object *scope_find_object(const char* name)
{
  Object *current = scope;
  Object *local = map_get(scope->desc, ".");
  if (local != 0) current = local;
  Object *object = map_get(current->desc, name);
  while ((object == 0) && (current->parent != 0)) {
	current = current->parent;
	object = map_get(current->desc, name);
  }
  return object;
}

void scope_add_object(const char *name, Object *object)
{
  // We now allow for replacing values
  object_retain(object);
  if (object->is_local) {
	Object *local = map_get(scope->desc, ".");
	if (local == 0) {
	  local = object_new(Const, typeMap);
	  scope->desc = map_set(scope->desc, ".", local);
	  local->parent = scope;
	  local->level = current_level;
	}
	local->desc = map_set(local->desc, name, object);
	object->parent = local;
	object->level = current_level + 1;
  } else {
	Object *obj = map_get(scope->desc, name);
	if (obj == 0) {
	  scope->desc = map_set(scope->desc, name, object);
	} else {
	  object_release(object);
	  object_set(obj, object);
	}
	object->parent = scope;
	object->level = current_level;
  }
}
 
Object *object_new(Mode mode, Type *type)
{
  Object *obj = as_mallocz(sizeof(Object));
  obj->ref_count = 1;
  obj->mode = mode;
  obj->type = type_retain(type);
  obj->readonly = false;
  obj->is_local = false;
  return obj;
}

void object_print(FILE *file, const Object *value)
{
  if (value->type == typeByte) {
	fprintf(file, "  %02x", (char)value->int_val);
  } else if (value->type == typeBool) {
	fprintf(file, "  %02x", (char)value->int_val); 
  } else if (value->type == typeChar) {
	fprintf(file, "  %02x", (char)value->int_val);
  } else if (value->type == typeInt) {
	fprintf(file, "%04x", (int)value->int_val);
  } else if (value->type == typeReal) {
	fprintf(file, "%8f", value->real_val);
  } else if (value->type == typeNilType) {
	fprintf(file, " nil");
  } else if (value->type == typeNoType) {
	fprintf(file, "void");
  } else if (value->type == typeSet) {
	fprintf(file, "s %02x", (int)value->int_val);
  } else if (value->type == typeString) {
	fprintf(file, "%.8s", value->string_val);
  }
}

void object_string(char *buffer, const Object *value)
{
  if (value->type == typeByte) {
	sprintf(buffer, "%2x", (char)value->int_val);
  } else if (value->type == typeBool) {
	sprintf(buffer, "%2x", (char)value->int_val); 
  } else if (value->type == typeChar) {
	sprintf(buffer, "%2x", (char)value->int_val);
  } else if (value->type == typeInt) {
	sprintf(buffer, "%4x", (int)value->int_val);
  } else if (value->type == typeReal) {
	sprintf(buffer, "%8f", value->real_val);
  } else if (value->type == typeNilType) {
	sprintf(buffer, "nil");
  } else if (value->type == typeNoType) {
	sprintf(buffer, "void");
  } else if (value->type == typeSet) {
	sprintf(buffer, "set %2x", (int)value->int_val);
  } else if (value->type == typeString) {
	sprintf(buffer, "%.16s", value->string_val);
  }
}

Object *object_retain(Object *object)
{
  object->ref_count++;
  return object;
}

Object *object_copy(Object *value)
{
  Object *v = object_new(value->mode, value->type);
  v->readonly = value->readonly;
  v->exported = value->exported;
  v->is_local = value->is_local;

  if (v->type == typeByte) {
	v->int_val = value->int_val; 
  } else if (v->type == typeInt) {
	v->int_val = value->int_val;
  } else if (v->type == typeChar) {
	v->int_val = value->int_val;
  } else if (v->type == typeInt) {
	v->int_val = value->int_val;
  } else if (v->type == typeReal) {
	v->real_val = value->real_val;
  } else if (v->type == typeString) {
	v->string_val = as_strdup(value->string_val);
  }
  return v;
}

void object_set(Object *to, Object *from)
{
  to->readonly = from->readonly;
  to->exported = from->exported;
  to->is_local = from->is_local;

  if (to->type == typeByte) {
	to->int_val = from->int_val; 
  } else if (to->type == typeInt) {
	to->int_val = from->int_val;
  } else if (to->type == typeChar) {
	to->int_val = from->int_val;
  } else if (to->type == typeInt) {
	to->int_val = from->int_val;
  } else if (to->type == typeReal) {
	to->real_val = from->real_val;
  } else if (to->type == typeString) {
	to->string_val = as_strdup(from->string_val);
  }
  // Does not copy or merge desc
}
 
Object *object_add(const Object *l, const Object *r)
{
  Object *result = object_new(Const, typeInt);
  result->int_val = l->int_val + r->int_val;
  return result;
}

Object *object_sub(const Object *l, const Object *r)
{
  Object *result = object_new(Const, typeInt);
  result->int_val = l->int_val - r->int_val;
  return result;
}

Object *object_mul(const Object *l, const Object *r)
{
  Object *result = object_new(Const, typeInt);
  result->int_val = l->int_val * r->int_val;
  return result;

}

Object *object_div(const Object *l, const Object *r)
{
  Object *result = object_new(Const, typeInt);
  result->int_val = l->int_val / r->int_val;
  return result;

}

Object *object_idiv(const Object *l, const Object *r)
{
  Object *result = object_new(Const, typeInt);
  result->int_val = l->int_val / r->int_val;
  return result;
}

Object *object_mod(const Object *l, const Object *r)
{
  Object *result = object_new(Const, typeInt);
  result->int_val = l->int_val % r->int_val;
  return result;
}

Object *object_and(const Object *l, const Object *r)
{
  Object *result = object_new(Const, typeInt);
  result->int_val = l->int_val & r->int_val;
  return result;
}

Object *object_or(const Object *l, const Object *r)
{
  Object *result = object_new(Const, typeInt);
  result->int_val = l->int_val | r->int_val;
  return result;
}

Object *object_not(const Object *l)
{
  Object *result = object_new(Const, typeInt);
  result->int_val = !(l->int_val);
  return result;

}

Object *object_lowbyte(const Object *l)
{
  Object *result = object_new(Const, typeInt);
  result->int_val = l->int_val & 0xff;
  return result;

}

Object *object_highbyte(const Object *l)
{
  Object *result = object_new(Const, typeInt);
  result->int_val = (l->int_val >> 8) & 0xff;
  return result;

}

Object *object_bankbyte(const Object *l)
{
  Object *result = object_new(Const, typeInt);
  result->int_val = (l->int_val >> 16) & 0xff;
  return result;

}

Object *object_neg(const Object *l)
{
  Object *result = object_new(Const, typeInt);
  result->int_val = -l->int_val;
  return result;
}

Object *object_equal(const Object *l, const Object *r)
{
  Object *result = object_new(Const, typeInt);
  result->int_val = l->int_val == r->int_val;
  return result;
}

Object *object_notequal(const Object *l, const Object *r)
{
  Object *result = object_new(Const, typeInt);
  result->int_val = l->int_val != r->int_val;
  return result;
}

Object *object_greaterthan(const Object *l, const Object *r)
{
  Object *result = object_new(Const, typeInt);
  result->int_val = l->int_val > r->int_val;
  return result;
}

Object *object_greaterthanequal(const Object *l, const Object *r)
{
  Object *result = object_new(Const, typeInt);
  result->int_val = l->int_val >= r->int_val;
  return result;
}

Object *object_lessthan(const Object *l, const Object *r)
{
  Object *result = object_new(Const, typeInt);
  result->int_val = l->int_val < r->int_val;
  return result;
}

Object *object_lessthanequal(const Object *l, const Object *r)
{
  Object *result = object_new(Const, typeInt);
  result->int_val = l->int_val <= r->int_val;
  return result;
}

Object *object_leftshift(const Object *l, const Object *r)
{
  Object *result = object_new(Const, typeInt);
  result->int_val = l->int_val << r->int_val;
  return result;
}

Object *object_rightshift(const Object *l, const Object *r)
{
  Object *result = object_new(Const, typeInt);
  result->int_val = l->int_val >> r->int_val;
  return result;				  
}

void object_reset(Object *object)
{
  object->mode = Const;
  object->readonly = false;
  object->exported = false;
  object->is_local = false;
  object->int_val = 0;
}

void object_release(Object *value)
{
  if (value == 0) return;
  value->ref_count--;
  if (value->ref_count == 0) {
	if (value->type == typeString) {
	  as_free(value->string_val);
	} else if (value->type == typeMap) {
	  map_delete(value->map_val);
	} else if (value->type == typeMacro) {
	  macro_delete(value->macro_val);
	}
	type_release(value->type);
	as_free(value);
  }
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

void object_list_add(Object ***ptab, int *num_ptr, Object *data)
{
  int num = *num_ptr;
  int num_alloc = 1;
  Object **pp = *ptab;

  // Every power of two we double array size
  if ((num & (num - 1)) == 0) {
    if (num) num_alloc = num * 2;
    pp = as_realloc(pp, num_alloc * sizeof(void*));
    *ptab = pp;
  }
  pp[num++] = object_retain(data);
  *num_ptr = num;
}

void object_list_reset(Object ***ptab, int *n)
{
  Object **tab = *ptab;
  if (tab != 0) {
    Object **p;
    for (p = tab; *n; ++p, --*n)
      if (*p != 0) object_release(*p);
    *(Object**)ptab = 0;
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
For debugging
*/
void map_print(MapNode *map)
{
  if (map == 0) return;
  printf("%s\n", map->key);
  map_print(map->left);
  map_print(map->right);
}

/*
 Public
*/

MapNode *map_set(MapNode *map, const char *key, Object *value)
{
  MapNode* nnew = map_find(map, key);
  if (nnew == 0) {
    nnew = (MapNode *)as_mallocz(sizeof(struct MapNode));
    nnew->key = as_strdup(key); 
    if (map) map = insert(map, nnew); else map = nnew;
  } else {
    object_release(nnew->value);
  }
  nnew->value = object_retain(value);
  return map;
}

MapNode *map_set_anon(MapNode *map, Object *value)
{
  MapNode *nnew = (MapNode *)as_mallocz(sizeof(struct MapNode));
  char *key = as_malloc(10);
  sprintf(key, "anon%d", map_count(map));
  nnew->key = key;
  nnew->value = object_retain(value);
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
  object_release(map->value);
  as_free((void *)map->key);
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

void buf_add_char(unsigned char **pbuf, ELF_Word *num_ptr, const char data)
{
  unsigned char *buf = (unsigned char *)&data;
  buf_add(pbuf, num_ptr, buf, 1);
}

void buf_add_short(unsigned char **pbuf, ELF_Word *num_ptr, const short data)
{
  unsigned char *buf = (unsigned char *)&data;
  buf_add(pbuf, num_ptr, buf, 2);
}

void buf_add_int(unsigned char **pbuf, ELF_Word *num_ptr, const int data)
{
  unsigned char *buf = (unsigned char *)&data;
  buf_add(pbuf, num_ptr, buf, 4);
}

void buf_add_long(unsigned char **pbuf, ELF_Word *num_ptr, const long data)
{
  unsigned char *buf = (unsigned char *)&data;
  buf_add(pbuf, num_ptr, buf, 8);
}

void buf_add_string(unsigned char **pbuf, ELF_Word *num_ptr, const char* data)
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
	//	obj = map_get(mod->desc, name);
  }
  return obj;
}

Object *thisField(Type *rec)
{
  return 0;
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

void xwrite(void)
{
}

void outType(void)
{
}

void export(void)
{
}

