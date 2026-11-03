#!/bin/bash
resp=$(curl -sS -m 20 -X POST "https://account.guangyapan.com/v1/auth/device/code" -H "Content-Type: application/json" -d '{"scope":"user","client_id":"aMe-8VSlkrbQXpUR"}')
complete=$(echo "$resp" | sed -n 's/.*"verification_uri_complete":"\([^"]*\)".*/\1/p')
echo "URL=$complete"
s1=$(curl -sS -m 25 -L -o /tmp/p1.html -w "%{http_code}" -H "Accept: text/html" "$complete")
echo "complete_status=$s1"
s2=$(curl -sS -m 25 -L -o /tmp/p2.html -w "%{http_code}" -H "Accept: text/html" "https://account.guangyapan.com/__/auth/device/")
echo "device_status=$s2"