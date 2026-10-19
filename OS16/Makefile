# Makefile for OS16.
#
# The sources in src/ (a module for each class of the OS16 model, and
# the support modules beside them), the fonts used, the applications,
# the sample and the tests are copied to build/ and compiled there in
# the order they import each other: Oberon with oc816 (the self-hosted
# 65C816 compiler of the oc repository), assembly with as. Edit the
# files where they are, not in build/.
#
#   make          everything into build/
#   make test     run the tests on em16 (test/*.expected)
#   make fonts    every font of fonts/, not only those used
#   make clean
#
# The boot ROM: python3 tools/makerom.py build/BootLoader.816 boot.rom

OC   ?= ../../../oc/self/s816/oc816
ASM  ?= ../bin/as
EM16 ?= ../bin/em16
OUT  ?= ../oc/test/Out.Mod

B := build

# In order of import. Out comes from the oc test library.
SYSTEM  := Out MemoryManager HeapManager InterruptManager EventManager \
           Driver CharacterDriver BlockDriver BusDriver NetworkInterface \
           Serial Floppy HardDisk SCSIManager ADBManager \
           FileSystem FatFS ModuleLoader MakeImage BootLoader \
           ProcessManager Numerics
FONTS   ?= Ohlfs9 Helve12
UI      := Graphics UIKit $(FONTS) FontManager InputManager WindowManager \
           ClipboardManager MenuManager View Control Button TextView \
           TextField Switch Select ListView ScrollView Window Dialog FileDialog
APPS    := UIMouse Terminal GraphicsWindow
TESTS   := FatFSTest Payload GfxDemo TestFB
MODULES := $(SYSTEM) $(UI) $(APPS) $(TESTS)

.PHONY: all test fonts clean

all:
	@mkdir -p $(B)
	@cp src/*.Mod src/*.s app/*/*.Mod app/*/*.s sample/*.Mod test/*.Mod $(B)/
	@cp $(OUT) $(B)/Out.Mod
	@for f in $(FONTS); do cp fonts/$$f.Mod $(B)/; done
	@cd $(B) && for m in $(MODULES); do \
	  if [ -f $$m.s ]; then $(abspath $(ASM)) -o $$m.816 $$m.s > $$m.log 2>&1; \
	  else $(abspath $(OC)) $$m.Mod -s > $$m.log 2>&1; fi; \
	  if [ ! -f $$m.816 ] || grep -q "FAIL\|Error\|  pos " $$m.log; then \
	    echo "$$m: failed"; cat $$m.log; exit 1; fi; \
	  rm -f $$m.log; \
	done
	@echo "OS16 built in $(B)/"

test: all
	@cd $(B) && rm -f fs.img && dd if=/dev/zero of=fs.img bs=1024 count=720 2> /dev/null && \
	  echo "" | perl -e 'alarm 60; exec @ARGV' $(abspath $(EM16)) -disk0 fs.img FatFSTest.816 2> /dev/null \
	    | sed -nE '/^driver /,/^(gone|still there)$$/p' > FatFSTest.out; \
	  if cmp -s FatFSTest.out ../test/FatFSTest.expected; then echo "PASS FatFSTest"; \
	  else echo "FAIL FatFSTest"; diff ../test/FatFSTest.expected FatFSTest.out; exit 1; fi

fonts:
	@mkdir -p $(B)
	@cp $(OUT) $(B)/Out.Mod; cp fonts/*.Mod $(B)/
	@cd $(B) && for f in ../fonts/*.Mod; do m=$$(basename $$f .Mod); \
	  $(abspath $(OC)) $$m.Mod -s > /dev/null 2>&1 || echo "$$m: failed"; done

clean:
	rm -rf $(B)
