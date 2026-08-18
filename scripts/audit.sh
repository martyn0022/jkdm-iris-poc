#!/usr/bin/env bash
# JKDM SMK POC - show the ingestion audit trail.
#
# The evidence view: what arrived, from whom, whether it parsed, which
# backend priced it, and what the partner was told.
#
#   ./scripts/audit.sh                # Flow A ingestion trail
#   ./scripts/audit.sh equivalence    # duty.calculate verdicts
#   ./scripts/audit.sh diffs          # every field difference found
#   ./scripts/audit.sh combined       # file-origin traffic + verdicts
#   ./scripts/audit.sh m-equivalence  # manifest.lookup verdicts
#   ./scripts/audit.sh m-diffs        # manifest differences only
set -euo pipefail

case "${1:-audit}" in
  equivalence)   METHOD='Equivalence()' ;;
  diffs)         METHOD='Diffs()' ;;
  combined)      METHOD='Combined()' ;;
  m-equivalence) METHOD='Equivalence("manifest.lookup")' ;;
  m-diffs)       METHOD='Diffs(12,"manifest.lookup")' ;;
  *)             METHOD='Audit()' ;;
esac

echo "do ##class(JKDM.Util.Report).${METHOD} halt" \
  | docker exec -i jkdm-iris iris session IRIS -U JKDMPOC 2>&1 \
  | grep -vE "^JKDMPOC>|^Node:|^$"
