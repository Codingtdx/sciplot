# Data-to-Template v1 Handoff
**Status:** v1 flow is functionally complete and considered shippable after stabilization.

Historical note (2026-03-28):

- This document describes the Plot-side data-to-template refactor, not the canonical whole-app information architecture.
- For current app-level product scope, workflows, and IA rules, use `README.md` and `docs/product-architecture.md`.
- Older desktop-shell references in this handoff should be read as implementation history, not as the current app-shell truth.

## 1. Title + status
- This document is the handoff for the **v1 data-to-template flow** refactor.
- The v1 flow is **shippable / functionally complete** for current scope.

## 2. What this work changed
The product flow is now centered on:
- **data -> detect -> recommend (3-5) -> choose -> tweak -> export**

Major additions completed in this refactor:
- `NormalizedDataset` as shared normalized input metadata for inspect/recommend/preflight/render paths.
- `TemplateCatalog` as contract-backed template listing/spec source.
- `TemplateRecommender` with ranked, deterministic, explainable template recommendations.
- `StyleComposer` for publication profile + visual theme composition.
- Explicit layering of **publication profile (hard)** vs **visual theme (soft)**.
- Six added structural templates:
  - `scatter_with_fit`
  - `annotated_heatmap`
  - `replicate_curves_with_band`
  - `grouped_bar_compare`
  - `distribution_compare`
  - `histogram_density`
- Compatibility preservation of the legacy single recommendation field:
  - `inspection.recommendation` remains present and stable.
  - Ranked recommendations are additive via `inspection.recommendations`.

## 3. Final architecture overview
### Layer model
- **Structural template layer:** chart family/template choice and renderer entry points.
- **Publication profile layer (hard constraints):** contract/publication profile authority for protected styling and publication defaults.
- **Visual theme layer (soft overrides):** optional project-level/per-figure visual polishing that must not override protected publication keys.

### Core processing flow
- **Inspect / normalize**
  - detect model + build normalized metadata + produce compatibility recommendation(s).
- **Recommend**
  - run rules + soft priors, produce deterministic ranked list (3-5 default in product flow).
- **Preflight**
  - validate template/data fit, emit blockers and warnings, predict output filenames.
- **Render**
  - execute chosen template renderer with resolved options/style composition.
- **Export**
  - export PDFs + bundle artifacts (inspection/preflight/options/report/manifest).

## 4. Files / modules that matter most
Core rendering seams:
- `src/rendering/dataset_models.py`
  - input model detection, `NormalizedDataset`, quality flags, role/shape metadata.
- `src/rendering/recommender.py`
  - rules + soft priors + deterministic ranking.
- `src/rendering/recommendation.py`
  - inspect orchestration and legacy compatibility recommendation.
- `src/rendering/preflight.py`
  - template-specific validation and warning/blocker behavior.
- `src/rendering/render.py`
  - renderer dispatch and template render entry points.
- `src/rendering/common.py`
  - shared validation helpers, output naming, replicate/curve utility seams.
- `src/rendering/template_catalog.py`
  - contract-backed template specs surfaced to higher layers.
- `src/rendering/style_composer.py`
  - publication profile + visual theme composition with protected keys.
- `src/rendering/themes.py`
  - publication profile hard constraints, protected key derivation, visual theme soft catalog.

Contract + option boundaries:
- `src/plot_contract.json`
  - source-of-truth templates/options/profiles/rules.
- `src/rendering/options.py`
  - template option validation and defaults resolution.

Sidecar API/schema boundaries:
- `app/sidecar/schemas.py`
  - request/response shapes for inspect/preflight/render/export.
- `app/sidecar/routes_render.py`
  - inspect/preflight/preview/export endpoint orchestration.
- `app/sidecar/routes_meta_storage.py`
  - meta/contract payload wiring to desktop.
- `app/sidecar/server_utils.py`
  - option payload normalization and route utilities.

Desktop continuity seams:
- `app/macos/Sources/App/**`
  - native macOS app shell, commands, and runtime ownership for the supported desktop frontend.
- `app/macos/Sources/Features/Plot/**`
  - Plot workbench flow that consumes the inspect/recommend/preflight/render/export sidecar chain.
- `app/desktop/src/mock/**`
  - protected Plot-only mock reference; useful for local Plot-flow continuity, but not for whole-app IA decisions.
- `README.md`
  - maintainer-facing summary of the retained workbench model.
- `docs/product-architecture.md`
  - canonical app-level IA and workflow normalization reference.

## 5. Locked design decisions
- **Publication profile is the hard authority.**
- **Visual theme is soft-only.**
- **Protected publication keys come from contract/publication-profile truth source** (not hardcoded side lists).
- Recommender is **Rules + Soft Priors**.
- Ranking is **deterministic and explainable**.
- **No adaptive/learned ranking in v1**.
- `distribution_compare` is **one structural family in v1** with deterministic internal variant selection, not a family-selector UI.
- Endpoint names and compatibility fields were intentionally preserved.
- This work is **Plotly-inspired in product flow/template breadth**, not donor-code porting.

## 6. Structural templates now available
Newly added (and integrated through recommendation/preflight/render/export):
- `scatter_with_fit`
- `annotated_heatmap`
- `replicate_curves_with_band`
- `grouped_bar_compare`
- `distribution_compare`
- `histogram_density`

These are wired end-to-end in inspect/recommend/preflight/render/export paths.

## 7. Compatibility guarantees
Intentionally preserved:
- Legacy single recommendation field (`inspection.recommendation`) remains compatibility default.
- Endpoint semantics remain stable (inspect/preflight/preview/export shape and behavior model).
- Publication defaults remain controlled by contract/publication profiles unless explicitly changed.
- Visual themes cannot override protected publication settings.

## 8. Known limitations / non-goals
- `histogram_density` remains heuristic (deterministic, but still heuristic).
- Recommendation quality is rule-driven and may not match every niche domain preference.
- Some preflight guidance is warning-level rather than blocking by design.
- No broader UI redesign in this release.
- No assumption that the protected Plot mock defines the whole app shell.
- No endpoint expansion in this release.
- No Plotly donor-code transplantation.

## 9. What future contributors should do
- Tune recommendation rules/priors using real representative datasets.
- Extend regression coverage for edge cases (sparse/discrete/ambiguous structures).
- Continue minor wording and UX polish where it improves current flow clarity.
- Keep Plot subsystem improvements aligned with the retained four-workbench app model rather than restoring old app-shell assumptions.
- Validate behavior with real-world data before expanding breadth.

## 10. What future contributors should NOT do
- Do not merge visual theme behavior back into publication profile defaults.
- Do not hardcode protected keys outside contract/publication-profile truth source.
- Do not add template families without full recommendation/preflight/render/export integration.
- Do not introduce adaptive/learned ranking casually.
- Do not broaden wizard/UI without explicit product justification.
- Do not treat old wizard/workbench shell files as the current product IA truth.
- Do not expand scope just because Plotly has additional chart types.

## 11. Validation / release readiness
This v1 flow passed the stabilization gate:
- lint (`ruff`)
- tests (`pytest`, including rendering/sidecar coverage)
- smoke check (`scripts/smoke_check.py`)
- desktop tests/build (`xcodebuild test`, `xcodebuild build`)

Current assessment: **v1 data-to-template flow is release-ready within defined scope.**
