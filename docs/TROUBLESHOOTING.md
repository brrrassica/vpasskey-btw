# Troubleshooting

Run the built-in checks first — they answer most questions:

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

## After updating or moving files

Rebuild and reinstall:

```sh
./install.sh
```

The installer stops the running services before replacing them, so it is safe to
run while everything is up.

## Reading the logs

```sh
journalctl --user -u passkey-tpm-agent -b -f    # your session agent
sudo journalctl -u passkey-tpm-uvd -b -f        # the privileged service
```

The broker logs each request as `request uid=... command=... len=...`.

## Start over

```sh
./uninstall.sh --purge
./install.sh
```

`--purge` deletes your stored passkeys, so treat it as a factory reset. Sites
where you registered will need a new passkey afterwards.