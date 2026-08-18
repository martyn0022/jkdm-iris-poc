#!/usr/bin/env bash
# JKDM SMK POC - run this before the room fills up.
#
# Checks every moving part the session depends on and prints a verdict.
# Takes about 40 seconds. Run it after `docker compose up -d --build`
# and again after any break where a laptop may have slept.
set -uo pipefail

# Ports come from .env, the same file docker compose reads. Do not
# hardcode them here - if another IRIS already owns 52773 the whole
# session moves to a different port and every script must follow.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "${ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${ROOT}/.env"
  set +a
fi

IRIS_PORT="${IRIS_WEB_PORT:-52773}"
IRIS="http://localhost:${IRIS_PORT}/jkdm"
COBOL_PORT="${COBOL_PORT:-8081}"
PHP_PORT="${PHP_PORT:-8082}"

PASS=0
FAIL=0

ok()   { printf '  \033[32mOK\033[0m    %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '        %s\n' "$1"; }

echo
echo "JKDM SMK POC - preflight"
echo "========================================================"

# ---- containers ------------------------------------------------
echo
echo "Containers"
for c in jkdm-postgres jkdm-cobol-core jkdm-php-service jkdm-sftp jkdm-iris; do
  if [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" = "true" ]; then
    ok "$c running"
  else
    bad "$c NOT running"
    note "docker compose up -d"
  fi
done

# ---- backends --------------------------------------------------
echo
echo "Backends"
if curl -fsS -m 5 "http://localhost:${COBOL_PORT}/health" >/dev/null 2>&1; then
  ok "COBOL core answering on ${COBOL_PORT}"
else
  bad "COBOL core not answering on ${COBOL_PORT}"
fi

PHP_BODY=$(curl -fsS -m 20 -X POST -H 'Content-Type: application/json' \
  -d '{"declarationRef":"K1-2026-000104"}' \
  "http://localhost:${PHP_PORT}/duty/calculate" 2>/dev/null || true)
if echo "${PHP_BODY}" | grep -q '"totalDutyAmount"'; then
  ok "PHP service computing against Postgres"
else
  bad "PHP service not returning a calculation"
  note "usually the .env DB settings - check laravel/entrypoint.sh ran"
fi

# ---- fail mode must be OFF -------------------------------------
FAILMODE=$(docker exec jkdm-php-service sh -c 'cat /opt/app/storage/failmode 2>/dev/null' 2>/dev/null || true)
if [ -z "${FAILMODE}" ] || [ "${FAILMODE}" = "off" ]; then
  ok "PHP failure injection is off"
else
  bad "PHP failure injection is '${FAILMODE}' - left on from a previous run"
  note "./scripts/php-fail.sh off"
fi

# ---- IRIS contract ---------------------------------------------
# IRIS reports healthy well before the web application and the
# production are up. Without this wait a preflight run straight after
# `docker compose up` prints four red failures that fix themselves in
# thirty seconds, which is the wrong thing to see on the morning.
echo
echo "Fabric"
printf '        waiting for IRIS'
for _ in $(seq 30); do
  curl -fsS -m 5 "${IRIS}/health" >/dev/null 2>&1 && break
  printf '.'
  sleep 3
done
printf '\r%*s\r' 40 ''

if curl -fsS -m 10 "${IRIS}/health" >/dev/null 2>&1; then
  ok "IRIS contract reachable on ${IRIS_PORT}"
else
  bad "IRIS contract NOT reachable on ${IRIS_PORT}"
  note "if another IRIS owns 52773, set IRIS_WEB_PORT in .env"
fi

MODE=$(curl -fsS -m 10 "${IRIS}/routes" 2>/dev/null | grep -o '"mode":"[A-Z_]*"' | head -1 | cut -d'"' -f4 || true)
if [ "${MODE}" = "LEGACY" ]; then
  ok "duty.calculate starts in LEGACY"
elif [ -n "${MODE}" ]; then
  bad "duty.calculate is ${MODE} - the demo should start from LEGACY"
  note "curl -X PUT ${IRIS}/routes/duty.calculate/LEGACY"
else
  bad "cannot read the routing table"
fi

# ---- the money moment ------------------------------------------
COB=$(curl -fsS -m 20 -X POST -H 'Content-Type: application/json' \
  -d '{"declarationRef":"K1-2026-000104"}' "${IRIS}/duty/calculate" 2>/dev/null \
  | grep -o '"totalDutyAmount":[0-9.]*' | cut -d: -f2 || true)
PHP=$(echo "${PHP_BODY}" | grep -o '"totalDutyAmount":[0-9.]*' | cut -d: -f2 || true)

if [ "${COB}" = "1088.47" ] && [ "${PHP}" = "1088.46" ]; then
  ok "the one-cent difference is live (COBOL ${COB} / PHP ${PHP})"
else
  bad "expected COBOL 1088.47 and PHP 1088.46, got '${COB}' and '${PHP}'"
  note "if PHP now matches COBOL, someone 'fixed' the float arithmetic"
fi

# ---- production and ingestion ----------------------------------
echo
echo "Ingestion"
PRODSTATE=$(echo 'set s=##class(Ens.Director).GetProductionStatus(.n,.st) write "STATE:",st halt' \
  | docker exec -i jkdm-iris iris session IRIS -U JKDMPOC 2>/dev/null \
  | grep -o 'STATE:[0-9]' | cut -d: -f2 || true)
if [ "${PRODSTATE}" = "1" ]; then
  ok "JKDM.Production is running"
else
  bad "JKDM.Production is not running (state='${PRODSTATE}')"
  note 'echo "do ##class(Ens.Director).StartProduction(\"JKDM.Production\") halt" | docker exec -i jkdm-iris iris session IRIS -U JKDMPOC'
fi

if docker exec jkdm-sftp test -d /home/dftz/inbound/cusdec 2>/dev/null; then
  ok "partner drop directory present"
else
  bad "partner drop directory missing"
fi

SAMPLES=$(ls edi/samples/*.edi 2>/dev/null | wc -l | tr -d ' ')
if [ "${SAMPLES}" -ge 9 ]; then
  ok "${SAMPLES} EDIFACT samples present"
else
  bad "only ${SAMPLES} EDIFACT samples found (expected 9)"
  note "python3 edi/generate_samples.py"
fi

echo
echo "========================================================"
if [ "${FAIL}" -eq 0 ]; then
  printf '\033[32mREADY\033[0m - %s checks passed\n\n' "${PASS}"
  echo "Reset to a clean start before you begin:"
  echo "  ./scripts/reset.sh"
else
  printf '\033[31mNOT READY\033[0m - %s passed, %s failed\n\n' "${PASS}" "${FAIL}"
  exit 1
fi
