from __future__ import annotations

import sys
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.routing import APIRoute

from app.sidecar.routes_code_console import create_code_console_router
from app.sidecar.routes_composer import create_composer_router
from app.sidecar.routes_meta_storage import create_meta_storage_router
from app.sidecar.routes_projects import create_projects_router
from app.sidecar.routes_render import create_render_router
from app.sidecar.routes_tensile import create_tensile_router
from app.sidecar.server_utils import open_path_with_host as _open_path_with_host
from src.rendering import (
    cleanup_managed_storage,
    managed_storage_snapshot,
    materialize_data_template_folder,
    prepare_managed_plot_export_dir,
)

CRITICAL_SIDECAR_ROUTES: tuple[tuple[str, str], ...] = (
    ("GET", "/meta"),
    ("GET", "/plot-contract"),
    ("POST", "/data-templates/folder"),
)

# Keep these names on `app.sidecar.server` for compatibility with existing tests
# and local monkeypatch-based diagnostics.
_COMPAT_EXPORTS = (
    _open_path_with_host,
    cleanup_managed_storage,
    managed_storage_snapshot,
    materialize_data_template_folder,
    prepare_managed_plot_export_dir,
)


def _registered_route_signatures() -> list[tuple[str, str]]:
    signatures: set[tuple[str, str]] = set()
    for route in app.routes:
        if not isinstance(route, APIRoute):
            continue
        for method in route.methods or ():
            signatures.add((method, route.path))
    return sorted(signatures, key=lambda item: (item[1], item[0]))


def _assert_critical_sidecar_routes() -> list[tuple[str, str]]:
    registered = set(_registered_route_signatures())
    missing = [signature for signature in CRITICAL_SIDECAR_ROUTES if signature not in registered]
    if missing:
        missing_text = ", ".join(f"{method} {path}" for method, path in missing)
        raise RuntimeError(f"Critical sidecar routes are missing: {missing_text}")
    return sorted(
        registered & set(CRITICAL_SIDECAR_ROUTES),
        key=lambda item: (item[1], item[0]),
    )


@asynccontextmanager
async def sidecar_lifespan(_: FastAPI):
    matched = _assert_critical_sidecar_routes()
    registered_text = ", ".join(
        f"{method} {path}" for method, path in _registered_route_signatures()
    )
    critical_text = ", ".join(f"{method} {path}" for method, path in matched)
    print(f"[sidecar] registered routes: {registered_text}", flush=True)
    print(f"[sidecar] critical routes ready: {critical_text}", flush=True)
    yield


def _server_module() -> object:
    return sys.modules[__name__]


app = FastAPI(title="SciPlot God Sidecar", version="5.0.0", lifespan=sidecar_lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(create_meta_storage_router(dep_provider=_server_module))
app.include_router(create_code_console_router())
app.include_router(create_render_router(dep_provider=_server_module))
app.include_router(create_tensile_router())
app.include_router(create_composer_router())
app.include_router(create_projects_router())


def main() -> None:
    import uvicorn

    uvicorn.run("app.sidecar.server:app", host="127.0.0.1", port=8765, reload=False)


if __name__ == "__main__":
    main()
