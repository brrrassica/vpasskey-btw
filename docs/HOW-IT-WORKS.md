# How it works

## Why Linux browsers say "partial passkey support"

A passkey has two halves:

1. **A credential manager** that stores your keys.
2. A way to **verify it's really you** — usually a system "platform
   authenticator" such as Touch ID (macOS), Windows Hello (Windows) or the
   screen-lock biometric (Android/iOS).

Linux browsers have the first half but **no platform authenticator**, so
`navigator.credentials` can create passkeys only on a security key or through a
browser extension. When a website asks the browser *"is there a built-in
authenticator?"*, the answer is `false`, and it shows the "partial passkey
support" warning.

There is no setting that changes this. The fix is to give the system an
authenticator it can see.

## Giving Linux an authenticator

`vpasskey-btw` presents a **virtual USB FIDO2 security key** built from two
small services:

```
   Browser (Chrome/Chromium/Brave/Firefox)
        │  CTAP2 over /dev/hidrawN
        ▼
 ┌───────────────────────────┐        your login session
 │  passkey-tpm-agent         │  creates the virtual key via /dev/uhid
 └───────────────────────────┘
        │  D-Bus (io.github.dangerousplay.PasskeyTpm1)
        ▼
 ┌───────────────────────────┐        system service, user "passkey-tpm"
 │  passkey-tpm-uvd  (broker) │  owns the TPM, runs user verification
 └───────────────────────────┘
        │                         │
        ▼                         ▼
   TPM 2.0  ────────────────   polkit ── PAM (pam_fprintd) ── reader
   (private keys, wrapped)      │
                                └─ or fprintd directly (fallback)
```

- The **agent** runs as you. It creates a virtual HID device through
  `/dev/uhid`, so the kernel and every browser treat it like a real security
  key. It holds no secrets.
- The **broker** runs as a dedicated `passkey-tpm` system account. It is the
  only process that touches the TPM. It is also the only process allowed to
  ask `fprintd` to verify a fingerprint on your behalf (via a narrow Polkit
  rule), and it owns the `io.github.dangerousplay.PasskeyTpm1.verify` polkit
  action used for the desktop prompt.
- When a browser asks the virtual key to sign, the broker checks that **you have
  an active local session**, asks for a **fingerprint**, and only a successful
  check unlocks the TPM key for that one operation.
- On Omarchy the check is delegated to polkit: the broker calls
  `CheckAuthorization` for your agent's bus name, and the desktop polkit agent
  shows its native fingerprint card. The actual scan is done by
  `pam_fprintd` in `/etc/pam.d/polkit-1`, the same stack `sudo` uses. If that
  module is not configured, the broker keeps the direct `fprintd` path and the
  agent shows a notification instead.

## The security model

- **Keys are generated inside the TPM** and sealed to it (`FixedTPM`,
  `FixedParent`). Copying `/var/lib/passkey-tpm` to another machine produces
  nothing usable.
- **Every operation needs a fresh check.** There is no "remember for a while":
  the polkit action has no `_keep` default, and the direct path takes one
  fingerprint scan per request. When polkit/PAM is used, PAM's configured
  fallback (normally the account password) is also accepted, exactly as it is
  for `sudo`; the direct path remains fingerprint-only.
- **Per user, per machine.** Credentials are namespaced by your user id; other
  accounts on the same laptop cannot use them.
- **Fail closed.** If the fingerprint sensor, the notification service or the
  session check is unavailable, the request is denied rather than falling back
  to something weaker.
- **No fingerprint data is stored** — only the yes/no result from `fprintd`
  matters to this system.

## Honest limitations

- It presents as a **security key**, not a true platform authenticator. That is
  invisible in day-to-day use, but a site that hard-checks for a platform
  authenticator (as GitHub's warning does) may still show "partial".
- The upstream authenticator is **pre-alpha and unaudited**. Treat the
  convenience as such and keep recovery options for critical accounts.
- Nothing here can help a browser that is sandboxed away from HID devices
  (Snap/Flatpak) without per-sandbox rules.