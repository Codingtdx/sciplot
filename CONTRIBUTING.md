# Contributing to SciPlot

Thanks for taking a look at SciPlot. This project is in `0.1.0-beta`, so the highest-value contributions are focused bug reports, reproducible data fixtures, validation improvements, and small patches that preserve the current architecture.

## Before You Start

Read these first:

- `README.md` for setup and validation commands.
- `AGENTS.md` for repo boundaries and source-of-truth rules.
- `docs/maintenance-governance.md` for review expectations.

## Development Setup

```bash
python3 -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/pip install -r requirements.txt
```

The native app expects the sidecar to run from `.venv/bin/python`.

## Pull Request Expectations

- Keep changes scoped to one behavior or workflow.
- Add or update tests for behavior changes.
- Do not introduce a second source of truth for plot templates, styles, palettes, themes, or project schema.
- Keep `.sciplot` as the only supported project file extension.
- Do not restore removed desktop routes, old compatibility endpoints, or legacy UI shells.
- Update `README.md`, `AGENTS.md`, or docs when public behavior changes.

## Validation

Run the relevant targeted tests while developing, then run the broader gate before opening a PR:

```bash
.venv/bin/python -m ruff check .
.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering
.venv/bin/python -m pytest tests
.venv/bin/python scripts/smoke_check.py
```

For macOS changes, also run:

```bash
xcodebuild \
  -project app/macos/SciPlot.xcodeproj \
  -scheme SciPlotMac \
  -destination 'platform=macOS' \
  -derivedDataPath app/macos/.derivedData \
  test
```

## Reporting Bugs

When filing a bug, include:

- macOS and Python versions
- the command or workflow you ran
- a small input file if the bug is data-dependent
- expected behavior and actual behavior
- traceback, logs, or screenshots when available

Please do not attach private research data unless you have permission to share it publicly.
