#!/usr/bin/env bash
# 在 WSL 里跑纯逻辑包单测（macOS CI 排队时的本地快速反馈通道）。
set -uo pipefail

export PATH=/opt/swift/usr/bin:$PATH
SRC=/mnt/e/Code/LemonPlayer/Packages
DST=/root/lemon

rm -rf "$DST"
mkdir -p "$DST"
cp -r "$SRC" "$DST/"

cd "$DST/Packages" || exit 1

FAILED=0
for p in LemonCore LemonNetwork LemonGuangya LemonSubtitle; do
  echo "===== $p ====="
  if swift test --package-path "$p" 2>&1 | tail -30; then
    :
  else
    FAILED=1
  fi
done

echo "===== summary ====="
[ "$FAILED" -eq 0 ] && echo "ALL_PACKAGES_PASSED" || echo "SOME_PACKAGES_FAILED"
exit "$FAILED"
