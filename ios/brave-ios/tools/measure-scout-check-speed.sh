#!/usr/bin/env bash
# Times a fixed set of checks against the live service, so "faster" is a number.
set -uo pipefail
H=https://many-apps-30-day-challenge.fly.dev
SITES=(
  https://www.bbc.co.uk/news
  https://www.gov.uk/browse/childcare-parenting
  https://www.nhm.ac.uk/discover/dinosaurs.html
  https://stackoverflow.com/
  https://github.com/
)
total=0
for u in "${SITES[@]}"; do
  t=$(curl -s -o /dev/null -w "%{time_total}" -X POST "$H/api/kid-safe/check" \
    -H 'content-type: application/json' -H 'x-app-id: kid-safe' \
    -d "{\"url\":\"$u\",\"audience\":\"general\"}")
  printf "  %6.2fs  %s\n" "$t" "$u"
  total=$(python3 -c "print($total + $t)")
done
python3 -c "print(f'  mean {$total/${#SITES[@]}:.2f}s')"
echo "  warm list: $(curl -s -H 'x-app-id: kid-safe' "$H/api/kid-safe/warm-list" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d.get("entries") or []), "entries, version", d.get("version"))')"
