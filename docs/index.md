# vpasskey-btw

**Use your laptop's fingerprint reader for passkeys on Linux.**

Chrome, Chromium, Brave, and Firefox normally need a USB security key for
passkeys on Linux. This project turns the laptop itself into a passkey
authenticator: your **TPM** stores the keys and your **fingerprint** approves
each login.

No USB dongle. No browser extension. No cloud account.

## Install in four commands

```sh
git clone https://github.com/brrrassica/vpasskey-btw.git
cd vpasskey-btw
./install.sh
./verify.sh
```

You will be asked for your password once. The installer builds the
authenticator, installs the system integration, and starts it.

## Use it

1. Open a site that supports passkeys, such as <https://webauthn.io>.
2. Choose to add a passkey or a security key.
3. When the browser asks where to keep it, choose **"Use a security key"**.
4. A fingerprint prompt appears naming the site. **Hold your finger on the
   reader for about a second.**

That is all. Next time, choose the same option and touch the reader again.

On Omarchy the prompt is the same polkit dialog as `sudo`; a notification or a
terminal prompt is used when polkit cannot prompt. Check this session's choice
with `./verify.sh --prompt`.

## Guides

- [Install](INSTALL.md) — requirements, verification, uninstall.
- [Usage](USAGE.md) — registering, signing in, PINs, managing passkeys.
- [How it works](HOW-IT-WORKS.md) — architecture and security model.
- [Compatibility](COMPATIBILITY.md) — tested browsers and sites, known limits.
- [Troubleshooting](TROUBLESHOOTING.md) — diagnosing and fixing problems.
- [Credits](CREDITS.md) — upstream projects and licenses.

## Honest limits

- Passkeys are bound to this machine and this user. They cannot be copied to
  another computer.
- Wiping the TPM or the local credential store invalidates every passkey. Keep
  a recovery method for important accounts.
- The upstream authenticator is pre-alpha and has not had a security review.
- It presents as a security key, not a true platform authenticator, so some
  sites may still warn about "partial passkey support".
