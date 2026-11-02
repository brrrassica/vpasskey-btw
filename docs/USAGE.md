# Using vpasskey-btw

Once installed, a background service runs for your login session and quietly
offers a virtual security key to every native browser. There is nothing to click
and nothing to configure in the browser.

## Registering a passkey

1. Open a site that supports passkeys. Good test sites:
   - <https://webauthn.io>
   - <https://github.com> → Settings → Passkeys
2. Choose to add a passkey or a security key.
3. When the browser asks where to keep it, choose **"Use a security key"**
   (sometimes worded "USB security key" or "External security key").
4. A fingerprint prompt appears naming the site. On Omarchy this is the same
   polkit dialog as `sudo`; elsewhere it may be a notification or a terminal
   prompt. **Hold your finger on the reader for about a second.**

The browser confirms, and the passkey is stored in your TPM.

> **Hold, don't tap.** The most common cause of a failed scan is lifting the
> finger too early. Rest it flat on the sensor until you feel/see it take.

## Logging in

Exactly the same: pick the passkey / security key option, then touch the reader.

## The fingerprint prompt

The prompt names the relying party the browser asked about. What you see depends
on the session and on `PASSKEY_PROMPT`:

| Backend | When it is used |
|---|---|
| `polkit` | Default on a graphical session where the installed polkit action and `pam_fprintd` in `/etc/pam.d/polkit-1` are available. Shows the Omarchy/desktop fingerprint card. |
| `notification` | Fallback when polkit cannot prompt. A top-right notification asks for the fingerprint. |
| `terminal` | Fallback when there is no graphical session, such as a TTY or an SSH login. |

`PASSKEY_PROMPT=auto` is the default. It prefers polkit, then a notification,
then the terminal. You can force a backend with
`PASSKEY_PROMPT=polkit|notification|terminal`; an unavailable choice falls back
to the same automatic order rather than failing the operation. `native` is
reserved for the full-screen Omarchy overlay, which is not built yet, so it also
falls back.

A mismatch is retried up to three times, 500 ms apart. The whole request expires
after 60 seconds by default; set `PASSKEY_UV_TIMEOUT_SECS` for a different
deadline. Cancelling in the browser stops the prompt and any retry in progress.

Check what this session will use:

```sh
./verify.sh --prompt
```

## A local test page

To prove it works without touching a third-party site:

```sh
python3 -m http.server 8765 --directory .
google-chrome-stable http://localhost:8765/browser-test.html
```

- Click **Register passkey**, choose **Use a security key**, touch the reader.
- Click **Authenticate**, touch again.
- The black box should print `OK`.

`localhost` is required — WebAuthn refuses IP-address origins such as
`127.0.0.1`.

For the larger compatibility matrix — attachment modes, resident keys, user
verification variants, allow/exclude lists, `credProtect`, cancellation,
concurrent requests, and retry — run:

```sh
./verify.sh --compat
```

It prints the path to `browser-test-compat.html` and the local HTTP command.

## Security-key PIN (optional)

Some sites require a PIN when you register a security key. Set one once:

```sh
fido2-token -L                     # find the device, e.g. /dev/hidraw5
fido2-token -S /dev/hidraw5        # set the PIN (you'll touch to approve)
```

After a few wrong entries the PIN locks for a while; the TPM also slows down
guessing. Keep the PIN somewhere safe.

## Managing your passkeys

- **From the browser:** Chrome → Settings → Privacy and security → Security →
  Manage security keys. You can see and delete passkeys here.
- **From the command line:**

  ```sh
  fido2-token -L -r /dev/hidraw5   # list stored resident credentials
  fido2-token -R    /dev/hidraw5   # reset: deletes ALL your passkeys and PIN
  ```

Listing is safe. A reset is permanent for this user.

## Using it for `sudo` too (optional)

The same virtual key can approve `sudo` and Polkit prompts via `pam_u2f`, the
same way a hardware security key would. Keep a root terminal open while you test
PAM changes. See your distribution's `pam_u2f` documentation; the key already
appears to `pamu2fcfg` and `fido2-token`.

## Turning it off temporarily

```sh
systemctl --user stop passkey-tpm-agent    # hide the virtual key
systemctl --user start passkey-tpm-agent   # bring it back
```

Useful if you also own a physical security key and want to avoid confusion
during a browser prompt.