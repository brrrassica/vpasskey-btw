# Troubleshooting

For per-site status, see [COMPATIBILITY.md](COMPATIBILITY.md). Run the built-in
checks first — they answer most questions:

```sh
./verify.sh          # services, device, TPM, fingerprint enrolment
passkey-tpm info     # same information from the installed tool
sudo passkey-tpm info   # add TPM vendor details
```

## The browser says no security key is found

1. Is the session service running?

   ```sh
   systemctl --user status passkey-tpm-agent
   ```

   If it's not active:

   ```sh
   systemctl --user enable --now passkey-tpm-agent
   ```

2. Does the device exist?

   ```sh
   fido2-token -L
   ```

   You should see a line with `passkey-tpm`. If not, check the log:

   ```sh
   journalctl --user -u passkey-tpm-agent -b
   ```

3. Is the browser native (not Snap/Flatpak)? Sandboxed browsers generally
   cannot open the device.

## No fingerprint card appears (only a notification, or nothing)

Check which prompt the broker will use:

```sh
./verify.sh --prompt
sudo journalctl -u passkey-tpm-uvd -b | grep 'user-verification prompt'
```

`auto` prefers `polkit`, then `notification`, then `terminal`. If you see
`notification` on Omarchy, polkit prompting is unavailable. If you see
`terminal` from a graphical session, the agent did not detect a graphical
session. `PASSKEY_PROMPT` can force a backend, but an unavailable explicit
choice still falls back instead of failing the operation.

`polkit` means the broker asks the desktop agent for each operation. It needs
both pieces installed:

- `/usr/share/polkit-1/actions/io.github.dangerousplay.PasskeyTpm1.policy`
- `pam_fprintd.so` in an `auth` line of `/etc/pam.d/polkit-1`

On Omarchy, `omarchy-setup-security-fingerprint` writes that PAM line. If it is
missing, the broker falls back to `fprintd` and the session agent shows a
notification. Reinstall this project after changing either file so the action
file is present, then restart the broker:

```sh
sudo systemctl restart passkey-tpm-uvd
systemctl --user restart passkey-tpm-agent
```

If the desktop dialog appears but has only a password field, the PAM stack is
not using `pam_fprintd`; re-run Omarchy's fingerprint setup. A dismissed dialog
shows up as a failed WebAuthn operation, and `Cancel` from the browser closes
the dialog.

## The fingerprint is never accepted

- **Hold the finger still for about a second.** A quick tap is the usual failure.
- Confirm the reader itself works:

  ```sh
  fprintd-verify
  ```

  If that also fails, re-enrol: `fprintd-enroll`.
- Try again after a short pause. Repeated failures trigger a short cooldown.

## Nothing works after a reboot

The virtual key is created at login. Log out and back in, then:

```sh
systemctl --user enable --now passkey-tpm-agent
```

The system service `passkey-tpm-uvd` starts on demand and does not need enabling.

## "TPM not available" / permission errors for `passkey-tpm`

That is expected when you run `passkey-tpm` as your normal user — only the
background service is meant to touch the TPM. Run `sudo passkey-tpm info` to see
the TPM, and trust `./verify.sh` for the user-facing view.

If the *service* can't reach the TPM, make sure the `passkey-tpm` account exists
and is in the `tss` group:

```sh
getent passwd passkey-tpm
getent group tss         # should list passkey-tpm
```

## Sites still show *"partial passkey support"*

This is **expected and not a bug in your setup**. See
[HOW-IT-WORKS.md](HOW-IT-WORKS.md). Linux browsers have no true *platform*
authenticator, so a site that specifically asks the browser "do you have a
built-in authenticator?" gets "no" and warns. Your passkeys still register and
work through the *security key* path.

## A site rejects a passkey that used to work

This is usually a **stale credential**: the site's stored passkey no longer
matches the credential on this machine. Delete the passkey in the site's
security settings and register a new one.

Deleting the passkey on the site invalidates only the platform-side record; it
does **not** wipe the local key store. Re-registering creates a matching pair.
See [COMPATIBILITY.md](COMPATIBILITY.md) for the full recovery steps.

## "You already registered on this device"

Expected when the site still has a passkey for your account. The registration
request includes that credential in `excludeCredentials`, the authenticator
matches it, and the browser refuses the duplicate as `InvalidStateError`.

Delete the old passkey on the site first if you intend to replace it.

## After updating or moving files

Rebuild and reinstall:

```sh
./install.sh
```

The installer stops the running services before replacing them, so it is safe to
run while everything is up.

## The installer refuses to run: "not root-owned"

`install.sh` checks every directory it writes into and stops when one of them is
not owned by `root:root`, printing the offending path. That check exists because
a system directory owned by a normal user can be replaced by any process running
as that user, including `sudo` itself.

An older version of the installer (`cp -a` of the staging tree) could cause this.
The current installer installs file by file and verifies that the shared
directories are unchanged afterwards, so it can no longer cause the drift, but it
cannot repair a system that is already in that state.

Repair the reported directories, then install again:

```sh
sudo chown root:root /usr /usr/bin /usr/lib /usr/share \
	/usr/lib/systemd /usr/lib/udev /usr/lib/sysusers.d \
	/usr/lib/modules-load.d /usr/share/doc /usr/share/dbus-1 \
	/usr/share/polkit-1
sudo chown -R root:root \
	/usr/lib/passkey-tpm /usr/share/doc/passkey-tpm /usr/share/licenses/passkey-tpm
sudo pacman -Qkk filesystem
./install.sh --force
```

`./install.sh --force` reinstalls every managed file as `root:root`, including
`/usr/bin/passkey-tpm-tray`, which earlier installs left user-owned. Afterwards,
`find /usr -user "$USER"` should print nothing.

## Reading the logs

```sh
journalctl --user -u passkey-tpm-agent -b -f    # your session agent
sudo journalctl -u passkey-tpm-uvd -b -f        # the privileged service
```

The broker logs each request as `request uid=... command=... len=...`.

## Collecting a redacted trace

Run the doctor before changing anything, so the report shows the failing state:

```sh
./scripts/passkey-doctor.sh --output passkey-doctor.txt
```

It collects service state, recent journals, `passkey-tpm info`, TPM and
fido2-token facts, fingerprint enrolment, browser versions, and Omarchy /
Hyprland detection. Credential IDs and long binary values are replaced with
placeholders. Review the file before sharing it.

To capture what happens during one failing operation, run a trace and perform
the browser flow while it records:

```sh
./scripts/passkey-doctor.sh --trace 30
```

The broker side needs passwordless `sudo`; without it the report records only
the agent side and says so. To sanitize an existing capture, use
`--redact FILE`.

For a repeatable real-site record — options skeleton, redacted doctor output,
and journal trace — use the capture kit:

```sh
./scripts/capture-webauthn-site.sh --site cloudflare --flow authenticate
./scripts/capture-webauthn-site.sh --site openrouter --flow register
```

The protocol and the fields to record are in
[plans/compat/README.md](../plans/compat/README.md). The site flows need a real
authenticated browser session and a physical fingerprint scan.

## Checking the compatibility matrix

```sh
./verify.sh --compat
```

This prints the path to `browser-test-compat.html` and the local HTTP command.
The page exercises attachment mode, resident keys, user verification, allow and
exclude lists, `credProtect`, cancellation, concurrent requests, and retry after
one mismatch. Use it to separate a browser/site policy problem from an
authenticator problem before filing an issue.

## Start over

```sh
./uninstall.sh --purge
./install.sh
```

`--purge` deletes your stored passkeys, so treat it as a factory reset. Sites
where you registered will need a new passkey afterwards.