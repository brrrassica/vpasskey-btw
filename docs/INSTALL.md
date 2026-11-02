# Installing vpasskey-btw

## Before you start

You need:

- **A TPM 2.0.** Check with `ls /dev/tpmrm0`. If that prints a path, you're fine.
  On most modern laptops you may need to enable it in the BIOS/UEFI
  ("TPM", "PTT" on Intel, "fTPM" on AMD).
- **A fingerprint reader that `fprintd` can use, with a finger enrolled.**

  ```sh
  fprintd-list "$USER"       # should list a finger, e.g. right-index-finger
  fprintd-enroll             # enrol one if the list is empty
  ```

- **systemd, D-Bus and polkit** — standard on Arch and Omarchy.
- A **native** browser. Snap and Flatpak browsers are sandboxed away from the
  device, so use the distro packages.

You do **not** need to install Rust yourself. The installer builds the
authenticator from source and will fetch the toolchain if needed.

## Install

```sh
git clone https://github.com/brrrassica/vpasskey-btw.git
cd vpasskey-btw
./install.sh
```

The installer will:

1. Fetch the upstream authenticator (`passkey-tpm`) from `versions.env`, verify
   that the ref resolves to the pinned commit, and check out that exact commit.
2. Apply the local patch series in `patches/` on top of the pristine pin.
3. Build it with Cargo.
4. Install its files into `/usr` with explicit `root:root` ownership and modes
   (you'll approve this with your password).
5. Create the `passkey-tpm` service account and load the `uhid` kernel module.
6. Start the per-user session service.

The current pin is `passkey-tpm v0.1.0-beta.2` (commit `1372cf4`). Keep the
wrapper's `versions.env` as the source of truth rather than editing
`install.sh`. For development, `PASSKEY_TPM_REPO`, `PASSKEY_TPM_REF`, and
`PASSKEY_TPM_COMMIT` can override the pin; a custom ref without a matching
commit disables the SHA check.

It is safe to run again — for example after a `git pull` — to rebuild and
reinstall. A dirty `passkey-tpm/` checkout is a hard error; `--force` reinstalls
a matching version but does not discard local changes.

## Confirm it worked

```sh
./verify.sh
```

Look for a security key in the output:

```
security keys (fido2-token -L)  /dev/hidrawN: vendor=0x1209, product=0xf1d0 ( passkey-tpm)
```

Then do a real registration and login against your own fingerprint:

```sh
./verify.sh --bio
```

Touch the reader **twice**, holding for about a second each time. Success ends
with `OK: registration and UV assertion verified`.

Other checks:

```sh
./verify.sh --prompt   # selected fingerprint prompt backend and session detection
./verify.sh --compat   # path and local HTTP command for the compatibility matrix
```

## Fingerprint prompt configuration

On a graphical Omarchy session the polkit fingerprint dialog is used. The
fallbacks are a notification and then a terminal prompt. The agent reads these
environment variables from its user service:

| Variable | Default | Meaning |
|---|---|---|
| `PASSKEY_PROMPT` | `auto` | `auto`, `polkit`, `notification`, or `terminal`. `native` is reserved for the not-yet-built full-screen overlay and falls back. |
| `PASSKEY_UV_TIMEOUT_SECS` | `60` | Overall user-verification deadline shared with the broker. The agent adds 15 s of headroom for the D-Bus call. |

`auto` prefers polkit, then a notification, then the terminal. An unavailable
explicit choice falls back the same way instead of failing the operation. Up to
three mismatches are retried, 500 ms apart, and cancelling in the browser stops
the retries.

## Where things are installed

| Path | What it is |
|---|---|
| `/usr/bin/passkey-tpm` | admin/info command |
| `/usr/lib/passkey-tpm/passkey-tpm-uvd` | privileged background service (TPM + fingerprint) |
| `/usr/lib/passkey-tpm/passkey-tpm-agent` | per-session service (creates the virtual key) |
| `/usr/lib/systemd/system/passkey-tpm-uvd.service` | system service (starts on demand) |
| `/usr/lib/systemd/user/passkey-tpm-agent.service` | your session service (starts at login) |
| `/usr/lib/udev/rules.d/70-passkey-tpm-uhid.rules` | lets your user create the virtual key |
| `/usr/share/polkit-1/rules.d/50-passkey-tpm-fprintd.rules` | lets the service verify your fingerprint directly |
| `/usr/share/polkit-1/actions/io.github.dangerousplay.PasskeyTpm1.policy` | the desktop prompt action for fingerprint approval |
| `/var/lib/passkey-tpm` | your passkeys (TPM-wrapped) |

On Omarchy, a passkey operation opens the same polkit dialog as `sudo`: the
agent shows the fingerprint card because `pam_fprintd.so` is in
`/etc/pam.d/polkit-1`. The broker still owns the verification decision; when
that PAM module is absent it falls back to driving `fprintd` itself and the
session agent shows a notification.

## Uninstall

```sh
./uninstall.sh          # removes the software, keeps your passkeys
./uninstall.sh --purge  # also deletes your passkeys and the service user
```

Then reboot, or log out and back in, so the virtual key is fully released.

If you only want to pause it for a while:

```sh
systemctl --user disable --now passkey-tpm-agent
systemctl --user enable  --now passkey-tpm-agent
```