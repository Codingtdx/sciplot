from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.routing import APIRoute

from app.sidecar import APP_VERSION
from app.sidecar.routes_code_console import create_code_console_router
from app.sidecar.routes_composer import create_composer_router
from app.sidecar.routes_data_studio import create_data_studio_router
from app.sidecar.routes_labplot_runtime import create_labplot_runtime_router
from app.sidecar.routes_meta import create_meta_router
from app.sidecar.routes_plot_themes import create_plot_themes_router
from app.sidecar.routes_render import create_render_router
from app.sidecar.routes_scientific_text import create_scientific_text_router

CRITICAL_SIDECAR_ROUTES: tuple[tuple[str, str], ...] = (
    ("GET", "/health"),
    ("GET", "/meta"),
    ("GET", "/plot-contract"),
    ("GET", "/plot-themes"),
    ("POST", "/plot-themes/preview"),
    ("POST", "/plot-themes"),
    ("PUT", "/plot-themes/{theme_id:path}"),
    ("DELETE", "/plot-themes/{theme_id:path}"),
    ("GET", "/scientific-text/rules"),
    ("POST", "/scientific-text/rules/preview"),
    ("POST", "/scientific-text/rules"),
    ("PUT", "/scientific-text/rules/{rule_id:path}"),
    ("DELETE", "/scientific-text/rules/{rule_id:path}"),
    ("POST", "/inspect-file"),
    ("POST", "/source-table-preview"),
    ("POST", "/fit-analysis"),
    ("POST", "/analysis-operation"),
    ("POST", "/import-preview"),
    ("POST", "/plot-edit-command/normalize"),
    ("POST", "/save-project"),
    ("POST", "/open-project"),
    ("POST", "/preflight-render"),
    ("POST", "/render-preview"),
    ("POST", "/export-render"),
    ("POST", "/code-console/context"),
    ("POST", "/code-console/run"),
    ("POST", "/compose-preview"),
    ("POST", "/compose-export"),
    ("GET", "/data-studio/templates"),
    ("POST", "/data-studio/template-preview"),
    ("POST", "/data-studio/template-recommendations"),
    ("POST", "/data-studio/build-workbook"),
    ("POST", "/data-studio/import-workbook"),
    ("POST", "/data-studio/workbook-preview"),
    ("POST", "/data-studio/comparison-context"),
    ("POST", "/data-studio/comparison-preview"),
    ("POST", "/data-studio/comparison-export"),
    ("POST", "/data-studio/session/normalize"),
)


def _registered_route_signatures(application: FastAPI) -> list[tuple[str, str]]:
    signatures: set[tuple[str, str]] = set()
    for route in application.routes:
        if not isinstance(route, APIRoute):
            continue
        for method in route.methods or ():
            signatures.add((method, route.path))
    return sorted(signatures, key=lambda item: (item[1], item[0]))


def _assert_critical_sidecar_routes(application: FastAPI) -> list[tuple[str, str]]:
    registered = set(_registered_route_signatures(application))
    missing = [signature for signature in CRITICAL_SIDECAR_ROUTES if signature not in registered]
    if missing:
        missing_text = ", ".join(f"{method} {path}" for method, path in missing)
        raise RuntimeError(f"Critical sidecar routes are missing: {missing_text}")
    return sorted(registered & set(CRITICAL_SIDECAR_ROUTES), key=lambda item: (item[1], item[0]))


@asynccontextmanager
async def sidecar_lifespan(application: FastAPI):
    matched = _assert_critical_sidecar_routes(application)
    registered_text = ", ".join(
        f"{method} {path}" for method, path in _registered_route_signatures(application)
    )
    critical_text = ", ".join(f"{method} {path}" for method, path in matched)
    print(f"[sidecar] registered routes: {registered_text}", flush=True)
    print(f"[sidecar] critical routes ready: {critical_text}", flush=True)
    yield


def create_app() -> FastAPI:
    application = FastAPI(
        title="SciPlot Sidecar",
        version=APP_VERSION,
        lifespan=sidecar_lifespan,
    )
    application.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    application.include_router(create_meta_router())
    application.include_router(create_plot_themes_router())
    application.include_router(create_scientific_text_router())
    application.include_router(create_render_router())
    application.include_router(create_labplot_runtime_router())
    application.include_router(create_code_console_router())
    application.include_router(create_data_studio_router())
    application.include_router(create_composer_router())
    return application


app = create_app()


def main() -> None:
    import uvicorn

    uvicorn.run("app.sidecar.server:app", host="127.0.0.1", port=8765, reload=False)


if __name__ == "__main__":
    main()
