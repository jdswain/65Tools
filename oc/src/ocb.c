#include "ocb.h"

void base_init(void) {
}

void base_export(char *module, bool newSF, long key) {
}

struct Object *base_NewObj(char *id, int class) {
  struct Object *new;
  struct Object *x;

  x = topScope;
  while ((x->next != 0) && (strcmp(x->next->name,id) == 0)) {
	x = x->next;
  }
  if (x->next == 0) {
	new = malloc(sizeof(struct Object));
	new->name = id; /* ToDo: copy? */
	new->class = class;
	new->next = 0;
	new->rdo = false;
	new->dsc = 0;
	x->next = new;
	return new;
  } else {
	scanner_mark("mult def");
	return x->next;
  }
}

struct Object *base_thisObj(void) {
}

struct Object *base_thisimport(struct Object mod) {
}

struct Object *base_thisfield(struct Type rec) {
}

void base_openScope(void) {
}

void base_closeScope(void) {
}


struct Type *base_type(int ref, int form, long size) {
}

void base_enter(char *name, int cl, struct Type *type, long n) {
}
