# Local upstream patches

These patches are applied by [`install.sh`](../install.sh) after it checks out the
upstream pin from [`versions.env`](../versions.env):

1. `git apply --check` every patch; abort the install if any patch no longer applies.
2. `git apply` them in filename order.
3. Commit the result in the checkout so the next install's dirty-tree guard still sees a
   clean working tree. The files here, not that local commit, are the source of truth.

The pin (`v0.1.0-brrr1`) already contains patches 0001–0003, so `install.sh`
checks a per-patch marker and skips only the patches already in the tree. Patch
0004 is newer than the pin and is applied on top of it. The series remains the
reference for older pristine pins, and the pin itself still keeps its SHA
integrity check. When you add a patch, add its marker check to the
`patch_marker` function in [`install.sh`](../install.sh:189) and list it here.

## Current series

- `0001-0.2.0-retries-timeouts-prompt-foundation.patch`
  - M3.2: retry a `verify-no-match` up to 3 times inside one WebAuthn request, with a
    500 ms pause, cancellation between attempts, and a single overall deadline.
  - M3.2: `PASSKEY_UV_TIMEOUT_SECS` (default 60 s) for the broker; the agent derives its
    broker call timeout from the same value plus 15 s of headroom.
  - M4.1/M4.2: prompt backend selection (`PASSKEY_PROMPT=auto|native|polkit|notification|terminal`),
    Omarchy/Hyprland/Wayland detection, and `passkey-tpm-agent --probe-prompt` (also used by
    `verify.sh --prompt`). The full-screen native overlay itself is still M4.3.
- `0002-0.2.0-getinfo-advertisement-audit.patch`
  - M3.1: `firmwareVersion` is derived from the crate version instead of the stale literal
    `0x00020000` (which claimed 2.0.0 for a 0.1.0-beta.2 authenticator).
  - M3.1: advertise `uvModality` (0x12) as fingerprint, matching how UV is actually done.
  - M3.1: `maxMsgSize` and `maxCredentialIdLength` now come from the enforcing constants
    (`ctaphid::MAX_MSG`, `credid::MAX_LEN`) instead of duplicated literals.
  - M3.1: a table-driven `getInfo` regression test pins every member and option, including
    the capability-vs-configuration semantics of `uv` and `clientPin`.
  - No option values changed: `plat: false`, `clientPin: pin_set`, `uv: uv_enrolled`,
    `makeCredUvNotRqd: false`, and the absences (`alwaysUv`, `authnrCfg`, `bioEnroll`,
    `largeBlobs`, `ep`, `setMinPINLength`, …) were audited and are correct.
- `0003-0.2.0-polkit-fingerprint-prompt.patch`
  - M4.5: reuse the desktop polkit prompt instead of a private overlay. When
    `io.github.dangerousplay.PasskeyTpm1.policy` is installed and
    `/etc/pam.d/polkit-1` contains `pam_fprintd.so`, the broker calls
    `CheckAuthorization` with the calling agent's `system-bus-name` and
    `AllowUserInteraction`; Omarchy's polkit agent shows its fingerprint card and
    PAM performs the scan. The action is owned by `unix-user:passkey-tpm` (polkit
    127 trust), and uses `auth_self` without `_keep` so every operation
    re-authenticates.
  - The broker and agent both detect the same precondition
    (`passkey_tpm_uv::polkit::available`); the agent suppresses its toast while
    the broker drives the desktop dialog. If the action or `pam_fprintd` is
    absent, the old direct-fprintd + notification path is unchanged.
  - Adds `UvMethod::Polkit` / `UvEvidence::from_polkit_authorization` so the
    evidence records that the desktop PAM stack authorized the request.
  - Packaging: `packaging/polkit/io.github.dangerousplay.PasskeyTpm1.policy`,
    installed by `cargo xtask dist`; the wrapper's install/uninstall lists are
    updated.
- `0004-0.2.0-credprotect-enforcement.patch`
 - M3.3: `enforceCredentialProtectionPolicy` is no longer ignored. It is
   type-checked, and `true` without `credProtect` returns
   `CTAP2_ERR_INVALID_OPTION` (CTAP 2.1 §6.1.3).
 - M3.3: a `true` flag with a policy stays valid because every credential is
   already created at `credProtect` level 3, which satisfies any requested
   level. No credential is ever created at a weaker level.
 - M3.3: tests pin levels 1/2/3 upgrading to 3, out-of-range and wrong-typed
   values, and that a protected credential is never signed without UV (no
   presence-only signature, no silent assertion).
 - Marker: `enforceCredentialProtectionPolicy` in
   `crates/core/src/ctap2/make_credential.rs`.

## Refreshing a patch

```bash
# Edit the checkout, then (new files need add -N so git diff includes them):
git -C passkey-tpm add -N path/to/new/file.rs
git -C passkey-tpm diff --binary --src-prefix=a/ --dst-prefix=b/ \
  > patches/0001-0.2.0-retries-timeouts-prompt-foundation.patch
git -C passkey-tpm reset --hard HEAD
git -C passkey-tpm clean -fd
git -C passkey-tpm apply --check ../patches/0001-0.2.0-retries-timeouts-prompt-foundation.patch
```

`target/` is gitignored, so `git clean -fd` (without `-x`) keeps build output.
