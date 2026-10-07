#!/usr/bin/env bash
# Remove passkey-tpm. Credentials in /var/lib/passkey-tpm are kept unless --purge.
set -euo pipefail

PURGE=0
[[ "${1:-}" == "--purge" ]] && PURGE=1

log() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }

log "Stopping session agent"
systemctl --user disable --now passkey-tpm-agent 2>/dev/null || true

log "Stopping broker"
sudo systemctl stop passkey-tpm-uvd 2>/dev/null || true

log "Removing installed files"
sudo rm -rf /usr/lib/passkey-tpm /usr/bin/passkey-tpm
sudo rm -f \
	/usr/lib/systemd/system/passkey-tpm-uvd.service \
	/usr/lib/systemd/user/passkey-tpm-agent.service \
	/usr/share/dbus-1/system.d/io.github.dangerousplay.PasskeyTpm1.conf \
	/usr/share/dbus-1/system-services/io.github.dangerousplay.PasskeyTpm1.service \
	/usr/share/polkit-1/rules.d/50-passkey-tpm-fprintd.rules \
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

log "Reloading daemons"
sudo systemctl daemon-reload
sudo udevadm control --reload-rules
sudo systemctl reload dbus.service 2>/dev/null || true

log "Done. Reboot or log out/in to fully release the virtual HID device."