# Capture protocol

Use this protocol to produce a repeatable evidence record for one WebAuthn flow
(register or authenticate) on one real site. A complete record lets you classify
a failure before filing an issue:

- platform-attachment filtering
- CTAP behavior bug
- request-policy mismatch
- browser UI limitation
- not reproduced

## Running a capture

Run the capture kit from the project root:

```sh
./scripts/capture-webauthn-site.sh --site cloudflare --flow authenticate
./scripts/capture-webauthn-site.sh --site openrouter --flow register --seconds 45 \
  --options /path/to/options.json
```

Required: `--site NAME` (letters, digits, dot, dash, underscore) and
`--flow register|authenticate`. Options:

- `--browser NAME`: browser label (default: first of Chrome/Chromium/Firefox found).
- `--seconds N`: journal trace length in seconds (default 30, 5-300).
- `--options FILE`: DevTools WebAuthn options export to redact and include.
- `--output-dir DIR`: where to write evidence (default: `plans/compat`, not
  tracked in git).
- `--dry-run`: print what would be created and capture nothing.

The script prints the site, flow, browser, record path, doctor path, and trace
length. When `passkey-doctor.sh --trace` prints "Start your passkey operation
now", perform the site flow in the named browser and keep the tab focused until
the trace window ends. Once the trace succeeds, the script writes the record
skeleton; if the doctor fails, it reports "Evidence incomplete" and no record
is written for that run.

Broker journal capture needs passwordless `sudo`. Without it, only the agent
side is recorded and the report notes the gap; to capture the broker side, run
`sudo journalctl -u passkey-tpm-uvd -b -f` in a second terminal during the next
capture and save and redact its output.

## What the record contains

Each run writes a record skeleton and a redacted trace:

- `<site>-<flow>-<browser>-<timestamp>.md`: capture metadata, options, field
  summary table, observed outcome, classification, and evidence file list.
- `<site>-<flow>-<browser>-<timestamp>.doctor.txt`: redacted `passkey-doctor.sh`
  trace output.

The record header starts with `Status: trace captured, classification pending`:
the script writes the record only after the doctor trace succeeded. If the
doctor exits with a non-zero status, the script reports "Evidence incomplete"
and exits without writing a record for that run. A failed `--redact` of the
DevTools options export leaves the options section with an explicit failure
marker and makes the script exit non-zero after writing the record.

## Field summary

Fill the field summary table in the generated record from the DevTools WebAuthn
options export for that flow:

| Field | What to record |
|---|---|
| `rp.id` | Relying party identifier from the request. |
| `authenticatorSelection.authenticatorAttachment` | `platform`, `cross-platform`, or absent. |
| `authenticatorSelection.residentKey` | `required`, `preferred`, `discouraged`, or absent. |
| `authenticatorSelection.requireResidentKey` | Boolean value, or absent. |
| `authenticatorSelection.userVerification` | `required`, `preferred`, or `discouraged`. |
| `attestation` | Requested attestation conveyance (`none`, `indirect`, `direct`, `enterprise`). |
| `extensions` | Extension keys present and their relevant values. |
| `excludeCredentials` | Count and each transport, if any (registration). |
| `allowCredentials` | Count and each transport, if any (authentication). |
| `timeout` (ms) | Request timeout value. |
| `mediation / conditional UI` | Mediation mode or conditional UI, if applicable. |
| `hints` | Hint values, if present. |

## Classification

Pick the single category that best explains the outcome:

- **platform-attachment filtering**: the request or browser filtered out the
  virtual key because it is not a built-in platform authenticator.
- **CTAP behavior bug**: the authenticator or broker handled a valid request
  incorrectly.
- **request-policy mismatch**: site policy (resident key, user verification,
  attestation, transports, or credential lists) does not fit this authenticator.
- **browser UI limitation**: the browser UI prevented or misrepresented a flow
  the authenticator could otherwise serve.
- **not reproduced**: the captured run succeeded or the reported failure did not
  occur with current evidence.

## Sharing

The capture kit redacts credential IDs and long binary values, but review every
file before attaching it to an issue.

- `<...>.md`: the evidence record you filled in.
- `<...>.doctor.txt`: redacted doctor/trace output.
- Options JSON: if you passed `--options`, the record includes redacted JSON
  from `passkey-doctor.sh --redact`; keep the original export private.
- `.device-log.txt`: `chrome://device-log` excerpt when available (TODO in the
  generated skeleton). Add it manually if it helps explain the browser side.
