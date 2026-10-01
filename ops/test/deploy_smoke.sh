#!/usr/bin/env bash
# Post-deploy smoke test (tasks.md T088). Run from OUTSIDE the VPS (e.g. your PC with Git Bash):
#
#   DOMAIN=buildozer.dpdns.org VPS_IP=<public ip> bash ops/test/deploy_smoke.sh
#
# Passes when api.<domain>/healthz and sync.<domain>/probes/liveness answer 200 over HTTPS with a
# certificate curl trusts, and Postgres (5432) is not reachable on the VPS's public address.
set -uo pipefail

DOMAIN="${DOMAIN:?set DOMAIN, e.g. buildozer.dpdns.org}"
VPS_IP="${VPS_IP:?set VPS_IP to the VPS public address}"
failed=0

check_https() {
  local url="$1" code
  # No -k: an invalid or self-signed certificate fails here.
  if code="$(curl -sS -o /dev/null -w '%{http_code}' -m 15 "$url")" && [[ "$code" == 200 ]]; then
    echo "ok   $url"
  else
    echo "FAIL $url (HTTP ${code:-none})"; failed=1
  fi
}

check_https "https://api.$DOMAIN/healthz"
check_https "https://sync.$DOMAIN/probes/liveness"

# bash's /dev/tcp: connect succeeds only if the port is open.
if timeout 5 bash -c "exec 3<>/dev/tcp/$VPS_IP/5432" 2>/dev/null; then
  echo "FAIL postgres port 5432 is reachable on $VPS_IP"; failed=1
else
  echo "ok   postgres port 5432 closed on $VPS_IP"
fi

exit "$failed"
