# Local upstream patches

These patches are applied by [`install.sh`](../install.sh) after it checks out the
upstream pin from [`versions.env`](../versions.env):

1. `git apply --check` every patch; abort the install if any patch no longer applies.
2. `git apply` them in filename order.
3. Commit the result in the checkout so the next install's dirty-tree guard still sees a
   clean working tree. The files here, not that local commit, are the source of truth.

The upstream pin stays at the pristine upstream commit (`v0.1.0-beta.2` @ `1372cf4`),
so `versions.env` keeps its integrity check.

## Current series

- `0001-0.2.0-retries-timeouts-prompt-foundation.patch`
  - M3.2: retry a `verify-no-match` up to 3 times inside one WebAuthn request, with a
    500 ms pause, cancellation between attempts, and a single overall deadline.
  - M3.2: `PASSKEY_UV_TIMEOUT_SECS` (default 60 s) for the broker; the agent derives its
    broker call timeout from the same value plus 15 s of headroom.
  - M4.1/M4.2: prompt backend selection (`PASSKEY_PROMPT=auto|native|polkit|notification|terminal`),
    Omarchy/Hyprland/Wayland detection, and `passkey-tpm-agent --probe-prompt` (also used by
    `verify.sh --prompt`). The full-screen native overlay itself is still M4.3.

## Refreshing a patch

```bash
# Edit the checkout, then (new files need add -N so git diff includes them):
git -C passkey-tpm add -N path/to/new/file.rs
git -C passkey-tpm diff --binary --src-prefix=a/ --dst-prefix=b/ \
  > patches/0001-0.2.0-retries-timeouts-prompt-foundation.patch
git -C passkey-tpm reset --hard HEAD
git -C passkey-tpm clean -fd
git -C passkey-tpm apply --check ../patches/0001-0.2.0-retries-timeouts-prompt-foundation.patch
```

`target/` is gitignored, so `git clean -fd` (without `-x`) keeps build output.
