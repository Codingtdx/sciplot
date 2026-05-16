# Engineering Handoff

This public handoff replaces the private beta work log. It keeps only the current state needed by maintainers and contributors.

## Current Release Target

- Product name: SciPlot
- Release channel: `0.1.0-beta`
- Distribution model: source preview only; no signed or notarized macOS app bundle is published.
- Project extension: `.sciplot` only.

## Supported Architecture

- `app/macos`: native SwiftUI desktop frontend.
- `app/sidecar`: FastAPI sidecar and route surface.
- `src/rendering`: plot inspection, recommendation, preflight, rendering, cache, options, and IO.
- `src/data_studio`: Data Studio intake, template, workbook, and comparison services.
- `src/composer.py` and related composer modules: composition service surface.
- `src/code_console_service.py` and `src/code_console_runtime.py`: Code Console context and run service.

## Maintainer Notes

- Keep `src/plot_contract.json` as the single source of truth for public plot templates, styles, palettes, themes, defaults, and gallery metadata.
- Keep project open/save routed through sidecar schema normalization.
- Keep `.sciplot` self-contained: embedded sources and workbooks are the restore truth, not original absolute paths.
- Keep macOS as the only supported desktop frontend.
- Keep `Launch_SciPlot.command` as the source-run launcher for the beta.
- Keep LabPlot-inspired work clean-room while SciPlot remains Apache-2.0. See `docs/labplot-informed-roadmap.md`; `scripts/check_labplot_cleanroom.py` rejects copied LabPlot GPL source headers.

## Validation

Recommended local gate:

```bash
.venv/bin/python scripts/blocking_gate.py
```

Useful component checks:

```bash
.venv/bin/python scripts/check_labplot_cleanroom.py
.venv/bin/python -m ruff check .
.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering
.venv/bin/python -m pytest tests
.venv/bin/python scripts/smoke_check.py
xcodebuild -project app/macos/SciPlot.xcodeproj -scheme SciPlotMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test
```

## Known Beta Limits

- No packaged app is published.
- App signing, hardened runtime, and notarization are not configured for external distribution.
- Project schema and some route payloads may still change before a stable release.
- Manual desktop smoke evidence is still required before calling a build ready for broader testers.
