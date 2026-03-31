#!/bin/bash
set -e

IMG=/tmp/boottest.dmg

# Usage: make_test_disk.sh <file.816> [<file2.816> ...]
if [ $# -eq 0 ]; then
  echo "Usage: $0 <file.816> [<file2.816> ...]"
  exit 1
fi

# Clean up any previous image
rm -f "$IMG"

# Create 720K FAT12 image
hdiutil create -size 720k -fs "MS-DOS FAT12" -layout NONE -o "${IMG%.dmg}"

# Mount the image
ATTACH_OUTPUT=$(hdiutil attach -imagekey diskimage-class=CRawDiskImage "$IMG")
DEV=$(echo "$ATTACH_OUTPUT" | tail -1 | awk '{print $1}')
MOUNT_POINT=$(echo "$ATTACH_OUTPUT" | grep -o '/Volumes/.*')

if [ -z "$MOUNT_POINT" ] || [ ! -d "$MOUNT_POINT" ]; then
  echo "Failed to mount image. Output was:"
  echo "$ATTACH_OUTPUT"
  hdiutil detach "$DEV" 2>/dev/null || true
  exit 1
fi

echo "Mounted at: $MOUNT_POINT"

# Create directory structure
mkdir -p "$MOUNT_POINT/Library/Modules"

# Copy all specified .816 files
for f in "$@"; do
  cp "$f" "$MOUNT_POINT/Library/Modules/"
  echo "Copied $(basename "$f")"
done

ls -la "$MOUNT_POINT/Library/Modules/"

# Unmount
hdiutil detach "$DEV"
echo "Boot disk created: $IMG"
