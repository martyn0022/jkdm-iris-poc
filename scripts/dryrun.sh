#!/usr/bin/env bash
# One pass over everything the session depends on. ~2 minutes.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "${ROOT}/.env" ] && { set -a; . "${ROOT}/.env"; set +a; }
IRIS="http://localhost:${IRIS_WEB_PORT:-52773}/jkdm"

step() { printf '\n\033[36m== %s\033[0m\n' "$1"; }
duty() { curl -s -X POST -H 'Content-Type: application/json' \
           -d "{\"declarationRef\":\"$1\"}" "${IRIS}/duty/calculate"; }

step "reset"
"${ROOT}/scripts/reset.sh" >/dev/null

step "Flow A - ingest, reject, ack"
"${ROOT}/scripts/drop-edi.sh" all >/dev/null
"${ROOT}/scripts/drop-edi.sh" bad >/dev/null
"${ROOT}/scripts/drop-edi.sh" manifest >/dev/null
sleep 45
"${ROOT}/scripts/audit.sh"
echo "acks written: $(ls "${ROOT}"/sftp/outbound/ | wc -l | tr -d ' ')"

step "Flow B - fiscal lock"
for mode in SHADOW LIVE_NEW; do
  printf '%-9s %s\n' "${mode}" \
    "$(curl -s -o /dev/null -w '%{http_code}' -X PUT "${IRIS}/routes/duty.calculate/${mode}") (409 = refused, correct)"
done

step "Flow B - three modes on the non-fiscal operation"
for mode in LEGACY SHADOW LIVE_NEW; do
  curl -s -X PUT "${IRIS}/routes/manifest.lookup/${mode}" >/dev/null
  printf '%-9s served by %s\n' "${mode}" \
    "$(curl -s -D- -o /dev/null "${IRIS}/manifest/MANIFEST-2026-0044" | grep -i x-smk-backend | tr -d '\r' | awk '{print $2}')"
done
curl -s -X PUT "${IRIS}/routes/manifest.lookup/LEGACY" >/dev/null

step "resilience - PHP down, SHADOW consumer unaffected"
curl -s -X PUT "${IRIS}/routes/manifest.lookup/SHADOW" >/dev/null
"${ROOT}/scripts/php-fail.sh" on >/dev/null
printf 'php-down  served by %s\n' \
  "$(curl -s -D- -o /dev/null "${IRIS}/manifest/MANIFEST-2026-0044" | grep -i x-smk-backend | tr -d '\r' | awk '{print $2}')"
"${ROOT}/scripts/php-fail.sh" off >/dev/null

step "the cent - why duty.calculate is locked"
printf 'COBOL %s   PHP %s\n' \
  "$(curl -s -X POST -H 'Content-Type: application/json' -d '{"declarationRef":"K1-2026-000104"}' \
      "http://localhost:${COBOL_PORT:-8081}/duty/calculate" >/dev/null 2>&1; duty K1-2026-000104 | grep -o '"totalDutyAmount":[0-9.]*' | cut -d: -f2)" \
  "$(curl -s -X POST -H 'Content-Type: application/json' -d '{"declarationRef":"K1-2026-000104"}' \
      "http://localhost:${PHP_PORT:-8082}/duty/calculate" | grep -o '"totalDutyAmount":[0-9.]*' | cut -d: -f2)"

step "manifest (exercise stage 2 substrate)"
curl -s -X PUT "${IRIS}/routes/manifest.lookup/SHADOW" >/dev/null
for m in 0041 0044; do curl -s "${IRIS}/manifest/MANIFEST-2026-${m}" >/dev/null; done
sleep 5
"${ROOT}/scripts/audit.sh" m-diffs

step "back to LEGACY"
curl -s -X PUT "${IRIS}/routes/manifest.lookup/LEGACY" >/dev/null
echo done
