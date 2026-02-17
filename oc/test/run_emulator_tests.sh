#!/bin/bash
# Automated emulator test script
# Compiles .Mod files, runs them through the emulator, and compares UART output

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OC="$PROJECT_DIR/bin/oc"
EM16="$PROJECT_DIR/../bin/em16"
TIMEOUT_SECS=5

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

# Library modules that other tests may depend on
LIBRARY_MODULES=("Out" "Runtime" "TestTool")

# Get list of dependency .816 files for a module
# Parses IMPORT line and returns .816 paths for non-SYSTEM imports
get_dependencies() {
  local modfile="$1"
  local deps=""
  local import_line
  import_line=$(grep "IMPORT" "$modfile" | head -1)
  if [ -z "$import_line" ]; then
    echo ""
    return
  fi
  # Extract module names from IMPORT line (strip IMPORT keyword, semicolons, commas, CR)
  local modules
  modules=$(echo "$import_line" | tr -d '\r' | sed 's/.*IMPORT//; s/;//; s/,/ /g')
  for mod in $modules; do
    mod=$(echo "$mod" | tr -d ' ')
    if [ "$mod" = "SYSTEM" ] || [ -z "$mod" ]; then
      continue
    fi
    local dep_816="$SCRIPT_DIR/$mod.816"
    if [ -f "$dep_816" ]; then
      deps="$deps $dep_816"
    fi
  done
  echo "$deps"
}

echo "=== Oberon Emulator Tests ==="
echo "Compiler: $OC"
echo "Emulator: $EM16"
echo ""

# Pre-compile library modules so dependencies are available
for lib in "${LIBRARY_MODULES[@]}"; do
  libfile="$SCRIPT_DIR/$lib.Mod"
  if [ -f "$libfile" ]; then
    "$OC" "$libfile" -s >/dev/null 2>&1
  fi
done

for expected_file in "$SCRIPT_DIR"/*.expected; do
  [ -f "$expected_file" ] || continue
  # Skip levelled tests (L1_, L2_, etc.) — they have their own runners
  case "$(basename "$expected_file")" in L[0-9]*) continue;; esac
  TOTAL=$((TOTAL + 1))

  basename=$(basename "$expected_file" .expected)
  modfile="$SCRIPT_DIR/$basename.Mod"
  objfile="$SCRIPT_DIR/$basename.816"

  if [ ! -f "$modfile" ]; then
    echo "SKIP  $basename (no .Mod file)"
    SKIP=$((SKIP + 1))
    continue
  fi

  # Compile
  compile_output=$("$OC" "$modfile" 2>&1)
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

  # Find dependency .816 files for multi-module tests
  dep_files=$(get_dependencies "$modfile")

  # Run through emulator with timeout (dependencies loaded before main module)
  full_output=$(echo "" | perl -e "alarm $TIMEOUT_SECS; exec @ARGV" "$EM16" $dep_files "$objfile" 2>/dev/null)
  run_rc=$?

  if [ $run_rc -eq 142 ]; then
    echo "FAIL  $basename (timeout)"
    FAIL=$((FAIL + 1))
    continue
  fi

  # Extract just the program's UART output
  # Everything after first "Initialising at" and before "Executed" stats line,
  # excluding "Initialising at" lines themselves
  actual=$(echo "$full_output" | awk '/^Initialising at/{found=1; next} /^Executed /{exit} found{print}')

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
