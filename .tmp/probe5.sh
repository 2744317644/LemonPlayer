#!/bin/bash
resp=$(curl -sS -m 20 -X POST "https://account.guangyapan.com/v1/auth/device/code" -H "Content-Type: application/json" -d '{"scope":"user","client_id":"aMe-8VSlkrbQXpUR"}')
complete=$(echo "$resp" | sed -n 's/.*"verification_uri_complete":"\([^"]*\)".*/\1/p')
echo "== html accept =="
curl -sS -m 25 -L -o /tmp/page.html -w "status=%{http_code} size=%{size_download}\n" -H "Accept: text/html,application/xhtml+xml" "$complete"
head -c 200 /tmp/page.html; echo
echo "== html accept page2 =="
curl -sS -m 25 -L -o /tmp/page2.html -w "status=%{http_code} size=%{size_download}\n" -H "Accept: text/html" "https://account.guangyapan.com/__/auth/device/"
head -c 200 /tmp/page2.html; echo