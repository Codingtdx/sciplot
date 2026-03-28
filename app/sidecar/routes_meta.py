from __future__ import annotations

from typing import Any

from fastapi import APIRouter

from app.sidecar.schemas import HealthResponse
from src.plot_contract import meta_payload, plot_contract_dict
from src.rendering.constants import PALETTE_PRESET_CHOICES, SIZE_CHOICES, TEMPLATE_CHOICES
from src.rendering.template_lifecycle import template_identity
from src.rendering.themes import visual_theme_catalog_payload


def create_meta_router() -> APIRouter:
    router = APIRouter()

    @router.get("/health", response_model=HealthResponse)
    def health() -> HealthResponse:
        return HealthResponse(status="ok", version="5.0.0")

    @router.get("/meta", response_model=dict[str, Any])
    def meta() -> dict[str, Any]:
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
        return payload

    @router.get("/plot-contract", response_model=dict[str, Any])
    def plot_contract() -> dict[str, Any]:
        return plot_contract_dict()

    return router
