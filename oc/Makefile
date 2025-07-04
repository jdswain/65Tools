# Makefile for Oberon Compiler Components

CC = gcc
CFLAGS = -Wall -Wextra -O2 -g -I./include
LDFLAGS = -lm

# Directories
SRCDIR = src
INCDIR = include
OBJDIR = obj
BINDIR = bin

# Source files
SOURCES = $(wildcard $(SRCDIR)/*.c)
OBJECTS = $(SOURCES:$(SRCDIR)/%.c=$(OBJDIR)/%.o)

# Executables
TARGETS = $(BINDIR)/test_scanner $(BINDIR)/test_orb $(BINDIR)/oc

# Create directories if they don't exist
$(shell mkdir -p $(OBJDIR) $(BINDIR))

# Targets
all: $(TARGETS)

# Scanner test
$(BINDIR)/test_scanner: $(OBJDIR)/ORS.o $(OBJDIR)/test_scanner.o
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

# ORB test
$(BINDIR)/test_orb: $(OBJDIR)/ORS.o $(OBJDIR)/ORB.o $(OBJDIR)/Files.o $(OBJDIR)/test_orb.o
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

# ORP test (parser)
$(BINDIR)/test_orp: $(OBJDIR)/ORS.o $(OBJDIR)/ORB.o $(OBJDIR)/Files.o $(OBJDIR)/ORP.o $(OBJDIR)/test_orp.o
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

# Main Oberon compiler
$(BINDIR)/oc: $(OBJDIR)/ORS.o $(OBJDIR)/ORB.o $(OBJDIR)/ORP.o $(OBJDIR)/ORG.o $(OBJDIR)/Texts.o $(OBJDIR)/Files.o
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

# Object files
$(OBJDIR)/%.o: $(SRCDIR)/%.c
	$(CC) $(CFLAGS) -c $< -o $@

# Dependencies
$(OBJDIR)/ORS.o: $(SRCDIR)/ORS.c $(INCDIR)/ORS.h
$(OBJDIR)/ORB.o: $(SRCDIR)/ORB.c $(INCDIR)/ORB.h $(INCDIR)/ORS.h $(INCDIR)/Files.h
$(OBJDIR)/ORP.o: $(SRCDIR)/ORP.c $(INCDIR)/ORP.h $(INCDIR)/ORB.h $(INCDIR)/ORS.h $(INCDIR)/ORG.h
$(OBJDIR)/ORG.o: $(SRCDIR)/ORG.c $(INCDIR)/ORG.h $(INCDIR)/ORB.h $(INCDIR)/ORS.h
$(OBJDIR)/Texts.o: $(SRCDIR)/Texts.c $(INCDIR)/Texts.h
$(OBJDIR)/Files.o: $(SRCDIR)/Files.c $(INCDIR)/Files.h
$(OBJDIR)/test_scanner.o: $(SRCDIR)/test_scanner.c $(INCDIR)/ORS.h
$(OBJDIR)/test_orb.o: $(SRCDIR)/test_orb.c $(INCDIR)/ORB.h $(INCDIR)/ORS.h
$(OBJDIR)/test_orp.o: $(SRCDIR)/test_orp.c $(INCDIR)/ORP.h $(INCDIR)/ORB.h $(INCDIR)/ORS.h

clean:
	rm -rf $(OBJDIR) $(BINDIR)
	rm -f test.Mod *.smb

# Example test files
test: test_scanner test_orb test_orp

test_scanner: $(BINDIR)/test_scanner
	@echo "=== Testing Scanner ==="
	@echo 'MODULE Test;' > test.Mod
	@echo 'CONST Pi = 3.14159;' >> test.Mod
	@echo 'VAR x, y: INTEGER;' >> test.Mod
	@echo 'BEGIN' >> test.Mod
	@echo '  x := 42;' >> test.Mod
	@echo '  y := x * 2 + 1;' >> test.Mod
	@echo '  (* This is a comment *)' >> test.Mod
	@echo 'END Test.' >> test.Mod
	@echo ""
	@echo "Running scanner on test.Mod..."
	@echo ""
	$(BINDIR)/test_scanner test.Mod

test_orb: $(BINDIR)/test_orb
	@echo ""
	@echo "=== Testing Symbol Table ==="
	@echo ""
	$(BINDIR)/test_orb

test_orp: $(BINDIR)/test_orp
	@echo ""
	@echo "=== Testing Parser ==="
	@echo 'MODULE Hello;' > hello.Mod
	@echo 'BEGIN' >> hello.Mod
	@echo 'END Hello.' >> hello.Mod
	@echo ""
	$(BINDIR)/test_orp hello.Mod
	@echo ""
	@echo "Testing a more complex module..."
	@echo 'MODULE Complex;' > complex.Mod
	@echo 'CONST' >> complex.Mod
	@echo '  Max = 100;' >> complex.Mod
	@echo 'TYPE' >> complex.Mod
	@echo '  Vector = ARRAY Max OF INTEGER;' >> complex.Mod
	@echo 'VAR' >> complex.Mod
	@echo '  v: Vector;' >> complex.Mod
	@echo '  i: INTEGER;' >> complex.Mod
	@echo 'BEGIN' >> complex.Mod
	@echo '  FOR i := 0 TO Max-1 DO' >> complex.Mod
	@echo '    v[i] := i * i' >> complex.Mod
	@echo '  END' >> complex.Mod
	@echo 'END Complex.' >> complex.Mod
	@echo ""
	$(BINDIR)/test_orp complex.Mod

# Install target (optional)
PREFIX ?= /usr/local
install: $(TARGETS)
	install -d $(PREFIX)/bin
	install -m 755 $(BINDIR)/test_scanner $(PREFIX)/bin/oberon-scanner
	install -m 755 $(BINDIR)/test_orb $(PREFIX)/bin/oberon-orb-test
	install -m 755 $(BINDIR)/test_orp $(PREFIX)/bin/oberon-parser

.PHONY: all clean test test_scanner test_orb test_orp install
