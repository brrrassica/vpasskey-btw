#!/usr/bin/env bash
# Preflight and end-to-end checks for passkey-tpm.
#   --bio     fingerprint end-to-end check (asks for a fingerprint twice)
#   --prompt  report the selected fingerprint prompt backend and Omarchy detection
#   --compat  point at the local WebAuthn compatibility matrix page
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
	cat <<'EOF'
usage: verify.sh [--bio|--prompt|--compat|--help]

  --bio      Run the biometric end-to-end check (touch the reader twice).
  --prompt   Print the selected prompt backend and session detection.
  --compat   Print the path to the local compatibility matrix page.
  --help     Show this help.
EOF
}

# The probe must never run the agent: an installed binary that predates the 0.2.0 prompt
# patch ignores --probe-prompt and starts the agent loop instead, which used to hang this
# script. Bound it, and say what to do when it does not answer.
prompt_probe() {
	local bin out
	for bin in \
		/usr/lib/passkey-tpm/passkey-tpm-agent \
		"$ROOT/passkey-tpm/target/release/passkey-tpm-agent"; do
		if [[ -x "$bin" ]]; then
			if ! out=$(timeout 15 "$bin" --probe-prompt 2>&1); then
				echo "error: $bin did not report a prompt backend" >&2
				echo "The installed agent may predate the 0.2.0 prompt patch." >&2
				echo "Reinstall the patched build: ./install.sh" >&2
				return 1
			fi
			printf '%s\n' "$out"
			return 0
		fi
	done
	echo "passkey-tpm-agent not found; run ./install.sh (or cargo build --release) first" >&2
	return 1
}

case "${1:-}" in
	--help|-h)
		usage
		exit 0
		;;
	--prompt)
		echo "== prompt backend =="
		prompt_probe
		exit 0
		;;
	--compat)
		echo "Open this page in Chrome/Chromium and Firefox:"
		echo "  $ROOT/browser-test-compat.html"
		echo "Serve it locally if your browser blocks file:// WebAuthn:"
		echo "  python3 -m http.server --directory $ROOT 8000"
		echo "  then open http://localhost:8000/browser-test-compat.html"
		exit 0
		;;
	--bio|"")
		;;
	*)
		echo "error: unknown option: $1" >&2
		usage >&2
		exit 2
		;;
esac

echo "== services =="
systemctl --user is-active passkey-tpm-agent || true
systemctl is-active passkey-tpm-uvd 2>/dev/null || true

echo
echo "== device =="
if command -v fido2-token >/dev/null 2>&1; then
	fido2-token -L || true
else
	echo "(fido2-token not installed; install libfido2 for device diagnostics)"
fi

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
