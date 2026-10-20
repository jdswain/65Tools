# OS16

The operating system for the 65C816 machines, in Oberon (compiled by
oc816) and 65C816 assembly (`as`).

    make            build everything into build/
    make test       boot PAYLOAD.816 off a floppy on em16 -fpga
    make test-fs    FatFSTest; needs an em16 with the 82077AA (Hardware)
    make test-disk  DiskTest; needs an em16 with the 53C80 (Hardware)
    make fonts      compile every font, not only those used

## Layout

    src/       a directory for each package of the OS16 model, with a
               module for each of its classes and the support modules
               they need:
      Kernel/      BootManager, ModuleManager, MemoryManager,
                   ProcessManager; HeapManager, InterruptManager,
                   MakeImage; Numerics
      Driver/      Driver, CharacterDriver, BlockDriver, BusDriver,
                   NetworkInterface, Serial, Floppy, SCSIManager,
                   SCSIDisk, DiskPartition, ADBManager
      Filesystem/  Files, FatFS
      UI/          Graphics.s, UIKit, FontManager, InputManager,
                   WindowManager, ClipboardManager, MenuManager,
                   EventManager, View and the controls, Window, Dialog,
                   FileDialog
    fonts/     the bitmap fonts, a module each (made by FontTool)
    app/       applications: terminal/ (Terminal, and its mouse
               cursor UIMouse.s)
    sample/    GraphicsWindow, a window drawn with Graphics
    test/      FatFSTest (make test-fs), DiskTest (make test-disk),
               Boot.expected (make test), and the boot loader's
               payloads: Payload, GfxDemo, TestFB
    tools/     makerom.py (a boot ROM from BootManager.816),
               makepayload.py (a payload for the boot loader),
               mkgpt.py (the GPT disk image of make test-disk)
    images/    BootDisk.img
    resources/ the fonts' bitmap sources
    doc/       design notes and plans
    attic/     what is no longer used (below)
    build/     what make writes; not in git

The build copies the packages' sources into build/ and compiles them
there, so a module imports another by name whatever its package.

## The model

The classes are those of the OS16 model in EOModeller (`qa/os16`,
package Structure), in its containers Kernel, Driver, Filesystem and
UI, the directories of src/ (Numerics is in none; it is in Kernel).
Each is a module of the same name. A class in the model's inheritance
tree is also a type, `Module.Module`, extending its parent's type, with
the parent's procedures as methods that the child overrides:

    Driver                      Get, Set
      CharacterDriver           Read, Write
        Serial
      BlockDriver               ReadBlock, WriteBlock, Blocks
        Floppy
        SCSIDisk                a disk on the SCSI bus, all of it
        DiskPartition           a GPT partition of another BlockDriver
      BusDriver                 Reset, Poll
        ADBManager
        SCSIManager             Command
      NetworkInterface
    Files                       Format, Mount, Sync, Old, New, Register,
                                Close, Delete, Rename, Length, Date,
                                CreateDir, RemoveDir, ReadByte, WriteByte
      FatFS
    View                        Draw, Handle, SetBounds, Contains
      Control                   enabled, value
        Button  TextView  TextField  Switch  Select  ListView
      ScrollView
      Window
      Dialog
        FileDialog

(Files' type is Files.FileSystem.) The managers and services that stand
alone are modules without a type, an Oberon module being an object of
which there is one: BootManager, ModuleManager, MemoryManager,
ProcessManager, EventManager, InputManager, MenuManager, WindowManager,
ClipboardManager, FontManager, Graphics, Numerics.

Where each came from:

| Class | Was |
|---|---|
| BootManager | `boot/Boot.Mod`, then BootLoader |
| ModuleManager | `src/Modules.Mod`, then ModuleLoader |
| MemoryManager, EventManager, ADBManager | the same, ADBManager now also a BusDriver |
| Driver, CharacterDriver, BlockDriver | the records of procedure variables in `src/Driver.Mod` |
| Floppy | `src/FloppyDriver.Mod`; its state is now per drive |
| Files | the interface of `src/Files.Mod`: Files, Riders and the directory, through the FileSystem mounted (the class was FileSystem) |
| FatFS | the rest of `src/Files.Mod`, as a FileSystem |
| SCSIManager, SCSIDisk, DiskPartition | new (DiskPartition was the HardDisk skeleton) |
| Graphics | `src/UIGraphics.s` |
| FontManager | `src/UIText.Mod` |
| Window | `app/terminal/UIWindow.Mod` |
| MenuManager | `app/terminal/UIMenuBar.Mod` (its type is MenuBar) |
| BusDriver, View, Control | new: the base types |
| ProcessManager, Serial, NetworkInterface, Numerics, InputManager, WindowManager, ClipboardManager, Button, TextView, TextField, Switch, Select, ListView, ScrollView, Dialog, FileDialog | new skeletons: the type and its parent, no behaviour yet |

Support modules, needed but not classes of the model: HeapManager (the
heap NEW allocates from, inside a MemoryManager block),
InterruptManager (the IRQ trampoline and its handlers), UIKit (the
screen's size and colours), MakeImage (the kernel image tool, on
ModuleManager), and Out (taken from `../oc/test`).

Clients use files through Files alone, the interface `src/Files.Mod`
had: Old, New, Register, Close, Delete, Rename, Length, Date,
CreateDir, RemoveDir, Riders (Set, Pos, Base, Read, ReadInt,
ReadString, ReadBytes and the Writes) and Init and Format on a block
device. Files passes each to a FileSystem's methods: to the mounted
one, or to the one a file is on. A file system reads and writes a file
a byte at a time, at a position; the riders are Files' own. FatFS,
when loaded, installs itself as the file system Init and Format make
for a device (Files.Install); Files.Mount mounts one made directly.

## Disks

A file system is on a BlockDriver, which it is given (Files.Init(d),
FatFS.ForDevice(d)) and reads and writes by block number only, a
LONGINT; Blocks() is its size. The block drivers:

    Floppy          a drive of the 82077AA
    SCSIDisk        a disk on the SCSI bus, all of it: READ(10),
                    WRITE(10), READ CAPACITY, through its SCSIManager
    DiskPartition   blocks first .. first + count - 1 of another
                    BlockDriver; DiskPartition.Scan reads a disk's GUID
                    partition table and makes one for each partition

    SCSIManager.New()              the bus, reset and scanned (INQUIRY)
    SCSIDisk.New(bus, id)          the disk at an ID
    DiskPartition.Scan(disk, ps)   its partitions, SD0p1, SD0p2, ...
    Files.Init(ps[0])              FatFS on the first

SCSIDisk is a layer of its own, rather than part of SCSIManager or of
DiskPartition: the partition table is on the whole disk, which so is a
BlockDriver itself, and DiskPartition then works on any BlockDriver,
not only a SCSI one. Reading the GPT is DiskPartition's (Scan), which
needs no module of its own. A GPT is checked as UEFI has it: the
signature, the header's CRC32 and that of the entries, the backup
header at the last block if the first is bad.

## Hardware

Floppy and BootManager work the carrier's Intel 82077AA (card 0 of the
SoC's external bus, $0800) by polling: SPECIFY non-DMA, CONFIGURE
implied seek, RECALIBRATE, then READ and WRITE DATA a sector at a time.
The density (720K, 1.44M or 2.88M) is found by reading sector 0 at each
data rate in turn. BootManager and the payloads print on channel A of
the SoC's Z85C30 SCC ($0822 control, $0823 data), BootManager turning
its transmitter on. SCSIManager works the 53C80 of the carrier's Z85C80
(card 3, $0830) by programmed I/O, the initiator at ID 7.

`make test` boots: the boot ROM loads PAYLOAD.816 off a FAT12 floppy on
`em16 -fpga` and runs it. FatFSTest (`make test-fs`) runs as .816
modules, which em16 loads only on its default machine, whose floppy
controller is the WD1793; it passes on an em16 with the 82077AA there
instead (`make test-fs EM16=...`), on 720K and 1.44M disks. DiskTest
(`make test-disk`) runs the same way and needs the 53C80 on the
default machine, which em16 has only under -fpga: it passes on an em16
with it at $0830 there (`make test-disk EM16=...`).

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
