# Makefile
#
# Makefile for BDF font converter

CC = gcc
CFLAGS = -Wall -Wextra -O2
OC = ../bin/oc
BINDIR = ../bin

SRCDIR = src
FONTDIR = fonts
BDF_DIR = bitmapSources

.PHONY: all clean convert compile fonts

all: $(BINDIR)/bdf2mod

$(BINDIR)/bdf2mod: $(SRCDIR)/bdf2mod.c
	@mkdir -p $(BINDIR)
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f $(BINDIR)/bdf2mod
	rm -f $(FONTDIR)/*.816 $(FONTDIR)/*.smb

# Convert all BDF fonts found in bitmapSources/
convert: $(BINDIR)/bdf2mod
	@mkdir -p $(FONTDIR)
	@for dir in $(BDF_DIR)/*/; do \
		for f in "$$dir"*; do \
			case "$$f" in *.places|*.list) continue;; esac; \
			[ -f "$$f" ] && $(BINDIR)/bdf2mod "$$f" $(FONTDIR); \
		done; \
	done

# Compile converted fonts
compile: convert
	@for f in $(FONTDIR)/*.Mod; do \
		echo "Compiling $$f"; \
		$(OC) "$$f" -s || exit 1; \
	done

# Full pipeline: convert + compile
fonts: compile
