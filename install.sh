#!/usr/bin/env bash
# Build and install passkey-tpm: a TPM-backed virtual FIDO2 security key whose
# user verification is a fingerprint scan through fprintd.
#
# Run as your normal user; privileged steps use sudo.
set -euo pipefail

REPO_URL="https://github.com/dangerousplay/passkey-tpm"
TAG="${PASSKEY_TPM_TAG:-v0.1.0-beta.1}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/passkey-tpm"
LIBEXECDIR="/usr/lib"   # Arch policy (rather than /usr/libexec)

log() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }

if [[ ! -d "$SRC/.git" ]]; then
	log "Cloning passkey-tpm @ $TAG"
	git clone --depth 1 --branch "$TAG" "$REPO_URL" "$SRC"
fi

log "Building release binaries"
( cd "$SRC" && cargo build --release )

log "Staging FHS install tree (libexecdir=$LIBEXECDIR)"
( cd "$SRC" && cargo xtask dist --no-build --libexecdir "$LIBEXECDIR" )
STAGE="$(find "$SRC/target/dist" -maxdepth 1 -type d -name 'passkey-tpm-*' | sort | tail -1)"
[[ -n "$STAGE" ]] || { echo "staging tree not found" >&2; exit 1; }

log "Stopping running services before replacing binaries"
systemctl --user stop passkey-tpm-agent 2>/dev/null || true
sudo systemctl stop passkey-tpm-uvd 2>/dev/null || true

log "Installing files into / (sudo)"
sudo cp -a "$STAGE/usr/." /usr/
sudo chown root:root \
	/usr/bin/passkey-tpm \
	/usr/lib/passkey-tpm/passkey-tpm-agent \
	/usr/lib/passkey-tpm/passkey-tpm-uvd \
	/usr/lib/systemd/system/passkey-tpm-uvd.service \
	/usr/lib/systemd/user/passkey-tpm-agent.service \
	/usr/share/dbus-1/system.d/io.github.dangerousplay.PasskeyTpm1.conf \
	/usr/share/dbus-1/system-services/io.github.dangerousplay.PasskeyTpm1.service \
	/usr/share/polkit-1/rules.d/50-passkey-tpm-fprintd.rules \
	/usr/lib/udev/rules.d/70-passkey-tpm-uhid.rules \
	/usr/lib/sysusers.d/passkey-tpm.conf \
	/usr/lib/modules-load.d/passkey-tpm.conf
# cp -a preserves the staging tree's ownership, so the directories created
# above are owned by the invoking user until chowned here.
sudo chown -R root:root \
	/usr/lib/passkey-tpm \
	/usr/share/doc/passkey-tpm \
	/usr/share/licenses/passkey-tpm

log "Creating broker user (passkey-tpm, member of tss)"
sudo systemd-sysusers /usr/lib/sysusers.d/passkey-tpm.conf

log "Loading uhid and reloading udev/dbus/systemd"
sudo modprobe uhid
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=misc --sysname-match=uhid
sudo systemctl daemon-reload
sudo systemctl reload dbus.service

log "Enabling per-user session agent"
systemctl --user daemon-reload
systemctl --user enable --now passkey-tpm-agent

sleep 1
log "Result"
passkey-tpm info || true