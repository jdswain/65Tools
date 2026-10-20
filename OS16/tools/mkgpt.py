#!/usr/bin/env python3
"""A SCSI disk image with a GUID partition table, for make test-disk.

    mkgpt.py disk.img           write it: 32768 blocks of 512 bytes, a
                                protective MBR, the GPT and its backup,
                                partition 1 "OS16 System" (blocks 40 to
                                2919, 2880 blocks) and partition 2
                                "OS16 Data" (blocks 4096 to 32734), both
                                empty (zeros)
    mkgpt.py --check disk.img   after DiskTest: what is on it, a line each

--check prints that the GPT is still valid, what each partition holds (the
OEM name and layout of a FAT boot sector, and the files of its root
directory) and whether anything outside the partitions was written.
"""
import contextlib
import io
import os
import struct
import sys
import tempfile
import uuid
import zlib

BLOCKS = 32768
BS = 512
ENTRIES = 128
ESIZE = 128
BASIC_DATA = uuid.UUID("EBD0A0A2-B9E5-4433-87C0-68B6B72699C7")
DISK_GUID = uuid.UUID("0516C0DE-0000-4000-8000-000000000016")
PARTS = [  # first, last, name, unique GUID
    (40, 2919, "OS16 System", uuid.UUID("0516C0DE-0001-4000-8000-000000000001")),
    (4096, 32734, "OS16 Data", uuid.UUID("0516C0DE-0002-4000-8000-000000000002")),
]
FIRST_USABLE = 34
LAST_USABLE = BLOCKS - 34


def entries():
    e = bytearray(ENTRIES * ESIZE)
    for i, (first, last, name, guid) in enumerate(PARTS):
        n = name.encode("utf-16-le").ljust(72, b"\0")
        e[i * ESIZE:(i + 1) * ESIZE] = (BASIC_DATA.bytes_le + guid.bytes_le
                                        + struct.pack("<QQQ", first, last, 0) + n)
    return bytes(e)


def header(current, backup, entries_lba, ecrc):
    h = bytearray(struct.pack("<8sIIIIQQQQ16sQIII", b"EFI PART", 0x10000, 92, 0, 0,
                              current, backup, FIRST_USABLE, LAST_USABLE,
                              DISK_GUID.bytes_le, entries_lba, ENTRIES, ESIZE, ecrc))
    struct.pack_into("<I", h, 16, zlib.crc32(bytes(h)))
    return bytes(h).ljust(BS, b"\0")


def write(path):
    img = bytearray(BLOCKS * BS)
    mbr = bytearray(BS)   # protective MBR: one partition of type EE, all of it
    mbr[446:462] = struct.pack("<BBBBBBBBII", 0, 0, 2, 0, 0xEE, 0xFF, 0xFF, 0xFF, 1, BLOCKS - 1)
    mbr[510:512] = b"\x55\xAA"
    img[0:BS] = mbr
    e = entries()
    ecrc = zlib.crc32(e)
    img[BS:2 * BS] = header(1, BLOCKS - 1, 2, ecrc)
    img[2 * BS:2 * BS + len(e)] = e
    backup_entries = BLOCKS - 1 - len(e) // BS
    img[backup_entries * BS:backup_entries * BS + len(e)] = e
    img[(BLOCKS - 1) * BS:] = header(BLOCKS - 1, 1, backup_entries, ecrc)
    with open(path, "wb") as f:
        f.write(img)
    print(f"{path}: {BLOCKS} blocks, GPT, {len(PARTS)} partitions")


def check(path):
    img = open(path, "rb").read()
    # the GPT
    ok = True
    for lba in (1, BLOCKS - 1):
        h = bytearray(img[lba * BS:lba * BS + 92])
        crc = struct.unpack_from("<I", h, 16)[0]
        struct.pack_into("<I", h, 16, 0)
        at, n, size, ecrc = struct.unpack_from("<QIII", h, 72)
        e = img[at * BS:at * BS + n * size]
        ok = ok and h[:8] == b"EFI PART" and zlib.crc32(bytes(h)) == crc and zlib.crc32(e) == ecrc
    print("image: GPT", "valid" if ok else "BAD")
    for p, (first, last, _, _) in enumerate(PARTS, 1):
        boot = img[first * BS:(first + 1) * BS]
        oem = boot[3:11].decode("ascii", "replace").rstrip()
        print(f"image: partition {p} boot sector OEM {oem!r}, signature {boot[510:512].hex()}")
        if boot[510:512] == b"\x55\xaa":
            spc, res, nfat = boot[13], boot[14] | boot[15] << 8, boot[16]
            root, tot, fpf = boot[17] | boot[18] << 8, boot[19] | boot[20] << 8, boot[22] | boot[23] << 8
            print(f"image: partition {p} {tot} sectors, clusters of {spc}, FAT of {fpf}, root of {root}")
            rootat = first + res + nfat * fpf
            names = []
            for i in range(root):
                d = img[rootat * BS + i * 32:rootat * BS + i * 32 + 32]
                if d[0] == 0:
                    break
                if d[0] != 0xE5 and d[11] != 0x0F:
                    names.append(d[0:8].decode().rstrip() + "." + d[8:11].decode().rstrip()
                                 + f" {int.from_bytes(d[28:32], 'little')}")
            print(f"image: partition {p} root:", ", ".join(names) if names else "(empty)")
    # outside the partitions: as written
    with tempfile.TemporaryDirectory() as d:
        with contextlib.redirect_stdout(io.StringIO()):
            write(os.path.join(d, "orig.img"))
        orig = open(os.path.join(d, "orig.img"), "rb").read()
    outside, at = True, 0
    for first, last, _, _ in PARTS + [(BLOCKS, BLOCKS, None, None)]:
        outside = outside and img[at * BS:first * BS] == orig[at * BS:first * BS]
        at = last + 1
    print("image: outside the partitions", "untouched" if outside else "CHANGED")

if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--check":
        check(sys.argv[2])
    elif len(sys.argv) == 2:
        write(sys.argv[1])
    else:
        sys.exit(__doc__)
