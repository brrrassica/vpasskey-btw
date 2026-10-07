# Credits and attributions

`vpasskey-btw` is a thin, friendly wrapper: an installer, documentation, and a
test harness. The hard part — the actual FIDO2/WebAuthn authenticator — is other
people's excellent work. Please support and star the upstream projects.

## The authenticator

**[passkey-tpm](https://github.com/dangerousplay/passkey-tpm)** by **Davi
Henrique ([@dangerousplay](https://github.com/dangerousplay))**.

- License: MIT OR Apache-2.0
- It implements the TPM-backed virtual security key, the broker/agent split, the
  CTAP2 logic, the fprintd user verification, and the packaging files.
- This project pins it at tag `v0.1.0-beta.1` and builds it from source.

If you find a bug in the passkey behaviour itself, it most likely belongs
upstream.

## Lineage of the idea

The "virtual FIDO2 key over `/dev/uhid`" approach comes from:

- **[psanford/tpm-fido](https://github.com/psanford/tpm-fido)** by Peter
  Sanford — the original TPM-backed FIDO token for Linux.
- **[mc256/tpm-fido2-thinkpad-linux](https://github.com/mc256/tpm-fido2-thinkpad-linux)**
  by mc256 — the ThinkPad-focused fingerprint/TPM variant that inspired the
  fingerprint user-verification flow.

Related prior art worth knowing:

- [xe-nvdk/llavero](https://github.com/xe-nvdk/llavero)
- [myrtree/cv2-fido](https://github.com/myrtree/cv2-fido)
- [cowboyrushforth/verifidod](https://github.com/cowboyrushforth/verifidod)

## System components used

| Component | Role | License |
|---|---|---|
| [fprintd](https://gitlab.freedesktop.org/libfprint/fprintd) / [libfprint](https://gitlab.freedesktop.org/libfprint/libfprint) | fingerprint verification | LGPL-2.1+ |
| [tpm2-tss](https://github.com/tpm2-software/tpm2-tss) | TPM 2.0 access | BSD-2-Clause |
| [systemd](https://systemd.io/) | services, sessions, sysusers | LGPL-2.1+ |
| [polkit](https://gitlab.freedesktop.org/polkit/polkit) | authorising fprintd for the broker | LGPL-2.0+ |
| [libfido2](https://github.com/Yubico/libfido2) | diagnostic tools (`fido2-token`) | BSD-2-Clause |

## This project

Installer, scripts, test page, and documentation: **MIT © 2026 Sam Ralial**.

See [../LICENSE](../LICENSE).

## Trademarks

YubiKey, Windows Hello, Touch ID, Chrome, Chromium, Brave, Firefox and other
names are trademarks of their respective owners and are used here only to
describe interoperability.