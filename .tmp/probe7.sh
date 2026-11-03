#!/bin/bash
for host in guangyupan.com www.guangyupan.com account.guangyapan.com; do
  s=$(curl -sS -m 20 -o /dev/null -w "%{http_code}" -H "Accept: text/html" "https://$host/" 2>/dev/null || echo ERR)
  echo "$host -> $s"
done
echo "-- device page on apex --"
curl -sS -m 20 -o /dev/null -w "apex_device=%{http_code}\n" -H "Accept: text/html" "https://guangyupan.com/__/auth/device/?client_id=aMe-8VSlkrbQXpUR" 2>/dev/null || echo "apex_device=ERR"
echo "-- dns --"
getent hosts www.guangyupan.com guangyupan.com 2>/dev/null || echo NODNS