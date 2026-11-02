#!/usr/bin/env bash
# passkey-doctor.sh - collect redacted passkey-tpm diagnostics for a bug report.
#
# Every probe is best effort: a missing tool or service becomes a line in the
# report, never a fatal error. Credential IDs and long binary values are
# redacted before they reach stdout or the output file.
#
# Usage:
#   ./scripts/passkey-doctor.sh
#   ./scripts/passkey-doctor.sh --output passkey-doctor.txt
#   ./scripts/passkey-doctor.sh --trace 15
#   ./scripts/passkey-doctor.sh --redact saved-trace.txt
set -u

PROG=${0##*/}
PROBE_TIMEOUT=15
TRACE_SECONDS=0
REDACT_FILE=""
OUTPUT_FILE=""
WORK_DIR=""

trap '[[ -n "$WORK_DIR" ]] && rm -rf "$WORK_DIR"' EXIT

usage() {
	cat <<EOF
usage: $PROG [options]

Collect redacted passkey-tpm diagnostics (services, TPM, fingerprint, browsers).

Options:
  --output FILE     also write the report to FILE
  --trace [SECONDS] capture agent/broker journal while you perform an operation
                    (default 15 seconds; broker capture needs passwordless sudo)
  --redact FILE     only redact an existing trace file and print the result
  -h, --help        show this help

No option changes system state. The report is safe to attach to an issue after
a quick review: credential IDs, long hex values, and long base64url values are
replaced with placeholders.
EOF
}

die() {
	printf '%s: %s\n' "$PROG" "$*" >&2
	exit 2
}

have() {
	command -v "$1" >/dev/null 2>&1
}

# Replace credential-looking values with placeholders. Order matters: explicit
# credential_id= patterns first, then generic long hex and base64url blobs.
redact() {
	sed -E \
		-e 's/((credential|cred)[ _-]?id[[:space:]]*[:=][[:space:]]*)[^[:space:],;]+/\1<redacted>/Ig' \
		-e 's/(Fingerprints for user )[^[:space:]]+/\1<redacted-user>/g' \
		-e 's/\b[0-9a-fA-F]{40,}\b/<redacted-hex>/g' \
		-e 's/[A-Za-z0-9_-]{43,}/<redacted-b64url>/g'
}

section() {
	printf '\n## %s\n' "$*"
}

# run LABEL COMMAND [ARG...]
run() {
	local label=$1
	shift
	section "$label"
	if ! have "$1"; then
		printf '(not installed: %s)\n' "$1"
		return 0
	fi
	local out status
	out=$(timeout "$PROBE_TIMEOUT" "$@" 2>&1)
	status=$?
	if [[ -n "$out" ]]; then
		printf '%s\n' "$out" | redact
	else
		printf '(no output)\n'
	fi
	if (( status == 124 )); then
		printf '(timed out after %ss)\n' "$PROBE_TIMEOUT"
	fi
	return 0
}

print_var() {
	local name=$1
	printf '%s=%s\n' "$name" "${!name:-<unset>}"
}

collect_os() {
	section "OS and session"
	if [[ -r /etc/os-release ]]; then
		grep -E '^(NAME|PRETTY_NAME|ID|VERSION_ID)=' /etc/os-release | redact
	else
		printf '(no /etc/os-release)\n'
	fi
	printf 'kernel: %s\n' "$(uname -srm 2>&1)"
	printf 'session type: %s\n' "${XDG_SESSION_TYPE:-<unset>}"
	printf 'desktop: %s\n' "${XDG_CURRENT_DESKTOP:-<unset>}"
	printf 'desktop session: %s\n' "${DESKTOP_SESSION:-<unset>}"
	printf 'wayland display: %s\n' "${WAYLAND_DISPLAY:-<unset>}"
	print_var PASSKEY_PROMPT
	print_var PASSKEY_TPM_TCTI
}

collect_omarchy() {
	section "Omarchy / Hyprland detection"
	if have omarchy; then
		printf 'omarchy command: %s\n' "$(command -v omarchy)"
	else
		printf 'omarchy command: not found\n'
	fi
	printf 'OMARCHY_PATH=%s\n' "${OMARCHY_PATH:-<unset>}"
	if [[ -n "${HOME:-}" && -d "${HOME:-}/.local/share/omarchy" ]]; then
		printf 'home-local omarchy data dir: present\n'
	else
		printf 'home-local omarchy data dir: absent\n'
	fi
	if [[ -r /etc/omarchy-release ]]; then
		printf '/etc/omarchy-release:\n'
		head -n 5 /etc/omarchy-release | redact
	else
		printf '/etc/omarchy-release: absent\n'
	fi
	if have hyprctl; then
		local out
		out=$(timeout "$PROBE_TIMEOUT" hyprctl version 2>&1)
		printf '%s\n' "$out" | head -n 6 | redact
	else
		printf 'hyprctl: not found\n'
	fi
}

collect_services() {
	section "Services"
	if have systemctl; then
		printf 'agent (passkey-tpm-agent): '
		systemctl --user is-active passkey-tpm-agent.service 2>&1 || true
		printf 'broker (passkey-tpm-uvd): '
		systemctl is-active passkey-tpm-uvd.service 2>&1 || true
		run "agent status" systemctl --user status passkey-tpm-agent.service --no-pager -n 20
		run "broker status" systemctl status passkey-tpm-uvd.service --no-pager -n 20
	else
		printf '(systemctl not installed)\n'
	fi
}

collect_journal() {
	section "Recent journal"
	if ! have journalctl; then
		printf '(journalctl not installed)\n'
		return
	fi
	printf '%s\n' '-- agent (user) --'
	timeout 10 journalctl --user -u passkey-tpm-agent -b -n 100 --no-pager 2>&1 | redact || true
	printf '%s\n' '-- broker (system; may require sudo) --'
	timeout 10 journalctl -u passkey-tpm-uvd -b -n 100 --no-pager 2>&1 | redact || true
	if sudo -n true 2>/dev/null; then
		printf '%s\n' '-- broker (sudo) --'
		timeout 10 sudo -n journalctl -u passkey-tpm-uvd -b -n 200 --no-pager 2>&1 | redact || true
	else
		printf '(passwordless sudo unavailable; run: sudo journalctl -u passkey-tpm-uvd -b -n 200)\n'
	fi
}

collect_cli() {
	run "passkey-tpm version" passkey-tpm version
	run "passkey-tpm info" passkey-tpm info
}

collect_devices() {
	run "Security keys (fido2-token -L)" fido2-token -L
}

collect_fingerprint() {
	section "Fingerprint"
	if have fprintd-list; then
		local user fp_out count
		user=${USER:-$(id -un)}
		fp_out=$(timeout "$PROBE_TIMEOUT" fprintd-list "$user" 2>&1)
		if [[ -n "$fp_out" ]]; then
			printf '%s\n' "$fp_out" | redact
		else
			printf '(no output)\n'
		fi
		count=$(printf '%s\n' "$fp_out" | grep -cE '^[[:space:]]*-[[:space:]]*#[0-9]+' || true)
		printf 'enrolled finger count: %s\n' "$count"
	else
		printf '(fprintd-list not installed)\n'
	fi
}

collect_browsers() {
	section "Browsers"
	local found=0 browser version
	for browser in google-chrome-stable google-chrome chromium chromium-browser firefox; do
		if have "$browser"; then
			found=1
			version=$(timeout 10 "$browser" --version 2>&1 | head -n 1)
			printf '%s: %s\n' "$browser" "$version"
		fi
	done
	if (( found == 0 )); then
		printf '(no native Chrome/Chromium/Firefox binary found)\n'
	fi
	if have flatpak; then
		printf 'flatpak browsers: '
		timeout 10 flatpak list --app --columns=application 2>/dev/null \
			| grep -iE 'chrome|chromium|firefox' | tr '\n' ' ' || true
		printf '\n'
	fi
	if have snap; then
		printf 'snap browsers: '
		timeout 10 snap list 2>/dev/null | awk 'NR>1 {print $1}' \
			| grep -iE 'chrome|chromium|firefox' | tr '\n' ' ' || true
		printf '\n'
	fi
	printf 'note: sandboxed (Snap/Flatpak) browsers usually cannot open /dev/hidraw*\n'
}

capture_trace() {
	section "CTAP trace capture (${TRACE_SECONDS}s)"
	if ! have journalctl; then
		printf '(journalctl not installed; cannot capture a trace)\n'
		return
	fi

	printf 'Start your passkey operation now; capture runs for %ss...\n' "$TRACE_SECONDS" >&2
	WORK_DIR=$(mktemp -d)
	local pids=() pid
	timeout "$TRACE_SECONDS" journalctl --user -u passkey-tpm-agent -f -n 0 --no-pager \
		> "$WORK_DIR/agent.log" 2>&1 &
	pids+=($!)
	if sudo -n true 2>/dev/null; then
		timeout "$TRACE_SECONDS" sudo -n journalctl -u passkey-tpm-uvd -f -n 0 --no-pager \
			> "$WORK_DIR/broker.log" 2>&1 &
		pids+=($!)
	else
		printf '(broker trace skipped: passwordless sudo unavailable)\n' > "$WORK_DIR/broker.log"
	fi
	for pid in "${pids[@]}"; do
		wait "$pid" 2>/dev/null || true
	done

	printf '%s\n' '-- agent --'
	redact < "$WORK_DIR/agent.log"
	printf '%s\n' '-- broker --'
	redact < "$WORK_DIR/broker.log"
	rm -rf "$WORK_DIR"
	WORK_DIR=""
}

main() {
	printf '# passkey-tpm doctor\n'
	printf 'generated: %s\n' "$(date -Iseconds 2>/dev/null || date)"
	printf 'script: %s\n' "$PROG"
	printf 'note: credential IDs and long binary values are redacted; review before sharing.\n'

	collect_os
	collect_omarchy
	collect_services
	collect_journal
	collect_cli
	collect_devices
	collect_fingerprint
	collect_browsers
	if (( TRACE_SECONDS > 0 )); then
		capture_trace
	fi

	printf '\n## Next steps\n'
	printf '1. Compare the fingerprint and service lines with docs/TROUBLESHOOTING.md.\n'
	printf '2. For a failing site, run the matching scenario in browser-test-compat.html.\n'
	printf '3. Attach this report, the browser result, and any --trace output to the issue.\n'
}

while (($# > 0)); do
	case "$1" in
		--output)
			(($# >= 2)) || die "--output needs a file"
			OUTPUT_FILE=$2
			shift 2
			;;
		--trace)
			if (($# >= 2)) && [[ "$2" =~ ^[0-9]+$ ]]; then
				TRACE_SECONDS=$2
				shift 2
			else
				TRACE_SECONDS=15
				shift
			fi
			;;
		--trace=*)
			TRACE_SECONDS=${1#*=}
			shift
			;;
		--redact)
			(($# >= 2)) || die "--redact needs a file"
			REDACT_FILE=$2
			shift 2
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

[[ "$TRACE_SECONDS" =~ ^[0-9]+$ ]] || die "--trace must be a number of seconds"
(( TRACE_SECONDS <= 300 )) || die "--trace must be 300 seconds or less"

if [[ -n "$REDACT_FILE" ]]; then
	[[ -r "$REDACT_FILE" ]] || die "cannot read $REDACT_FILE"
	redact < "$REDACT_FILE"
	exit 0
fi

if [[ -n "$OUTPUT_FILE" ]]; then
	main 2>&1 | tee "$OUTPUT_FILE"
	exit "${PIPESTATUS[0]}"
fi

main 2>&1
