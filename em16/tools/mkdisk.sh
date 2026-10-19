#!/bin/sh
# mkdisk.sh - disk images for em16 -fpga, made and opened on the Mac.
#
#   mkdisk.sh create image size [file ...]   a FAT volume, with the files in its root
#   mkdisk.sh mount image                    open it in the Finder (/Volumes/...)
#   mkdisk.sh unmount image                  close it again before em16 uses it
#
# size is 720k, 1440k or 2880k for a floppy (-disk0, -disk1: FAT12, as
# a PC formats one), or any other size, such as 5m, for the SCSI disk
# (-scsi: FAT16). The image is the volume alone, from block 0, with no
# partition map, which is what em16 and the boot code read.
set -e

usage() { sed -n '3,6p' "$0" | sed 's/^# //' >&2; exit 2; }

# the /dev/diskN that holds the image, if it is attached
device() {
  hdiutil info | awk -v img="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")" '
    /^image-path/ { sub(/^image-path *: */, ""); p = ($0 == img) }
    p && /^\/dev\/disk/ { print $1; exit }'
}

case "$1" in
create)
  [ $# -ge 3 ] || usage
  img=$2; size=$3; shift 3
  case "$size" in
    720k|720K|1440k|1440K|2880k|2880K) fs="MS-DOS FAT12" ;;
    *) fs="MS-DOS FAT16" ;;
  esac
  tmp=$(mktemp -d)
  hdiutil create -quiet -size "$size" -fs "$fs" -volname EM16 -layout NONE -o "$tmp/disk"
  mv "$tmp/disk.dmg" "$img"; rmdir "$tmp"
  # hdiutil gives a floppy 32 sectors a track and 16 heads; a PC's boot
  # sector says what the disk is: sectors a track, 2 heads, the media byte
  case "$size" in
    720k|720K)   spt='\011'; media='\371' ;;
    1440k|1440K) spt='\022'; media='\360' ;;
    2880k|2880K) spt='\044'; media='\360' ;;
    *) spt= ;;
  esac
  if [ -n "$spt" ]; then
    printf "$media" | dd of="$img" bs=1 seek=21 conv=notrunc 2>/dev/null
    printf "$spt\000\002\000" | dd of="$img" bs=1 seek=24 conv=notrunc 2>/dev/null
    printf "$media" | dd of="$img" bs=1 seek=512 conv=notrunc 2>/dev/null
  fi
  if [ $# -gt 0 ]; then
    out=$(hdiutil attach -imagekey diskimage-class=CRawDiskImage "$img")
    dev=$(echo "$out" | tail -1 | awk '{print $1}')
    vol=$(echo "$out" | grep -o '/Volumes/.*' | tail -1)
    cp "$@" "$vol/"
    hdiutil detach -quiet "$dev"
  fi
  echo "$img: $(wc -c < "$img" | tr -d ' ') bytes, $fs"
  ;;
mount)
  [ $# -eq 2 ] || usage
  hdiutil attach -imagekey diskimage-class=CRawDiskImage "$2" | grep -o '/Volumes/.*'
  ;;
unmount|umount)
  [ $# -eq 2 ] || usage
  case "$2" in
    /Volumes/*) hdiutil detach "$2" ;;
    *) dev=$(device "$2"); [ -n "$dev" ] || { echo "$2 is not mounted" >&2; exit 1; }
       hdiutil detach "$dev" ;;
  esac
  ;;
*) usage ;;
esac
