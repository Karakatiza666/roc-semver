#!/bin/bash
# All checks of this repository: check, fmt, L0 tests, L1 fuzz targets (fixed count, TW6).
# Usage: scripts/test.sh [ROC [FUZZ_ROC]]. ROC (default: `roc` on PATH, at the nightly of .roc-version)
# runs check, fmt and L0. FUZZ_ROC (default: ROC) checks, builds and runs the fuzz targets.
# Env: RUNS (default 100000). Exit 0 only when all pass.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ROC=${1:-roc}
FUZZ_ROC=${2:-$ROC}
RUNS=${RUNS:-100000}
W=$ROOT/.work
mkdir -p "$W/fuzz"
# No `..` in these paths: roc stops with PathOutsideWorkspace.
export XDG_CACHE_HOME=${XDG_CACHE_HOME:-$W/xdg} ROC_CACHE_DIR=${ROC_CACHE_DIR:-$W/xdg/roc}
cd "$ROOT"
FAIL=0
step() { echo; echo "== $*"; }
rc() { [ "$1" = 0 ] || { echo "FAIL ($1): $2"; FAIL=1; }; }

step "check: $("$ROC" version)"
"$ROC" check package/main.roc; rc $? "check package/main.roc"
for f in tests/*.roc fuzz/*.roc; do "$ROC" check "$f" >/dev/null 2>&1; rc $? "check $f"; done
for f in fuzz/*.roc; do "$FUZZ_ROC" check "$f" >/dev/null 2>&1; rc $? "check $f (fuzz roc)"; done

step "format"
"$ROC" fmt --check package tests fuzz; rc $? "fmt --check"

step "L0"
for f in tests/*.roc; do "$ROC" test "$f" --no-cache; rc $? "test $f"; done

step "L1: $RUNS runs, seed 1, $("$FUZZ_ROC" version)"
for f in fuzz/*.roc; do
	n=$(basename "$f" .roc)
	if ! "$FUZZ_ROC" build --fuzz "$f" --output="$W/fuzz/$n" >"$W/fuzz/$n.build.log" 2>&1; then
		rc 1 "build $f (see $W/fuzz/$n.build.log)"; continue
	fi
	rm -rf "$W/fuzz/art-$n"
	"$W/fuzz/$n" run --runs="$RUNS" --seed=1 --time=0 --artifact-dir="$W/fuzz/art-$n" >"$W/fuzz/$n.log" 2>&1
	r=$?; rc $r "fuzz $n (see $W/fuzz/$n.log)"
	[ $r = 0 ] && grep -m1 '^Done' "$W/fuzz/$n.log"
done

echo; [ $FAIL = 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAIL"; exit 1; }
