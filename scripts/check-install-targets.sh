#!/usr/bin/env bash
# Guard against installing files into directories this project does not own.
#
# Background: install.sh used to copy a staging tree with `cp -a`/`cp -r` into
# /usr. That preserves (or recreates) the invoking user's ownership on shared
# system directories, and on 2026-11-02 it left 19 directories under /usr owned
# by a normal user. An installer must never change the metadata of directories
# it does not own, so the installer now installs file by file and uses this
# script to refuse to start on a drifted system and to prove it changed nothing.
#
# Read-only: it never touches the filesystem.
#
#   check-install-targets.sh [--quiet] DEST...
#       Fail if any parent directory of DEST is missing, not root:root, or
#       group/world-writable.
#
#   check-install-targets.sh --snapshot FILE DEST...
#       Record the parent directories' owner, group and mode in FILE.
#
#   check-install-targets.sh --compare FILE DEST...
#       Fail if the parent directories no longer match FILE.
set -euo pipefail

usage() {
	cat <<'EOF'
usage: check-install-targets.sh [--quiet|--snapshot FILE|--compare FILE] DEST...

  (no mode)       Verify every parent directory of DEST is root:root and not
                  group/world-writable.
  --snapshot FILE Record the parent directories' uid, gid and mode in FILE.
  --compare FILE  Verify the parent directories still match FILE.
  --quiet         Print nothing on success.
  --help          Show this help.
EOF
}

die() { printf 'error: %s\n' "$*" >&2; exit 2; }

MODE=check
STATE_FILE=""
QUIET=0

while (( $# > 0 )); do
	case "$1" in
		--snapshot)
			[[ $# -ge 2 ]] || die "--snapshot needs a file"
			MODE=snapshot
			STATE_FILE="$2"
			shift 2
			;;
		--compare)
			[[ $# -ge 2 ]] || die "--compare needs a file"
			MODE=compare
			STATE_FILE="$2"
			shift 2
			;;
		--quiet) QUIET=1; shift ;;
		--help|-h) usage; exit 0 ;;
		--) shift; break ;;
		-*) die "unknown option: $1 (see --help)" ;;
		*) break ;;
	esac
done

(( $# > 0 )) || die "no destination paths given"

# Unique parent directories, in a stable order.
parent_dirs() {
	local dest
	for dest in "$@"; do
		dirname -- "$dest"
	done | sort -u
}

state_of() {
	local dir
	while IFS= read -r dir; do
		if [[ -d "$dir" ]]; then
			stat -c '%n %u %g %a' -- "$dir"
		else
			printf '%s missing missing missing\n' "$dir"
		fi
	done < <(parent_dirs "$@")
}

case "$MODE" in
snapshot)
	state_of "$@" >"$STATE_FILE"
	;;
compare)
	[[ -f "$STATE_FILE" ]] || die "no snapshot at $STATE_FILE"
	current="$(state_of "$@")"
	if ! diff -u "$STATE_FILE" <(printf '%s\n' "$current") >/dev/null; then
		printf 'error: the install changed shared system directories:\n' >&2
		diff -u "$STATE_FILE" <(printf '%s\n' "$current") | sed -n '3,$p' >&2 || true
		exit 1
	fi
	;;
check)
	bad=0
	while IFS= read -r dir; do
		if [[ ! -d "$dir" ]]; then
			printf 'missing system directory: %s\n' "$dir" >&2
			bad=1
			continue
		fi
		read -r _ uid gid mode < <(stat -c '%n %u %g %a' -- "$dir")
		if [[ "$uid" != "0" || "$gid" != "0" ]]; then
			printf '%s is owned by uid %s gid %s, expected root:root\n' \
				"$dir" "$uid" "$gid" >&2
			bad=1
		fi
		if (( (8#$mode & 8#022) != 0 )); then
			printf '%s is group or world writable (mode %s)\n' "$dir" "$mode" >&2
			bad=1
		fi
	done < <(parent_dirs "$@")
	if (( bad )); then
		printf 'refusing to install into directories that are not root-owned\n' >&2
		exit 1
	fi
	if (( ! QUIET )); then
		printf 'install targets ok: %s\n' "$(parent_dirs "$@" | sed 's/^/ /' | tr -d '\n')"
	fi
	;;
*) die "unreachable mode $MODE" ;;
esac
