#!/usr/bin/env bash
# capture-webauthn-site.sh - bundle M2 evidence for one real-site passkey flow.
#
# Creates a record skeleton plus a redacted doctor/journal trace under
# plans/compat/ so a Cloudflare or OpenRouter failure can be classified. It does
# not drive the browser: the user performs the flow while the trace runs.
#
# Usage:
#   ./scripts/capture-webauthn-site.sh --site cloudflare --flow register
#   ./scripts/capture-webauthn-site.sh --site openrouter --flow authenticate --seconds 45
#   ./scripts/capture-webauthn-site.sh --site cloudflare --flow register \
#       --options plans/compat/cloudflare-register.options.json
set -u

PROG=${0##*/}
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd) || exit 2
DOCTOR="$ROOT/scripts/passkey-doctor.sh"

SITE=""
FLOW=""
BROWSER=""
TRACE_SECONDS=30
OPTIONS_FILE=""
OUTPUT_DIR="$ROOT/plans/compat"
DRY_RUN=0

usage() {
	cat <<EOF
usage: $PROG --site NAME --flow FLOW [options]

Capture evidence for one real-site passkey flow (M2).

Required:
  --site NAME         short site label, e.g. cloudflare or openrouter
  --flow FLOW         register or authenticate

Options:
  --browser NAME      browser label; default: detect chrome/chromium/firefox
  --seconds N         journal trace length (default 30, max 300)
  --options FILE      DevTools WebAuthn options export to include (redacted)
  --output-dir DIR    where to write evidence (default: plans/compat)
  --dry-run           print what would be created, capture nothing
  -h, --help          show this help

The script prints when to start the site flow, then runs
scripts/passkey-doctor.sh --trace. Broker journal capture needs passwordless
sudo; without it, only the agent side is recorded and the report says so.
EOF
}

die() {
	printf '%s: %s\n' "$PROG" "$*" >&2
	exit 2
}

have() {
	command -v "$1" >/dev/null 2>&1
}

detect_browser() {
	local candidate
	for candidate in google-chrome-stable google-chrome chromium chromium-browser firefox; do
		if have "$candidate"; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done
	printf 'unknown\n'
}

browser_version() {
	local browser=$1
	if [[ "$browser" == unknown ]] || ! have "$browser"; then
		printf 'unknown\n'
		return 0
	fi
	timeout 10 "$browser" --version 2>&1 | head -n 1
}

while (($# > 0)); do
	case "$1" in
		--site)
			(($# >= 2)) || die "--site needs a value"
			SITE=$2
			shift 2
			;;
		--flow)
			(($# >= 2)) || die "--flow needs a value"
			FLOW=$2
			shift 2
			;;
		--browser)
			(($# >= 2)) || die "--browser needs a value"
			BROWSER=$2
			shift 2
			;;
		--seconds)
			(($# >= 2)) || die "--seconds needs a value"
			TRACE_SECONDS=$2
			shift 2
			;;
		--options)
			(($# >= 2)) || die "--options needs a file"
			OPTIONS_FILE=$2
			shift 2
			;;
		--output-dir)
			(($# >= 2)) || die "--output-dir needs a value"
			OUTPUT_DIR=$2
			shift 2
			;;
		--dry-run)
			DRY_RUN=1
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			die "unknown option: $1 (try --help)"
			;;
	esac
done

[[ -n "$SITE" ]] || die "--site is required"
[[ -n "$FLOW" ]] || die "--flow is required"
[[ "$SITE" =~ ^[A-Za-z0-9._-]+$ ]] || die "--site must be letters, digits, dot, dash, underscore"
case "$FLOW" in
	register | authenticate) ;;
	*) die "--flow must be register or authenticate" ;;
esac
[[ "$TRACE_SECONDS" =~ ^[0-9]+$ ]] || die "--seconds must be a number"
((TRACE_SECONDS >= 5 && TRACE_SECONDS <= 300)) || die "--seconds must be between 5 and 300"
if [[ -n "$OPTIONS_FILE" && ! -r "$OPTIONS_FILE" ]]; then
	die "cannot read --options file: $OPTIONS_FILE"
fi

BROWSER=${BROWSER:-$(detect_browser)}
BROWSER_SLUG=$(printf '%s' "$BROWSER" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._-' '-')
BROWSER_SLUG=${BROWSER_SLUG%-}
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
BASE="$OUTPUT_DIR/${SITE}-${FLOW}-${BROWSER_SLUG}-${STAMP}"
RECORD="$BASE.md"
DOCTOR_OUT="$BASE.doctor.txt"

printf 'site:     %s\n' "$SITE"
printf 'flow:     %s\n' "$FLOW"
printf 'browser:  %s (%s)\n' "$BROWSER" "$(browser_version "$BROWSER")"
printf 'record:   %s\n' "$RECORD"
printf 'doctor:   %s\n' "$DOCTOR_OUT"
printf 'trace:    %ss\n' "$TRACE_SECONDS"

if ((DRY_RUN == 1)); then
	printf '\n(dry run: no files written, no trace captured)\n'
	exit 0
fi

[[ -x "$DOCTOR" ]] || die "missing or not executable: $DOCTOR"
mkdir -p "$OUTPUT_DIR" || die "cannot create $OUTPUT_DIR"

# The backticks below are literal Markdown code spans, not command substitution.
# shellcheck disable=SC2016
{
	printf '# %s - %s capture\n\n' "$SITE" "$FLOW"
	printf -- '- Status: trace captured, classification pending\n'
	printf -- '- Captured (UTC): %s\n' "$STAMP"
	printf -- '- Machine / OS: %s\n' "$(uname -srm 2>&1)"
	printf -- '- Hostname: %s\n' "$(hostname 2>/dev/null || printf '<unknown>')"
	printf -- '- Session: XDG_SESSION_TYPE=%s XDG_CURRENT_DESKTOP=%s\n' \
		"${XDG_SESSION_TYPE:-<unset>}" "${XDG_CURRENT_DESKTOP:-<unset>}"
	printf -- '- Browser and version: %s (%s)\n' "$BROWSER" "$(browser_version "$BROWSER")"
	printf -- '- passkey-tpm version: %s\n' "$(timeout 10 passkey-tpm version 2>&1 | head -n 1)"
	printf -- '- Doctor trace: %s\n' "$(basename "$DOCTOR_OUT")"
	printf -- '- Existing credential on this site: unknown\n\n'
	printf '## Options as captured\n\n'
	printf 'Source: DevTools WebAuthn panel export. Replace this section with the\n'
	printf 'field summary from `plans/compat/README.md`.\n\n'
	if [[ -n "$OPTIONS_FILE" ]]; then
		printf '```json\n'
		"$DOCTOR" --redact "$OPTIONS_FILE"
		printf '```\n'
	else
		printf '```json\n{}\n```\n'
	fi
	printf '\n## Field summary\n\n'
	printf '| Field | Value |\n|---|---|\n'
	printf '| rp.id | |\n'
	printf '| authenticatorSelection.authenticatorAttachment | |\n'
	printf '| authenticatorSelection.residentKey | |\n'
	printf '| authenticatorSelection.requireResidentKey | |\n'
	printf '| authenticatorSelection.userVerification | |\n'
	printf '| attestation | |\n'
	printf '| extensions | |\n'
	printf '| excludeCredentials (count / transports) | |\n'
	printf '| allowCredentials (count / transports) | |\n'
	printf '| timeout (ms) | |\n'
	printf '| mediation / conditional UI | |\n'
	printf '| hints | |\n'
	printf '\n## Observed outcome\n\n'
	printf -- '- Browser result:\n- Error name/message:\n'
	printf -- '- Fingerprint prompt shown: yes/no/which backend\n'
	printf -- '- Number of fingerprint attempts:\n- Broker journal highlights:\n\n'
	printf '```\n```\n'
	printf '\n## Classification\n\n'
	printf 'Pick one: platform-attachment filtering / CTAP behavior bug /\n'
	printf 'request-policy mismatch / browser UI limitation / not reproduced.\n\n'
	printf 'Classification:\n\nReasoning:\n\n'
	printf '## Evidence files\n\n'
	printf -- '- `.options.json`: %s\n' "${OPTIONS_FILE:+attached above}"
	printf -- '- `.device-log.txt`: TODO\n'
	printf -- '- `.doctor.txt`: %s\n' "$(basename "$DOCTOR_OUT")"
} >"$RECORD" || die "cannot write $RECORD"

printf '\nWhen the doctor prints "Start your passkey operation now", perform the\n'
printf '%s %s flow in %s. Keep the tab focused until the trace window ends.\n\n' "$SITE" "$FLOW" "$BROWSER"

"$DOCTOR" --trace "$TRACE_SECONDS" --output "$DOCTOR_OUT"
DOCTOR_STATUS=$?

if ! sudo -n true 2>/dev/null; then
	printf '\nNote: the broker journal was not captured because passwordless sudo is\n'
	printf 'unavailable. For broker-side evidence, run this in a second terminal during\n'
	printf 'the next capture, then save and redact its output:\n'
	printf '  sudo journalctl -u passkey-tpm-uvd -b -f\n'
fi

printf '\nEvidence written:\n'
printf '  %s\n' "$RECORD"
printf '  %s\n' "$DOCTOR_OUT"
printf '\nNext: add the DevTools options export and chrome://device-log excerpt, then fill\n'
printf 'in the field summary and classification. See plans/compat/README.md.\n'

exit "$DOCTOR_STATUS"
