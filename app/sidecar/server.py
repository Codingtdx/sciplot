from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.routing import APIRoute

from app.sidecar.routes_code_console import create_code_console_router
from app.sidecar.routes_composer import create_composer_router
from app.sidecar.routes_data_studio import create_data_studio_router
from app.sidecar.routes_meta import create_meta_router
from app.sidecar.routes_render import create_render_router

CRITICAL_SIDECAR_ROUTES: tuple[tuple[str, str], ...] = (
    ("GET", "/health"),
    ("GET", "/meta"),
    ("GET", "/plot-contract"),
    ("POST", "/inspect-file"),
    ("POST", "/source-table-preview"),
    ("POST", "/fit-analysis"),
    ("POST", "/save-project"),
    ("POST", "/open-project"),
    ("POST", "/code-console/context"),
    ("POST", "/code-console/run"),
    ("POST", "/compose-preview"),
    ("GET", "/data-studio/templates"),
    ("POST", "/data-studio/source-preview"),
    ("POST", "/data-studio/build-workbook"),
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
        title="SciPlot God Sidecar",
        version="5.0.0",
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
    application.include_router(create_render_router())
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
