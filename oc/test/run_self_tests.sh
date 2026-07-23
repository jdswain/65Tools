#!/bin/bash
# run_self_tests.sh — drive the em16 golden suite with the self-hosted
# Oberon compiler (oc816) instead of the C reference compiler.
#
# This is a copy of the per-level runners' logic, generalised over all
# levels and with the compiler overridable. The C compiler and its own
# run_level*_tests.sh scripts stay untouched as the reference.
#
# Usage:
#   OC=/path/to/oc816 ./test/run_self_tests.sh [level ...]
#     OC     compiler binary (default: the built self/s816/oc816 in the oc repo)
#     args   optional list of level prefixes to run (e.g. L1 L5); default all
#
# Parity note: oc816 uses the shared (latest) Oberon frontend. Its REAL
# literal conversion is correctly-rounded and can differ in the last
# printed digit from the C compiler's (e.g. 3.14159 vs 3.14158) — oc816 is
# the accurate one. Such REAL-precision goldens predate the switchover.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

OC="${OC:-$PROJECT_DIR/../../../oc/self/s816/oc816}"
EM16="${EM16:-$PROJECT_DIR/../bin/em16}"
TIMEOUT_SECS="${TIMEOUT_SECS:-5}"

if [ ! -x "$OC" ];   then echo "ERROR: compiler not found/executable at $OC"; exit 1; fi
if [ ! -x "$EM16" ]; then echo "ERROR: emulator not found at $EM16"; exit 1; fi

# Work in a scratch dir so oc816's v5 .smb / .816 artifacts never clobber
# the C compiler's outputs in test/.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$SCRIPT_DIR"/*.Mod "$WORK"/ 2>/dev/null
cp "$SCRIPT_DIR"/*.expected "$WORK"/ 2>/dev/null
cd "$WORK" || exit 1

# Pre-compile library modules so dependencies resolve.
for lib in Out Runtime TestTool; do
  [ -f "$lib.Mod" ] && "$OC" "$lib.Mod" -s >/dev/null 2>&1
done

# Pre-compile helper/dependency modules — any *.Mod that is not a library and
# has no *.expected of its own (e.g. the cross-module OO base/extension, or
# L*_Lib helpers). Two passes so an extension picks up its base's fresh .smb.
for pass in 1 2; do
  for m in *.Mod; do
    bn="${m%.Mod}"
    case "$bn" in Out|Runtime|TestTool) continue;; esac
    [ -f "$bn.expected" ] && continue   # a test driver — compiled+run below
    "$OC" "$m" -s >/dev/null 2>&1
  done
done

LEVELS=("$@")
if [ ${#LEVELS[@]} -eq 0 ]; then
  # Discover level prefixes present as *.expected (L0..L15, sorted numerically).
  LEVELS=($(ls L*.expected 2>/dev/null | sed -E 's/^(L[0-9]+)_.*/\1/' | sort -u -t L -k2 -n))
fi

TOTAL=0; PASS=0; FAIL=0; SKIP=0
for lvl in "${LEVELS[@]}"; do
  for exp in "${lvl}"_*.expected; do
    [ -f "$exp" ] || continue
    TOTAL=$((TOTAL + 1))
    bn="$(basename "$exp" .expected)"
    marker="$(head -1 "$exp")"

    # "!skip <reason>": a known gap (unsupported feature, missing dependency
    # modules). Documented, not counted as a failure.
    if [ "${marker%% *}" = "!skip" ]; then
      echo "SKIP  $bn (${marker#!skip })"; SKIP=$((SKIP + 1)); continue
    fi

    if [ ! -f "$bn.Mod" ]; then echo "SKIP  $bn (no .Mod)"; SKIP=$((SKIP + 1)); continue; fi
    out="$("$OC" "$bn.Mod" 2>&1)"

    # "!compile-error": a negative test — a compile error IS the expected
    # (passing) result. Remaining lines are substrings that must all appear in
    # the diagnostics, so the test pins down WHICH error is reported.
    if [ "$marker" = "!compile-error" ]; then
      if echo "$out" | grep -q "  pos [0-9]"; then
        ok=1
        while IFS= read -r sub; do
          [ -z "$sub" ] && continue
          echo "$out" | grep -qF "$sub" || ok=0
        done < <(tail -n +2 "$exp")
        if [ "$ok" = 1 ]; then
          echo "PASS  $bn (rejected as expected)"; PASS=$((PASS + 1))
        else
          echo "FAIL  $bn (wrong diagnostic)"; echo "$out" | grep "  pos [0-9]" | head -1 | sed 's/^/      /'
          FAIL=$((FAIL + 1))
        fi
      else
        echo "FAIL  $bn (expected a compile error, got none)"; FAIL=$((FAIL + 1))
      fi
      continue
    fi

    # Positive test.
    if echo "$out" | grep -q "  pos [0-9]"; then
      echo "FAIL  $bn (compile error)"; echo "$out" | grep "  pos [0-9]" | head -2 | sed 's/^/      /'
      FAIL=$((FAIL + 1)); continue
    fi
    [ -f "$bn.816" ] || { echo "SKIP  $bn (no .816)"; SKIP=$((SKIP + 1)); continue; }
    full="$(echo "" | perl -e "alarm $TIMEOUT_SECS; exec @ARGV" "$EM16" "$bn.816" 2>/dev/null)"
    [ $? -eq 142 ] && { echo "FAIL  $bn (timeout)"; FAIL=$((FAIL + 1)); continue; }
    # Output from the first module init through to "Executed" — this includes
    # the deterministic "OK" startup line most goldens in this tree capture.
    # (The C run_level*_tests.sh reset the buffer per-init and so strip it; the
    # goldens are historically inconsistent about it, so this runner keeps the
    # OK-including convention and owns its own regenerated goldens.)
    actual="$(echo "$full" | awk '/^Initialising at/{f=1;next} /^Executed /{exit} f{print}')"
    if [ "$actual" = "$(cat "$exp")" ]; then
      echo "PASS  $bn"; PASS=$((PASS + 1))
    else
      echo "FAIL  $bn (output mismatch)"; FAIL=$((FAIL + 1))
    fi
  done
done

echo ""
echo "=== oc816 self-test results ==="
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL  Skip: $SKIP"
[ $FAIL -gt 0 ] && exit 1 || exit 0
