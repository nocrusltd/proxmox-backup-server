#!/usr/bin/env bash
# Boot the image with throwaway volumes and check it serves the PBS GUI/API on 8007 and
# reports the expected package version. Usage: smoke-test.sh <image> <expected-version>
set -euo pipefail
IMAGE="$1"; EXPECTED="$2"; NAME="pbs-smoke-$$"
cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run -d --name "$NAME" --tmpfs /run \
  -v /etc/proxmox-backup -v /var/lib/proxmox-backup -v /var/log/proxmox-backup \
  -p 127.0.0.1:18007:8007 "$IMAGE" >/dev/null

for _ in $(seq 1 60); do
  code=$(curl -sk -o /dev/null -w '%{http_code}' https://127.0.0.1:18007/ || true)
  [[ "$code" == 200 ]] && break
  sleep 2
done
docker logs "$NAME" 2>&1 | tail -20
[[ "$code" == 200 ]] || { echo "GUI did not return 200 (last: $code)"; exit 1; }
curl -sk https://127.0.0.1:18007/ | grep -q '<title>.*Proxmox Backup Server' \
  || { echo "GUI title missing"; exit 1; }
# Unauthenticated API call must reach the API daemon and be rejected (401), not 5xx.
api=$(curl -sk -o /dev/null -w '%{http_code}' https://127.0.0.1:18007/api2/json/version)
[[ "$api" == 401 ]] || { echo "API returned $api, expected 401"; exit 1; }

out=$(docker exec "$NAME" proxmox-backup-manager versions)
echo "$out"
grep -q "proxmox-backup-server ${EXPECTED} running version: ${EXPECTED%-*}" <<<"$out" \
  || { echo "expected proxmox-backup-server ${EXPECTED}"; exit 1; }
# No enabled apt source may point at the enterprise repository: without a subscription
# it answers 401 and the daily aptupdate task ends with a warning.
uris=$(docker exec "$NAME" apt-get update --print-uris)   # lists what would be fetched; fetches nothing
grep -q 'download.proxmox.com/debian/pbs/dists/trixie/pbs-no-subscription/' <<<"$uris" \
  || { echo "pbs-no-subscription apt source is not enabled"; exit 1; }
if grep -q 'enterprise.proxmox.com' <<<"$uris"; then
  echo "the pbs-enterprise apt source is enabled"; exit 1
fi
echo "SMOKE TEST OK"
