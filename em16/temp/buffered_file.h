#ifndef Buffered_File_H
#define Buffered_File_H

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>

/*
BufferedFile

Reads source code a line at a time while keeping track of file position.

A BufferedFile allows for nesting for include files.
*/

#define MAX_PATH 1024
#define IO_BUF_SIZE 4096

#define CH_EOB (-2)
#define CH_EOF (-1)

#ifdef _WIN32
#define PathSep ';'
#else
#define PathSep ':'
#endif

enum FileType {
  FileNone = 0,
  FileExecutable, /*  */
  FileAsmSrc,     /* .s, .asm */
  FileCHeader,    /* .h */
  FileCSrc,       /* .c */
  FileObject,     /* .o */
  FileLib,        /* .lib */
  FileDylib,      /* .dylib */
  FileS19,        /* .srec */
  FileS28,        /* .srec */
  FileS37,        /* .srec */
  FileIntel,      /* .hex */
  FileTIM,        /* .tim */
  FileBinary,     /* .bin */
  FileLinkMap,    /* .map */
  FileUnknown,
};
typedef enum FileType FileType;

typedef struct BufferedFile {
  uint8_t *buf_ptr;
  uint8_t *buf_end;
  int fd;
  struct BufferedFile *prev;
  int line_num;
  int line_pos;
  char filename[MAX_PATH];
  unsigned char buffer[IO_BUF_SIZE + 1]; // Extra char for CH_EOB character
} BufferedFile;

extern BufferedFile *file; // The current file

extern int total_lines;
extern int total_bytes;
  
int bf_open(const char* filename);
int bf_memory(const char* filename, int len);
void bf_close(void);

char bf_next(void);
int bf_line(void);
int bf_pos(void);

void as_error(const char *message, ...);
void as_warn(const char *message, ...);

FileType as_file_type(const char *filename);

#endif

