#include "interp.h"

#include "scanner.h"
#include "memory.h"
#include "buffered_file.h" // For as_error
#include "codegen.h"

void interp_interp(Op **instrs, int num_instrs, bool exec[16], int exec_level, bool last_exec);

Object **stack;
int num_stack_entries;
int stack_pointer;
int line_start;
FILE *list_file;
int out_addr;
bool macro_def; /* If we are defining a macro */

void stack_push(Object *value)
{
  object_retain(value);
  if (stack_pointer == num_stack_entries)
    object_list_add(&stack, &num_stack_entries, value);
  else
    stack[stack_pointer] = value;
  stack_pointer += 1;

  char buffer[32];
  object_string((char *)&buffer, value);
  // printf("Stack push [%d] %s\n", stack_pointer, buffer);
}

/* This is the current non-local label for the assembler */
/* It is basically the scope. */
Object *current_label = 0;

void stack_push_var(Object *label)
{
  Object *value = 0;
  if (label->is_local && (current_label == 0)) {
	as_warn("Local variable declared but not in label range.");
  }
  if (label->is_local && (current_label != 0)) {
	Object *parent = as_get_symbol(current_label->string_val);
  	value = map_get(parent->desc, label->string_val);
	/*
	if (value) {
	  //  printf("Get local: %s.%s", current_label->string_val, label->string_val);
	} else {
	  printf("Local not found: %s.%s\n", current_label->string_val, label->string_val);
	  map_print(parent->desc);
	}
	*/
  } else {
	char *str = as_strdup(label->string_val);
	char *token = strtok(str, ".");
	value = as_get_symbol(token);
	token = strtok(0, ".");
	while (token && value) {
	  value = map_get(value->desc, token);
	  token = strtok(0, ".");
	}
  }
  if (value) {
    stack_push(value);
	// printf("  Pushed var %s\n", label->string_val);
  } else {
	if( pass() == 0) {
	  printf("Undefined %svariable: %s\n", (label->is_local?"local ":""), label->string_val);
	}
	object_retain(&objectZero);
    stack_push(&objectZero);
  }
}

Object *stack_pop(void)
{
  stack_pointer -= 1;
  Object *value = stack[stack_pointer];
  stack[stack_pointer] = 0;
  // printf("Stack pop  [%d]\n", stack_pointer);

  return value;
}

void stack_pop_var(Object *value)
{
  Object *obj = stack_pop();
  as_define_symbol(as_strdup(value->string_val), obj);
  object_release(obj);
  char buffer[20];
  object_string((char *)&buffer, obj);
  // printf("  Popped var %s := %s\n", value->string_val, buffer);
}

Object *stack_top(void)
{
  return stack[stack_pointer];
}

void stack_dup(void)
{
  stack_push(object_retain(stack_top()));
  // printf("Stack dup  [%d]\n", stack_pointer);
}

void stack_delete(int count)
{
  if (count > 0) 
	while (count--) object_release(stack_pop());

  // printf("Stack del  [%d] %d\n", stack_pointer, count);
}

void stack_add(void)
{
  Object *r = stack_pop();
  Object *l = stack_pop();
  stack_push(object_add(l, r));
  object_release(l);
  object_release(r);
}

void stack_sub(void)
{
  Object *r = stack_pop();
  Object *l = stack_pop();
  stack_push(object_sub(l, r));
  object_release(l);
  object_release(r);
}

void stack_mul(void)
{
  Object *r = stack_pop();
  Object *l = stack_pop();
  stack_push(object_mul(l, r));
  object_release(l);
  object_release(r);
}

void stack_div(void)
{
  Object *r = stack_pop();
  Object *l = stack_pop();
  stack_push(object_div(l, r));
  object_release(l);
  object_release(r);
}

void stack_idiv(void)
{
  Object *r = stack_pop();
  Object *l = stack_pop();
  stack_push(object_idiv(l, r));
  object_release(l);
  object_release(r);
}

void stack_mod(void)
{
  Object *r = stack_pop();
  Object *l = stack_pop();
  stack_push(object_mod(l, r));
  object_release(l);
  object_release(r);
}

void stack_and(void)
{
  Object *r = stack_pop();
  Object *l = stack_pop();
  stack_push(object_and(l, r));
  object_release(l);
  object_release(r);
}

void stack_or(void)
{
  Object *r = stack_pop();
  Object *l = stack_pop();
  stack_push(object_or(l, r));
  object_release(l);
  object_release(r);
}

void stack_neg(void)
{
  Object *l = stack_pop();
  stack_push(object_neg(l));
  object_release(l);
}

void stack_not(void)
{
  Object *l = stack_pop();
  stack_push(object_not(l));
  object_release(l);
}

void stack_lowbyte(void)
{
  Object *l = stack_pop();
  stack_push(object_lowbyte(l));
  object_release(l);
}

void stack_highbyte(void)
{
  Object *l = stack_pop();
  stack_push(object_highbyte(l));
  object_release(l);
}

void stack_bankbyte(void)
{
  Object *l = stack_pop();
  stack_push(object_bankbyte(l));
  object_release(l);
}

void stack_equal(void)
{
  Object *r = stack_pop();
  Object *l = stack_pop();
  stack_push(object_equal(l, r));
  object_release(l);
  object_release(r);
}

void stack_notequal(void)
{
  Object *r = stack_pop();
  Object *l = stack_pop();
  stack_push(object_notequal(l, r));
  object_release(l);
  object_release(r);
}

void stack_greaterthan(void)
{
  Object *r = stack_pop();
  Object *l = stack_pop();
  stack_push(object_greaterthan(l, r));
  object_release(l);
  object_release(r);
}

void stack_greaterthanequal(void)
{
  Object *r = stack_pop();
  Object *l = stack_pop();
  stack_push(object_greaterthanequal(l, r));
  object_release(l);
  object_release(r);
}

void stack_lessthan(void)
{
  Object *r = stack_pop();
  Object *l = stack_pop();
  stack_push(object_lessthanequal(l, r));
  object_release(l);
  object_release(r);
}

void stack_lessthanequal(void)
{
  Object *r = stack_pop();
  Object *l = stack_pop();
  stack_push(object_lessthanequal(l, r));
  object_release(l);
  object_release(r);
}

void stack_leftshift(void)
{
  Object *r = stack_pop();
  Object *l = stack_pop();
  stack_push(object_leftshift(l, r));
  object_release(l);
  object_release(r);
}

void stack_rightshift(void)
{
  Object *r = stack_pop();
  Object *l = stack_pop();
  stack_push(object_rightshift(l, r));
  object_release(l);
  object_release(r);
}

void set_title(void)
{
  Object *title = stack_pop();
  as_define_symbol("title", title);
}

void set_subheading(void)
{
  Object *subheading = stack_pop();
  as_define_symbol("subheading", subheading);
}

void set_page(void)
{
  if (list_file) {
	Object *title = as_get_symbol("title");
	Object *subheading = as_get_symbol("subheading");

	fprintf(list_file, "\f"); /* Form Feed */
	if (title) fprintf(list_file, "%s\n", title->string_val);
	if (subheading) fprintf(list_file, "%s\n", subheading->string_val);
  }
}

void emit_instr(Op *op)
{
  Instr *instr = &(op->instr);
  int val0 = 0;
  int val1 = 0;
  int val2 = 0;
  int params = codegen_params(instr);
  if (params > 0) {
    Object *v = stack_pop();
    if (v->type == typeInt) {
      val0 = v->int_val;
    } else if (v->type->form == ProcForm) {
      val0 = v->addr;
    } else if (v->mode == Macro) {
      val0 = v->int_val;
    }
	object_release(v);
  }
  if (params > 1) { Object *v = stack_pop(); val1 = v->int_val; object_release(v); }
  if (params > 2) { Object *v = stack_pop(); val2 = v->int_val; object_release(v); }
  codegen_gen(op->filename, op->line_num, instr, val0, val1, val2);
}

void emit_text(Object *value, enum OpType type)
{
  int i, j;
  if (type == OpTextLen) {
    int l = 0;
    for (i = value->int_val; i > 0; --i) {
      Object *v = stack[stack_pointer-i];
	  if (v->type == typeInt) {
		l += (v->int_val > 0xff ? 2 : 0);
	  } else if (v->type == typeString) {
		// ToDo: This counts incorrectly as we need to work out escapes
		l += strlen(v->string_val);
	  } else {
		as_error("ToDo");
      }
    }
    codegen_byte(l);
  }

  char c;
  for (i = value->int_val; i > 0; --i) {
    Object *v = stack[stack_pointer-i];
	if (v->type == typeInt) {
      if (v->int_val > 0xff) codegen_byte(v->int_val >> 8);
      codegen_byte(v->int_val);
	} else if (v->type == typeString) {
      j = 0;
      while ((c = v->string_val[j++]) != 0) {
		if (c == '\\') {
		  //--i;
		  switch (v->string_val[j++]) {
		  case 0: break; // \ at end of string
		  case 'n': c = 0x0a; break;
		  case 't': c = 0x09; break;
		  case 'b': c = 0x08; break;
		  case 'r': c = 0x0d; break;
		  case 'a': c = 0x07; break;
		  case '\'': c = '\''; break;
		  case '\"': c = '\"'; break;
		  case '\\': c = '\\'; break;
		  case 'f': c = 0x0c; break;
		  case 'v': c = 0x0b; break;
		  case '0': c = 0x00; break;
		  case 'x':
			// ToDo: hex
			break;
		  }
		}
		if ((type == OpTextBit7) && (i == 1) && (v->string_val[j] == 0)) {
		  codegen_byte(c | 0x80);
		} else {
		  codegen_byte(c);
		}
      }
    }
  }
  if (type == OpTextZero) codegen_byte(0);
  stack_delete(value->int_val);
}

void print_byte(int line_start, int bytes, int i)
{
  if (list_file != 0) {
    if ((bytes > i) && (!section_is_bss(section))) {
      fprintf(list_file, "%02x ", section->data[line_start + i]);
    } else {
      fprintf(list_file, "   ");
    }
  }
}

void emit_line(Object *text, bool exec)
{
  int i = 0;
  
  if ((list_file != 0) && (pass() == 0)) {
	// printf("%s\n", text->string_val);
    int bytes = section->shdr->sh_size - line_start;
	if (!exec) bytes = 0; /* No code generated if not exec */
    fprintf(list_file, "%04x: ", out_addr);
    if (exec) { 
      for( i = 0; i < 6; i++ ) print_byte(line_start, bytes, i);
    } else {
      fprintf(list_file, "XX                ");
    }
    if (text->string_val != 0) {
	  fprintf(list_file, "%s", text->string_val);
	}
    while (i < bytes) {
      if (i > 0) fprintf(list_file, "\n");
      fprintf(list_file, "%04x: ", out_addr + i);
      for( int j = 0; j < 6; j++ ) print_byte(line_start + i, bytes - i, j);
      i = i + 6;
    }
	if (i > 6) fprintf(list_file, "\n");
    out_addr = codegen_here();
    line_start = section->shdr->sh_size;
  }
}

bool stack_if(void)
{
  bool result = false;
  Object *v = stack_pop();
  if (v->type == typeByte) {
	result = v->int_val != 0;
  } else if (v->type == typeBool) {
	result = v->int_val != 0;
  } else if (v->type == typeChar) {
	result = v->int_val != 0;
  } else if (v->type == typeInt) {
	result = v->int_val != 0;
  } else if (v->type == typeSet) {
	result = v->int_val != 0;
  } else if (v->type == typeReal) {
	result = v->real_val != 0;
  } else if (v->type == typeNoType) {
	result = false;
  } else if (v->type == typeString) {
	as_warn("string if, %s", v->string_val);
	result = true;
  } else {
	result = false;
  }
  object_release(v);
  return result;
};

void stack_error(Object *value)
{
  if (pass() == 0) {
    char buffer[MAX_LINE]; 
    char *p = (char *)&buffer;
    int i;
    for (i = value->int_val; i > 0; --i) {
      Object *v = stack[stack_pointer-i];
	  if (v->type == typeInt) {
        p += sprintf(p, "%d", (int)v->int_val);
	  } else if (v->type == typeString) {
		p += sprintf(p, "%s", v->string_val);
	  }
    }
    as_error(buffer);
  }
  stack_delete(value->int_val);
}

void stack_error_if(Object *value)
{
  if ((pass() == 0) && stack_if()) { // Only run on last pass
    as_error("%s", value->string_val);
  }
}

void stack_message(Object *value)
{
  if (pass() == 0) {
    int i;
    for (i = value->int_val; i > 0; --i) {
      Object *v = stack[stack_pointer-i];
	  if (v->type == typeByte) {
        printf("$%lx", v->int_val);
	  } else if (v->type == typeBool) {
        printf("$%lx", v->int_val);
	  } else if (v->type == typeChar) {
        printf("$%lx", v->int_val);
	  } else if (v->type == typeInt) {
        printf("$%lx", v->int_val);
	  } else if (v->type == typeReal) {
        printf("%f", v->real_val); 
	  } else if (v->type == typeString) {
        printf("%s", v->string_val);
      }
    }
    printf("\n");
  }
  stack_delete(value->int_val);
}

void stack_fill(Object *value)
{
  int i;
  // ToDo:
  // Object is number of params, first is bytes
  int pattern = value->int_val - 1;
  int bytes = stack[stack_pointer-value->int_val]->int_val;
  int x = pattern;
  for (i = 0; i < bytes; i++) {
    codegen_byte(stack[stack_pointer-x]->int_val);
    // printf("%02x ", stack[stack_pointer-x]->int_val);
    if (x == 1) x = pattern; else --x;
  }
  // printf("\n");
  stack_delete(value->int_val);
}

void set_label_impl(Object *label)
{
  Object *object = scope_find_object(label->string_val);
  if (object == 0) {
	object = object_new(Const, type_retain(typeInt));
	scope_add_object(label->string_val, object);
  }
  if (object->type->form == ProcForm) {
	object->addr = codegen_here();
  } else {
	object->int_val = codegen_here();
  }
}

/*
  Sets an object in the scope with the label name to the address 
*/
void set_label(Object *label)
{
  if (label->is_local && (current_label != 0)) {
	//	printf("Set label: %s(%lx).%s(%lx)\n", current_label->string_val, (unsigned long)current_label, label->string_val, (unsigned long)label);
	Object *current = scope_get_object(current_label->string_val);
	scope_push_object(current);
	set_label_impl(label);
	// map_print(current->desc);
	scope_pop();
  } else {
	//	printf("Set label: %s\n", label->string_val);
	object_release(current_label);
	current_label = object_retain(label);
	set_label_impl(label);
  }
}

void stack_byte(Object *count)
{
  char *cp;
  int c = count->int_val + 1;
  while (--c) {
    Object *v = stack[stack_pointer - c];
	if (v->type == typeReal) {
	  codegen_byte((int)v->real_val);
	} else if (v->type == typeString) {
      cp = v->string_val;
      while (*cp) codegen_byte(*cp++);
	} else {
	  codegen_byte(v->int_val);
	} 
  }
  stack_delete(count->int_val);
}

void stack_word(Object *count)
{
  if (count->int_val == 0) return;
  
  int c = count->int_val + 1;
  while (--c) {
    Object *v = stack[stack_pointer - c];
    codegen_word(v->int_val);
  }
  stack_delete(count->int_val);
}

void stack_macro_call(Object *name, bool exec[16], int exec_level, bool last_exec)
{
  MacroDef *macro = as_get_macro(name->string_val);
  // printf("Exec macro %s (stack %d)\n", name->string_val, stack_pointer);
  if (macro != 0) {
    interp_interp(macro->instrs, macro->num_instrs, exec, exec_level, last_exec);
    scope_pop();
    macro = 0;
  } else {
    as_error("Expected macro name");
  }
}

void scope_begin(Object* name)
{
  printf("Scope get %s\n", name->string_val);
  Object *value = scope_get_object(name->string_val);
  scope_push_object(value);
  value->addr = codegen_here(); /* Set the address */
}

void interp_interp(Op **instrs, int num_instrs, bool exec[16], int exec_level, bool last_exec)
{
  for (int i=0; i<num_instrs; i++) {
    Op *instr = instrs[i];
    if (instr->type == OpScopeEnd) {
	  // scope_pop();
      if (exec_level > 0) {
		last_exec = exec[exec_level];
		exec_level--;
      }
    } else if (instr->type == OpListLine) {
      emit_line(instr->value, last_exec);
    } else if (exec[exec_level]) {
      switch (instr->type) {
      case OpPush:             stack_push(instr->value); break;
      case OpPushVar:          stack_push_var(instr->value); break;
      case OpPop:              object_release(stack_pop()); break;
      case OpPopVar:           stack_pop_var(instr->value); break;
      case OpDup:              stack_dup(); break;
      case OpAdd:              stack_add(); break;
      case OpSub:              stack_sub(); break;
      case OpMul:              stack_mul(); break;
      case OpDiv:              stack_div(); break;
      case OpIDiv:             stack_idiv(); break;
      case OpMod:              stack_mod(); break;
      case OpAnd:              stack_and(); break;
      case OpOr:               stack_or(); break;
      case OpNeg:              stack_neg(); break;
      case OpNot:              stack_not(); break;
      case OpLowByte:          stack_lowbyte(); break;
      case OpHighByte:         stack_highbyte(); break;
      case OpBankByte:         stack_bankbyte(); break;
      case OpEqual:            stack_equal(); break;
      case OpNotEqual:         stack_notequal(); break;
      case OpGreaterThan:      stack_greaterthan(); break;
      case OpGreaterThanEqual: stack_greaterthanequal(); break;
      case OpLessThan:         stack_lessthan(); break;
      case OpLessThanEqual:    stack_lessthanequal(); break;
      case OpLeftShift:        stack_leftshift(); break;
      case OpRightShift:       stack_rightshift(); break;
      case OpEmit:             emit_instr(instr); break;
      case OpIfBegin:
		exec_level++; exec[exec_level] = stack_if(); break;
      case OpElseBegin:
		exec_level++; exec[exec_level] = !last_exec; break;
      case OpElseIfBegin:
		exec_level++; exec[exec_level] = stack_if(); break;
      case OpJump:             break;
      case OpScopeBegin:       scope_begin(instr->value); exec_level++; exec[exec_level] = true; break;
      case OpError:            stack_error(instr->value); break;
      case OpErrorIf:          stack_error_if(instr->value); break;
      case OpMessage:          stack_message(instr->value); break;
      case OpLabel:            set_label(instr->value); break;
      case OpFillByte:         stack_fill(instr->value); break;
      case OpFillWord:         stack_fill(instr->value); break;
      case OpFillLong:         stack_fill(instr->value); break;
      case OpConCat:           /* ToDo */ break;
      case OpByte:             stack_byte(instr->value); break;
      case OpWord:             stack_word(instr->value); break;
      case OpLong:             /* ToDo */ break;
      case OpFloat:            break;
      case OpDouble:           /* ToDo */ break;
      case OpText:             emit_text(instr->value, OpText); break;
      case OpTextBit7:         emit_text(instr->value, OpTextBit7); break;
      case OpTextLen:          emit_text(instr->value, OpTextLen); break;
      case OpTextZero:         emit_text(instr->value, OpTextZero); break;
      case OpScopeEnd:         /* Already handled above */ break;
      case OpListLine:         /* Already handled above */ break;
      case OpMacroCall:        stack_macro_call(instr->value, exec, exec_level, last_exec); break;
      case OpTitle:            set_title(); break; 
      case OpSubheading:       set_subheading(); break;
      case OpPageBreak:        set_page(); break;
      } // Switch
      if (instr->type == OpJump) {
	i = 100;
      } // If
      last_exec = exec[exec_level];
    } // If
  } // For
}

int interp_run(const char *filename)
{
  int code_len = 0;
  char buf[MAX_PATH];
  
  elf_section_t **s = elf_context->sections;
  while (scope->parent != 0) scope = scope->parent;
  
  if ((pass() == 0) && (filename != 0)) {
    printf("Final Pass\n");

    strncpy(buf, filename, MAX_PATH);
    char *index = strrchr(buf, '.');
    strcpy(index, ".lst");
    printf("  Listing file is '%s'\n", buf);
    list_file = fopen(buf, "w");
    if (list_file == 0) perror("Listing File");
  } else {
    printf("Pass %d\n", pass());
    list_file = 0;
  }
  
  for (int si = 0; si < elf_context->ehdr->e_shnum; si++) {
    section = *s++;
    if (section->num_instrs > 0) { // Only process sections with code in them

      if (pass() == 0)
	printf("  Section %s, %d instructions.\n", elf_string_get(elf_context->shstrtab, section->shdr->sh_name), section->num_instrs);

      line_start = 0;
      long addr = section->shdr->sh_addr;
      out_addr = addr;
      pc = 0;
      stack = 0;
      macro_def = false;
      dpage = 0;
      dbreg = 0;
      pbreg = 0;
      num_stack_entries = 0;
      stack_pointer = 0;

      // Reset all state to default values for each pass to ensure consistency
      codegen_setlonga(false);
      codegen_setlongi(false);
      
      // Clear all output buffers
      buf_reset(&(section->data), &(section->shdr->sh_size));
      
      bool exec[16];
      exec[0] = true;

      interp_interp(section->instrs, section->num_instrs, exec, 0, true);
      
      code_len += section->shdr->sh_size;
      object_list_reset(&stack, &num_stack_entries);
    }
  }

  if (list_file != 0) {
    as_print_symbols(list_file);
    fclose(list_file);
  }
  // printf("Done\n");
  return code_len;
}

void interp_add(enum OpType type, Object *value)
{
  if (section == 0) return;
  
  Op *op = as_malloc(sizeof(Op));
  op->type = type;
  if (value != 0) 
    op->value = object_retain(value);
  else
    op->value = 0;
  if (file != 0) {
    op->line_num = file->line_num;
    op->filename = as_strdup(file->filename);
  } else {
    op->line_num = 0;
    op->filename = "";
  }
  if (macro_def == true) {
    list_add((void ***)&macro->instrs, &macro->num_instrs, op);
	//	printf("    in macro\n");
  } else {
    list_add((void ***)&section->instrs, &section->num_instrs, op);
  }
}

void interp_add_byte(char val) {
  if (section == 0) return;
  
  Op *op = as_malloc(sizeof(Op));
  op->type = OpPush;
  Object *valueObject = object_new(Const, typeByte);
  valueObject->int_val = val;
  op->value = valueObject;

  if (file != 0) {
    op->line_num = file->line_num;
    op->filename = as_strdup(file->filename);
  } else {
    op->line_num = 0;
    op->filename = "";
  }
  if (macro_def == true) {
    list_add((void ***)&macro->instrs, &macro->num_instrs, op);
  } else {
    list_add((void ***)&section->instrs, &section->num_instrs, op);
  }
}

void interp_add_word(int val) {
  if (section == 0) return;
  
  Op *op = as_malloc(sizeof(Op));
  op->type = OpPush;
  Object *valueObject = object_new(Const, typeInt);
  valueObject->int_val = val;
  op->value = valueObject;

  if (file != 0) {
    op->line_num = file->line_num;
    op->filename = as_strdup(file->filename);
  } else {
    op->line_num = 0;
    op->filename = "";
  }
  if (macro_def == true) {
	list_add((void ***)&macro->instrs, &macro->num_instrs, op); 
  } else {
     list_add((void ***)&section->instrs, &section->num_instrs, op); 
  } 
}

void interp_add_instr(OpCode instr, AddrMode mode, Modifier modifier)
{
  if (section == 0) return;

  Op *op = as_malloc(sizeof(Op));
  op->type = OpEmit;
  op->instr.opcode = instr;
  op->instr.mode = mode;
  op->instr.modifier = modifier;
  op->line_num = file->line_num;
  op->filename = as_strdup(file->filename);

  if (macro_def == true)  
	list_add((void ***)&macro->instrs, &macro->num_instrs, op); 
  else 
	list_add((void ***)&section->instrs, &section->num_instrs, op); 
}

void interp_macro_begin(char *label)
{
  macro = as_mallocz(sizeof(MacroDef));
  macro->num_params = 0;
  macro_def = true;
  printf("MACRO BEGIN %d\n", macro_def);
  as_define_macro(label, macro);
}

void interp_macro_end(void)
{
  macro_def = false;
  printf("MACRO END   %d\n", macro_def);
}

void interp_reset(void)
{
  // ToDo: Free all the values they are copies
  list_reset((void ***)&section->instrs, &section->num_instrs);
}



