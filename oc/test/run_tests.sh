#!/bin/bash
# Automated compilation test script
# Tests that all .Mod files compile (or fail with known reasons)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OC="$PROJECT_DIR/bin/oc"

PASS=0
FAIL=0
SKIP=0
TOTAL=0

# Known failures - these test files use features not yet implemented
KNOWN_FAILURES=(
)

# Library modules that other tests depend on - compile these first
# Order matters: modules listed first may be imported by later ones
LIBRARY_MODULES=(
  "Out.Mod"
  "Runtime.Mod"
  "TestTool.Mod"
)

is_known_failure() {
  local basename="$1"
  for f in "${KNOWN_FAILURES[@]}"; do
    if [ "$basename" = "$f" ]; then
      return 0
    fi
  done
  return 1
}

if [ ! -x "$OC" ]; then
  echo "ERROR: Compiler not found at $OC"
  echo "Run 'make' first to build the compiler."
  exit 1
fi

is_library_module() {
  local basename="$1"
  for f in "${LIBRARY_MODULES[@]}"; do
    if [ "$basename" = "$f" ]; then
      return 0
    fi
  done
  return 1
}

echo "=== Oberon Compilation Tests ==="
echo "Compiler: $OC"
echo ""

# Compile library modules first (with /s to generate .smb files)
echo "--- Compiling library modules ---"
for lib in "${LIBRARY_MODULES[@]}"; do
  libfile="$SCRIPT_DIR/$lib"
  if [ ! -f "$libfile" ]; then
    continue
  fi
  TOTAL=$((TOTAL + 1))
  output=$("$OC" "$libfile" /s 2>&1)
  if echo "$output" | grep -q "  pos [0-9]"; then
    echo "FAIL  $lib (library)"
    echo "$output" | grep "  pos [0-9]" | head -3 | sed 's/^/      /'
    FAIL=$((FAIL + 1))
  else
    echo "PASS  $lib (library)"
    PASS=$((PASS + 1))
  fi
done
echo ""

for modfile in "$SCRIPT_DIR"/*.Mod; do
  [ -f "$modfile" ] || continue
  TOTAL=$((TOTAL + 1))
  basename=$(basename "$modfile")

  if is_library_module "$basename"; then
    continue  # already compiled above
  fi

  # Skip L12 negative tests — they are expected to fail compilation
  case "$basename" in L12_*) TOTAL=$((TOTAL - 1)); continue ;; esac

  if is_known_failure "$basename"; then
    echo "SKIP  $basename (known limitation)"
    SKIP=$((SKIP + 1))
    continue
  fi

  # Run compiler, capture output and exit code
  output=$("$OC" "$modfile" 2>&1)
  rc=$?

  # Check for compilation errors in output (ORS_Mark produces "  pos N  message")
  if echo "$output" | grep -q "  pos [0-9]"; then
    echo "FAIL  $basename"
    echo "$output" | grep "  pos [0-9]" | head -3 | sed 's/^/      /'
    FAIL=$((FAIL + 1))
  elif [ $rc -ne 0 ]; then
    echo "FAIL  $basename (exit code $rc)"
    FAIL=$((FAIL + 1))
  else
    echo "PASS  $basename"
    PASS=$((PASS + 1))
  fi
done

echo ""
echo "=== Results ==="
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL  Skip: $SKIP"

if [ $FAIL -gt 0 ]; then
  exit 1
fi
exit 0
