#!/usr/bin/env bash
GW=$(ip route show default | awk '{print $3}')
echo "gateway: $GW"
for P in 7890 7891 1080; do
  code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 6 -x "http://$GW:$P" https://www.baidu.com 2>/dev/null || echo fail)
  echo "proxy $GW:$P -> $code"
done
echo "direct: $(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 https://swift.org 2>/dev/null || echo fail)"
