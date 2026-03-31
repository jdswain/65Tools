#include "elf_file.h"

#include <stdlib.h>
#include <stdio.h>

void assert(const char* msg, unsigned char predicate) {
  if( !predicate ) printf("%s\n", msg);
}

void testCreate(void) {
  elf_context_t* context = elf_create("myapp");
  elf_write(context);
  elf_release(context);
}

void testRead(void) {
  elf_context_t* context = elf_read("myapp");
  assert("read failed", context != 0);
  elf_release(context);
}

int main(int argc, char** argv) {
  testCreate();
  testRead();
  exit(0);
}
