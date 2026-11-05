#!/usr/bin/env bash
# Build and install passkey-tpm: a TPM-backed virtual FIDO2 security key whose
# user verification is a fingerprint scan through fprintd.
#
# Run as your normal user; privileged steps use sudo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/passkey-tpm"
PATCH_DIR="$ROOT/patches"
LIBEXECDIR="/usr/lib"   # Arch policy (rather than /usr/libexec)
VERSIONS_FILE="$ROOT/versions.env"

DRY_RUN=0
FORCE=0
SHOW_VERSION=0

usage() {
	cat <<'EOF'
usage: install.sh [--dry-run] [--force] [--version] [--help]

  --dry-run   Print what would be done; touch nothing and run no sudo/build.
  --force     Reinstall even if the installed version already matches the pin.
              A dirty passkey-tpm/ checkout is still fatal.
  --version   Print the wrapper version and the upstream pin, then exit.
  --help      Show this help.
EOF
}

log() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

while (( $# > 0 )); do
	case "$1" in
		--dry-run) DRY_RUN=1 ;;
		--force) FORCE=1 ;;
		--version|-V) SHOW_VERSION=1 ;;
		--help|-h) usage; exit 0 ;;
		*) die "unknown option: $1 (see --help)" ;;
	esac
	shift
done

# This script must run as the invoking user: it builds and stages inside the
# project checkout, and only individual privileged steps use sudo. A root run
# both breaks the per-user systemd calls (root has no session bus) and leaves
# root-owned files in the checkout, which makes the next normal run fail.
# If it was started with sudo, drop back to the real user and continue.
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
	if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != root ]]; then
		log "Re-running as $SUDO_USER; do not invoke install.sh with sudo"
		exec sudo -u "$SUDO_USER" -H \
			--preserve-env=PASSKEY_TPM_REPO,PASSKEY_TPM_REF,PASSKEY_TPM_COMMIT \
			-- "$0" "$@"
	fi
	die "run install.sh as your normal user; it invokes sudo for privileged steps"
fi

# Remember whether the caller overrode the pin, so a custom REF without a
# custom COMMIT does not get checked against versions.env's commit.
CUSTOM_REF=0
CUSTOM_COMMIT=0
[[ -n "${PASSKEY_TPM_REF:-}" ]] && CUSTOM_REF=1
[[ -n "${PASSKEY_TPM_COMMIT:-}" ]] && CUSTOM_COMMIT=1

[[ -f "$VERSIONS_FILE" ]] || die "missing $VERSIONS_FILE"
# shellcheck source=versions.env disable=SC1091
source "$VERSIONS_FILE"

REPO_URL="${PASSKEY_TPM_REPO:-}"
REF="${PASSKEY_TPM_REF:-}"
COMMIT="${PASSKEY_TPM_COMMIT:-}"
WRAPPER_VERSION="${VPASSKEY_VERSION:-unknown}"
[[ -n "$REPO_URL" ]] || die "PASSKEY_TPM_REPO is not set"
[[ -n "$REF" ]] || die "PASSKEY_TPM_REF is not set"
if (( CUSTOM_REF && ! CUSTOM_COMMIT )); then
	log "Custom PASSKEY_TPM_REF=$REF; commit verification disabled"
	COMMIT=""
fi

if (( SHOW_VERSION )); then
	printf 'vpasskey-btw %s\n' "$WRAPPER_VERSION"
	printf 'upstream: %s\n' "$REF"
	printf 'commit:   %s\n' "${COMMIT:-<not verified>}"
	exit 0
fi

# REF is normally a tag like v0.1.0-brrr1; strip the leading v for comparing
# with `passkey-tpm version`.
TARGET_VERSION="${REF#v}"

patch_files() {
	[[ -d "$PATCH_DIR" ]] || return 0
	local patches=("$PATCH_DIR"/*.patch)
	[[ -e "${patches[0]}" ]] || return 0
	printf '%s\n' "${patches[@]}"
}

# The installed CLI reports only the upstream package version, so a pin that
# stays on the same tag cannot tell us whether the local patch series changed.
# Record the pin and a fingerprint of the patch contents with the install, and
# use both when deciding whether a rebuild is needed.
INSTALL_STAMP="/usr/lib/passkey-tpm/install-state"
install_state() {
	local patches_hash
	patches_hash="$(
		while IFS= read -r patch; do
			printf '%s\n' "$(basename "$patch")"
			sha256sum < "$patch"
		done < <(patch_files) | sha256sum | awk '{print $1}'
	)"
	printf 'wrapper=%s\nref=%s\ncommit=%s\npatches=%s\n' \
		"$WRAPPER_VERSION" "$REF" "${COMMIT:-}" "$patches_hash"
}
INSTALL_STATE="$(install_state)"

# Skip a pointless rebuild unless the user asks to reinstall. Both the
# installed version and the full install state must match: a matching version
# with a stale patch series still needs a rebuild. --dry-run always prints the
# plan, even when the installed version matches.
if (( ! FORCE && ! DRY_RUN )) && command -v passkey-tpm >/dev/null 2>&1; then
	installed_version="$(passkey-tpm version 2>/dev/null | awk '{print $2}' || true)"
	installed_state="$(cat "$INSTALL_STAMP" 2>/dev/null || true)"
	if [[ "$installed_version" == "$TARGET_VERSION" ]] \
		&& [[ "$installed_state" == "$INSTALL_STATE" ]]; then
		log "passkey-tpm $installed_version is already installed; use --force to reinstall"
		exit 0
	fi
fi

# Files installed from the staging tree. Keep this list in sync with
# cargo xtask dist and the uninstaller.
BIN_FILES=(
	/usr/bin/passkey-tpm
	/usr/bin/passkey-tpm-tray
	/usr/lib/passkey-tpm/passkey-tpm-agent
	/usr/lib/passkey-tpm/passkey-tpm-uvd
)
CONF_FILES=(
	/etc/xdg/autostart/passkey-tpm-tray.desktop
	/usr/lib/systemd/system/passkey-tpm-uvd.service
	/usr/lib/systemd/user/passkey-tpm-agent.service
	/usr/share/dbus-1/system.d/io.github.dangerousplay.PasskeyTpm1.conf
	/usr/share/dbus-1/system-services/io.github.dangerousplay.PasskeyTpm1.service
	/usr/share/polkit-1/rules.d/50-passkey-tpm-fprintd.rules
	/usr/share/polkit-1/actions/io.github.dangerousplay.PasskeyTpm1.policy
	/usr/lib/udev/rules.d/70-passkey-tpm-uhid.rules
	/usr/lib/sysusers.d/passkey-tpm.conf
	/usr/lib/modules-load.d/passkey-tpm.conf
)
TREE_PATHS=(
	/usr/lib/passkey-tpm
	/usr/share/doc/passkey-tpm
	/usr/share/licenses/passkey-tpm
)

if (( DRY_RUN )); then
	cat <<EOF

==> Dry run: no changes will be made

wrapper:          vpasskey-btw $WRAPPER_VERSION
upstream repo:    $REPO_URL
upstream ref:     $REF
expected commit:  ${COMMIT:-<not verified>}
source checkout:  $SRC
libexecdir:       $LIBEXECDIR

Would sync the source checkout (clone/fetch/checkout as needed).
EOF
	while IFS= read -r patch; do
		[[ -n "$patch" ]] && printf 'Would ensure patch (skipped only if already in the tree): %s\n' "$patch"
	done < <(patch_files)
	cat <<EOF
Would build release binaries and stage a dist tree.
Would install, file by file as root (0755 binaries / 0644 config, no recursive
copy and no recursive chown), these paths and their staged siblings:
$(printf '  %s\n' "${BIN_FILES[@]}" "${CONF_FILES[@]}")
Would refuse to start if any of their parent directories is not root-owned.
Would verify afterwards that no shared system directory changed owner or mode.
Would strip ACLs and verify no named ACL entries remain.
Would run systemd-sysusers, modprobe uhid, udev/dbus/systemd reloads.
Would enable and start passkey-tpm-agent for this user.
Would record the pin and patch state in /usr/lib/passkey-tpm/install-state.
EOF
	exit 0
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

# The pinned fork release already carries most of this series, and a later
# patch might not be in the pin yet. Each patch therefore has its own marker:
# the bit of tree it produces. Checking markers per patch (rather than one
# all-or-nothing marker) lets a pin that already has 0001..0003 receive a new
# 0004 without replaying the old patches. When you add a patch, add its marker
# here and to patches/README.md.
patch_marker() {
	case "$(basename "$1")" in
		0001-*)
			[[ -e "$SRC/crates/agent/src/prompt.rs" ]]
			;;
		0002-*)
			grep -q 'uvModality' "$SRC/crates/core/src/ctap2/info.rs"
			;;
		0003-*)
			[[ -e "$SRC/crates/uv/src/polkit.rs" ]]
			;;
		0004-*)
			grep -q 'enforceCredentialProtectionPolicy' \
				"$SRC/crates/core/src/ctap2/make_credential.rs"
			;;
		0005-*)
			grep -q 'empty allowList means' \
				"$SRC/crates/core/src/ctap2/get_assertion.rs"
			;;
		0006-*)
			grep -q 'hmac_secret_applies_only_to_the_first_assertion' \
				"$SRC/crates/core/src/ctap2/tests.rs"
			;;
		0007-*)
			grep -q 'status_codes_match_ctap_21_section_8_2' \
				"$SRC/crates/core/src/ctap2/tests.rs"
			;;
		*)
			return 1
			;;
	esac
}

# Apply the tracked local patch series, then commit it so the next run's
# dirty-checkout guard still sees a clean tree. The files under patches/ remain
# the source of truth.
apply_patches() {
	local patch

	while IFS= read -r patch; do
		[[ -n "$patch" ]] || continue
		if patch_marker "$patch"; then
			log "Already present in ${COMMIT:-$REF}: $(basename "$patch")"
			continue
		fi
		log "Applying $(basename "$patch")"
		if ! git -C "$SRC" apply --check "$patch"; then
			die "$(basename "$patch") does not apply to ${COMMIT:-$REF}; refresh the patch series"
		fi
		git -C "$SRC" apply "$patch"
	done < <(patch_files)

	if ! git -C "$SRC" diff --quiet || ! git -C "$SRC" diff --cached --quiet; then
		git -C "$SRC" add -A
		git -C "$SRC" -c user.name="vpasskey-btw" \
			-c user.email="vpasskey-btw@localhost" \
			commit -q -m "vpasskey-btw: apply local patch series"
		log "Committed the local patch series (working tree left clean)"
	fi
}

# An earlier privilege-confused run (before the guard above) can leave
# root-owned artifacts in the checkout. `target/dist` then makes staging fail
# with EACCES for the invoking user, and root-owned `.git` objects break later
# maintenance. Both are generated trees the project owns, so reclaim them
# rather than refusing. The working tree itself stays protected by the dirty
# checkout guard.
reclaim_root_owned() {
	local path owner
	owner="$(id -u):$(id -g)"
	for path in "$SRC/.git" "$SRC/target/dist"; do
		[[ -e "$path" ]] || continue
		if [[ -n "$(find "$path" ! -user "$(id -u)" -print -quit 2>/dev/null)" ]]; then
			log "Reclaiming root-owned files under $path from an earlier privileged run"
			sudo chown -R "$owner" "$path"
		fi
	done
}

reclaim_root_owned
sync_source
apply_patches

log "Building release binaries"
( cd "$SRC" && cargo build --release )

log "Staging FHS install tree (libexecdir=$LIBEXECDIR)"
( cd "$SRC" && cargo xtask dist --no-build --libexecdir "$LIBEXECDIR" )
# cargo xtask dist names its tree after the checked-out workspace version, not
# after the requested ref. Derive that exact path so a stale higher version
# left by an earlier install (or a downgrade) cannot be selected.
dist_version="$(sed -n 's/^version = "\(.*\)"$/\1/p' "$SRC/Cargo.toml" | head -n 1)"
[[ -n "$dist_version" ]] || die "could not read the workspace version from $SRC/Cargo.toml"
STAGE="$SRC/target/dist/passkey-tpm-$dist_version"
[[ -d "$STAGE/usr" ]] || die "staging tree not found: $STAGE"

# Drop the old stamp before changing the installed tree. It is the fast-path
# guard above, so keeping it through a failed install would make the retry
# report "already installed" and skip the step that failed.
sudo rm -f "$INSTALL_STAMP"

log "Stopping running services before replacing binaries"
systemctl --user stop passkey-tpm-agent 2>/dev/null || true
sudo systemctl stop passkey-tpm-uvd 2>/dev/null || true

log "Installing files into / (sudo)"
# Do NOT copy the staging tree into /usr. `cp -a` preserves the invoking user's
# ownership, and `cp -r` still rewrites directories this project does not own:
# on 2026-11-02 that left 19 directories under /usr owned by a normal user.
# Install one staged file at a time via `install`, which sets the owner, group
# and mode of the file itself and never recurses. Then prove that no shared
# system directory changed owner or mode.
# cargo xtask dist also stages the tray's XDG autostart entry under etc/.
# Install it from the same tree so the package and the uninstaller agree on
# what the tray owns.
STAGE_ROOTS=("$STAGE/usr")
[[ -d "$STAGE/etc" ]] && STAGE_ROOTS+=("$STAGE/etc")
STAGED_FILES=()
while IFS= read -r -d '' staged; do
	STAGED_FILES+=("${staged#"$STAGE"}")
done < <(find "${STAGE_ROOTS[@]}" -type f -print0 | sort -z)
(( ${#STAGED_FILES[@]} > 0 )) || die "staging tree $STAGE has no files"

# Shared parents outside /usr must already exist and be root-owned. The tray
# autostart directory is normally present on a desktop system; create it only
# when missing, before the preflight snapshot, so the install never adopts or
# re-modes an existing shared directory.
for dest in "${STAGED_FILES[@]}"; do
	[[ "$dest" == /usr/* ]] && continue
	parent="$(dirname -- "$dest")"
	if [[ ! -d "$parent" ]]; then
		sudo install -d -o root -g root -m 0755 "$parent"
	fi
done

# Everything outside the project's own trees goes into shared directories; those
# are checked before and after the install.
SHARED_DESTS=()
for dest in "${STAGED_FILES[@]}"; do
	for tree in "${TREE_PATHS[@]}"; do
		if [[ "$dest" == "$tree"/* ]]; then
			continue 2
		fi
	done
	SHARED_DESTS+=("$dest")
done

CHECK_TARGETS="$ROOT/scripts/check-install-targets.sh"
[[ -x "$CHECK_TARGETS" ]] || die "missing $CHECK_TARGETS"
SNAPSHOT="$(mktemp)"
trap 'rm -f "$SNAPSHOT"' EXIT
if (( ${#SHARED_DESTS[@]} > 0 )); then
	if ! "$CHECK_TARGETS" --snapshot "$SNAPSHOT" "${SHARED_DESTS[@]}"; then
		die "could not read the install target directories"
	fi
	if ! "$CHECK_TARGETS" "${SHARED_DESTS[@]}"; then
		die "refusing to install into directories that are not root-owned; repair them first (see docs/TROUBLESHOOTING.md)"
	fi
fi

# The project's own trees are ours to create; only their staged files are copied
# into them, each one explicitly root-owned.
sudo install -d -o root -g root -m 0755 "${TREE_PATHS[@]}"

for dest in "${STAGED_FILES[@]}"; do
	case "$dest" in
		/usr/bin/*|/usr/lib/passkey-tpm/*) mode=0755 ;;
		*) mode=0644 ;;
	esac
	sudo install -o root -g root -m "$mode" "$STAGE$dest" "$dest"
done

# Belt and braces for the ownership bug this replaced: the shared directories
# must be byte-for-byte unchanged in owner, group and mode.
if (( ${#SHARED_DESTS[@]} > 0 )) \
	&& ! "$CHECK_TARGETS" --compare "$SNAPSHOT" "${SHARED_DESTS[@]}"; then
	die "the install changed a shared system directory; inspect /usr before continuing"
fi

# The contract: every managed file exists, is root-owned, and has no ACLs. The
# staging tree belongs to the invoking user, so any named ACL or foreign owner
# here means the install is not trustworthy.
for dest in "${BIN_FILES[@]}" "${CONF_FILES[@]}"; do
	[[ -f "$dest" ]] || die "expected file was not installed: $dest"
	[[ "$(stat -c '%u:%g' "$dest")" == "0:0" ]] || die "$dest is not root-owned"
done

if command -v setfacl >/dev/null 2>&1; then
	sudo setfacl -bR "${TREE_PATHS[@]}"
	sudo setfacl -b -- "${STAGED_FILES[@]}"
fi
if command -v getfacl >/dev/null 2>&1; then
	if sudo getfacl -pR "${TREE_PATHS[@]}" 2>/dev/null | grep -Eq '^user:[^:]+:'; then
		die "installed tree still carries a named ACL entry; refusing to continue"
	fi
	if sudo getfacl -p -- "${STAGED_FILES[@]}" 2>/dev/null | grep -Eq '^user:[^:]+:'; then
		die "installed files still carry a named ACL entry; refusing to continue"
	fi
	log "Verified: installed files have no named ACL entries"
fi
log "Verified: shared system directories unchanged"

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

# Record the pin and patch state only after the ACL contract and the service
# setup have succeeded, so a failure leaves no stamp for the retry fast path.
# It lives in the project's own tree, so uninstall.sh removes it with the rest.
printf '%s\n' "$INSTALL_STATE" | sudo tee "$INSTALL_STAMP" >/dev/null
sudo chown root:root "$INSTALL_STAMP"
sudo chmod 0644 "$INSTALL_STAMP"

sleep 1
log "Result"
# libtss2 writes a permission error to stderr on every unprivileged run because
# only the broker user is meant to open the TPM. `info` already reports the
# device state and points at `sudo passkey-tpm info` for details, so drop the
# library noise: it made a successful install look broken.
passkey-tpm info 2>/dev/null || true
