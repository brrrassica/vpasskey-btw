# Local upstream patches

These patches are applied by [`install.sh`](../install.sh) after it checks out the
upstream pin from [`versions.env`](../versions.env):

1. `git apply --check` every patch; abort the install if any patch no longer applies.
2. `git apply` them in filename order.
3. Commit the result in the checkout so the next install's dirty-tree guard still sees a
   clean working tree. The files here, not that local commit, are the source of truth.

The pin (`v0.1.0-brrr1`) already contains patches 0001–0003, so `install.sh`
checks a per-patch marker and skips only the patches already in the tree. Patches
0004–0007 are newer than the pin and are applied on top of it. The series
remains the reference for older pristine pins, and the pin itself still keeps
its SHA integrity check. When you add a patch, add its marker check to the
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
- `0005-0.2.0-resident-key-coverage.patch`
 - M3.4: an empty `allowList` is treated as "no restriction", so a
   `getAssertion` with `allowCredentials: []` can use a discoverable credential
   instead of returning `CTAP2_ERR_NO_CREDENTIALS` (WebAuthn L3 §5.1.3).
 - M3.4: `rk: true` stores the full resident metadata and is discoverable;
   `rk: false` and an absent `rk` create non-discoverable credentials.
   `requireResidentKey` is WebAuthn-side and reaches CTAP only as `rk`.
 - M3.4: tests pin most-recent-first ordering across `getNextAssertion`, the
   `CTAP2_ERR_CREDENTIAL_EXCLUDED` result after a UV gesture (not before it),
   and `CTAP2_ERR_KEY_STORE_FULL` at 64 new resident credentials without
   creating one. Replacing the same `(rp_id, user_id)` still works when full.
 - M3.4: a fresh `Authenticator` over the same backend (a broker restart) still
   finds and returns the resident user metadata.
 - Marker: the empty-`allowList` comment in
   `crates/core/src/ctap2/get_assertion.rs`.
- `0006-0.2.0-hmac-secret-coverage.patch`
 - M3.5: pins the `hmac-secret` extension end to end. The advertisement stays
   `credProtect` + `hmac-secret`, and the test now asserts `prf` is not advertised
   because there is no WebAuthn PRF wiring.
 - M3.5: `makeCredential` with `hmac-secret: false` or no extension returns no
   extension output and creates no hmac keys; a non-boolean value is
   `CTAP2_ERR_CBOR_UNEXPECTED_TYPE`.
 - M3.5: malformed `getAssertion` inputs map to specific statuses: missing
   key/saltEnc/saltAuth is `CTAP2_ERR_MISSING_PARAMETER`, a malformed platform
   key or unsupported PIN/UV auth protocol is `CTAP2_ERR_INVALID_PARAMETER`, a
   decrypted salt that is neither 32 nor 64 bytes is `CTAP2_ERR_INVALID_LENGTH`,
   and a bad `saltAuth` remains `CTAP2_ERR_PIN_AUTH_INVALID`.
 - M3.5: a single salt produces exactly one deterministic 32-byte output; the
   raw output never appears in the response, only its AES-CBC ciphertext. An
   omitted `pinUvAuthProtocol` defaults to protocol one, and a 64-byte input
   returns `output1 ‖ output2`.
 - M3.5: on a multi-account discoverable assertion, `hmac-secret` is computed
   only for the first assertion; `getNextAssertion` reuses UV but carries no
   extension output.
 - Marker: the `hmac_secret_applies_only_to_the_first_assertion` test name in
   `crates/core/src/ctap2/tests.rs`.
- `0007-0.2.0-uv-pin-status-coverage.patch`
  - M3.6: the mismatch that reaches the built-in UV retry limit is now reported
    as `CTAP2_ERR_UV_BLOCKED` on that attempt instead of a generic
    `CTAP2_ERR_OPERATION_DENIED` (CTAP 2.1 §6.5.2.2), which also closes the open
    M3.2 line. Later requests keep returning `UV_BLOCKED`.
  - M3.6: the `uv` option is type-checked in `makeCredential` (key 7) and
    `getAssertion` (key 5). It was previously ignored, so `uv: 1` was silently
    accepted. `uv: false` (WebAuthn "discouraged") still verifies the user
    because every credential is created at credProtect level 3; CTAP 2.1
    §6.1.2/§6.2.2 permits the stricter behaviour.
  - M3.6: tests pin the required/preferred/discouraged matrix with and without a
    fingerprint reader and PIN (`NOT_ALLOWED`, `PUAT_REQUIRED`, UV flag set), the
    PIN/UV status matrix (`PIN_NOT_SET`, `PIN_INVALID`, `PIN_AUTH_BLOCKED`,
    `PIN_BLOCKED`, token permission errors), and every status constant against
    CTAP 2.1 §8.2. Status values themselves are unchanged.
  - Marker: the `status_codes_match_ctap_21_section_8_2` test name in
    `crates/core/src/ctap2/tests.rs`.

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
