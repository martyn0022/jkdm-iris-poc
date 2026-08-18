#!/usr/bin/env bash
# Failure injection on the PHP backend.
#
# In SHADOW the consumer's answer comes from COBOL, so breaking PHP must
# change nothing a consumer can observe. This makes that testable.
#
#   ./scripts/php-fail.sh on     # PHP returns HTTP 500
#   ./scripts/php-fail.sh hang   # PHP sleeps 30s
#   ./scripts/php-fail.sh off    # back to normal
set -euo pipefail

MODE="${1:-off}"
case "${MODE}" in
  on|hang|off) ;;
  *) echo "usage: $0 [on|hang|off]" >&2; exit 1 ;;
esac

docker exec jkdm-php-service sh -c "echo '${MODE}' > /opt/app/storage/failmode"
echo "php-service fail mode = ${MODE}"

if [[ "${MODE}" != "off" ]]; then
  echo
  echo "Now call the contract in SHADOW mode. The consumer must not notice:"
  echo "  ./scripts/demo.sh"
fi
