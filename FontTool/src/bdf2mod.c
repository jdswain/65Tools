/*
 * bdf2mod - Convert BDF font files to Oberon modules with structured constants
 *
 * Usage: bdf2mod <bdf-file>
 * Output: fonts/<Family><Size>.Mod
 *
 * The generated module contains:
 *   height, minX, maxX, minY, maxY - font metrics (scalar constants)
 *   T - ARRAY OF INTEGER, 256 entries: offset into raster for each char
 *   raster - ARRAY OF BYTE: per-glyph [dx, x, y, w, h] + bitmap bytes
 *
 * Raster layout per glyph:
 *   dx    - advance width (1 byte)
 *   x     - x offset from origin (1 byte, signed stored as unsigned)
 *   y     - y offset from origin (1 byte, signed stored as unsigned)
 *   w     - bitmap width in pixels (1 byte)
 *   h     - bitmap height in pixels (1 byte)
 *   data  - ceil(w/8) * h bytes, MSB-left bitmap rows top to bottom
 *
 * T[ch] = offset into raster; 0 = null glyph (5 zero bytes at raster[0..4])
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#define MAX_GLYPHS 256
#define MAX_RASTER 16000
#define MAX_BITMAP_ROWS 64
#define MAX_BITMAP_BYTES_PER_ROW 8

typedef struct {
  int encoding;
  int dwidth;
  int bbx_w, bbx_h, bbx_xoff, bbx_yoff;
  int bitmap_len;
  unsigned char bitmap[MAX_BITMAP_ROWS * MAX_BITMAP_BYTES_PER_ROW];
} Glyph;

static Glyph glyphs[MAX_GLYPHS];
static int glyph_present[MAX_GLYPHS];

static unsigned char raster[MAX_RASTER];
static int raster_len;

static int table[MAX_GLYPHS]; /* offset into raster for each char */

/* Font-wide metrics */
static int font_height;
static int font_minX, font_maxX, font_minY, font_maxY;

static void parse_bdf(const char *filename) {
  FILE *f = fopen(filename, "r");
  if (!f) {
    fprintf(stderr, "Cannot open %s\n", filename);
    exit(1);
  }

  char line[256];
  int in_bitmap = 0;
  int cur_encoding = -1;
  Glyph *g = NULL;
  int bytes_per_row = 0;
  int fbb_w = 0, fbb_h = 0, fbb_xoff = 0, fbb_yoff = 0;

  memset(glyphs, 0, sizeof(glyphs));
  memset(glyph_present, 0, sizeof(glyph_present));

  while (fgets(line, sizeof(line), f)) {
    /* Strip trailing whitespace */
    int len = strlen(line);
    while (len > 0 && (line[len-1] == '\n' || line[len-1] == '\r' || line[len-1] == ' '))
      line[--len] = '\0';

    if (strncmp(line, "FONTBOUNDINGBOX ", 16) == 0) {
      sscanf(line + 16, "%d %d %d %d", &fbb_w, &fbb_h, &fbb_xoff, &fbb_yoff);
      font_height = fbb_h;
      font_minX = fbb_xoff;
      font_maxX = fbb_xoff + fbb_w - 1;
      font_minY = fbb_yoff;
      font_maxY = fbb_yoff + fbb_h - 1;
    } else if (strncmp(line, "ENCODING ", 9) == 0) {
      cur_encoding = atoi(line + 9);
    } else if (strncmp(line, "DWIDTH ", 7) == 0) {
      if (cur_encoding >= 0 && cur_encoding < MAX_GLYPHS) {
        glyphs[cur_encoding].dwidth = atoi(line + 7);
      }
    } else if (strncmp(line, "BBX ", 4) == 0) {
      if (cur_encoding >= 0 && cur_encoding < MAX_GLYPHS) {
        g = &glyphs[cur_encoding];
        sscanf(line + 4, "%d %d %d %d", &g->bbx_w, &g->bbx_h, &g->bbx_xoff, &g->bbx_yoff);
        g->encoding = cur_encoding;
        bytes_per_row = (g->bbx_w + 7) / 8;
      }
    } else if (strcmp(line, "BITMAP") == 0) {
      if (cur_encoding >= 0 && cur_encoding < MAX_GLYPHS) {
        in_bitmap = 1;
        g = &glyphs[cur_encoding];
        g->bitmap_len = 0;
      }
    } else if (strcmp(line, "ENDCHAR") == 0) {
      if (cur_encoding >= 0 && cur_encoding < MAX_GLYPHS) {
        glyph_present[cur_encoding] = 1;
      }
      in_bitmap = 0;
      cur_encoding = -1;
      g = NULL;
    } else if (in_bitmap && g) {
      /* Parse hex bitmap row */
      for (int i = 0; i < bytes_per_row && line[i*2] && line[i*2+1]; i++) {
        char hex[3] = { line[i*2], line[i*2+1], '\0' };
        g->bitmap[g->bitmap_len++] = (unsigned char)strtol(hex, NULL, 16);
      }
    }
  }

  fclose(f);
}

static void build_raster(void) {
  /* Raster[0..4] = font metrics header / null glyph sentinel
   * raster[0] = height, raster[1] = maxY (ascent), raster[2] = minY (descent, signed as byte)
   * T[ch]=0 for undefined chars; DrawGlyph/StringWidth check T[ch]#0 before reading,
   * so these bytes are never interpreted as glyph metrics. */
  raster_len = 5;
  raster[0] = (unsigned char)font_height;
  raster[1] = (unsigned char)(font_maxY & 0xFF);
  raster[2] = (unsigned char)(font_minY & 0xFF);
  raster[3] = 0;
  raster[4] = 0;
  memset(table, 0, sizeof(table));

  for (int ch = 0; ch < MAX_GLYPHS; ch++) {
    if (!glyph_present[ch]) {
      table[ch] = 0; /* points to null glyph */
      continue;
    }

    Glyph *g = &glyphs[ch];
    int bytes_per_row = (g->bbx_w + 7) / 8;
    int data_len = bytes_per_row * g->bbx_h;

    if (raster_len + 5 + data_len > MAX_RASTER) {
      fprintf(stderr, "Raster overflow at char %d\n", ch);
      exit(1);
    }

    table[ch] = raster_len;

    /* Metrics: dx, x, y, w, h */
    raster[raster_len++] = (unsigned char)g->dwidth;
    raster[raster_len++] = (unsigned char)(g->bbx_xoff & 0xFF);
    raster[raster_len++] = (unsigned char)(g->bbx_yoff & 0xFF);
    raster[raster_len++] = (unsigned char)g->bbx_w;
    raster[raster_len++] = (unsigned char)g->bbx_h;

    /* Bitmap data — stored bottom-to-top for Cartesian screen coordinates */
    for (int row = g->bbx_h - 1; row >= 0; row--) {
      memcpy(&raster[raster_len], &g->bitmap[row * bytes_per_row], bytes_per_row);
      raster_len += bytes_per_row;
    }
  }
}

/* Extract family name and size from path like "bitmapSources/Ohlfs/10.Ohlfs" */
static void extract_names(const char *path, char *family, int *size, char *modname) {
  /* Find the filename part */
  const char *slash = strrchr(path, '/');
  const char *fname = slash ? slash + 1 : path;

  /* Parse "10.Ohlfs" -> size=10, family="Ohlfs" */
  *size = atoi(fname);
  const char *dot = strchr(fname, '.');
  if (dot) {
    strcpy(family, dot + 1);
  } else {
    strcpy(family, "Unknown");
  }

  sprintf(modname, "%s%d", family, *size);
}

static void write_module(const char *outdir, const char *modname) {
  char outpath[512];
  sprintf(outpath, "%s/%s.Mod", outdir, modname);

  FILE *f = fopen(outpath, "w");
  if (!f) {
    fprintf(stderr, "Cannot create %s\n", outpath);
    exit(1);
  }

  fprintf(f, "MODULE %s;\n", modname);
  fprintf(f, "  CONST\n");
  fprintf(f, "    height* = %d; minX* = %d; maxX* = %d; minY* = %d; maxY* = %d;\n",
          font_height, font_minX, font_maxX, font_minY, font_maxY);

  /* T table: 256 INTEGER entries */
  fprintf(f, "    T* = ARRAY OF INTEGER {");
  for (int i = 0; i < 256; i++) {
    if (i > 0) fprintf(f, ",");
    if (i % 16 == 0) fprintf(f, "\n      ");
    fprintf(f, "%d", table[i]);
  }
  fprintf(f, "};\n");

  /* Raster: byte array */
  fprintf(f, "    raster* = ARRAY OF BYTE {");
  for (int i = 0; i < raster_len; i++) {
    if (i > 0) fprintf(f, ",");
    if (i % 20 == 0) fprintf(f, "\n      ");
    fprintf(f, "%d", raster[i]);
  }
  fprintf(f, "};\n");

  fprintf(f, "END %s.\n", modname);
  fclose(f);

  int nglyph = 0;
  for (int i = 0; i < 256; i++)
    if (glyph_present[i]) nglyph++;
  printf("Generated %s (%d raster bytes, %d glyphs)\n",
         outpath, raster_len, nglyph);
}

int main(int argc, char *argv[]) {
  if (argc < 2) {
    fprintf(stderr, "Usage: bdf2mod <bdf-file> [output-dir]\n");
    fprintf(stderr, "  Default output dir: fonts/\n");
    return 1;
  }

  const char *bdf_path = argv[1];
  const char *outdir = argc >= 3 ? argv[2] : "fonts";

  char family[64];
  int font_size;
  char modname[64];

  extract_names(bdf_path, family, &font_size, modname);

  printf("Parsing %s -> %s (family=%s, size=%d)\n", bdf_path, modname, family, font_size);

  parse_bdf(bdf_path);
  build_raster();
  write_module(outdir, modname);

  return 0;
}
