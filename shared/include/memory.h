#ifndef MEMORY_H
#define MEMORY_H

// Memory Management

#define free(ptr) use_as_free(ptr)
#define malloc(ptr) use_as_malloc(ptr)
#define realloc(ptr,size) use_as_realloc(ptr,size)

void as_free(void *ptr);
void *as_malloc(unsigned long size);
void *as_mallocz(unsigned long size);
void *as_realloc(void *ptr, unsigned long size);
char *as_strdup(const char *str);
void as_memstats(void);

#endif
