# vpasskey-btw

**Use your laptop's fingerprint reader for passkeys on Linux.**

Chrome, Chromium, Brave, and Firefox normally can't use passkeys on Linux
without a USB security key or a browser extension. This project turns your
laptop itself into a passkey authenticator: your **TPM** stores the keys and
your **fingerprint** approves each login.

No USB dongle. No browser extension. No cloud account.

> Built for **Omarchy / Arch Linux**. Verified on a Lenovo ThinkPad E14 Gen 4
> (AMD) with a Goodix 550A fingerprint sensor.

## Why this exists

Many sites tell Linux users:

> *"This browser or device is reporting partial passkey support."*

Linux browsers can create passkeys, but they have no built-in *platform
authenticator* — the local "this is really me" check that Touch ID and Windows
Hello provide. Without one, passkeys need an external key.

`vpasskey-btw` gives the system that missing piece.

## What you get

A small background service presents a **virtual security key** to every native
browser. Browsers treat it like a plugged-in FIDO2 key, except:

- the private keys stay in your **TPM 2.0** and never leave the machine;
- each use asks for your **fingerprint** rather than a button press;
- it works in all native browsers at once, with nothing to install in the
  browser.

On Omarchy the fingerprint request opens the same **polkit dialog** as `sudo`.
If that dialog is unavailable, a notification or terminal prompt is used
instead. A mismatch is retried up to three times before the request fails, and
the deadline is 60 seconds by default.

## Requirements

- Linux with a TPM 2.0.
- A fingerprint reader that Linux supports, with at least one finger enrolled.
- A standard Arch/Omarchy desktop (systemd, D-Bus, and polkit).
- A native browser. Snap and Flatpak browsers are sandboxed away from the
  virtual key and will not work.

See [docs/INSTALL.md](docs/INSTALL.md) for exact checks and supported setups.

## Install

```sh
git clone https://github.com/brrrassica/vpasskey-btw.git
cd vpasskey-btw
./install.sh
```

The installer builds the authenticator, installs the system integration, and
starts it. You will be asked for your password once.

Check that it is running:

```sh
./verify.sh
```

For the selected prompt backend:

```sh
./verify.sh --prompt
```

For a full registration and login test, see [docs/INSTALL.md](docs/INSTALL.md).

## Use it

1. Open a site that supports passkeys, such as <https://webauthn.io>.
2. Choose to add a passkey or a security key.
3. When the browser asks where to keep it, choose **"Use a security key"**.
4. **Hold your finger on the reader for about a second.**

That is all. Next time, choose the same option and touch the reader again.

> **Hold, don't tap.** A quick tap can end before the sensor finishes.

A step-by-step guide, including optional PIN setup and local testing, is in
[docs/USAGE.md](docs/USAGE.md).

## Status and compatibility

`vpasskey-btw` 0.1.5 is a halfway development release on the way to 0.2.0.
It upgrades the pinned authenticator to `passkey-tpm v0.1.0-brrr1`, adds the
polkit fingerprint
prompt, retries, a configurable verification timeout, and safer installers. See
[CHANGELOG.md](CHANGELOG.md) for the full list.

Verified on the reference Omarchy machine in Chrome and Chromium:

- Cloudflare sign-in and OpenRouter registration and sign-in work through the
  security-key path.
- Passkeys created earlier for GitHub and webauthn.io remain valid.
- The GitHub-style *"partial passkey support"* warning may remain. It does not
  stop passkeys from working.
- If a site rejects a passkey that used to work, delete that passkey on the site
  and register it again.

The full matrix, including what has not been re-tested, is in
[docs/COMPATIBILITY.md](docs/COMPATIBILITY.md).

## Troubleshooting

Start with the site-specific notes in
[docs/COMPATIBILITY.md](docs/COMPATIBILITY.md), then the full guide in
[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

The most common fixes are holding the finger longer and confirming that the
background service is running. Both are covered in the troubleshooting guide.

## Uninstall

```sh
./uninstall.sh          # removes the software, keeps your passkeys
./uninstall.sh --purge  # also deletes your passkeys and the service user
```

See [docs/INSTALL.md](docs/INSTALL.md) for details and for how to pause it
temporarily.

## Security and honest limits

- Passkeys are bound to **this machine and this user**. They cannot be copied to
  another computer, and other accounts cannot use them.
- Wiping the TPM or the local credential store **invalidates every passkey**.
  Keep a recovery method for important accounts.
- The upstream authenticator is **pre-alpha and has not had a security review**.
  Use it as a convenience, not as your only way in.
- It presents as a **security key**, not a true platform authenticator, so sites
  that require a built-in authenticator may still warn or refuse.

The security model and architecture are explained in
[docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md).

## Documentation

| Guide | What it covers |
|---|---|
| [Install](docs/INSTALL.md) | requirements, installation, verification, uninstall |
| [Usage](docs/USAGE.md) | registering, signing in, PINs, prompt backends, managing passkeys |
| [How it works](docs/HOW-IT-WORKS.md) | architecture and security model |
| [Compatibility](docs/COMPATIBILITY.md) | tested browsers and sites, known limits |
| [Troubleshooting](docs/TROUBLESHOOTING.md) | diagnosing and fixing problems, collecting a trace |
| [Changelog](CHANGELOG.md) | release-by-release changes and upgrade notes |
| [Credits](docs/CREDITS.md) | upstream projects and licenses |

## Credits

`vpasskey-btw` is an installer, documentation, and test harness around
**[passkey-tpm](https://github.com/dangerousplay/passkey-tpm)** by **Davi
Henrique ([@dangerousplay](https://github.com/dangerousplay))**. Thank you.

Full attributions, the upstream pin, and related prior art are in
[docs/CREDITS.md](docs/CREDITS.md).

## License

MIT © 2026 Sam Ralial. The upstream `passkey-tpm` is licensed **MIT OR
Apache-2.0** and is built from source at install time; see
[docs/CREDITS.md](docs/CREDITS.md).
