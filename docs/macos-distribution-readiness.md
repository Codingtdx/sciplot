# macOS Distribution Readiness

SciPlot is currently configured for local developer-machine runs. The app target uses disabled code signing and no hardened runtime, which is acceptable for `Launch_SciPlot.command` and automated macOS tests but not for sharing a beta app with external users.

## Supported Modes

- `local_unsigned`: local debug app built from this checkout.
- `developer_signed_beta`: signed app suitable for controlled beta sharing.
- `notarized_beta`: signed, exported, and notarized app suitable for broader distribution.

## Readiness Check

Run:

```bash
.venv/bin/python scripts/check_macos_distribution_readiness.py
```

For a signed beta gate:

```bash
.venv/bin/python scripts/check_macos_distribution_readiness.py --require-mode developer_signed_beta
```

For notarization readiness:

```bash
.venv/bin/python scripts/check_macos_distribution_readiness.py --require-mode notarized_beta
```

## Current Blockers

- `CODE_SIGNING_ALLOWED` is `NO` for the app target.
- `ENABLE_HARDENED_RUNTIME` is `NO` for the app target.
- No `DEVELOPMENT_TEAM` is configured.
- No `ExportOptions.plist` exists for archive export.

Those are distribution blockers only. They are not blockers for ordinary local debug runs or automated validation.
