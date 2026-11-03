#!/bin/bash
URL="https://account.guangyapan.com/v1/auth/device/code"
B='{"scope":"user","client_id":"aMe-8VSlkrbQXpUR"}'
resp=$(curl -sS -m 20 -X POST "$URL" -H "Content-Type: application/json" -d "$B")
echo "resp=$resp"
code=$(echo "$resp" | sed -n 's/.*"device_code":"\([^"]*\)".*/\1/p')
user=$(echo "$resp" | sed -n 's/.*"user_code":"\([^"]*\)".*/\1/p')
echo "device_code=$code user_code=$user"
sleep 3
echo "== poll =="
curl -sS -m 20 -o /tmp/poll.json -w "status=%{http_code}\n" -X POST "https://account.guangyapan.com/v1/auth/token" -H "Content-Type: application/json" -d "{\"grant_type\":\"urn:ietf:params:oauth:grant-type:device_code\",\"device_code\":\"$code\",\"client_id\":\"aMe-8VSlkrbQXpUR\"}"
cat /tmp/poll.json; echo
echo "== auth page =="
curl -sS -m 20 -o /dev/null -w "verification_url_status=%{http_code}\n" "https://account.guangyapan.com/__/auth/device/?client_id=aMe-8VSlkrbQXpUR&scope=user"