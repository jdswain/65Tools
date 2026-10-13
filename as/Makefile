# Makefile for the 65xx assembler, written in Oberon.
#
# The sources in src/ are compiled by the Oberon compiler of the oc
# repository (the LLVM compiler, bin/oc there) and linked with its POSIX
# runtime into ../bin/as. Override OC to use another checkout:
#
#   make OC=/path/to/oc/bin/oc
#
# The compiler writes its .smb/.o/.ll/.deps files beside the source, so
# the sources are copied to obj/ and compiled there; src/ stays clean.
# Edit the files in src/.

OC     ?= ../../../oc/bin/oc
OC     := $(abspath $(OC))
RT     := $(dir $(OC))../runtime/posix
SRCDIR := src
OBJDIR := obj
BINDIR := ../bin
TARGET := $(BINDIR)/as

# In order of import: each module needs the symbol files of those before it.
MODS := ASC ASH ASS ASB ASG ASL ASI ASP ASO AS
OBJS := $(MODS:%=$(OBJDIR)/%.o)

# Runtime modules the assembler imports. Their .smb/.o are build
# artifacts of the oc repository and may be missing in a clean checkout.
RT_SMB := $(RT)/Errors.smb $(RT)/Out.smb $(RT)/Files.smb $(RT)/Env.smb

.PHONY: all test clean

# keep the copies, or make would recompile everything each time
.SECONDARY: $(MODS:%=$(OBJDIR)/%.Mod)

all: $(TARGET)

$(RT)/Errors.smb: $(RT)/Errors.Mod
	$(OC) -s $<
$(RT)/Out.smb: $(RT)/Out.Mod
	$(OC) -s $<
$(RT)/Env.smb: $(RT)/Env.Mod
	$(OC) -s $<
$(RT)/Files.smb: $(RT)/Files.Mod $(RT)/Errors.smb
	$(OC) -s $<

$(OBJDIR) $(BINDIR):
	mkdir -p $@

$(OBJDIR)/%.Mod: $(SRCDIR)/%.Mod | $(OBJDIR)
	cp $< $@

# A module is recompiled when its source or a module it imports changed.
$(OBJDIR)/%.o: $(OBJDIR)/%.Mod $(RT_SMB)
	cd $(OBJDIR) && $(OC) -s $*.Mod

$(OBJDIR)/ASS.o: $(OBJDIR)/ASC.o $(OBJDIR)/ASH.o
$(OBJDIR)/ASB.o: $(OBJDIR)/ASS.o
$(OBJDIR)/ASG.o: $(OBJDIR)/ASS.o
$(OBJDIR)/ASL.o: $(OBJDIR)/ASB.o $(OBJDIR)/ASG.o
$(OBJDIR)/ASI.o: $(OBJDIR)/ASL.o
$(OBJDIR)/ASP.o: $(OBJDIR)/ASI.o
$(OBJDIR)/ASO.o: $(OBJDIR)/ASB.o $(OBJDIR)/ASG.o
$(OBJDIR)/AS.o: $(OBJDIR)/ASP.o $(OBJDIR)/ASO.o

# -o links AS with every module it imports, the runtime, and the C part
# of the host interface.
$(TARGET): $(OBJS) $(SRCDIR)/ASH_rt.c | $(BINDIR)
	cd $(OBJDIR) && $(OC) -o $(abspath $(TARGET)) AS.Mod $(abspath $(SRCDIR)/ASH_rt.c)

test: $(TARGET)
	@sh test/run_tests.sh $(abspath $(TARGET))

clean:
	rm -rf $(OBJDIR) test/out
	rm -f $(TARGET)
