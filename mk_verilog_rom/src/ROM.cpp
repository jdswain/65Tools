#include <stdio.h>

void header()
{
  printf("always @(address)\n");
  printf("begin\n");
  printf("  if ((address[15] == 1'b1) && (address[14] == 1'b1)) begin\n");
  printf("    case (address[7:0])\n");
}

void footer()
{
  printf("    default: datab <= 8'h00;\n");
  printf("    endcase\n");
  printf("  end else begin\n");
  printf("    datab <= 8'bzzzzzzzz;\n");
  printf("  end\n");
  printf("end\n");
}

void line(int i, unsigned char b)
{
  printf("    8'h%.2X: datab <= 8'h%.2X;\n", i, b);
}

FILE* in;
FILE* out;

int main(int argc, char** argv)
{
  in = fopen("test.bin", "r");
  out = fopen("test.v", "w");
  int i = 0;
  char b;
  header();
  while( !feof(in) ) {b = fgetc(in); line(i++, b); }
  footer();
}
