#include "memory.h"

#undef free
#undef malloc
#undef realloc

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Memory Management

#ifdef MEM_DEBUG
int mem_cur_size;
int mem_max_size;
unsigned malloc_usable_size(void*); // This is a GNU extension
#endif

void *as_malloc(unsigned long size)
{
  void *ptr = malloc(size);
  if (!ptr && size) printf("Memory full.\n");
#ifdef MEM_DEBUG
  mem_cur_size += malloc_usable_size(ptr);
  if (mem_cur_size > mem_max_size) mem_max_size = mem_cur_size;
#endif
  return ptr;
}

void *as_mallocz(unsigned long size)
{
  void *ptr = as_malloc(size);
  memset(ptr, 0, size);
  return ptr;
}

void* as_realloc(void *ptr, unsigned long size)
{
#ifdef MEM_DEBUG
  mem_cur_size -= malloc_usable_size(ptr);
#endif
  void *ptr1 = realloc(ptr, size);
  if (!ptr1 && size) printf("Memory full.\n");
#ifdef MEM_DEBUG
  mem_cur_size += malloc_usable_size(ptr1);
  if (mem_cur_size > mem_max_size) mem_max_size = mem_cur_size;
#endif
  return ptr1;
}
 
char *as_strdup(const char *str)
{
  if (str == 0) return 0;
  char *ptr = as_malloc(strlen(str) + 1);
  strcpy(ptr, str);
  return ptr;
}


void as_free(void *ptr)
{
#ifdef MEM_DEBUG
  mem_cur_size -= malloc_usable_size(ptr);
  printf("free %lx\n", (long)ptr);
#endif
  free(ptr);
}

void as_memstats(void)
{
#ifdef MEM_DEBUG
  printf("Memory: %d bytes, max %d bytes.\n", mem_cur_size, mem_max_size);
#endif
}

#define free(ptr) use_as_free(ptr)
#define malloc(ptr) use_as_malloc(ptr)
#define realloc(ptr,size) use_as_realloc(ptr,size)


