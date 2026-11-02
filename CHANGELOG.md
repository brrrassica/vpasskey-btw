# Changelog

All notable changes to `vpasskey-btw` are recorded here. This project follows
[semantic versioning](https://semver.org/) for the wrapper; the upstream
authenticator has its own version.

The tested browser and site status is not repeated here. See
[docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) for the current matrix and
[plans/towards-0.2.0.md](plans/towards-0.2.0.md) for the release plan and open
items.

## [Unreleased] — 0.2.0-dev

### Added

- A prompt backend abstraction in the agent with
  `PASSKEY_PROMPT=auto|native|polkit|notification|terminal`.
  `auto` prefers the polkit desktop dialog, then a critical notification, then a
  terminal prompt. The native full-screen overlay is detected but not built yet;
  requesting it falls back to the next available backend instead of failing the
  passkey operation.
- A polkit-driven fingerprint prompt. When the installed
  `io.github.dangerousplay.PasskeyTpm1` action and a `pam_fprintd.so` line in
  `/etc/pam.d/polkit-1` are present, the broker calls `CheckAuthorization` and
  Omarchy shows the same fingerprint card as `sudo`. The broker still makes the
  verification decision and the direct `fprintd` path remains the fallback.
- A retry loop around fingerprint verification: up to 3 attempts per request,
  500 ms apart, with cancellation honoured between and during attempts.
- `PASSKEY_UV_TIMEOUT_SECS` to configure the user-verification deadline
  (default 60 s). The agent's broker timeout now tracks it with 15 s of
  headroom.
- `./verify.sh --prompt` to report the selected prompt backend and session
  detection, and `./verify.sh --compat` to locate the local WebAuthn
  compatibility page.
- `scripts/passkey-doctor.sh` for redacted diagnostics, including an optional
  live journal trace of the agent and broker.
- `scripts/capture-webauthn-site.sh` plus `plans/compat/` for recording a
  reproducible, redacted site capture.
- `browser-test-compat.html`, a localhost matrix for attachment mode, resident
  keys, user verification, allow/exclude lists, `credProtect`, cancellation,
  concurrent requests, and retry after a mismatch.
- `scripts/check-install-targets.sh` to refuse an install into a directory that
  is not `root:root`, and to verify the installer did not change directory
  ownership or modes.
- `install.sh --dry-run`, `--force`, `--version`, and `--help`; matching
  `--dry-run`, `--force`, `--version`, and `--help` in `uninstall.sh`.

### Changed

- The upstream pin is now `passkey-tpm v0.1.0-brrr1` (commit `dc4fda7`) from
  [`brrrassica/passkey-tpm`](https://github.com/brrrassica/passkey-tpm), read
  from `versions.env`. An existing `passkey-tpm/` checkout is fetched and
  detached to the pinned commit instead of being reused blindly, and the fetched
  ref must resolve to the pinned SHA unless a development ref is overridden.
- Local fixes are carried as a tracked patch series in `patches/`. The fork
  release `v0.1.0-brrr1` already contains patches 0001–0003, so `install.sh`
  checks a marker per patch and skips only those already in the tree. An older
  pristine pin still gets the whole series, and the patches newer than the pin
  (currently 0004 and 0005) are applied on top.
- The installer installs each staged file with explicit `root:root` ownership
  and modes instead of copying a staging tree, which previously could stamp the
  invoking user's ownership onto shared system directories.
- `getInfo` now derives `firmwareVersion` from the crate version, advertises
  `uvModality` (fingerprint), and aliases the enforced message and credential-ID
  limits instead of duplicating literals.
- Documentation now covers the prompt backends, installer safety checks,
  diagnostics, trace collection, and the tested compatibility matrix.

### Fixed

- A single `verify-no-match` no longer ends a WebAuthn request immediately.
- An empty `allowCredentials` list is treated as "no restriction", so a
 discoverable assertion can complete instead of returning
 `CTAP2_ERR_NO_CREDENTIALS`. Resident-key metadata, multi-credential ordering,
 exclusion, and the 64-credential limit are now covered by regression tests.
- A 30 s verification deadline no longer cuts off a browser or user that needs
  more time.
- The installer no longer skips a stale `passkey-tpm/` checkout, so a fresh
  install and an upgrade install both build the pinned commit.
- `install.sh` no longer leaves `/usr/bin/passkey-tpm-tray` unmanaged or
  user-owned.
- `enforceCredentialProtectionPolicy` is validated instead of silently ignored;
  a `true` flag without a `credProtect` policy now returns
  `CTAP2_ERR_INVALID_OPTION`.

### Upgrade notes

- Existing passkeys created under `v0.1.0-beta.1` remain valid. The credential
  store format did not change between the two upstream tags.
- If a site rejects a passkey that used to work, treat it as a stale
  credential: delete the passkey on the site, then register again. Deleting the
  platform-side passkey does not wipe the local key store.
- Re-run `./install.sh` to pick up the new pin, patches, and prompt behavior.
  `./install.sh --force` is available for a reinstall; a dirty `passkey-tpm/`
  checkout remains a hard error.

### Known limitations

- The native Omarchy layer-shell overlay is not implemented yet. On a graphical
  session the polkit dialog is the primary prompt, with a notification fallback.
- Linux browsers still report "partial passkey support" because the device is a
  virtual cross-platform security key, not a platform authenticator.
- Snap and Flatpak browsers cannot see the virtual key.
- The upstream authenticator is pre-alpha and has not had a security review.
