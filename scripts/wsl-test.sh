#!/usr/bin/env bash
# 在 WSL 里跑纯逻辑包单测（macOS CI 排队时的本地快速反馈通道）。
# 用法: bash wsl-test.sh [PackageName ...]
set -uo pipefail

export PATH=/opt/swift/usr/bin:$PATH
SRC=/mnt/e/Code/LemonPlayer/Packages
DST=/root/lemon

rm -rf "$DST/Packages"
mkdir -p "$DST"
cp -r "$SRC" "$DST/"

cd "$DST/Packages" || exit 1

PKGS="${*:-LemonCore LemonNetwork LemonGuangya LemonSubtitle}"
FAILED=0
for p in $PKGS; do
  echo "===== $p ====="
  LOG="/tmp/swift-test-$p.log"
  if swift test --package-path "$p" >"$LOG" 2>&1; then
    grep -E "Executed [0-9]+ tests|Test run with [0-9]+ test" "$LOG" | tail -2
    echo "PASS: $p"
  else
    echo "FAIL: $p"
    grep -nE "error: |XCTAssert|failed \(" "$LOG" | head -30
    FAILED=1
  fi
done

echo "===== summary ====="
[ "$FAILED" -eq 0 ] && echo "ALL_PACKAGES_PASSED" || echo "SOME_PACKAGES_FAILED"
exit "$FAILED"
