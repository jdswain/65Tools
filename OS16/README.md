# OS16

The operating system for the 65C816 machines, in Oberon (compiled by
oc816) and 65C816 assembly (`as`).

    make          build everything into build/
    make test     boot PAYLOAD.816 off a floppy on em16 -fpga
    make test-fs  FatFSTest; needs an em16 with the 82077AA (README)
    make fonts    compile every font, not only those used

## Layout

    src/       a module for each class of the OS16 model, and the
               support modules they need
    fonts/     the bitmap fonts, a module each (made by FontTool)
    app/       applications: terminal/ (Terminal, and its mouse
               cursor UIMouse.s)
    sample/    GraphicsWindow, a window drawn with Graphics
    test/      FatFSTest (make test-fs), Boot.expected (make test), and
               the boot loader's payloads:
               Payload, GfxDemo, TestFB
    tools/     makerom.py (a boot ROM from BootLoader.816),
               makepayload.py (a payload for the boot loader)
    images/    BootDisk.img
    resources/ the fonts' bitmap sources
    doc/       design notes and plans
    attic/     what is no longer used (below)
    build/     what make writes; not in git

## The model

The classes are those of the OS16 model in EOModeller (`qa/os16`,
package Structure). Each is a module of the same name. A class in the
model's inheritance tree is also a type, `Module.Module`, extending its
parent's type, with the parent's procedures as methods that the child
overrides:

    Driver                      Get, Set
      CharacterDriver           Read, Write
        Serial
      BlockDriver               ReadBlock, WriteBlock
        Floppy
        HardDisk
      BusDriver                 Reset, Poll
        ADBManager
        SCSIManager             owns its HardDisks
      NetworkInterface
    FileSystem                  Format, Mount, Sync
      FatFS
    View                        Draw, Handle, SetBounds, Contains
      Control                   enabled, value
        Button  TextView  TextField  Switch  Select  ListView
      ScrollView
      Window
      Dialog
        FileDialog

The managers and services that stand alone are modules without a type,
an Oberon module being an object of which there is one: BootLoader,
ModuleLoader, MemoryManager, ProcessManager, EventManager,
InputManager, MenuManager, WindowManager, ClipboardManager,
FontManager, Graphics, Numerics.

Where each came from:

| Class | Was |
|---|---|
| BootLoader | `boot/Boot.Mod` |
| ModuleLoader | `src/Modules.Mod` |
| MemoryManager, EventManager, ADBManager | the same, ADBManager now also a BusDriver |
| Driver, CharacterDriver, BlockDriver | the records of procedure variables in `src/Driver.Mod` |
| Floppy | `src/FloppyDriver.Mod`; its state is now per drive |
| FatFS | `src/Files.Mod`, with the Files interface kept |
| Graphics | `src/UIGraphics.s` |
| FontManager | `src/UIText.Mod` |
| Window | `app/terminal/UIWindow.Mod` |
| MenuManager | `app/terminal/UIMenuBar.Mod` (its type is MenuBar) |
| BusDriver, FileSystem, View, Control | new: the base types |
| ProcessManager, Serial, HardDisk, SCSIManager, NetworkInterface, Numerics, InputManager, WindowManager, ClipboardManager, Button, TextView, TextField, Switch, Select, ListView, ScrollView, Dialog, FileDialog | new skeletons: the type and its parent, no behaviour yet |

Support modules, needed but not classes of the model: HeapManager (the
heap NEW allocates from, inside a MemoryManager block),
InterruptManager (the IRQ trampoline and its handlers), UIKit (the
screen's size and colours), MakeImage (the kernel image tool, on
ModuleLoader), and Out (taken from `../oc/test`).

## Hardware

Floppy and BootLoader work the carrier's Intel 82077AA (card 0 of the
SoC's external bus, $0800) by polling: SPECIFY non-DMA, CONFIGURE
implied seek, RECALIBRATE, then READ and WRITE DATA a sector at a time.
The density (720K, 1.44M or 2.88M) is found by reading sector 0 at each
data rate in turn. BootLoader and the payloads print on channel A of
the SoC's Z85C30 SCC ($0822 control, $0823 data), BootLoader turning
its transmitter on.

`make test` boots: the boot ROM loads PAYLOAD.816 off a FAT12 floppy on
`em16 -fpga` and runs it. FatFSTest (`make test-fs`) runs as .816
modules, which em16 loads only on its default machine, whose floppy
controller is the WD1793; it passes on an em16 with the 82077AA there
instead (`make test-fs EM16=...`), on 720K and 1.44M disks.

## The attic

    attic/rom/        empty placeholder files
    attic/src/        BootWD1793.Mod (the boot loader of the WD1793 and
                      the ACIA, which em16's compare.sh runs on the
                      default machine), Graphics.s (an older copy of
                      UIGraphics.s) and
                      Graphics (the ELF object as made of it),
                      UIGraphics.s.orig, and
                      UIGraphicsDef.Mod (the stub that let oc816 import
                      the assembled UIGraphics before as wrote oc816's
                      symbol files)
    attic/artifacts/  the .816, .smb and .lst files and editor backups
                      that were beside the sources (not in git)
