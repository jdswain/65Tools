#!/bin/bash
# Level 15 DrawGlyph + bank-aware data access tests
# Compiles L15_*.Mod files, runs them through the emulator, compares UART output
# These tests require modules from multiple directories:
#   test/Out.816, ../OS16/src/UIGraphics.816, ../FontTool/fonts/*.816

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OC="$PROJECT_DIR/bin/oc"
EM16="$PROJECT_DIR/../bin/em16"
TIMEOUT_SECS=10

PASS=0
FAIL=0
SKIP=0
TOTAL=0

if [ ! -x "$OC" ]; then
  echo "ERROR: Compiler not found at $OC"
  exit 1
fi

if [ ! -x "$EM16" ]; then
  echo "ERROR: Emulator not found at $EM16"
  echo "Build with: cd ../em16 && make -f Makefile.macos"
  exit 1
fi

# Pre-compile library modules
for lib in Out; do
  libfile="$SCRIPT_DIR/$lib.Mod"
  if [ -f "$libfile" ]; then
    "$OC" "$libfile" -s >/dev/null 2>&1
  fi
done

echo "=== Level 15: DrawGlyph + Bank-Aware Data Tests ==="
echo "Compiler: $OC"
echo "Emulator: $EM16"
echo ""

for expected_file in "$SCRIPT_DIR"/L15_*.expected; do
  [ -f "$expected_file" ] || continue
  TOTAL=$((TOTAL + 1))

  basename=$(basename "$expected_file" .expected)
  modfile="$SCRIPT_DIR/$basename.Mod"
  objfile="$SCRIPT_DIR/$basename.816"

  if [ ! -f "$modfile" ]; then
    echo "SKIP  $basename (no .Mod file)"
    SKIP=$((SKIP + 1))
    continue
  fi

  # Compile with search paths for Graphics and font modules
  compile_output=$("$OC" "$modfile" -I "$PROJECT_DIR/../OS16/src" -I "$PROJECT_DIR/../FontTool/fonts" 2>&1)
  if echo "$compile_output" | grep -q "  pos [0-9]"; then
    echo "FAIL  $basename (compilation error)"
    echo "$compile_output" | grep "  pos [0-9]" | head -3 | sed 's/^/      /'
    FAIL=$((FAIL + 1))
    continue
  fi

  if [ ! -f "$objfile" ]; then
    echo "SKIP  $basename (no .816 output)"
    SKIP=$((SKIP + 1))
    continue
  fi

  # Collect dependency .816 files (Out, UIGraphics, fonts)
  deps=""
  deps="$deps $SCRIPT_DIR/Out.816"
  [ -f "$PROJECT_DIR/../OS16/src/UIGraphics.816" ] && deps="$deps $PROJECT_DIR/../OS16/src/UIGraphics.816"

  # Add font modules referenced by the test (scan IMPORT list)
  for font_816 in "$PROJECT_DIR/../FontTool/fonts"/*.816; do
    font_name=$(basename "$font_816" .816)
    if grep -q "IMPORT.*$font_name" "$modfile" 2>/dev/null; then
      deps="$deps $font_816"
    fi
  done

  # Run through emulator with all dependencies
  full_output=$(echo "" | perl -e "alarm $TIMEOUT_SECS; exec @ARGV" "$EM16" $deps "$objfile" 2>/dev/null)
  run_rc=$?

  if [ $run_rc -eq 142 ]; then
    echo "FAIL  $basename (timeout)"
    FAIL=$((FAIL + 1))
    continue
  fi

  # Extract just the program's UART output
  actual=$(echo "$full_output" | awk '/^Initialising at/{found=1; buf=""; next} /^Executed /{exit} found{buf = buf (buf ? "\n" : "") $0} END{print buf}')

  expected=$(cat "$expected_file")

  if [ "$actual" = "$expected" ]; then
    echo "PASS  $basename"
    PASS=$((PASS + 1))
  else
    echo "FAIL  $basename (output mismatch)"
    echo "      Expected: $(echo "$expected" | head -3)"
    echo "      Actual:   $(echo "$actual" | head -3)"
    FAIL=$((FAIL + 1))
  fi
done

echo ""
echo "=== Results ==="
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL  Skip: $SKIP"

if [ $FAIL -gt 0 ]; then
  exit 1
fi
exit 0
