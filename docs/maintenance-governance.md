# SciPlot Maintenance Governance

This document is the maintainer-facing governance guide for SciPlot.

It is intended for two audiences:

- engineers or AI collaborators taking over ongoing work
- maintainers making daily decisions about scope, review, validation, rollback, and documentation

It does not replace runtime truth sources. It defines how this repo should be maintained without creating a second product spec.

## 1. Purpose And Precedence

Use the following precedence order when documents appear to overlap:

| Source | Role | What it must not become |
| --- | --- | --- |
| code, schemas, and `src/plot_contract.json` | runtime truth for behavior, payloads, and contract-backed semantics | a hidden policy layer that only exists in implementation |
| `AGENTS.md` | hard engineering boundary rules, forbidden restores, workflow invariants, validation matrix | a round-by-round history log |
| `docs/maintenance-governance.md` | maintenance method, change classification, review gates, release and rollback expectations | a duplicate business-rules catalog |
| `README.md` | project entrypoint, supported runtime, onboarding path | the only place where hard rules live |
| `docs/product-architecture.md` | app/workbench model and product structure | a runtime contract file |
| `docs/engineering-handoff.md` | persistent round ledger, decision records, troubleshooting, regression evidence | a place to restate every standing rule each round |

Rules for precedence:

- If behavior changes, update the runtime truth source first.
- If repo boundaries, ownership, workflow invariants, or forbidden legacy restores change, update `AGENTS.md` in the same round.
- If the maintenance method changes, update this document in the same round.
- If onboarding, discoverability, or supported runtime summary changes, update `README.md` in the same round.
- If the change affects architecture, runtime strategy, or long-lived operating assumptions, record it in `docs/engineering-handoff.md` as a decision.

## 2. Supported Boundary And Ownership Map

Maintain one clear owner layer per subsystem. Do not solve ambiguity by adding adapter layers or duplicate helpers.

| Area | Primary truth source | Ownership boundary |
| --- | --- | --- |
| Plot product flow | `app/macos/Sources/Features/Plot`, `src/rendering`, `src/plot_contract.json` | Plot UI consumes ranked recommendations and contract-backed render semantics; it must not invent a second template catalog or scoring model |
| Data Studio product flow | `app/macos/Sources/Features/DataStudio`, `src/data_studio`, sidecar data-studio schemas/routes | workbook build, preview, specimen filtering, compare, and export stay inside Data Studio until explicit handoff to Plot |
| Composer product flow | `app/macos/Sources/Features/Composer`, `src/composer.py`, composer sidecar routes/schemas | Composer v2 schema and canvas/export invariants are owned here; do not reintroduce deleted facade modules |
| Code Console product flow | `app/macos/Sources/Features/CodeConsole`, `src/code_console_service.py`, `src/code_console_runtime.py` | controlled runner, context binding, outputs, and handoff behavior stay repo-native and typed |
| Sidecar API boundary | `app/sidecar/server.py`, `app/sidecar/routes_*.py`, `app/sidecar/schemas_*.py` | sidecar is the only supported app/backend surface; endpoints return explicit response models |
| Rendering semantics | `src/rendering`, `src/plot_contract.json`, `src/plot_contract.py` | recommendation, preflight, render, export, and option validation share one contract-backed source of truth |
| Persistence and managed artifacts | `src/infrastructure/persistence`, sidecar save/open schemas | retention, output layout, and project serialization rules are centralized here |
| Project schema and migration | sidecar save/open routes and schemas | project files must pass schema validation and migration; never bypass this with direct JSON IO |
| Documentation set | `README.md`, `AGENTS.md`, `docs/product-architecture.md`, `docs/engineering-handoff.md`, this file | docs are layered by role; do not spread the same rule text across five files |

Non-negotiable boundary rules:

- Supported desktop runtime is `app/macos` only.
- Supported backend runtime is `app/sidecar` only.
- `app/desktop/**`, `src/entry/**`, and other deleted compatibility chains must not return.
- GUI layers consume business semantics; they do not recompute template/public-surface meaning locally.

## 3. Change Taxonomy

Classify every round before editing code. If a round spans multiple classes, satisfy the strictest row that applies.

| Change class | Primary source to edit first | Required follow-through | Required validation |
| --- | --- | --- | --- |
| Contract / plot semantics | `src/plot_contract.json` | regenerate plot-contract docs, then update Python, sidecar, and macOS consumers | full standard matrix |
| Sidecar route / schema | `app/sidecar/routes_*.py`, `app/sidecar/schemas_*.py` | keep explicit response models, update affected callers, update docs if public behavior shifts | full standard matrix |
| macOS workflow / UX / runtime behavior | `app/macos/**` | keep workbench-local workflow, disabled-plus-help semantics, shared async orchestration rules | full standard matrix |
| Persistence / project format | sidecar save/open schemas and migration paths | preserve migration compatibility, define rollback point, document file-format risk clearly | full standard matrix |
| Refactor / performance / cleanup | owning subsystem files | remove dead code in the same round, record decision if runtime strategy changes | at minimum targeted checks; full matrix when shared/runtime surfaces are touched |
| Docs-only governance / onboarding / handoff | relevant docs | keep docs layered by role, avoid second truth source, update handoff ledger | document consistency review plus full matrix when repo rules require it |

Default classification rules:

- If templates, defaults, allowed sizes, presentation metadata, or public ids change, treat the round as contract/plot semantics.
- If a view change also changes action gating, saved-state meaning, async orchestration, or export flow, treat it as workflow/runtime work, not cosmetic-only work.
- If the change exists only to preserve compatibility for a deleted legacy surface, stop and re-check whether the change violates `AGENTS.md`.

## 4. Standard Maintenance Workflow

Use this sequence for every round:

1. Classify the change and identify the primary truth source.
2. Read the relevant standing rules in `AGENTS.md` before editing.
3. Implement the change at the truth source first, then update dependent layers outward.
4. In the same round, remove dead helpers, duplicate branches, stale aliases, or duplicate UI derivations created or revealed by the change.
5. Run the required validation matrix for the touched surface. Do not skip smoke/build/test because the change feels small.
6. Update docs in the same round:
   - `README.md` when discoverability, responsibilities, or supported flow summaries change
   - `AGENTS.md` when boundaries, invariants, or the validation matrix change
   - `docs/engineering-handoff.md` every round
   - generated docs when contract semantics change
7. Write explicit risk and rollback points before considering the round complete.

Maintenance defaults:

- Prefer a single typed state or presentation model over parallel booleans and view-local derivation.
- Prefer deleting obsolete code now instead of recording "cleanup later."
- Prefer changing one layer completely over partially patching multiple layers with compatibility glue.

## 5. Review Gates

Every review should check these gates before approval:

### Truth-source gates

- Is the changed behavior defined in exactly one place?
- Did the edit touch the correct primary truth source first?
- Does macOS consume backend/session truth instead of re-guessing template, scoring, or workflow semantics?

### Boundary gates

- Does the change preserve the supported runtime boundary: `app/macos + app/sidecar + src/*`?
- Does it avoid reviving deleted legacy routes, shells, facades, or compatibility chains?
- Are public template/style surfaces still explicit and contract-backed?

### Workflow and UX gates

- Are critical actions `disabled + help` instead of silent no-op?
- Does the change keep local workflow inside the current workbench rather than promoting steps into app-level navigation?
- Does the change preserve canonical handoff boundaries between Plot, Data Studio, Composer, and Code Console?

### Maintenance-quality gates

- Were dead code, duplicate helpers, and obsolete branches removed in the same round?
- Were new helper types introduced because they reduce real duplication and clarify ownership?
- Did the change avoid adding a second constant set, second scoring path, second formatter, or second implicit state machine?

## 6. Release, Rollback, And Incident Rules

Every round recorded in `docs/engineering-handoff.md` must include:

- absolute date
- scope
- user-visible impact, or explicit `None` / `No user-visible change`
- risks
- rollback points
- validation commands and pass/fail result

Add or extend a decision record when the round changes:

- runtime lifecycle or ownership strategy
- async orchestration semantics
- default workflow or interaction model
- caching or persistence strategy
- contract/public-surface semantics
- any rule that future maintainers could otherwise "rediscover" by accident

Add or extend troubleshooting guidance when:

- investigation time exceeds 15 minutes
- the failure mode is likely to recur
- the issue involves toolchain, xcodebuild, sidecar boot, cache invalidation, schema migration, or compatibility normalization

Rollback expectations:

- Rollback points must be file-level and concrete.
- If rollback depends on preserving a new migration or alias layer, say so explicitly.
- If the round is docs-only, rollback still needs a document-level boundary: usually the new doc, README pointer, and handoff entry.

## 7. Documentation Duties

Use documents by role rather than by convenience:

| Document | Update when | Do not put here |
| --- | --- | --- |
| `README.md` | supported runtime summary, discoverability links, onboarding order, high-level workflows | deep round history or line-by-line maintenance rules |
| `AGENTS.md` | hard boundaries, forbidden restores, invariants, validation matrix, required engineering behavior | round-specific regression evidence |
| `docs/maintenance-governance.md` | maintenance taxonomy, review gates, rollback duties, documentation policy | duplicated product semantics or copied rule catalogs |
| `docs/engineering-handoff.md` | every round, decision records, troubleshooting, executed validation evidence | permanent duplicate copies of all standing rules |
| `docs/plot_contract.md` | generated contract documentation after contract changes | manual edits that drift from the generator |

Documentation anti-drift rules:

- Link to the truth source instead of copying long rule blocks.
- If two docs say the same thing, one of them should usually become a pointer.
- If a rule affects runtime behavior, make sure the code or schema expresses it somewhere authoritative.
- If a doc references deleted routes, deleted directories, or removed product semantics, fix it in the same round.

Required generator step for contract changes:

- update `src/plot_contract.json`
- run `.venv/bin/python scripts/generate_plot_contract_docs.py`
- then update downstream consumers and affected docs

## 8. 30-Minute Takeover Standard

A new maintainer should be able to do the following within 30 minutes, without oral background:

1. identify the only supported runtime and active product model
2. locate the primary truth source for Plot, Data Studio, Composer, Code Console, and plot contract semantics
3. run the standard validation matrix successfully
4. find the latest two rounds of risk and rollback notes
5. understand what must be updated when changing contract semantics, workflow/runtime semantics, or docs/governance

Recommended takeover path:

1. read `AGENTS.md`
2. read this document
3. read `docs/engineering-handoff.md`
4. read `README.md` and `docs/product-architecture.md` as needed for product framing
5. run the validation matrix
6. walk one end-to-end flow in each workbench

If a maintainer cannot complete that handoff quickly, the documentation set is incomplete and the current round should not be considered fully handed off.
