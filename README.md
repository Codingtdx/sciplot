# SciPlot God

SciPlot God is a native macOS scientific figure workflow tool.

The app has four primary workbenches:

1. Plot
2. Data Studio
3. Composer
4. Code Console

These four are the only app-level primary destinations.

## Supported Runtime

- Desktop frontend: `app/macos` (SwiftUI)
- Backend: `app/sidecar` (FastAPI)
- Rendering/core: `src/rendering`, `src/data_studio`, `src/composer.py`

The historical `app/desktop` and Tauri/mock chain has been removed.

## Canonical Workflows

- Plot: `Import -> Inspect -> Template -> Refine -> Preflight -> Export`
- Data Studio: `Import -> Group Review -> Compare Preview -> Export / Open in Plot`
- Composer: `Assets -> Layout -> Compose -> Inspect -> Export`
- Code Console: `Bind Context -> Inspect Inputs -> Prompt/Code -> Run -> Outputs -> Handoff`

Canonical internal steps can be richer than user-visible UI; only user decision surfaces should stay visible.

## Backend/API Boundaries

- `POST /inspect-file` is the single inspection/recommendation entry.
- Ranked recommendation fields are canonical:
  - `recommendations`
  - `primary_recommendation`
  - `alternative_recommendations`
  - `advanced_templates`
  - `recommendation_confidence`
  - `recommendation_summary`
- Legacy fields/endpoints have been removed:
  - `POST /recommend-render`
  - `inspection.recommendation`
  - `/preprocess-tensile-replicates`
  - `/inspect-tensile-workbook`
  - `/export-tensile-comparison`

## Single Sources Of Truth

- Plot contract: `src/plot_contract.json`
- Contract loader: `src/plot_contract.py`
- Sidecar schema/validation/migration:
  - `app/sidecar/schemas.py`
  - `app/sidecar/schemas_render.py`
  - `app/sidecar/schemas_data_studio.py`
  - `app/sidecar/schemas_code_console.py`

When behavior is a contract change, update contract first, regenerate docs, then update Python/sidecar/macOS consumers.

## Entrypoints

- CLI: `make_plot.py`
- Sidecar app: `app/sidecar/server.py`
- Native desktop launcher: `Launch_Plotter.command`

## Validation

- Clean:
  - `.venv/bin/python scripts/clean_repo.py`
- Ruff:
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`
- Mypy:
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`
- Pytest:
  - `.venv/bin/python -m pytest tests`
- Smoke:
  - `.venv/bin/python scripts/smoke_check.py`
- macOS build:
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`
- macOS test:
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`

## More

- Product architecture: `docs/product-architecture.md`
- Plot contract doc (generated): `docs/plot_contract.md`
- Contributor/agent rules: `AGENTS.md`
- Engineering handoff + runbook: `docs/engineering-handoff.md`

## Handoff / Onboarding

If you are taking over development, use this order:

1. Read `AGENTS.md` for boundaries, invariants, and forbidden legacy restores.
2. Read `docs/engineering-handoff.md` for latest change history, risk points, and troubleshooting.
3. Run the full validation matrix once in your machine:
   - clean
   - ruff
   - mypy
   - pytest
   - smoke_check
   - xcodebuild build/test
4. Confirm you can execute one complete end-to-end flow in each workbench:
   - Plot
   - Data Studio
   - Composer
   - Code Console
5. Before shipping any change, update both:
   - `AGENTS.md` / `README.md` (if responsibilities/boundaries/workflow changed)
   - `docs/engineering-handoff.md` (every round, required)
