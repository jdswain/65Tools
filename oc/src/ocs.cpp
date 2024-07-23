# 0 "src/ocs.c"
# 0 "<built-in>"
# 0 "<command-line>"
# 1 "/usr/include/stdc-predef.h" 1 3 4
# 0 "<command-line>" 2
# 1 "src/ocs.c"



# 1 "include/ocs.h" 1



# 1 "/usr/lib/gcc/aarch64-linux-gnu/13/include/stdbool.h" 1 3 4
# 5 "include/ocs.h" 2
# 14 "include/ocs.h"
typedef enum {


# 1 "include/oc_tokens.h" 1


sARRAY,
sBEGIN,
sBY,
sCASE,
sCHAR,
sCONST,
sDIV,
sDO,
sELSE,
sELSIF,
sEND,
sEXIT,
sFALSE,
sFOR,
sIF,
sIMPORT,
sIN,
sIS,
sLOOP,
sMOD,
sMODULE,
sNIL,
sOF,
sOR,
sPOINTER,
sPROCEDURE,
sRECORD,
sREPEAT,
sRETURN,
sTHEN,
sTO,
sTRUE,
sTYPE,
sUNTIL,
sVAR,
sWHILE,
sWITH,

sIDENT,
sINTEGER,
sREAL,
sSTRING,
sPLUS,
sMINUS,
sAST,
sSLASH,
sTILDE,
sAND,
sPERIOD,
sCOMMA,
sSEMICOLON,
sBAR,
sLPAREN,
sRPAREN,
sLSQ,
sRSQ,
sLBRACE,
sRBRACE,
sBECOMES,
sCARET,
sEQL,
sNEQ,
sLSS,
sLEQ,
sGTR,
sGEQ,
sDOTDOT,
sCOLON,
sNULL,
sEOF,
# 18 "include/ocs.h" 2


} Symbol;




extern Symbol scanner_sym;
extern char scanner_id[];

extern int scanner_ival;
extern double scanner_rval;

extern int scanner_errcnt;

void scanner_init(void);
void scanner_start(void);
void scanner_next(void);
void scanner_mark(char *msg);
void scanner_copyId(char *dest);

char *token_to_string(Symbol val);
# 5 "src/ocs.c" 2

# 1 "/usr/include/string.h" 1 3 4
# 26 "/usr/include/string.h" 3 4
# 1 "/usr/include/aarch64-linux-gnu/bits/libc-header-start.h" 1 3 4
# 33 "/usr/include/aarch64-linux-gnu/bits/libc-header-start.h" 3 4
# 1 "/usr/include/features.h" 1 3 4
# 394 "/usr/include/features.h" 3 4
# 1 "/usr/include/features-time64.h" 1 3 4
# 20 "/usr/include/features-time64.h" 3 4
# 1 "/usr/include/aarch64-linux-gnu/bits/wordsize.h" 1 3 4
# 21 "/usr/include/features-time64.h" 2 3 4
# 1 "/usr/include/aarch64-linux-gnu/bits/timesize.h" 1 3 4
# 22 "/usr/include/features-time64.h" 2 3 4
# 395 "/usr/include/features.h" 2 3 4
# 502 "/usr/include/features.h" 3 4
# 1 "/usr/include/aarch64-linux-gnu/sys/cdefs.h" 1 3 4
# 576 "/usr/include/aarch64-linux-gnu/sys/cdefs.h" 3 4
# 1 "/usr/include/aarch64-linux-gnu/bits/wordsize.h" 1 3 4
# 577 "/usr/include/aarch64-linux-gnu/sys/cdefs.h" 2 3 4
# 1 "/usr/include/aarch64-linux-gnu/bits/long-double.h" 1 3 4
# 578 "/usr/include/aarch64-linux-gnu/sys/cdefs.h" 2 3 4
# 503 "/usr/include/features.h" 2 3 4
# 526 "/usr/include/features.h" 3 4
# 1 "/usr/include/aarch64-linux-gnu/gnu/stubs.h" 1 3 4




# 1 "/usr/include/aarch64-linux-gnu/bits/wordsize.h" 1 3 4
# 6 "/usr/include/aarch64-linux-gnu/gnu/stubs.h" 2 3 4


# 1 "/usr/include/aarch64-linux-gnu/gnu/stubs-lp64.h" 1 3 4
# 9 "/usr/include/aarch64-linux-gnu/gnu/stubs.h" 2 3 4
# 527 "/usr/include/features.h" 2 3 4
# 34 "/usr/include/aarch64-linux-gnu/bits/libc-header-start.h" 2 3 4
# 27 "/usr/include/string.h" 2 3 4






# 1 "/usr/lib/gcc/aarch64-linux-gnu/13/include/stddef.h" 1 3 4
# 214 "/usr/lib/gcc/aarch64-linux-gnu/13/include/stddef.h" 3 4

# 214 "/usr/lib/gcc/aarch64-linux-gnu/13/include/stddef.h" 3 4
typedef long unsigned int size_t;
# 34 "/usr/include/string.h" 2 3 4
# 43 "/usr/include/string.h" 3 4
extern void *memcpy (void *__restrict __dest, const void *__restrict __src,
       size_t __n) __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));


extern void *memmove (void *__dest, const void *__src, size_t __n)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));





extern void *memccpy (void *__restrict __dest, const void *__restrict __src,
        int __c, size_t __n)
    __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2))) __attribute__ ((__access__ (__write_only__, 1, 4)));




extern void *memset (void *__s, int __c, size_t __n) __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));


extern int memcmp (const void *__s1, const void *__s2, size_t __n)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));
# 80 "/usr/include/string.h" 3 4
extern int __memcmpeq (const void *__s1, const void *__s2, size_t __n)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));
# 107 "/usr/include/string.h" 3 4
extern void *memchr (const void *__s, int __c, size_t __n)
      __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));
# 141 "/usr/include/string.h" 3 4
extern char *strcpy (char *__restrict __dest, const char *__restrict __src)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));

extern char *strncpy (char *__restrict __dest,
        const char *__restrict __src, size_t __n)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));


extern char *strcat (char *__restrict __dest, const char *__restrict __src)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));

extern char *strncat (char *__restrict __dest, const char *__restrict __src,
        size_t __n) __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));


extern int strcmp (const char *__s1, const char *__s2)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));

extern int strncmp (const char *__s1, const char *__s2, size_t __n)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));


extern int strcoll (const char *__s1, const char *__s2)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));

extern size_t strxfrm (char *__restrict __dest,
         const char *__restrict __src, size_t __n)
    __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (2))) __attribute__ ((__access__ (__write_only__, 1, 3)));



# 1 "/usr/include/aarch64-linux-gnu/bits/types/locale_t.h" 1 3 4
# 22 "/usr/include/aarch64-linux-gnu/bits/types/locale_t.h" 3 4
# 1 "/usr/include/aarch64-linux-gnu/bits/types/__locale_t.h" 1 3 4
# 27 "/usr/include/aarch64-linux-gnu/bits/types/__locale_t.h" 3 4
struct __locale_struct
{

  struct __locale_data *__locales[13];


  const unsigned short int *__ctype_b;
  const int *__ctype_tolower;
  const int *__ctype_toupper;


  const char *__names[13];
};

typedef struct __locale_struct *__locale_t;
# 23 "/usr/include/aarch64-linux-gnu/bits/types/locale_t.h" 2 3 4

typedef __locale_t locale_t;
# 173 "/usr/include/string.h" 2 3 4


extern int strcoll_l (const char *__s1, const char *__s2, locale_t __l)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2, 3)));


extern size_t strxfrm_l (char *__dest, const char *__src, size_t __n,
    locale_t __l) __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (2, 4)))
     __attribute__ ((__access__ (__write_only__, 1, 3)));





extern char *strdup (const char *__s)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__malloc__)) __attribute__ ((__nonnull__ (1)));






extern char *strndup (const char *__string, size_t __n)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__malloc__)) __attribute__ ((__nonnull__ (1)));
# 246 "/usr/include/string.h" 3 4
extern char *strchr (const char *__s, int __c)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));
# 273 "/usr/include/string.h" 3 4
extern char *strrchr (const char *__s, int __c)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));
# 286 "/usr/include/string.h" 3 4
extern char *strchrnul (const char *__s, int __c)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));





extern size_t strcspn (const char *__s, const char *__reject)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));


extern size_t strspn (const char *__s, const char *__accept)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));
# 323 "/usr/include/string.h" 3 4
extern char *strpbrk (const char *__s, const char *__accept)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));
# 350 "/usr/include/string.h" 3 4
extern char *strstr (const char *__haystack, const char *__needle)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));




extern char *strtok (char *__restrict __s, const char *__restrict __delim)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (2)));



extern char *__strtok_r (char *__restrict __s,
    const char *__restrict __delim,
    char **__restrict __save_ptr)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (2, 3)));

extern char *strtok_r (char *__restrict __s, const char *__restrict __delim,
         char **__restrict __save_ptr)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (2, 3)));
# 380 "/usr/include/string.h" 3 4
extern char *strcasestr (const char *__haystack, const char *__needle)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));







extern void *memmem (const void *__haystack, size_t __haystacklen,
       const void *__needle, size_t __needlelen)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 3)))
    __attribute__ ((__access__ (__read_only__, 1, 2)))
    __attribute__ ((__access__ (__read_only__, 3, 4)));



extern void *__mempcpy (void *__restrict __dest,
   const void *__restrict __src, size_t __n)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));
extern void *mempcpy (void *__restrict __dest,
        const void *__restrict __src, size_t __n)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));




extern size_t strlen (const char *__s)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));




extern size_t strnlen (const char *__string, size_t __maxlen)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));




extern char *strerror (int __errnum) __attribute__ ((__nothrow__ , __leaf__));
# 432 "/usr/include/string.h" 3 4
extern int strerror_r (int __errnum, char *__buf, size_t __buflen) __asm__ ("" "__xpg_strerror_r") __attribute__ ((__nothrow__ , __leaf__))

                        __attribute__ ((__nonnull__ (2)))
    __attribute__ ((__access__ (__write_only__, 2, 3)));
# 458 "/usr/include/string.h" 3 4
extern char *strerror_l (int __errnum, locale_t __l) __attribute__ ((__nothrow__ , __leaf__));



# 1 "/usr/include/strings.h" 1 3 4
# 23 "/usr/include/strings.h" 3 4
# 1 "/usr/lib/gcc/aarch64-linux-gnu/13/include/stddef.h" 1 3 4
# 24 "/usr/include/strings.h" 2 3 4










extern int bcmp (const void *__s1, const void *__s2, size_t __n)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));


extern void bcopy (const void *__src, void *__dest, size_t __n)
  __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));


extern void bzero (void *__s, size_t __n) __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));
# 68 "/usr/include/strings.h" 3 4
extern char *index (const char *__s, int __c)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));
# 96 "/usr/include/strings.h" 3 4
extern char *rindex (const char *__s, int __c)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));






extern int ffs (int __i) __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__const__));





extern int ffsl (long int __l) __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__const__));
__extension__ extern int ffsll (long long int __ll)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__const__));



extern int strcasecmp (const char *__s1, const char *__s2)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));


extern int strncasecmp (const char *__s1, const char *__s2, size_t __n)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));






extern int strcasecmp_l (const char *__s1, const char *__s2, locale_t __loc)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2, 3)));



extern int strncasecmp_l (const char *__s1, const char *__s2,
     size_t __n, locale_t __loc)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2, 4)));



# 463 "/usr/include/string.h" 2 3 4



extern void explicit_bzero (void *__s, size_t __n) __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)))
    __attribute__ ((__access__ (__write_only__, 1, 2)));



extern char *strsep (char **__restrict __stringp,
       const char *__restrict __delim)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));




extern char *strsignal (int __sig) __attribute__ ((__nothrow__ , __leaf__));
# 489 "/usr/include/string.h" 3 4
extern char *__stpcpy (char *__restrict __dest, const char *__restrict __src)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));
extern char *stpcpy (char *__restrict __dest, const char *__restrict __src)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));



extern char *__stpncpy (char *__restrict __dest,
   const char *__restrict __src, size_t __n)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));
extern char *stpncpy (char *__restrict __dest,
        const char *__restrict __src, size_t __n)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2)));




extern size_t strlcpy (char *__restrict __dest,
         const char *__restrict __src, size_t __n)
  __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2))) __attribute__ ((__access__ (__write_only__, 1, 3)));



extern size_t strlcat (char *__restrict __dest,
         const char *__restrict __src, size_t __n)
  __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1, 2))) __attribute__ ((__access__ (__read_write__, 1, 3)));
# 552 "/usr/include/string.h" 3 4

# 7 "src/ocs.c" 2


# 1 "include/buffered_file.h" 1



# 1 "/usr/include/stdio.h" 1 3 4
# 27 "/usr/include/stdio.h" 3 4
# 1 "/usr/include/aarch64-linux-gnu/bits/libc-header-start.h" 1 3 4
# 28 "/usr/include/stdio.h" 2 3 4





# 1 "/usr/lib/gcc/aarch64-linux-gnu/13/include/stddef.h" 1 3 4
# 34 "/usr/include/stdio.h" 2 3 4


# 1 "/usr/lib/gcc/aarch64-linux-gnu/13/include/stdarg.h" 1 3 4
# 40 "/usr/lib/gcc/aarch64-linux-gnu/13/include/stdarg.h" 3 4
typedef __builtin_va_list __gnuc_va_list;
# 37 "/usr/include/stdio.h" 2 3 4

# 1 "/usr/include/aarch64-linux-gnu/bits/types.h" 1 3 4
# 27 "/usr/include/aarch64-linux-gnu/bits/types.h" 3 4
# 1 "/usr/include/aarch64-linux-gnu/bits/wordsize.h" 1 3 4
# 28 "/usr/include/aarch64-linux-gnu/bits/types.h" 2 3 4
# 1 "/usr/include/aarch64-linux-gnu/bits/timesize.h" 1 3 4
# 29 "/usr/include/aarch64-linux-gnu/bits/types.h" 2 3 4


typedef unsigned char __u_char;
typedef unsigned short int __u_short;
typedef unsigned int __u_int;
typedef unsigned long int __u_long;


typedef signed char __int8_t;
typedef unsigned char __uint8_t;
typedef signed short int __int16_t;
typedef unsigned short int __uint16_t;
typedef signed int __int32_t;
typedef unsigned int __uint32_t;

typedef signed long int __int64_t;
typedef unsigned long int __uint64_t;






typedef __int8_t __int_least8_t;
typedef __uint8_t __uint_least8_t;
typedef __int16_t __int_least16_t;
typedef __uint16_t __uint_least16_t;
typedef __int32_t __int_least32_t;
typedef __uint32_t __uint_least32_t;
typedef __int64_t __int_least64_t;
typedef __uint64_t __uint_least64_t;



typedef long int __quad_t;
typedef unsigned long int __u_quad_t;







typedef long int __intmax_t;
typedef unsigned long int __uintmax_t;
# 141 "/usr/include/aarch64-linux-gnu/bits/types.h" 3 4
# 1 "/usr/include/aarch64-linux-gnu/bits/typesizes.h" 1 3 4
# 142 "/usr/include/aarch64-linux-gnu/bits/types.h" 2 3 4
# 1 "/usr/include/aarch64-linux-gnu/bits/time64.h" 1 3 4
# 143 "/usr/include/aarch64-linux-gnu/bits/types.h" 2 3 4


typedef unsigned long int __dev_t;
typedef unsigned int __uid_t;
typedef unsigned int __gid_t;
typedef unsigned long int __ino_t;
typedef unsigned long int __ino64_t;
typedef unsigned int __mode_t;
typedef unsigned int __nlink_t;
typedef long int __off_t;
typedef long int __off64_t;
typedef int __pid_t;
typedef struct { int __val[2]; } __fsid_t;
typedef long int __clock_t;
typedef unsigned long int __rlim_t;
typedef unsigned long int __rlim64_t;
typedef unsigned int __id_t;
typedef long int __time_t;
typedef unsigned int __useconds_t;
typedef long int __suseconds_t;
typedef long int __suseconds64_t;

typedef int __daddr_t;
typedef int __key_t;


typedef int __clockid_t;


typedef void * __timer_t;


typedef int __blksize_t;




typedef long int __blkcnt_t;
typedef long int __blkcnt64_t;


typedef unsigned long int __fsblkcnt_t;
typedef unsigned long int __fsblkcnt64_t;


typedef unsigned long int __fsfilcnt_t;
typedef unsigned long int __fsfilcnt64_t;


typedef long int __fsword_t;

typedef long int __ssize_t;


typedef long int __syscall_slong_t;

typedef unsigned long int __syscall_ulong_t;



typedef __off64_t __loff_t;
typedef char *__caddr_t;


typedef long int __intptr_t;


typedef unsigned int __socklen_t;




typedef int __sig_atomic_t;
# 39 "/usr/include/stdio.h" 2 3 4
# 1 "/usr/include/aarch64-linux-gnu/bits/types/__fpos_t.h" 1 3 4




# 1 "/usr/include/aarch64-linux-gnu/bits/types/__mbstate_t.h" 1 3 4
# 13 "/usr/include/aarch64-linux-gnu/bits/types/__mbstate_t.h" 3 4
typedef struct
{
  int __count;
  union
  {
    unsigned int __wch;
    char __wchb[4];
  } __value;
} __mbstate_t;
# 6 "/usr/include/aarch64-linux-gnu/bits/types/__fpos_t.h" 2 3 4




typedef struct _G_fpos_t
{
  __off_t __pos;
  __mbstate_t __state;
} __fpos_t;
# 40 "/usr/include/stdio.h" 2 3 4
# 1 "/usr/include/aarch64-linux-gnu/bits/types/__fpos64_t.h" 1 3 4
# 10 "/usr/include/aarch64-linux-gnu/bits/types/__fpos64_t.h" 3 4
typedef struct _G_fpos64_t
{
  __off64_t __pos;
  __mbstate_t __state;
} __fpos64_t;
# 41 "/usr/include/stdio.h" 2 3 4
# 1 "/usr/include/aarch64-linux-gnu/bits/types/__FILE.h" 1 3 4



struct _IO_FILE;
typedef struct _IO_FILE __FILE;
# 42 "/usr/include/stdio.h" 2 3 4
# 1 "/usr/include/aarch64-linux-gnu/bits/types/FILE.h" 1 3 4



struct _IO_FILE;


typedef struct _IO_FILE FILE;
# 43 "/usr/include/stdio.h" 2 3 4
# 1 "/usr/include/aarch64-linux-gnu/bits/types/struct_FILE.h" 1 3 4
# 35 "/usr/include/aarch64-linux-gnu/bits/types/struct_FILE.h" 3 4
struct _IO_FILE;
struct _IO_marker;
struct _IO_codecvt;
struct _IO_wide_data;




typedef void _IO_lock_t;





struct _IO_FILE
{
  int _flags;


  char *_IO_read_ptr;
  char *_IO_read_end;
  char *_IO_read_base;
  char *_IO_write_base;
  char *_IO_write_ptr;
  char *_IO_write_end;
  char *_IO_buf_base;
  char *_IO_buf_end;


  char *_IO_save_base;
  char *_IO_backup_base;
  char *_IO_save_end;

  struct _IO_marker *_markers;

  struct _IO_FILE *_chain;

  int _fileno;
  int _flags2;
  __off_t _old_offset;


  unsigned short _cur_column;
  signed char _vtable_offset;
  char _shortbuf[1];

  _IO_lock_t *_lock;







  __off64_t _offset;

  struct _IO_codecvt *_codecvt;
  struct _IO_wide_data *_wide_data;
  struct _IO_FILE *_freeres_list;
  void *_freeres_buf;
  size_t __pad5;
  int _mode;

  char _unused2[15 * sizeof (int) - 4 * sizeof (void *) - sizeof (size_t)];
};
# 44 "/usr/include/stdio.h" 2 3 4


# 1 "/usr/include/aarch64-linux-gnu/bits/types/cookie_io_functions_t.h" 1 3 4
# 27 "/usr/include/aarch64-linux-gnu/bits/types/cookie_io_functions_t.h" 3 4
typedef __ssize_t cookie_read_function_t (void *__cookie, char *__buf,
                                          size_t __nbytes);







typedef __ssize_t cookie_write_function_t (void *__cookie, const char *__buf,
                                           size_t __nbytes);







typedef int cookie_seek_function_t (void *__cookie, __off64_t *__pos, int __w);


typedef int cookie_close_function_t (void *__cookie);






typedef struct _IO_cookie_io_functions_t
{
  cookie_read_function_t *read;
  cookie_write_function_t *write;
  cookie_seek_function_t *seek;
  cookie_close_function_t *close;
} cookie_io_functions_t;
# 47 "/usr/include/stdio.h" 2 3 4





typedef __gnuc_va_list va_list;
# 63 "/usr/include/stdio.h" 3 4
typedef __off_t off_t;
# 77 "/usr/include/stdio.h" 3 4
typedef __ssize_t ssize_t;






typedef __fpos_t fpos_t;
# 128 "/usr/include/stdio.h" 3 4
# 1 "/usr/include/aarch64-linux-gnu/bits/stdio_lim.h" 1 3 4
# 129 "/usr/include/stdio.h" 2 3 4
# 148 "/usr/include/stdio.h" 3 4
extern FILE *stdin;
extern FILE *stdout;
extern FILE *stderr;






extern int remove (const char *__filename) __attribute__ ((__nothrow__ , __leaf__));

extern int rename (const char *__old, const char *__new) __attribute__ ((__nothrow__ , __leaf__));



extern int renameat (int __oldfd, const char *__old, int __newfd,
       const char *__new) __attribute__ ((__nothrow__ , __leaf__));
# 183 "/usr/include/stdio.h" 3 4
extern int fclose (FILE *__stream) __attribute__ ((__nonnull__ (1)));
# 193 "/usr/include/stdio.h" 3 4
extern FILE *tmpfile (void)
  __attribute__ ((__malloc__)) __attribute__ ((__malloc__ (fclose, 1))) ;
# 210 "/usr/include/stdio.h" 3 4
extern char *tmpnam (char[20]) __attribute__ ((__nothrow__ , __leaf__)) ;




extern char *tmpnam_r (char __s[20]) __attribute__ ((__nothrow__ , __leaf__)) ;
# 227 "/usr/include/stdio.h" 3 4
extern char *tempnam (const char *__dir, const char *__pfx)
   __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__malloc__)) __attribute__ ((__malloc__ (__builtin_free, 1)));






extern int fflush (FILE *__stream);
# 244 "/usr/include/stdio.h" 3 4
extern int fflush_unlocked (FILE *__stream);
# 263 "/usr/include/stdio.h" 3 4
extern FILE *fopen (const char *__restrict __filename,
      const char *__restrict __modes)
  __attribute__ ((__malloc__)) __attribute__ ((__malloc__ (fclose, 1))) ;




extern FILE *freopen (const char *__restrict __filename,
        const char *__restrict __modes,
        FILE *__restrict __stream) __attribute__ ((__nonnull__ (3)));
# 298 "/usr/include/stdio.h" 3 4
extern FILE *fdopen (int __fd, const char *__modes) __attribute__ ((__nothrow__ , __leaf__))
  __attribute__ ((__malloc__)) __attribute__ ((__malloc__ (fclose, 1))) ;





extern FILE *fopencookie (void *__restrict __magic_cookie,
     const char *__restrict __modes,
     cookie_io_functions_t __io_funcs) __attribute__ ((__nothrow__ , __leaf__))
  __attribute__ ((__malloc__)) __attribute__ ((__malloc__ (fclose, 1))) ;




extern FILE *fmemopen (void *__s, size_t __len, const char *__modes)
  __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__malloc__)) __attribute__ ((__malloc__ (fclose, 1))) ;




extern FILE *open_memstream (char **__bufloc, size_t *__sizeloc) __attribute__ ((__nothrow__ , __leaf__))
  __attribute__ ((__malloc__)) __attribute__ ((__malloc__ (fclose, 1))) ;
# 333 "/usr/include/stdio.h" 3 4
extern void setbuf (FILE *__restrict __stream, char *__restrict __buf) __attribute__ ((__nothrow__ , __leaf__));



extern int setvbuf (FILE *__restrict __stream, char *__restrict __buf,
      int __modes, size_t __n) __attribute__ ((__nothrow__ , __leaf__));




extern void setbuffer (FILE *__restrict __stream, char *__restrict __buf,
         size_t __size) __attribute__ ((__nothrow__ , __leaf__));


extern void setlinebuf (FILE *__stream) __attribute__ ((__nothrow__ , __leaf__));







extern int fprintf (FILE *__restrict __stream,
      const char *__restrict __format, ...);




extern int printf (const char *__restrict __format, ...);

extern int sprintf (char *__restrict __s,
      const char *__restrict __format, ...) __attribute__ ((__nothrow__));





extern int vfprintf (FILE *__restrict __s, const char *__restrict __format,
       __gnuc_va_list __arg);




extern int vprintf (const char *__restrict __format, __gnuc_va_list __arg);

extern int vsprintf (char *__restrict __s, const char *__restrict __format,
       __gnuc_va_list __arg) __attribute__ ((__nothrow__));



extern int snprintf (char *__restrict __s, size_t __maxlen,
       const char *__restrict __format, ...)
     __attribute__ ((__nothrow__)) __attribute__ ((__format__ (__printf__, 3, 4)));

extern int vsnprintf (char *__restrict __s, size_t __maxlen,
        const char *__restrict __format, __gnuc_va_list __arg)
     __attribute__ ((__nothrow__)) __attribute__ ((__format__ (__printf__, 3, 0)));





extern int vasprintf (char **__restrict __ptr, const char *__restrict __f,
        __gnuc_va_list __arg)
     __attribute__ ((__nothrow__)) __attribute__ ((__format__ (__printf__, 2, 0))) ;
extern int __asprintf (char **__restrict __ptr,
         const char *__restrict __fmt, ...)
     __attribute__ ((__nothrow__)) __attribute__ ((__format__ (__printf__, 2, 3))) ;
extern int asprintf (char **__restrict __ptr,
       const char *__restrict __fmt, ...)
     __attribute__ ((__nothrow__)) __attribute__ ((__format__ (__printf__, 2, 3))) ;




extern int vdprintf (int __fd, const char *__restrict __fmt,
       __gnuc_va_list __arg)
     __attribute__ ((__format__ (__printf__, 2, 0)));
extern int dprintf (int __fd, const char *__restrict __fmt, ...)
     __attribute__ ((__format__ (__printf__, 2, 3)));







extern int fscanf (FILE *__restrict __stream,
     const char *__restrict __format, ...) ;




extern int scanf (const char *__restrict __format, ...) ;

extern int sscanf (const char *__restrict __s,
     const char *__restrict __format, ...) __attribute__ ((__nothrow__ , __leaf__));





# 1 "/usr/include/aarch64-linux-gnu/bits/floatn.h" 1 3 4
# 23 "/usr/include/aarch64-linux-gnu/bits/floatn.h" 3 4
# 1 "/usr/include/aarch64-linux-gnu/bits/long-double.h" 1 3 4
# 24 "/usr/include/aarch64-linux-gnu/bits/floatn.h" 2 3 4
# 95 "/usr/include/aarch64-linux-gnu/bits/floatn.h" 3 4
# 1 "/usr/include/aarch64-linux-gnu/bits/floatn-common.h" 1 3 4
# 24 "/usr/include/aarch64-linux-gnu/bits/floatn-common.h" 3 4
# 1 "/usr/include/aarch64-linux-gnu/bits/long-double.h" 1 3 4
# 25 "/usr/include/aarch64-linux-gnu/bits/floatn-common.h" 2 3 4
# 96 "/usr/include/aarch64-linux-gnu/bits/floatn.h" 2 3 4
# 436 "/usr/include/stdio.h" 2 3 4
# 460 "/usr/include/stdio.h" 3 4
extern int fscanf (FILE *__restrict __stream, const char *__restrict __format, ...) __asm__ ("" "__isoc99_fscanf")

                               ;
extern int scanf (const char *__restrict __format, ...) __asm__ ("" "__isoc99_scanf")
                              ;
extern int sscanf (const char *__restrict __s, const char *__restrict __format, ...) __asm__ ("" "__isoc99_sscanf") __attribute__ ((__nothrow__ , __leaf__))

                      ;
# 486 "/usr/include/stdio.h" 3 4
extern int vfscanf (FILE *__restrict __s, const char *__restrict __format,
      __gnuc_va_list __arg)
     __attribute__ ((__format__ (__scanf__, 2, 0))) ;





extern int vscanf (const char *__restrict __format, __gnuc_va_list __arg)
     __attribute__ ((__format__ (__scanf__, 1, 0))) ;


extern int vsscanf (const char *__restrict __s,
      const char *__restrict __format, __gnuc_va_list __arg)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__format__ (__scanf__, 2, 0)));
# 536 "/usr/include/stdio.h" 3 4
extern int vfscanf (FILE *__restrict __s, const char *__restrict __format, __gnuc_va_list __arg) __asm__ ("" "__isoc99_vfscanf")



     __attribute__ ((__format__ (__scanf__, 2, 0))) ;
extern int vscanf (const char *__restrict __format, __gnuc_va_list __arg) __asm__ ("" "__isoc99_vscanf")

     __attribute__ ((__format__ (__scanf__, 1, 0))) ;
extern int vsscanf (const char *__restrict __s, const char *__restrict __format, __gnuc_va_list __arg) __asm__ ("" "__isoc99_vsscanf") __attribute__ ((__nothrow__ , __leaf__))



     __attribute__ ((__format__ (__scanf__, 2, 0)));
# 571 "/usr/include/stdio.h" 3 4
extern int fgetc (FILE *__stream);
extern int getc (FILE *__stream);





extern int getchar (void);






extern int getc_unlocked (FILE *__stream);
extern int getchar_unlocked (void);
# 596 "/usr/include/stdio.h" 3 4
extern int fgetc_unlocked (FILE *__stream);
# 607 "/usr/include/stdio.h" 3 4
extern int fputc (int __c, FILE *__stream);
extern int putc (int __c, FILE *__stream);





extern int putchar (int __c);
# 623 "/usr/include/stdio.h" 3 4
extern int fputc_unlocked (int __c, FILE *__stream);







extern int putc_unlocked (int __c, FILE *__stream);
extern int putchar_unlocked (int __c);






extern int getw (FILE *__stream);


extern int putw (int __w, FILE *__stream);







extern char *fgets (char *__restrict __s, int __n, FILE *__restrict __stream)
     __attribute__ ((__access__ (__write_only__, 1, 2)));
# 690 "/usr/include/stdio.h" 3 4
extern __ssize_t __getdelim (char **__restrict __lineptr,
                             size_t *__restrict __n, int __delimiter,
                             FILE *__restrict __stream) ;
extern __ssize_t getdelim (char **__restrict __lineptr,
                           size_t *__restrict __n, int __delimiter,
                           FILE *__restrict __stream) ;







extern __ssize_t getline (char **__restrict __lineptr,
                          size_t *__restrict __n,
                          FILE *__restrict __stream) ;







extern int fputs (const char *__restrict __s, FILE *__restrict __stream);





extern int puts (const char *__s);






extern int ungetc (int __c, FILE *__stream);






extern size_t fread (void *__restrict __ptr, size_t __size,
       size_t __n, FILE *__restrict __stream) ;




extern size_t fwrite (const void *__restrict __ptr, size_t __size,
        size_t __n, FILE *__restrict __s);
# 760 "/usr/include/stdio.h" 3 4
extern size_t fread_unlocked (void *__restrict __ptr, size_t __size,
         size_t __n, FILE *__restrict __stream) ;
extern size_t fwrite_unlocked (const void *__restrict __ptr, size_t __size,
          size_t __n, FILE *__restrict __stream);







extern int fseek (FILE *__stream, long int __off, int __whence);




extern long int ftell (FILE *__stream) ;




extern void rewind (FILE *__stream);
# 794 "/usr/include/stdio.h" 3 4
extern int fseeko (FILE *__stream, __off_t __off, int __whence);




extern __off_t ftello (FILE *__stream) ;
# 818 "/usr/include/stdio.h" 3 4
extern int fgetpos (FILE *__restrict __stream, fpos_t *__restrict __pos);




extern int fsetpos (FILE *__stream, const fpos_t *__pos);
# 844 "/usr/include/stdio.h" 3 4
extern void clearerr (FILE *__stream) __attribute__ ((__nothrow__ , __leaf__));

extern int feof (FILE *__stream) __attribute__ ((__nothrow__ , __leaf__)) ;

extern int ferror (FILE *__stream) __attribute__ ((__nothrow__ , __leaf__)) ;



extern void clearerr_unlocked (FILE *__stream) __attribute__ ((__nothrow__ , __leaf__));
extern int feof_unlocked (FILE *__stream) __attribute__ ((__nothrow__ , __leaf__)) ;
extern int ferror_unlocked (FILE *__stream) __attribute__ ((__nothrow__ , __leaf__)) ;







extern void perror (const char *__s) __attribute__ ((__cold__));




extern int fileno (FILE *__stream) __attribute__ ((__nothrow__ , __leaf__)) ;




extern int fileno_unlocked (FILE *__stream) __attribute__ ((__nothrow__ , __leaf__)) ;
# 881 "/usr/include/stdio.h" 3 4
extern int pclose (FILE *__stream);





extern FILE *popen (const char *__command, const char *__modes)
  __attribute__ ((__malloc__)) __attribute__ ((__malloc__ (pclose, 1))) ;






extern char *ctermid (char *__s) __attribute__ ((__nothrow__ , __leaf__))
  __attribute__ ((__access__ (__write_only__, 1)));
# 925 "/usr/include/stdio.h" 3 4
extern void flockfile (FILE *__stream) __attribute__ ((__nothrow__ , __leaf__));



extern int ftrylockfile (FILE *__stream) __attribute__ ((__nothrow__ , __leaf__)) ;


extern void funlockfile (FILE *__stream) __attribute__ ((__nothrow__ , __leaf__));
# 943 "/usr/include/stdio.h" 3 4
extern int __uflow (FILE *);
extern int __overflow (FILE *, int);
# 967 "/usr/include/stdio.h" 3 4

# 5 "include/buffered_file.h" 2
# 1 "/usr/lib/gcc/aarch64-linux-gnu/13/include/stdint.h" 1 3 4
# 9 "/usr/lib/gcc/aarch64-linux-gnu/13/include/stdint.h" 3 4
# 1 "/usr/include/stdint.h" 1 3 4
# 26 "/usr/include/stdint.h" 3 4
# 1 "/usr/include/aarch64-linux-gnu/bits/libc-header-start.h" 1 3 4
# 27 "/usr/include/stdint.h" 2 3 4

# 1 "/usr/include/aarch64-linux-gnu/bits/wchar.h" 1 3 4
# 29 "/usr/include/stdint.h" 2 3 4
# 1 "/usr/include/aarch64-linux-gnu/bits/wordsize.h" 1 3 4
# 30 "/usr/include/stdint.h" 2 3 4




# 1 "/usr/include/aarch64-linux-gnu/bits/stdint-intn.h" 1 3 4
# 24 "/usr/include/aarch64-linux-gnu/bits/stdint-intn.h" 3 4
typedef __int8_t int8_t;
typedef __int16_t int16_t;
typedef __int32_t int32_t;
typedef __int64_t int64_t;
# 35 "/usr/include/stdint.h" 2 3 4


# 1 "/usr/include/aarch64-linux-gnu/bits/stdint-uintn.h" 1 3 4
# 24 "/usr/include/aarch64-linux-gnu/bits/stdint-uintn.h" 3 4
typedef __uint8_t uint8_t;
typedef __uint16_t uint16_t;
typedef __uint32_t uint32_t;
typedef __uint64_t uint64_t;
# 38 "/usr/include/stdint.h" 2 3 4





typedef __int_least8_t int_least8_t;
typedef __int_least16_t int_least16_t;
typedef __int_least32_t int_least32_t;
typedef __int_least64_t int_least64_t;


typedef __uint_least8_t uint_least8_t;
typedef __uint_least16_t uint_least16_t;
typedef __uint_least32_t uint_least32_t;
typedef __uint_least64_t uint_least64_t;





typedef signed char int_fast8_t;

typedef long int int_fast16_t;
typedef long int int_fast32_t;
typedef long int int_fast64_t;
# 71 "/usr/include/stdint.h" 3 4
typedef unsigned char uint_fast8_t;

typedef unsigned long int uint_fast16_t;
typedef unsigned long int uint_fast32_t;
typedef unsigned long int uint_fast64_t;
# 87 "/usr/include/stdint.h" 3 4
typedef long int intptr_t;


typedef unsigned long int uintptr_t;
# 101 "/usr/include/stdint.h" 3 4
typedef __intmax_t intmax_t;
typedef __uintmax_t uintmax_t;
# 10 "/usr/lib/gcc/aarch64-linux-gnu/13/include/stdint.h" 2 3 4
# 6 "include/buffered_file.h" 2
# 28 "include/buffered_file.h"

# 28 "include/buffered_file.h"
enum FileType {
  FileNone = 0,
  FileExecutable,
  FileAsmSrc,
  FileCHeader,
  FileOberonSrc,
  FileObject,
  FileLib,
  FileDylib,
  FileS19,
  FileS28,
  FileS37,
  FileIntel,
  FileTIM,
  FileBinary,
  FileLinkMap,
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
  char filename[1024];
  char pwd[1024];
  unsigned char buffer[4096 + 1];
} BufferedFile;


extern BufferedFile *file;

extern int total_lines;
extern int total_bytes;
extern int error_count;

void bf_init(void);

int bf_open(const char* filename);
int bf_memory(const char* content, int len);
void bf_close(void);

char bf_next(void);
int bf_line(void);
int bf_pos(void);

void as_error(char *message, ...);
void as_gen_error(char* filename, int line_num, char* message, ...);
void as_warn(char *message, ...);
void as_gen_warn(char* filename, int line_num, char* message, ...);

FileType as_file_type(const char *filename);
# 10 "src/ocs.c" 2
# 1 "include/memory.h" 1
# 10 "include/memory.h"
void as_free(void *ptr);
void *as_malloc(unsigned long size);
void *as_mallocz(unsigned long size);
void *as_realloc(void *ptr, unsigned long size);
char *as_strdup(const char *str);
void as_memstats(void);
# 11 "src/ocs.c" 2

char scanner_id[1024];

char ch;

char* key[37];
Symbol symno[37];

Symbol scanner_sym;
int scanner_ival;
double scanner_rval;

char line[2][80];

# 24 "src/ocs.c" 3 4
_Bool 
# 24 "src/ocs.c"
    lineno;
int c;
int scanner_errcnt;

int K;

void print_line(void)
{
}

void next(void)
{
  if ((ch == '\n') || (ch == (char)(-1))) {
    line[(lineno?1:0)][c] = '\0';
    if (bf_line() > 2) print_line();
    lineno = !lineno;
    c = 0;
  }
  ch = bf_next(); if( ch == '\r' ) ch = bf_next();
  if (c < 80) line[(lineno?1:0)][c++] = ch;
}





void ident(void) {
  scanner_sym = sIDENT;

  int i = 0;
  int j, m, r;
  do {
    if( i < 1024 -1 ) scanner_id[i++] = ch;
    next();
  } while( (ch != (char)(-1)) && (((ch >= '0') && (ch <= '9')) || ((ch >= 'A') && (ch <= 'Z')) || (ch == '_') || ((ch >= 'a') && (ch <= 'z'))) );
  scanner_id[i] = 0;

  i = 0;
  j = 37;

  while( i < j ) {
 m = (i + j) / 2;
 printf("[%d] = %s, compared with %s = %d\n", m, key[m], scanner_id, strcasecmp(key[m],scanner_id));
 r = strcasecmp(key[m],scanner_id);
 if (r < 0) {
   i = m + 1;
 } else if (r > 0) {
   j = m;
 } else {
   i = j = m;
 }
  }
  if( strcasecmp(key[j],scanner_id) == 0 ) {
 scanner_sym = symno[j];
  }
  printf("indent: '%s'\n", scanner_id);
}

void number(void) {
  scanner_ival = 0;
  do {
    scanner_ival = 10 * scanner_ival + ch - '0';
    next();
  } while( ch >= '0' && ch <= '9' && (ch != (char)(-1)) );
  if (ch == '.') {

    scanner_sym = sREAL;
  } else {
    scanner_sym = sINTEGER;
  }
}

void hex(void) {
  int d;
  scanner_ival = 0;
  do {
    if( ('0' <= ch) && (ch <= '9') ) d = ch - '0';
    else if( ('A' <= ch) && (ch <= 'F') ) d = ch - 'A' + 10;
    else d = ch - 'a' + 10;
    scanner_ival = 0x10 * scanner_ival + d;
    next();
  } while( (ch != (char)(-1)) && ((ch >= '0' && ch <= '9') || ((ch >= 'A') && (ch <= 'F')) || ((ch >= 'a') && (ch <= 'f'))) );
}

void binary(void) {
  scanner_ival = 0;
  do {
    scanner_ival = 2 * scanner_ival + ch - '0';
    next();
  } while( ch >= '0' && ch <= '1' && (ch != (char)(-1)) );
}

void string(void) {
  int i = 0;
  do {
    if (ch == '\\') {
      scanner_id[i++] = ch;
      next();
      if ((ch != (char)(-1)) && (i < 1024)) scanner_id[i++] = ch;
    } else {
      scanner_id[i++] = ch;
    }
 next();
  } while( (ch != '"') && (ch != (char)(-1)) && (i < 1024) );
  scanner_id[i] = 0;

  next();
}

void comment(void) {
  next();
  while( (ch != (char)(-1)) && (ch != '*') ) next();
  if( (ch != (char)(-1)) ) { next(); if( ch != ')' ) comment(); }
  next();
}





void scanner_next(void) {
  do {

    while( (ch != (char)(-1)) && (ch != '\n') && (ch <= ' ') ) {
      next();
    }
    if( ch == (char)(-1) ) { scanner_sym = sEOF; next(); return; }

    if( ch < 'A' ) {
      if( ch < '0' ) {
        if( ch == '#' ) { next(); scanner_sym = sNEQ;
        } else if( ch == '&' ) { next(); scanner_sym = sAND;
        } else if( ch == '(' ) { next();
    if( ch == '*' ) { comment(); scanner_sym = sNULL;
    } else { scanner_sym = sLPAREN; }
        } else if( ch == ')' ) { next(); scanner_sym = sRPAREN;
        } else if( ch == '*' ) { next(); scanner_sym = sAST;
        } else if( ch == '+' ) { next(); scanner_sym = sPLUS;
        } else if( ch == ',' ) { next(); scanner_sym = sCOMMA;
        } else if( ch == '-' ) { next(); scanner_sym = sMINUS;
        } else if( ch == '.' ) { next();
    if( ch == '.') { next(); scanner_sym = sDOTDOT;
    } else { scanner_sym = sPERIOD; }
        } else if( ch == '/' ) { next(); scanner_sym = sSLASH;
        } else if( ch == '"' ) { next(); string(); scanner_sym = sSTRING;
        } else { next(); scanner_sym = sNULL; }
      } else if( ch <= '9' ) { number();
      } else if( ch == ':' ) { next();
  if( ch == '=' ) { next(); scanner_sym = sBECOMES;
  } else { scanner_sym = sCOLON; }
      } else if( ch == ';' ) { next(); scanner_sym = sSEMICOLON;
      } else if( ch == '<' ) { next();
        if( ch == '=' ) { next(); scanner_sym = sLEQ;
  } else { scanner_sym = sLSS; }
   } else if( ch == '=' ) { next(); scanner_sym = sEQL;
      } else if( ch == '>' ) { next();
        if( ch == '=' ) { next(); scanner_sym = sGEQ;
  } else { scanner_sym = sGTR; }
   } else if( ch < 'a' ) {
  if( ch <= 'Z' ) { ident();
  } else if( ch == '[' ) { next(); scanner_sym = sLSQ;
  } else if( ch == ']' ) { next(); scanner_sym = sRSQ;
  } else if( ch == '_' ) { ident();
  } else if( ch == '^' ) { next(); scanner_sym = sCARET; }
   } else { next(); scanner_sym = sNULL; }
 } else if( ch <= 'z' ) { ident();
 } else if( ch == '{' ) { next(); scanner_sym = sLBRACE;
 } else if( ch == '|' ) { next(); scanner_sym = sBAR;
 } else if( ch == '}' ) { next(); scanner_sym = sRBRACE;
 } else if( ch == '~' ) { next(); scanner_sym = sTILDE;
 } else { next(); scanner_sym = sNULL; }
  } while( scanner_sym == sNULL );
  as_warn("%s", token_to_string(scanner_sym));
}

void scanner_enter(char* word, Symbol val) {
  key[K] = word;
  symno[K++] = val;
}

void scanner_init()
{
  K = 0;



# 1 "include/oc_tokens.h" 1


scanner_enter("array", sARRAY);
scanner_enter("begin", sBEGIN);
scanner_enter("by", sBY);
scanner_enter("case", sCASE);
scanner_enter("char", sCHAR);
scanner_enter("const", sCONST);
scanner_enter("div", sDIV);
scanner_enter("do", sDO);
scanner_enter("else", sELSE);
scanner_enter("elsif", sELSIF);
scanner_enter("end", sEND);
scanner_enter("exit", sEXIT);
scanner_enter("false", sFALSE);
scanner_enter("for", sFOR);
scanner_enter("if", sIF);
scanner_enter("import", sIMPORT);
scanner_enter("in", sIN);
scanner_enter("is", sIS);
scanner_enter("loop", sLOOP);
scanner_enter("mod", sMOD);
scanner_enter("module", sMODULE);
scanner_enter("nil", sNIL);
scanner_enter("of", sOF);
scanner_enter("or", sOR);
scanner_enter("pointer", sPOINTER);
scanner_enter("procedure", sPROCEDURE);
scanner_enter("record", sRECORD);
scanner_enter("repeat", sREPEAT);
scanner_enter("return", sRETURN);
scanner_enter("then", sTHEN);
scanner_enter("to", sTO);
scanner_enter("true", sTRUE);
scanner_enter("type", sTYPE);
scanner_enter("until", sUNTIL);
scanner_enter("var", sVAR);
scanner_enter("while", sWHILE);
scanner_enter("with", sWITH);

;
;
;
;
;
;
;
;
;
;
;
;
;
;
;
;
;
;
;
;
;
;
;
;
;
;
;
;
;
;
;
;
# 211 "src/ocs.c" 2



  key[K] = "~";

  if( K != 37 ) printf("There are %d keys, please update NoOfKeys in ocs.h.\n", K);


  scanner_errcnt = 0;
}

void scanner_start()
{
  scanner_errcnt = 0;
  c = 0;
  next();
}

void scanner_copyId(char *dest) {
  strncpy(dest, (char *)&scanner_id, 1024);
}

char *token_to_string(Symbol val)
{
 switch( val ) {


# 1 "include/oc_tokens.h" 1


case sARRAY: return "array";
case sBEGIN: return "begin";
case sBY: return "by";
case sCASE: return "case";
case sCHAR: return "char";
case sCONST: return "const";
case sDIV: return "div";
case sDO: return "do";
case sELSE: return "else";
case sELSIF: return "elsif";
case sEND: return "end";
case sEXIT: return "exit";
case sFALSE: return "false";
case sFOR: return "for";
case sIF: return "if";
case sIMPORT: return "import";
case sIN: return "in";
case sIS: return "is";
case sLOOP: return "loop";
case sMOD: return "mod";
case sMODULE: return "module";
case sNIL: return "nil";
case sOF: return "of";
case sOR: return "or";
case sPOINTER: return "pointer";
case sPROCEDURE: return "procedure";
case sRECORD: return "record";
case sREPEAT: return "repeat";
case sRETURN: return "return";
case sTHEN: return "then";
case sTO: return "to";
case sTRUE: return "true";
case sTYPE: return "type";
case sUNTIL: return "until";
case sVAR: return "var";
case sWHILE: return "while";
case sWITH: return "with";

case sIDENT: return "IDENT";
case sINTEGER: return "INTEGER";
case sREAL: return "REAL";
case sSTRING: return "STRING";
case sPLUS: return "PLUS";
case sMINUS: return "MINUS";
case sAST: return "AST";
case sSLASH: return "SLASH";
case sTILDE: return "TILDE";
case sAND: return "AND";
case sPERIOD: return "PERIOD";
case sCOMMA: return "COMMA";
case sSEMICOLON: return "SEMICOLON";
case sBAR: return "BAR";
case sLPAREN: return "LPAREN";
case sRPAREN: return "RPAREN";
case sLSQ: return "LSQ";
case sRSQ: return "RSQ";
case sLBRACE: return "LBRACE";
case sRBRACE: return "RBRACE";
case sBECOMES: return "BECOMES";
case sCARET: return "CARET";
case sEQL: return "EQL";
case sNEQ: return "NEQ";
case sLSS: return "LSS";
case sLEQ: return "LEQ";
case sGTR: return "GTR";
case sGEQ: return "GEQ";
case sDOTDOT: return "DOTDOT";
case sCOLON: return "COLON";
case sNULL: return "NULL";
case sEOF: return "EOF";
# 239 "src/ocs.c" 2


 }
 as_error("unknown token %d", val);
 return "Unknown token";
}
