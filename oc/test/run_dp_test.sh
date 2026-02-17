#!/bin/bash
# DP relocation test: runs all test levels with Direct Page at $0200
# Verifies that all generated code uses DP-relative addressing correctly

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OC="$PROJECT_DIR/bin/oc"
EM16="$PROJECT_DIR/../bin/em16"
DP_ADDR="0x0200"
TIMEOUT_SECS=5

PASS=0
FAIL=0
TOTAL=0

if [ ! -x "$OC" ]; then
  echo "ERROR: Compiler not found at $OC"
  exit 1
fi

if [ ! -x "$EM16" ]; then
  echo "ERROR: Emulator not found at $EM16"
  exit 1
fi

echo "=== DP Relocation Test (DP=$DP_ADDR) ==="
echo "Compiler: $OC"
echo "Emulator: $EM16"
echo ""

# Pre-compile library modules needed by L9 tests
for lib in Out L9_Lib L9_Base L9_Mid L9_TypeBase L9_TypeLib; do
  libfile="$SCRIPT_DIR/$lib.Mod"
  if [ -f "$libfile" ]; then
    compile_output=$("$OC" "$libfile" /s 2>&1)
    if echo "$compile_output" | grep -q "  pos [0-9]"; then
      echo "ERROR: Failed to compile library $lib"
      echo "$compile_output" | grep "  pos [0-9]" | head -3 | sed 's/^/      /'
      exit 1
    fi
  fi
done

# Run all test levels (L1-L13) with -dp flag
for expected_file in "$SCRIPT_DIR"/L[0-9]_*.expected "$SCRIPT_DIR"/L[0-9][0-9]_*.expected; do
  [ -f "$expected_file" ] || continue

  basename=$(basename "$expected_file" .expected)

  # Skip library-only modules (no expected output to compare)
  case "$basename" in
    L9_Lib|L9_Base|L9_Mid|L9_TypeBase|L9_TypeLib) continue ;;
  esac

  # Skip L12 negative tests (compile-time error tests, no emulation)
  case "$basename" in
    L12_*) continue ;;
  esac

  TOTAL=$((TOTAL + 1))

  modfile="$SCRIPT_DIR/$basename.Mod"
  objfile="$SCRIPT_DIR/$basename.816"

  if [ ! -f "$modfile" ]; then
    echo "SKIP  $basename (no .Mod file)"
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
    continue
  fi

  # Run through emulator with DP at custom address
  full_output=$(echo "" | perl -e "alarm $TIMEOUT_SECS; exec @ARGV" "$EM16" -dp "$DP_ADDR" "$objfile" 2>/dev/null)
  run_rc=$?

  if [ $run_rc -eq 142 ]; then
    echo "FAIL  $basename (timeout)"
    FAIL=$((FAIL + 1))
    continue
  fi

  # Auto-detect awk pattern based on expected file convention:
  # L0 tests and tests starting with "OK": capture from first "Initialising at"
  #   (expected includes library init output like "OK" or "TTB")
  # Other tests: capture from LAST "Initialising at" only
  #   (expected does not include library init output)
  expected=$(cat "$expected_file")
  first_line=$(echo "$expected" | head -1)

  if [ "$first_line" = "OK" ] || [[ "$basename" == L0_* ]]; then
    actual=$(echo "$full_output" | awk '/^Initialising at/{found=1; next} /^Executed /{exit} found{print}')
  else
    actual=$(echo "$full_output" | awk '/^Initialising at/{found=1; buf=""; next} /^Executed /{exit} found{buf = buf (buf ? "\n" : "") $0} END{print buf}')
  fi

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
echo "=== Results (DP=$DP_ADDR) ==="
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"

if [ $FAIL -gt 0 ]; then
  exit 1
fi
exit 0
