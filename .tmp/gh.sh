#!/bin/bash
curl -sS -m 30 "https://raw.githubusercontent.com/ShukeBta/Guangyadisk/main/plugins.v2/shukguangyadisk/guangya_client.py" -o /tmp/gc.py
echo "bytes=$(wc -c < /tmp/gc.py)"
grep -n "device" /tmp/gc.py | head -30