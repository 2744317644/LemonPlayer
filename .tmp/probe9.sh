#!/bin/bash
base="https://account.guangyapan.com"
for p in /__/ /__/auth/ /__/auth/device/ /__/auth/device /__/auth/device/index.html /device/ /login /__/auth/login; do
  out=$(curl -sS -m 12 -o /dev/null -w "%{http_code}|%{content_type}" -H "Accept: text/html" "$base$p" 2>/dev/null || echo ERR)
  echo "$p -> $out"
done
echo "-- headers of device page --"
curl -sSI -m 12 -H "Accept: text/html" "$base/__/auth/device/" 2>&1 | head -12