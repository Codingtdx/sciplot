## Legacy Desktop Reference

This directory is no longer the supported desktop runtime for SciPlot God.

- The supported desktop frontend is the native macOS app in `app/macos`.
- `app/desktop/src/mock/**` remains protected as a visual/reference artifact for future mock-design passes.
- The remaining Tauri, Vite, and React files here are kept only for migration history, protected mock support, and selective legacy-reference work.

Use this directory only when you explicitly need to:

- inspect or preserve the protected mock flow
- reference historical Tauri-side sidecar bootstrapping behavior
- compare old shell assumptions during migration follow-up work

Do not treat `app/desktop` as the active product shell, the supported launcher path, or the source of truth for current app-level IA.
