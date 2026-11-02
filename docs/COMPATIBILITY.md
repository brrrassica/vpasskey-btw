# Compatibility

## Tested environment

- Omarchy 4.0.6 on Arch Linux, Hyprland 0.56.2 (Wayland).
- Lenovo ThinkPad E14 Gen 4, TPM 2.0, Goodix 550A fingerprint reader.
- Chrome 156 and Chromium 156 (native Arch packages).
- `passkey-tpm` 0.1.0-beta.2, installed by this project.

## Site matrix

| Site | Registration | Authentication | Notes |
|---|---|---|---|
| GitHub | Not re-tested | Existing passkey authenticates | A passkey created earlier still produces a valid assertion. The browser flow has not been re-checked for 0.2.0. |
| webauthn.io | Not re-tested | Existing passkey authenticates | Same as GitHub. |
| Cloudflare | Not captured | Passing | `getAssertion` completed with the virtual key and the browser signed in. |
| OpenRouter | Passing | Passing | The original failure was a stale credential. Delete the platform-side passkey and re-register. |

"Authenticates" means the credential produced a valid assertion. A row says
"passing" only when the full browser sign-in or registration completed on the
reference machine.

## Browser support

| Browser | Status |
|---|---|
| Chrome / Chromium (native) | Tested |
| Brave (native) | Expected to work; same engine, not re-tested |
| Firefox (native) | Expected to work; not re-tested for 0.2.0 |
| Snap / Flatpak browsers | Not supported; the sandbox hides the virtual key |

## The "partial passkey support" warning

Linux has no true platform authenticator. This project presents a virtual
security key, so a site that hard-checks for a built-in authenticator may warn
or refuse. That is a platform limitation, not a defect in the virtual key.

## If a site rejects a passkey that used to work

This is usually a **stale credential**: the site's stored credential no longer
matches the credential in this machine's store.

1. Delete the passkey for that site in the site's security settings. This
   invalidates only the platform-side entry; it does not wipe the local key
   store.
2. Register a new passkey on the site with this authenticator.
3. Sign in again.

The same situation can appear during registration as "you already registered on
this device". That is expected: the site's `excludeCredentials` list matched the
existing passkey. Delete the old passkey first if you intend to re-register.

## Collecting diagnostics

If a site still fails, collect a redacted report and a trace while reproducing
the flow:

```sh
./scripts/passkey-doctor.sh --output passkey-doctor.txt
./scripts/passkey-doctor.sh --trace 30
```

Credential IDs and long binary values are redacted. Review the report before
sharing it. See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for how to read the
output and [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for the request path.
