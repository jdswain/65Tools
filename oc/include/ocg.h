#ifndef ORG_H
#define ORG_H

extern int gen_pc;

void gen_open(void);
void gen_setDataSize(int sz);
void gen_header(void);
void gen_close(char *id, int key, int exno);

#endif
