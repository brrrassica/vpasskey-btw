#!/usr/bin/env bash
# Remove passkey-tpm. Credentials in /var/lib/passkey-tpm are kept unless --purge.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSIONS_FILE="$ROOT/versions.env"

DRY_RUN=0
FORCE=0
PURGE=0
SHOW_VERSION=0

usage() {
	cat <<'EOF'
usage: uninstall.sh [--purge] [--dry-run] [--force] [--version] [--help]

  --purge     Also remove /var/lib/passkey-tpm and the passkey-tpm user/group.
  --dry-run   Print what would be removed; touch nothing and run no sudo.
  --force     Best effort: ignore stop/removal errors and skip daemon reloads.
  --version   Print the wrapper version, then exit.
  --help      Show this help.
EOF
}

log() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }

# This script must run as the invoking user so `systemctl --user` reaches that
# user's session bus; only the privileged removal steps use sudo. A root run
# would disable/stop the agent in root's nonexistent session and leave the
# real user's agent enabled. If started with sudo, drop back to the real user
# before doing any work, preserving the original argv.
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
	if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != root ]]; then
		log "Re-running as $SUDO_USER; do not invoke uninstall.sh with sudo"
		exec sudo -u "$SUDO_USER" -H -- "$0" "$@"
	fi
	printf 'error: run uninstall.sh as your normal user; it invokes sudo for privileged steps\n' >&2
	exit 1
fi

while (( $# > 0 )); do
	case "$1" in
		--purge) PURGE=1 ;;
		--dry-run) DRY_RUN=1 ;;
		--force) FORCE=1 ;;
		--version|-V) SHOW_VERSION=1 ;;
		--help|-h) usage; exit 0 ;;
		*) printf 'error: unknown option: %s (see --help)\n' "$1" >&2; exit 2 ;;
	esac
	shift
done

WRAPPER_VERSION="unknown"
if [[ -f "$VERSIONS_FILE" ]]; then
	# shellcheck source=versions.env disable=SC1091
	source "$VERSIONS_FILE"
	WRAPPER_VERSION="${VPASSKEY_VERSION:-unknown}"
fi

if (( SHOW_VERSION )); then
	printf 'vpasskey-btw %s\n' "$WRAPPER_VERSION"
	exit 0
fi

# In dry-run mode, print each privileged command instead of running it.
run() {
	if (( DRY_RUN )); then
		printf '  [dry-run] %s\n' "$*"
	else
		"$@"
	fi
}

if (( DRY_RUN )); then
	cat <<EOF

==> Dry run: no changes will be made

wrapper: vpasskey-btw $WRAPPER_VERSION
purge:   $([[ "$PURGE" == "1" ]] && echo yes || echo no)

Would stop and disable passkey-tpm-agent and passkey-tpm-uvd.
Would remove /usr/lib/passkey-tpm, /usr/bin/passkey-tpm,
/usr/bin/passkey-tpm-tray, /etc/xdg/autostart/passkey-tpm-tray.desktop, and
the installed systemd, D-Bus, polkit, udev, sysusers, and modules-load files.
EOF
	if (( PURGE )); then
		echo "Would purge /var/lib/passkey-tpm and the passkey-tpm user/group."
	fi
	echo "Would reload systemd, udev, and D-Bus."
	exit 0
fi

# A missing service is not an error: run on a partial install must still clean
# up. --force additionally tolerates a broken/hung manager.
ignore_missing() {
	"$@" 2>/dev/null || true
}

log "Stopping session agent"
if ! systemctl --user disable --now passkey-tpm-agent 2>/dev/null; then
	if (( FORCE )); then
		printf 'warning: could not stop passkey-tpm-agent; continuing (--force)\n' >&2
	elif [[ -e /usr/lib/systemd/user/passkey-tpm-agent.service ]]; then
		printf 'error: could not stop passkey-tpm-agent for this user; retry with --force\n' >&2
		exit 1
	fi
fi

log "Stopping broker"
ignore_missing sudo systemctl stop passkey-tpm-uvd

log "Removing installed files"
sudo rm -rf /usr/lib/passkey-tpm
sudo rm -f /usr/bin/passkey-tpm /usr/bin/passkey-tpm-tray
sudo rm -f \
	/etc/xdg/autostart/passkey-tpm-tray.desktop \
	/usr/lib/systemd/system/passkey-tpm-uvd.service \
	/usr/lib/systemd/user/passkey-tpm-agent.service \
	/usr/share/dbus-1/system.d/io.github.dangerousplay.PasskeyTpm1.conf \
	/usr/share/dbus-1/system-services/io.github.dangerousplay.PasskeyTpm1.service \
	/usr/share/polkit-1/rules.d/50-passkey-tpm-fprintd.rules \
	/usr/share/polkit-1/actions/io.github.dangerousplay.PasskeyTpm1.policy \
	/usr/lib/udev/rules.d/70-passkey-tpm-uhid.rules \
	/usr/lib/modules-load.d/passkey-tpm.conf \
	/usr/lib/sysusers.d/passkey-tpm.conf
sudo rm -rf /usr/share/doc/passkey-tpm /usr/share/licenses/passkey-tpm

if [[ "$PURGE" == "1" ]]; then
	log "Purging credentials and broker user"
	sudo rm -rf /var/lib/passkey-tpm
	sudo userdel passkey-tpm 2>/dev/null || true
	sudo groupdel passkey-tpm 2>/dev/null || true
fi

if (( FORCE )); then
	log "Skipping daemon reloads (--force)"
else
	log "Reloading daemons"
	sudo systemctl daemon-reload
	sudo udevadm control --reload-rules
	sudo systemctl reload dbus.service 2>/dev/null || true
fi

log "Done. Reboot or log out/in to fully release the virtual HID device."
