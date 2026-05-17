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
- Keep LabPlot-scale capability status flowing through `/meta`, sidecar schemas, `.sciplot` document graph nodes, macOS decode models, and `docs/labplot-roadmap-progress.md`; do not add a second local capability table in Swift.
- Keep project open/save routed through sidecar schema normalization.
- Keep `.sciplot` self-contained: embedded sources and workbooks are the restore truth, not original absolute paths.
- Keep macOS as the only supported desktop frontend.
- Keep `Launch_SciPlot.command` as the source-run launcher for the beta.
- Keep LabPlot-inspired work clean-room while SciPlot remains Apache-2.0. See `docs/labplot-informed-roadmap.md`; `scripts/check_labplot_cleanroom.py` rejects copied LabPlot GPL source headers.

## LabPlot-Scale Capability Landing

- `enabled` means there is current runtime support behind the sidecar/macOS contract.
- `experimental` means the schema/catalog/project landing exists and may have partial runtime support, but still needs numerical fixture coverage, UI wiring, or performance hardening.
- `coming_soon` means the capability has an explicit landing point and help text but must remain disabled in UI.
- `disabled` means the project intentionally records the capability as out of current runtime scope.
- The clean-room policy still applies to every landing: LabPlot can inspire taxonomy, object ownership, and tests, but GPL source is not vendored.

Runtime surfaces added for the LabPlot-scale batch:

- `GET /meta` capability catalogs are built by `src/rendering/capability_registry.py`.
- `POST /source-table-preview` and `POST /fit-analysis` use shared `DataContainerPayload` helpers from `src/rendering/data_containers.py`.
- `POST /analysis-operation` runs the experimental SciPlot-owned analysis envelope in `src/rendering/analysis_operations.py`.
- `POST /import-preview` dispatches explicit filter previews from `src/rendering/import_filters.py`.
- `POST /plot-edit-command/normalize` validates undoable plot edit commands in `src/rendering/plot_object_commands.py`.
- `POST /code-console/run` returns `notebook_outputs` and readonly notebook output containers for generated figure/table artifacts.

Maintenance rules:

- Promote a catalog item from `experimental` to `enabled` only after route tests, numerical fixtures where relevant, Swift decoding, and module-local UI/error behavior are covered.
- Keep unsupported formats as `coming_soon` or `disabled + help`; do not pretend HDF5/NetCDF/FITS/ReadStat/Origin imports work until dependencies and malformed-file fixtures exist.
- Keep Code Console notebook outputs inside the existing Code Console module. Do not add a fifth Notebook module.
- Keep plot edit command state tied to typed render/document payloads and native `UndoManager` replay. Do not store durable scientific state only in inspector view state.

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
