#!/bin/bash
for base in "https://account.guangyapan.com" "https://api.guangyapan.com"; do
  for p in /v1/auth/qrcode/generate /v1/auth/qrcode /v1/auth/qr/generate /v1/auth/login/qrcode /v1/auth/device/code /v1/auth/token; do
    s=$(curl -sS -m 12 -o /dev/null -w "%{http_code}" -X POST "$base$p" -H "Content-Type: application/json" -d '{"client_id":"aMe-8VSlkrbQXpUR"}' 2>/dev/null || echo ERR)
    echo "$base$p -> $s"
  done
done