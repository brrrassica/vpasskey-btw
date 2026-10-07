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

1. Download the upstream authenticator (`passkey-tpm`) at a pinned version.
2. Build it with Cargo.
3. Copy its files into `/usr` (you'll approve this with your password).
4. Create the `passkey-tpm` service account and load the `uhid` kernel module.
5. Start the per-user session service.

It is safe to run again — for example after a `git pull` — to rebuild and
reinstall.

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

## Where things are installed

| Path | What it is |
|---|---|
| `/usr/bin/passkey-tpm` | admin/info command |
| `/usr/lib/passkey-tpm/passkey-tpm-uvd` | privileged background service (TPM + fingerprint) |
| `/usr/lib/passkey-tpm/passkey-tpm-agent` | per-session service (creates the virtual key) |
| `/usr/lib/systemd/system/passkey-tpm-uvd.service` | system service (starts on demand) |
| `/usr/lib/systemd/user/passkey-tpm-agent.service` | your session service (starts at login) |
| `/usr/lib/udev/rules.d/70-passkey-tpm-uhid.rules` | lets your user create the virtual key |
| `/usr/share/polkit-1/rules.d/50-passkey-tpm-fprintd.rules` | lets the service verify your fingerprint |
| `/var/lib/passkey-tpm` | your passkeys (TPM-wrapped) |

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