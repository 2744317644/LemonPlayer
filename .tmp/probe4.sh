#!/bin/bash
resp=$(curl -sS -m 20 -X POST "https://account.guangyapan.com/v1/auth/device/code" -H "Content-Type: application/json" -d '{"scope":"user","client_id":"aMe-8VSlkrbQXpUR"}')
complete=$(echo "$resp" | sed -n 's/.*"verification_uri_complete":"\([^"]*\)".*/\1/p')
echo "complete=$complete"
echo "== complete =="
curl -sS -m 20 -o /dev/null -w "status=%{http_code}\n" "$complete"
echo "== account device =="
curl -sS -m 20 -o /dev/null -w "status=%{http_code}\n" "https://account.guangyapan.com/__/auth/device"
echo "== www device =="
curl -sS -m 20 -o /dev/null -w "status=%{http_code}\n" "https://www.guangyupan.com/__/auth/device/?client_id=aMe-8VSlkrbQXpUR&scope=user"
echo "== account root =="
curl -sS -m 20 -o /dev/null -w "status=%{http_code}\n" "https://account.guangyapan.com/"
echo "== www root =="
curl -sS -m 20 -o /dev/null -w "status=%{http_code}\n" "https://www.guangyupan.com/"