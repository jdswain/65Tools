#!/bin/bash
# Level 12 negative tests — compiler error detection
# Compiles L12_*.Mod files and checks that compilation FAILS with the expected error

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OC="$PROJECT_DIR/bin/oc"

PASS=0
FAIL=0
SKIP=0
TOTAL=0

if [ ! -x "$OC" ]; then
  echo "ERROR: Compiler not found at $OC"
  exit 1
fi

echo "=== Level 12: Negative Tests (Compiler Error Detection) ==="
echo "Compiler: $OC"
echo ""

for expected_file in "$SCRIPT_DIR"/L12_*.expected; do
  [ -f "$expected_file" ] || continue
  TOTAL=$((TOTAL + 1))

  basename=$(basename "$expected_file" .expected)
  modfile="$SCRIPT_DIR/$basename.Mod"

  if [ ! -f "$modfile" ]; then
    echo "SKIP  $basename (no .Mod file)"
    SKIP=$((SKIP + 1))
    continue
  fi

  # Read expected error substring (first line, trimmed)
  expected_error=$(head -1 "$expected_file" | tr -d '\r\n')

  # Compile — we expect this to FAIL
  compile_output=$("$OC" "$modfile" 2>&1)

  # Check if compilation produced errors
  if echo "$compile_output" | grep -q "  pos [0-9]"; then
    # Compilation failed (good) — check for expected error substring
    if echo "$compile_output" | grep "  pos [0-9]" | grep -q "$expected_error"; then
      echo "PASS  $basename"
      PASS=$((PASS + 1))
    else
      echo "FAIL  $basename (wrong error)"
      echo "      Expected substring: $expected_error"
      echo "      Actual errors:"
      echo "$compile_output" | grep "  pos [0-9]" | head -3 | sed 's/^/      /'
      FAIL=$((FAIL + 1))
    fi
  else
    # Compilation succeeded — that's a failure for negative tests
    echo "FAIL  $basename (compilation should have failed)"
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
