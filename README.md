# vpasskey-btw

**Use your laptop's fingerprint reader for passkeys on Linux.**

Chrome, Chromium, Brave, and Firefox normally can't use passkeys on Linux
without a USB security key or a browser extension. This project turns your
laptop itself into a passkey authenticator: your **TPM** stores the keys and
your **fingerprint** (through `fprintd`) approves each login.

No USB dongle. No browser extension. No cloud account.

> Built for **Omarchy / Arch Linux**. Verified on a Lenovo ThinkPad E14 Gen 4
> (AMD) with a Goodix 550A fingerprint sensor.

---

## The problem this solves

If a website (GitHub, for example) has told you:

> *"This browser or device is reporting partial passkey support."*

…that is because Linux browsers have no built-in *platform authenticator* — the
thing that makes Touch ID on a Mac or Windows Hello on a PC work. Your browser
can do passkeys, but it has nowhere local to keep them and no way to check it's
really you.

`vpasskey-btw` gives it both.

## What you get

A small background service presents a **virtual FIDO2 security key** to the
system. Browsers see it exactly like a plugged-in YubiKey, except:

- the private keys live in your **TPM 2.0** and never leave the machine,
- each use asks for your **fingerprint** instead of a button press,
- it works in **every native browser at once** — nothing to install in the browser.

---

## Requirements

| Need | Check |
|---|---|
| Linux with a TPM 2.0 | `ls /dev/tpmrm0` |
| A fingerprint reader supported by `fprintd`, with a finger enrolled | `fprintd-list "$USER"` |
| systemd, D-Bus, polkit | (standard on Arch/Omarchy) |
| A native browser (Chrome/Chromium/Brave/Firefox) | Snap/Flatpak browsers can't reach the device |

Rust is only needed if you build from source; the installer handles that too.

## Install

```sh
git clone https://github.com/brrrassica/vpasskey-btw.git
cd vpasskey-btw
./install.sh
```

The installer builds the authenticator from source, installs a few system files,
and starts it. You'll be asked for your password **once**.

Then make sure it's alive:

```sh
./verify.sh
```

You should see the virtual key listed as something like
`/dev/hidrawN: vendor=0x1209, product=0xf1d0 ( passkey-tpm)`.

## Use it

1. Open a site that supports passkeys (try <https://webauthn.io>).
2. Choose to add a passkey or a security key.
3. When the browser asks where to save it, pick **"Use a security key"**.
4. **Hold your finger on the reader for about a second.**

That's it. Next login, do the same.

> **Tip: hold, don't tap.** A quick tap can time out before the sensor finishes.
> If a scan doesn't take, the reader will ask again — just try once more.

### Try it locally (no third-party site)

```sh
python3 -m http.server 8765 --directory .
google-chrome-stable http://localhost:8765/browser-test.html
```

Click **Register passkey**, choose **Use a security key**, and touch the reader.
Use `localhost`, **not** `127.0.0.1` — WebAuthn rejects IP-address sites.

## Verify

```sh
./verify.sh         # checks services, device, TPM and fingerprint enrolment
./verify.sh --bio   # full register + login, touching the reader twice
```

A passing biometric run ends with:

```
OK: registration and UV assertion verified
```

---

## Troubleshooting

The full list is in [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md). The
common ones:

| Symptom | Try |
|---|---|
| Browser finds no security key | `systemctl --user status passkey-tpm-agent` |
| Fingerprint never accepted | Hold longer; check `fprintd-verify` works |
| GitHub still says *"partial passkey support"* | Expected on Linux — see [Why](#the-problem-this-solves) and [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) |
| Nothing works after a reboot | `passkey-tpm info` and `systemctl --user enable --now passkey-tpm-agent` |

## Uninstall

```sh
./uninstall.sh          # keeps your registered passkeys
./uninstall.sh --purge  # also deletes the passkeys and the service user
```

Then reboot, or log out and back in.

## Security & honest limits

- Passkeys are bound to **this machine and this user**. They cannot be copied to
  another computer, and other users can't use them.
- Wiping the TPM or `/var/lib/passkey-tpm` **invalidates every passkey** here.
  Always keep a recovery method (another key or recovery codes) for important
  accounts.
- The underlying authenticator is **pre-alpha and has not had a security review**.
  Use it as a convenience, not as your only way in.
- The GitHub *"partial passkey support"* banner **may remain**. No non-patched
  Linux browser exposes a true platform authenticator, so sites that test for one
  will still warn. Your passkeys still work — through the *security key* path.

## Credits

This repository is a friendly installer, documentation, and test harness around
**[passkey-tpm](https://github.com/dangerousplay/passkey-tpm)** by **Davi
Henrique ([@dangerousplay](https://github.com/dangerousplay))** — the actual
authenticator. Thank you.

The virtual-FIDO-key idea descends from
**[psanford/tpm-fido](https://github.com/psanford/tpm-fido)** and the ThinkPad
work at **[mc256/tpm-fido2-thinkpad-linux](https://github.com/mc256/tpm-fido2-thinkpad-linux)**.

Full attributions and licenses: [docs/CREDITS.md](docs/CREDITS.md).

## License

MIT © 2026 Sam Ralial. The upstream `passkey-tpm` is licensed **MIT OR
Apache-2.0** and is downloaded at install time; see
[docs/CREDITS.md](docs/CREDITS.md).