#!/usr/bin/env bash
# Preflight and (with --bio) biometric end-to-end check for passkey-tpm.
# The --bio run asks for a fingerprint on every operation.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "== services =="
systemctl --user is-active passkey-tpm-agent || true
systemctl is-active passkey-tpm-uvd 2>/dev/null || true

echo
echo "== device =="
fido2-token -L

echo
echo "== info =="
passkey-tpm info || true

if [[ "${1:-}" == "--bio" ]]; then
	echo
	echo "Starting biometric e2e: touch the fingerprint reader when asked."
	exec "$ROOT/passkey-tpm/scripts/e2e-fido2.sh"
fi

echo
echo "Preflight complete. Now run: $0 --bio"
echo "Touch the fingerprint reader twice (register, then login)."