#!/usr/bin/env bash
# Drop an EDIFACT file on the DFTZ partner SFTP server.
#
# Simulates the partner uploading to their own drop directory. IRIS
# finds the file on its next poll and pulls it down. Nothing here calls
# IRIS.
#
#   ./scripts/drop-edi.sh                  # one clean declaration
#   ./scripts/drop-edi.sh all              # every valid CUSDEC
#   ./scripts/drop-edi.sh bad              # the two reject cases
#   ./scripts/drop-edi.sh manifest         # the CUSCAR (exercise input)
#   ./scripts/drop-edi.sh K1-2026-000104   # one specific declaration
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAMPLES="${ROOT}/edi/samples"
DROP="${ROOT}/sftp/inbound/cusdec"

mkdir -p "${DROP}"

drop() {
  local f="$1"
  if [[ ! -f "${SAMPLES}/${f}" ]]; then
    echo "no such sample: ${f}" >&2
    return 1
  fi
  cp "${SAMPLES}/${f}" "${DROP}/${f}"
  echo "  dropped ${f}"
}

case "${1:-one}" in
  one)
    echo ">>> partner uploads one declaration"
    drop "CUSDEC_K1-2026-000101.edi"
    ;;
  all)
    echo ">>> partner uploads the full valid batch"
    for f in "${SAMPLES}"/CUSDEC_K1-*.edi; do
      drop "$(basename "$f")"
    done
    ;;
  bad)
    echo ">>> partner uploads two files that will not lodge"
    echo "    (different failures - one syntax, one business)"
    drop "CUSDEC_MALFORMED.edi"
    drop "CUSDEC_UNPRICEABLE.edi"
    ;;
  manifest)
    echo ">>> partner uploads a CUSCAR manifest"
    echo "    (rejected today as an unsupported message type -"
    echo "     wiring it up is the hands-on exercise)"
    drop "CUSCAR_MANIFEST.edi"
    ;;
  *)
    echo ">>> partner uploads ${1}"
    drop "CUSDEC_${1}.edi"
    ;;
esac

echo
echo "IRIS polls every 5 seconds. Watch it arrive:"
echo "  Interoperability > View > Messages"
echo "  ./scripts/audit.sh"
