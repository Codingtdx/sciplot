from __future__ import annotations

from fastapi import APIRouter

from app.sidecar import APP_VERSION
from app.sidecar.schemas import HealthResponse, MetaResponse, PlotContractResponse
from src.plot_contract import meta_payload, plot_contract_dict
from src.rendering.constants import PALETTE_PRESET_CHOICES, SIZE_CHOICES, TEMPLATE_CHOICES
from src.rendering.template_lifecycle import template_identity
from src.rendering.themes import visual_theme_catalog_payload


def create_meta_router() -> APIRouter:
    router = APIRouter()

    @router.get("/health", response_model=HealthResponse)
    def health() -> HealthResponse:
        return HealthResponse(status="ok", version=APP_VERSION)

    @router.get("/meta", response_model=MetaResponse)
    def meta() -> MetaResponse:
        payload = meta_payload()
        enriched_templates: list[dict[str, object]] = []
        for item in payload.get("templates", []):
            if not isinstance(item, dict):
                continue
            template_id = str(item.get("id", ""))
            if not template_id:
                continue
            identity = template_identity(template_id)
            enriched_templates.append(
                {
                    **item,
                    "canonical_id": identity.canonical_id,
                    "role": identity.role,
                    "lifecycle_policy": identity.lifecycle_policy,
                    "implementation_id": identity.implementation_id,
                }
            )
        payload["templates"] = enriched_templates
        payload.update(
            {
                "template_ids": list(TEMPLATE_CHOICES),
                "size_ids": list(SIZE_CHOICES),
                "palette_preset_ids": list(PALETTE_PRESET_CHOICES),
                "visual_themes": visual_theme_catalog_payload(),
            }
        )
        return MetaResponse.model_validate(payload)

    @router.get("/plot-contract", response_model=PlotContractResponse)
    def plot_contract() -> PlotContractResponse:
        return PlotContractResponse.model_validate(plot_contract_dict())

    return router
