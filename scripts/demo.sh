#!/usr/bin/env bash
# The routing demo. Two halves, in this order:
#   1. the fiscal operation the router REFUSES to move
#   2. the non-fiscal operation walked through all three modes
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "${ROOT}/.env" ] && { set -a; . "${ROOT}/.env"; set +a; }
IRIS="${IRIS_URL:-http://localhost:${IRIS_WEB_PORT:-52773}/jkdm}"
MANIFEST="${MANIFEST_REF:-MANIFEST-2026-0044}"

hr() { printf '%*s\n' 72 '' | tr ' ' '-'; }

hr; echo "THE ROUTING TABLE IS A POLICY, NOT JUST CONFIG"; hr
curl -s "${IRIS}/routes" | python3 -m json.tool

hr; echo "1 - duty.calculate computes money. Try to move it."; hr
for mode in SHADOW LIVE_NEW; do
  printf '  PUT %-9s ' "${mode}"
  curl -s -o /tmp/jkdm-r -w 'HTTP %{http_code}  ' \
       -X PUT "${IRIS}/routes/duty.calculate/${mode}" || true
  python3 -c "import json;print(json.load(open('/tmp/jkdm-r')).get('error','ok'))"
done
echo
echo "  The router refuses. SMK 5.8 says leave the revenue core in COBOL,"
echo "  and that is now enforced rather than remembered."

hr; echo "2 - manifest.lookup moves no money. All three modes are open."; hr
for mode in LEGACY SHADOW LIVE_NEW; do
  curl -s -X PUT "${IRIS}/routes/manifest.lookup/${mode}" > /dev/null
  printf '  %-9s ' "${mode}"
  curl -s -D /tmp/jkdm-h -o /dev/null "${IRIS}/manifest/${MANIFEST}"
  printf 'served by %-6s ' "$(grep -i 'X-SMK-Backend' /tmp/jkdm-h | tr -d '\r' | awk '{print $2}')"
  curl -s "${IRIS}/manifest/${MANIFEST}" \
    | python3 -c "import json,sys;d=json.load(sys.stdin);print('consignments',d['consignmentCount'],' status',d['statusCode'])"
done

curl -s -X PUT "${IRIS}/routes/manifest.lookup/LEGACY" > /dev/null
hr
echo "Consumer called one URL throughout. Only the table changed."
echo "Reset: ./scripts/reset.sh"
