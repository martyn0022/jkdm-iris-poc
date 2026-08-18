#!/usr/bin/env bash
# JKDM SMK POC - return to a clean demo start state.
#
# Clears the audit trail, the comparison evidence, the partner drop and
# the acknowledgement directory, and puts duty.calculate back to
# LEGACY. Run between rehearsal and the real thing, and between the
# demo and the hands-on.
#
# Does NOT touch Postgres seed data or anyone's code.
set -euo pipefail

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

echo ">>> clearing partner directories"
rm -f "${ROOT}"/sftp/inbound/cusdec/*.edi 2>/dev/null || true
rm -f "${ROOT}"/sftp/outbound/*.aperak "${ROOT}"/sftp/outbound/*.contrl 2>/dev/null || true

echo ">>> clearing audit trail and comparison evidence"
docker exec -i jkdm-iris iris session IRIS -U JKDMPOC >/dev/null 2>&1 <<'EOF'
do ##class(JKDM.Msg.FileAuditRecord).%DeleteExtent()
do ##class(JKDM.Msg.ComparisonResult).%DeleteExtent()
halt
EOF

echo ">>> resetting routes to LEGACY"
# duty.calculate is fiscal and already locked there; only the manifest moves.
curl -fsS -m 10 -X PUT "http://localhost:${IRIS_PORT}/jkdm/routes/manifest.lookup/LEGACY" >/dev/null

echo ">>> turning off PHP failure injection"
docker exec jkdm-php-service sh -c "echo off > /opt/app/storage/failmode" 2>/dev/null || true

echo
echo "Clean. duty.calculate = LEGACY, no files ingested, no comparisons."
