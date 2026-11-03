#!/bin/bash
URL="https://account.guangyapan.com/v1/auth/device/code"
B1='{"scope":"user","client_id":"aMe-8VSlkrbQXpUR"}'
B2='{"client_id":"aMe-8VSlkrbQXpUR","scope":"user profile sso offline"}'
B3='{"data":{"scope":"user","client_id":"aMe-8VSlkrbQXpUR"}}'
echo "== A charset =="; curl -sS -m 20 -X POST "$URL" -H "Content-Type: application/json; charset=utf-8" -d "$B1" | head -c 300; echo
echo "== B full scope =="; curl -sS -m 20 -X POST "$URL" -H "Content-Type: application/json" -d "$B2" | head -c 300; echo
echo "== C data wrapper =="; curl -sS -m 20 -X POST "$URL" -H "Content-Type: application/json" -d "$B3" | head -c 300; echo
echo "== D browser UA =="; curl -sS -m 20 -X POST "$URL" -H "Content-Type: application/json" -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/147.0.0.0 Safari/537.36" -d "$B1" | head -c 300; echo
echo "== E Origin/Referer =="; curl -sS -m 20 -X POST "$URL" -H "Content-Type: application/json" -H "Origin: https://www.guangyupan.com" -H "Referer: https://www.guangyupan.com/" -d "$B1" | head -c 300; echo