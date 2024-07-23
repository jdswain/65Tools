#include "buffered_file.h"

#include <fcntl.h>
#include <libgen.h>
#include <stdarg.h>
#include <unistd.h>

#include <string.h> // temp
#include <errno.h>

#include "memory.h"

BufferedFile *file; // The current file

int total_lines;
int total_bytes;
int error_count;

void bf_init()
{
  total_lines = 0;
  total_bytes = 0;
  error_count = 0;
}

int bf_open(const char* filename)
{
  char cwd[100];
  if (getcwd(cwd, sizeof(cwd)) != NULL) {
    // printf("Current working dir: %s\n", cwd);
  }
      
  /* Open file */
  int fd = -1;
  if (strcmp(filename, "-") == 0) {
    fd = 0; filename = "stdin";
  } else {
    // We want to support relative paths here
    char *path = as_strdup(filename);
    dirname(path);
    const char *name = strrchr(filename, '/');
    if (name == 0) {
      name = filename; // No path attached
    } else {
      name++; // Move past the '/'
      if (chdir(path) != 0) {
		perror("Path not found");
      }
    }
    fd = open(name, O_RDONLY);
    if (fd == 0)
      fprintf( stdout, "Couldn't load file '%s'. Error %d is %s %d\n", filename, fd, strerror(errno), errno);
    as_free(path);
      
    //    if (getcwd(cwd, sizeof(cwd)) != NULL) {
    //      printf("Current working dir: %s\n", cwd);
    //    }
  }
  if (fd < 0) return -1;
  
  // Init
  struct BufferedFile *bf = as_malloc(sizeof(struct BufferedFile));
  bf->fd = fd;
  bf->buf_end = bf->buffer + IO_BUF_SIZE;
  bf->buf_end[0] = CH_EOB; // Lazy load
  bf->buf_ptr = bf->buf_end;
  strncpy(bf->filename, filename, sizeof(bf->filename));
  bf->line_num = 1;
  bf->line_pos = 1;
  bf->prev = file;
  strncpy(bf->pwd, cwd, 100);
  file = bf;

  return fd;
}

int bf_memory(const char* content, int len)
{
  if (len > IO_BUF_SIZE) return -1;
  
  struct BufferedFile *bf = as_malloc(sizeof(struct BufferedFile));

  // Init
  strncpy((char *)bf->buffer, content, IO_BUF_SIZE);
  bf->buf_ptr = bf->buffer;
  bf->buf_end = bf->buffer + len;
  bf->buf_end[0] = CH_EOF;
  strcpy(bf->filename, "memory");
  bf->line_num = 0;
  bf->line_pos = 0;
  bf->fd = -1;
  bf->pwd[0] = 0;
  bf->prev = file;
  file = bf;

  return len;
}

void bf_close(void) {
  if (file == 0) return;
  
  BufferedFile *bf = file;
  if (bf->fd > 0) {
    close(bf->fd);
    total_lines += bf->line_num;
  }
  if (bf->pwd[0] != 0) {
	int result = chdir(bf->pwd);
	if (result != 0) {
	  as_error("Failed to change directory when closing file");
	}
  }
  file = bf->prev;
  as_free(bf);
}

// Fill input buffer and peek next character
char bf_read(void) {
  struct BufferedFile* bf = file;

  if (bf->buf_ptr >= bf->buf_end) {
    int len = IO_BUF_SIZE;
    if (bf->fd != -1) {
      len = read(bf->fd, bf->buffer, len);
      if (len < 0) len = 0;
    } else {
      len = 0;
    }
    total_bytes += len;
    bf->buf_ptr = bf->buffer;
    bf->buf_end = bf->buffer + len;
    *(bf->buf_end) = CH_EOB;
  }
  if (bf->buf_ptr < bf->buf_end) {
    return bf->buf_ptr++[0];
  } else {
    bf->buf_ptr = bf->buf_end;
    return CH_EOF;
  }
}

char bf_next(void)
{
  if (file == 0) return CH_EOF;

  char ch = *((file->buf_ptr)++);

  if (ch == CH_EOB) {
	ch = bf_read();
  }

  while ((ch == CH_EOF) && (file != 0)) {
    bf_close();
    if (file != 0) {
      ch = *((file->buf_ptr)++);
      if (ch == CH_EOB) ch = bf_read();
    }
  }

  if (file != 0) {
    if (ch == 0x0A) { 
      file->line_num++; file->line_pos = 0;
    } else { 
      file->line_pos++;
    }
  }
  return ch;
}

int bf_line(void)
{
  return file->line_num;
}

int bf_pos(void)
{
  return file->line_pos; 
}

void as_gen_error(const char* filename, int line_num, const char* message, ...)
{
  va_list args;
  va_start(args, message);
  fprintf(stdout, "%s:%d: ", filename, line_num - 1);
  fprintf(stdout, "Error: ");
  vfprintf(stdout, message, args);
  fprintf(stdout, "\n");
  va_end(args);
}

void as_error(const char* message, ...)
{
  va_list args;
  va_start(args, message);
  if (file) 
    fprintf(stdout, "%s(%d,%d): ", file->filename, file->line_num - 1, file->line_pos);
  fprintf(stdout, "Error: ");
  vfprintf(stdout, message, args);
  fprintf(stdout, "\n");
  va_end(args);
  error_count++;
}


void as_gen_warn(const char* filename, int line_num, const char* message, ...) {
  va_list args;
  fprintf(stdout, "%s:%d: ", filename, line_num - 1);
  fprintf(stdout, "Warning: ");

  vfprintf(stdout, message, args);
  fprintf(stdout, "\n");
  va_end(args);
}

void as_warn(const char* message, ...)
{
  va_list args;
  va_start(args, message);
  if (file) 
    fprintf(stdout, "%s(%d,%d): ", file->filename, file->line_num - 1, file->line_pos);
  fprintf(stdout, "Warning: ");
  vfprintf(stdout, message, args);
  fprintf(stdout, "\n");
  va_end(args);
}

FileType as_file_type(const char *filename)
{
  const char *dot = strrchr(filename, '.');
  if (!dot || dot == filename) return FileExecutable; // No extension, means executable
  if (strcmp(dot, ".s") == 0) return FileAsmSrc;
  if (strcmp(dot, ".asm") == 0) return FileAsmSrc;
  if (strcmp(dot, ".h") == 0) return FileCHeader;
  if (strcmp(dot, ".Mod") == 0) return FileOberonSrc;
  if (strcmp(dot, ".mod") == 0) return FileOberonSrc;
  if (strcmp(dot, ".o") == 0) return FileObject;
  if (strcmp(dot, ".lib") == 0) return FileLib;
  if (strcmp(dot, ".dylib") == 0) return FileDylib;
  if (strcmp(dot, ".s19") == 0) return FileS19;
  if (strcmp(dot, ".s28") == 0) return FileS28;
  if (strcmp(dot, ".s37") == 0) return FileS37;
  if (strcmp(dot, ".hex") == 0) return FileIntel;
  if (strcmp(dot, ".tim") == 0) return FileTIM;
  if (strcmp(dot, ".bin") == 0) return FileBinary;
  if (strcmp(dot, ".map") == 0) return FileLinkMap;
  return FileUnknown;
}
