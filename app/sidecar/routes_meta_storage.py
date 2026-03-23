from __future__ import annotations

from collections.abc import Callable
from pathlib import Path

from fastapi import APIRouter

from app.sidecar.schemas import (
    DataTemplateCatalogResponse,
    HealthResponse,
    ManagedStorageCleanupRequest,
    ManagedStorageCleanupResponse,
    ManagedStorageStatusResponse,
    MaterializeDataTemplateFolderRequest,
    MaterializeDataTemplateFolderResponse,
    MaterializeDataTemplateRequest,
    MaterializeDataTemplateResponse,
    MetaResponse,
    OpenPathRequest,
    PathResponse,
    PlotContractResponse,
)
from app.sidecar.server_utils import http_bad_request, open_path_with_host
from src import plot_style
from src.plot_contract import meta_payload, plot_contract_dict
from src.rendering import (
    PALETTE_PRESET_CHOICES,
    SIZE_CHOICES,
    TEMPLATE_CHOICES,
    cleanup_managed_storage,
    managed_storage_snapshot,
    materialize_data_template,
    materialize_data_template_folder,
    plot_template_folder_catalog,
)


def create_meta_storage_router(
    *, dep_provider: Callable[[], object] | None = None
) -> APIRouter:
    router = APIRouter()

    def _dep(name: str, default: object) -> object:
        if dep_provider is None:
            return default
        return getattr(dep_provider(), name, default)

    @router.get("/health", response_model=HealthResponse)
    def health() -> HealthResponse:
        return HealthResponse(status="ok", version="5.0.0")

    @router.get("/meta", response_model=MetaResponse)
    def meta() -> MetaResponse:
        payload = meta_payload()
        payload.update(
            {
                "template_ids": list(TEMPLATE_CHOICES),
                "size_ids": list(SIZE_CHOICES),
                "palette_preset_ids": list(PALETTE_PRESET_CHOICES),
                "default_style": plot_style.DEFAULT_STYLE_PRESET,
                "default_palette": plot_style.DEFAULT_PALETTE_PRESET,
            }
        )
        return MetaResponse.model_validate(payload)

    @router.get("/plot-contract", response_model=PlotContractResponse)
    def plot_contract() -> PlotContractResponse:
        return PlotContractResponse.model_validate(plot_contract_dict())

    @router.get("/data-templates", response_model=DataTemplateCatalogResponse)
    def list_data_templates() -> DataTemplateCatalogResponse:
        return DataTemplateCatalogResponse.model_validate(
            {"templates": plot_template_folder_catalog()}
        )

    @router.post(
        "/data-templates/materialize",
        response_model=MaterializeDataTemplateResponse,
    )
    def create_data_template(
        request: MaterializeDataTemplateRequest,
    ) -> MaterializeDataTemplateResponse:
        try:
            payload = materialize_data_template(
                request.template_id,
                variant=request.variant,
            )
            return MaterializeDataTemplateResponse.model_validate(payload)
        except Exception as exc:
            raise http_bad_request("data_template", exc) from exc

    @router.post(
        "/data-templates/folder",
        response_model=MaterializeDataTemplateFolderResponse,
    )
    def create_data_template_folder(
        request: MaterializeDataTemplateFolderRequest,
    ) -> MaterializeDataTemplateFolderResponse:
        try:
            materialize_folder = _dep(
                "materialize_data_template_folder",
                materialize_data_template_folder,
            )
            payload = materialize_folder(variant=request.variant)
            return MaterializeDataTemplateFolderResponse.model_validate(payload)
        except Exception as exc:
            raise http_bad_request("data_template", exc) from exc

    @router.get("/managed-storage", response_model=ManagedStorageStatusResponse)
    def managed_storage_status() -> ManagedStorageStatusResponse:
        try:
            snapshot_fn = _dep("managed_storage_snapshot", managed_storage_snapshot)
            payload = snapshot_fn()
            return ManagedStorageStatusResponse.model_validate(payload)
        except Exception as exc:
            raise http_bad_request("managed_storage", exc) from exc

    @router.post(
        "/managed-storage/cleanup",
        response_model=ManagedStorageCleanupResponse,
    )
    def cleanup_managed_storage_endpoint(
        request: ManagedStorageCleanupRequest,
    ) -> ManagedStorageCleanupResponse:
        try:
            cleanup_fn = _dep("cleanup_managed_storage", cleanup_managed_storage)
            payload = cleanup_fn(strategy=request.strategy)
            return ManagedStorageCleanupResponse.model_validate(payload)
        except Exception as exc:
            raise http_bad_request("managed_storage", exc) from exc

    @router.post("/open-path", response_model=PathResponse)
    def open_path(request: OpenPathRequest) -> PathResponse:
        try:
            target = Path(request.output_path).expanduser()
            if not target.exists():
                raise FileNotFoundError(str(target))
            launcher = _dep("_open_path_with_host", open_path_with_host)
            launcher(target)
            return PathResponse(output_path=str(target))
        except Exception as exc:
            raise http_bad_request("open_path", exc) from exc

    return router
