# Makefile for em16, the 65C816 emulator, written in Oberon.
#
# The sources in src/ are compiled by the Oberon compiler of the oc
# repository (the LLVM compiler, bin/oc there) and linked with its POSIX
# runtime, the C host interface (EmHost_rt.c, EmFont.c) and the Cocoa
# windows (EmCocoa.m) into ../bin/em16. The SoC target (-fpga) is
# EmSoC and the modules after EmCore in MODS; see README.md. Override OC to use another
# checkout:
#
#   make OC=/path/to/oc/bin/oc
#
# The compiler writes its .smb/.o/.ll files beside the source, so the
# sources are copied to obj/ and compiled there. Edit the files in src/.
#
# The C++ em16 this was ported from is in ../em16-c (bin/em16-c);
# make compare runs both on the same programs (test/compare.sh).

OC     ?= ../../../oc/bin/oc
OC     := $(abspath $(OC))
RT     := $(dir $(OC))../runtime/posix
SRCDIR := src
OBJDIR := obj
BINDIR := ../bin
TARGET := $(BINDIR)/em16

# In order of import
MODS := EmHost EmSym EmUART EmVIA EmFDC EmL28 EmVideo EmLCD EmCore EmSDRAM EmACIA EmSCC EmADB EmBlit EmSoC EmMem EmCPU EmLoad EmHarte Em16
OBJS := $(MODS:%=$(OBJDIR)/%.o)
CSRC := $(SRCDIR)/EmHost_rt.c $(SRCDIR)/EmFont.c $(SRCDIR)/EmCocoa.m

RT_SMB := $(RT)/Errors.smb $(RT)/Out.smb $(RT)/Files.smb $(RT)/Env.smb

.PHONY: all test compare clean

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

# The compiler's own object files are not optimised; the LLVM it leaves
# beside them is compiled again with clang -O2, which makes em16 about
# three times faster.
$(OBJDIR)/%.o: $(OBJDIR)/%.Mod $(RT_SMB)
	cd $(OBJDIR) && $(OC) -s $*.Mod
	cd $(OBJDIR) && clang -O2 -Wno-override-module -c $*.ll -o $*.o

$(OBJDIR)/EmUART.o $(OBJDIR)/EmFDC.o $(OBJDIR)/EmL28.o $(OBJDIR)/EmLCD.o: $(OBJDIR)/EmHost.o
$(OBJDIR)/EmSDRAM.o: $(OBJDIR)/EmVideo.o
$(OBJDIR)/EmACIA.o $(OBJDIR)/EmSCC.o $(OBJDIR)/EmADB.o: $(OBJDIR)/EmHost.o
$(OBJDIR)/EmBlit.o: $(OBJDIR)/EmSDRAM.o
$(OBJDIR)/EmSoC.o: $(OBJDIR)/EmCore.o $(OBJDIR)/EmSDRAM.o $(OBJDIR)/EmACIA.o $(OBJDIR)/EmSCC.o $(OBJDIR)/EmADB.o \
                   $(OBJDIR)/EmBlit.o $(OBJDIR)/EmFDC.o $(OBJDIR)/EmVideo.o
$(OBJDIR)/EmMem.o: $(OBJDIR)/EmUART.o $(OBJDIR)/EmVIA.o $(OBJDIR)/EmFDC.o $(OBJDIR)/EmL28.o \
                   $(OBJDIR)/EmVideo.o $(OBJDIR)/EmLCD.o $(OBJDIR)/EmSoC.o
$(OBJDIR)/EmCPU.o: $(OBJDIR)/EmMem.o $(OBJDIR)/EmSym.o
$(OBJDIR)/EmSym.o: $(OBJDIR)/EmHost.o
$(OBJDIR)/EmLoad.o: $(OBJDIR)/EmCPU.o
$(OBJDIR)/EmCore.o: $(OBJDIR)/EmSym.o
$(OBJDIR)/EmHarte.o: $(OBJDIR)/EmCore.o
$(OBJDIR)/Em16.o: $(OBJDIR)/EmLoad.o $(OBJDIR)/EmHarte.o $(OBJDIR)/EmSoC.o

$(TARGET): $(OBJS) $(CSRC) | $(BINDIR)
	cd $(OBJDIR) && $(OC) -o $(abspath $(TARGET)) Em16.Mod \
	    $(abspath $(CSRC)) -framework Cocoa

test: $(TARGET)
	@sh test/run.sh

compare: $(TARGET)
	@sh test/compare.sh

clean:
	rm -rf $(OBJDIR)
	rm -f $(TARGET)
