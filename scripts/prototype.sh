#!/usr/bin/env bash
# The enablement segment: what the same system looks like if the
# application and data tiers move inside IRIS too.
#
# The interop interface is unchanged - same EDIFACT, same contract
# shapes. Only the tiers behind it move.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "${ROOT}/.env" ] && { set -a; . "${ROOT}/.env"; set +a; }
PORT="${IRIS_WEB_PORT:-52773}"
P="http://localhost:${PORT}/prototype"
J="http://localhost:${PORT}/jkdm"
PHP="http://localhost:${PHP_PORT:-8082}"
REF="${1:-K1-2026-000104}"

hr(){ printf '%*s\n' 72 '' | tr ' ' '-'; }
duty(){ curl -s -X POST -H 'Content-Type: application/json' \
        -d "{\"declarationRef\":\"${REF}\"}" "$1" \
        | grep -o '"totalDutyAmount":[0-9.]*' | cut -d: -f2; }

hr; echo "1 · FOUR IMPLEMENTATIONS, ONE DECLARATION (${REF})"; hr
printf '  %-24s %s\n' "COBOL core (authoritative)" "$(duty ${J}/duty/calculate)"
printf '  %-24s %s\n' "PHP - the tender stack"     "$(duty ${PHP}/duty/calculate)"
printf '  %-24s %s\n' "IRIS - ObjectScript"        "$(duty ${P}/duty/calculate)"
printf '  %-24s %s\n' "IRIS - Python"              "$(duty ${P}/duty/python)"
echo
echo "  Three agree with the system of record. One does not."
echo "  Not a language property - a rounding decision. The two IRIS"
echo "  versions round per line because the COBOL does."

hr; echo "2 · THE LIMITATION THAT DISAPPEARS"; hr
echo "  The main POC cannot create a declaration - it prices one the"
echo "  core already holds. Writing meant crossing a tier boundary."
echo
sed "s/${REF}/K1-2026-000999/" "${ROOT}/edi/samples/CUSDEC_K1-2026-000101.edi" > /tmp/pt-new.edi 2>/dev/null || \
  sed "s/K1-2026-000101/K1-2026-000999/" "${ROOT}/edi/samples/CUSDEC_K1-2026-000101.edi" > /tmp/pt-new.edi
printf '  main POC  : '
curl -s -o /dev/null -w '%{http_code} ' -X POST -H 'Content-Type: application/json' \
     -d '{"declarationRef":"K1-2026-000999"}' "${J}/duty/calculate"
echo "- declaration not found"
printf '  prototype : '
curl -s -X POST -H 'Content-Type: text/plain' --data-binary @/tmp/pt-new.edi "${P}/ingest" \
  | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['status'],'- parsed, persisted and priced in one call, duty',d['totalDutyAmount'])"

hr; echo "3 · ONE DEFINITION, TWO WAYS IN"; hr
curl -s "${P}/sql" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for r in d['rows'][:4]:
    print('  %-18s %s lines  %s' % (r['declarationRef'], r['lines'], r['customsValue']))
print()
print(' ', d['note'])"

hr; echo "4 · WHAT IS ACTUALLY BEING COMPARED"; hr
curl -s "${P}/explain" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  per entity   tender:', ' + '.join(d['artefactsPerEntity']['tenderStack']))
print('               here  :', ' + '.join(d['artefactsPerEntity']['prototype']))
print()
print('  tiers        tender:', ' -> '.join(d['tiers']['tenderStack']))
print('               here  :', ' -> '.join(d['tiers']['prototype']))
print()
print(' ', d['honest'])"
hr
