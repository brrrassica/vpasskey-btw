#!/usr/bin/env bash
# Build and install passkey-tpm: a TPM-backed virtual FIDO2 security key whose
# user verification is a fingerprint scan through fprintd.
#
# Run as your normal user; privileged steps use sudo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/passkey-tpm"
LIBEXECDIR="/usr/lib"   # Arch policy (rather than /usr/libexec)
VERSIONS_FILE="$ROOT/versions.env"

log() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Remember whether the caller overrode the pin, so a custom REF without a
# custom COMMIT does not get checked against versions.env's commit.
CUSTOM_REF=0
CUSTOM_COMMIT=0
[[ -n "${PASSKEY_TPM_REF:-}" ]] && CUSTOM_REF=1
[[ -n "${PASSKEY_TPM_COMMIT:-}" ]] && CUSTOM_COMMIT=1

[[ -f "$VERSIONS_FILE" ]] || die "missing $VERSIONS_FILE"
# shellcheck source=versions.env
source "$VERSIONS_FILE"

REPO_URL="${PASSKEY_TPM_REPO:-}"
REF="${PASSKEY_TPM_REF:-}"
COMMIT="${PASSKEY_TPM_COMMIT:-}"
[[ -n "$REPO_URL" ]] || die "PASSKEY_TPM_REPO is not set"
[[ -n "$REF" ]] || die "PASSKEY_TPM_REF is not set"
if (( CUSTOM_REF && ! CUSTOM_COMMIT )); then
	log "Custom PASSKEY_TPM_REF=$REF; commit verification disabled"
	COMMIT=""
fi

# Fetch the pinned ref and check out its exact commit. Works for a fresh
# clone, an existing checkout on another branch, and a stale checkout left
# behind by an older install.sh.
sync_source() {
	if [[ ! -d "$SRC/.git" ]]; then
		log "Cloning $REPO_URL"
		mkdir -p "$(dirname "$SRC")"
		git clone --no-checkout --filter=blob:none "$REPO_URL" "$SRC"
	else
		local origin_url
		origin_url="$(git -C "$SRC" remote get-url origin 2>/dev/null || true)"
		if [[ "$origin_url" != "$REPO_URL" ]]; then
			die "existing checkout $SRC tracks '${origin_url:-<none>}', expected '$REPO_URL'. Remove it or set PASSKEY_TPM_REPO."
		fi
		if ! git -C "$SRC" diff --quiet || ! git -C "$SRC" diff --cached --quiet; then
			die "$SRC has local changes; commit or stash them before installing."
		fi
	fi

	log "Fetching $REF from origin"
	git -C "$SRC" fetch --depth 1 --force origin "$REF"

	local resolved
	resolved="$(git -C "$SRC" rev-parse --verify 'FETCH_HEAD^{commit}')"
	if [[ -n "$COMMIT" && "$resolved" != "$COMMIT" ]]; then
		die "$REF resolved to $resolved, expected $COMMIT"
	fi

	log "Checking out ${COMMIT:-$resolved}"
	git -C "$SRC" -c advice.detachedHead=false checkout --detach "$resolved"
	local head
	head="$(git -C "$SRC" rev-parse HEAD)"
	[[ "$head" == "$resolved" ]] || die "checkout produced $head, expected $resolved"
	if [[ -n "$COMMIT" ]]; then
		log "Verified source integrity: $COMMIT"
	fi
}

sync_source

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