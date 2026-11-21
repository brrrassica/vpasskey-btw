#!/usr/bin/env bash
# Cheap repository checks for the wrapper: shell syntax, shellcheck where
# available, offline CLI smoke tests, relative Markdown links, and pin/docs
# consistency. Safe to run locally and in CI; it never touches the system.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

printf '== shell syntax\n'
mapfile -t shell_files < <(find . -maxdepth 2 -type f \( -name '*.sh' -o -name 'install.sh' -o -name 'uninstall.sh' -o -name 'verify.sh' \) \
	-not -path './passkey-tpm/*' -not -path './.git/*' | sort)
(( ${#shell_files[@]} > 0 )) || fail "no shell files found"
bash -n "${shell_files[@]}"

if command -v shellcheck >/dev/null 2>&1; then
	printf '== shellcheck\n'
	shellcheck -S warning "${shell_files[@]}"
else
	printf '== shellcheck (not installed; skipped)\n'
fi

printf '== offline CLI smoke tests\n'
./install.sh --version >/dev/null
./install.sh --dry-run >/dev/null
./uninstall.sh --version >/dev/null
./uninstall.sh --dry-run >/dev/null
./uninstall.sh --dry-run --force >/dev/null
./verify.sh --help >/dev/null
./verify.sh --compat >/dev/null
./scripts/check-install-targets.sh --help >/dev/null

printf '== pin/docs consistency\n'
# shellcheck source=versions.env disable=SC1091
source "$ROOT/versions.env"
[[ -n "${PASSKEY_TPM_REF:-}" ]] || fail "PASSKEY_TPM_REF is empty"
[[ -n "${PASSKEY_TPM_COMMIT:-}" ]] || fail "PASSKEY_TPM_COMMIT is empty"
for file in README.md CHANGELOG.md docs/INSTALL.md docs/CREDITS.md patches/README.md; do
	grep -Fq "$PASSKEY_TPM_REF" "$file" || fail "$file does not mention pin $PASSKEY_TPM_REF"
done
for file in README.md CHANGELOG.md docs/INSTALL.md docs/CREDITS.md; do
	grep -Fq "${PASSKEY_TPM_COMMIT:0:7}" "$file" || fail "$file does not mention commit ${PASSKEY_TPM_COMMIT:0:7}"
done

printf '== relative Markdown links\n'
python3 - <<'PY'
from pathlib import Path
import re
import sys
import urllib.parse

root = Path('.')
pattern = re.compile(r'(!?)\[[^\]]*\]\(([^)]+)\)')
bad = []
for md in sorted(root.rglob('*.md')):
    if any(part in {'.git', 'passkey-tpm', 'site', 'target'} for part in md.parts):
        continue
    text = md.read_text(errors='replace')
    for match in pattern.finditer(text):
        target = match.group(2).strip().strip('<>')
        if not target or target.startswith(('http://', 'https://', 'mailto:', '#')):
            continue
        path = urllib.parse.unquote(target.split('#', 1)[0].split('?', 1)[0])
        if not path:
            continue
        if not (md.parent / path).resolve().exists():
            line = text[:match.start()].count('\n') + 1
            bad.append(f'{md}:{line}: {target}')
if bad:
    print('error: broken relative Markdown links:', file=sys.stderr)
    print('\n'.join(bad), file=sys.stderr)
    raise SystemExit(1)
PY

printf '== repository checks passed\n'
