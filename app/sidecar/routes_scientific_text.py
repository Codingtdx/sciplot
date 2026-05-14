from __future__ import annotations

from fastapi import APIRouter

from app.sidecar.render_support import http_bad_request
from app.sidecar.schemas import StatusResponse, serialize_dataclass
from app.sidecar.schemas_scientific_text import (
    ScientificTextRuleListResponse,
    ScientificTextRulePayload,
    ScientificTextRulePreviewResponse,
    ScientificTextRuleResponse,
)
from src.scientific_text_rules import (
    delete_scientific_text_rule,
    list_scientific_text_rules,
    preview_scientific_text_rule,
    save_scientific_text_rule,
)


def create_scientific_text_router() -> APIRouter:
    router = APIRouter()

    @router.get("/scientific-text/rules", response_model=ScientificTextRuleListResponse)
    def list_rules() -> ScientificTextRuleListResponse:
        try:
            return ScientificTextRuleListResponse.model_validate(
                {"rules": [serialize_dataclass(rule) for rule in list_scientific_text_rules()]}
            )
        except Exception as exc:  # pragma: no cover - normalized by shared error helper
            raise http_bad_request("scientific_text_rules", exc) from exc

    @router.post("/scientific-text/rules/preview", response_model=ScientificTextRulePreviewResponse)
    def preview_rule(request: ScientificTextRulePayload) -> ScientificTextRulePreviewResponse:
        try:
            preview = preview_scientific_text_rule(request.model_dump(exclude_none=True))
            return ScientificTextRulePreviewResponse.model_validate(serialize_dataclass(preview))
        except Exception as exc:
            raise http_bad_request("scientific_text_rule_preview", exc) from exc

    @router.post("/scientific-text/rules", response_model=ScientificTextRuleResponse)
    def create_rule(request: ScientificTextRulePayload) -> ScientificTextRuleResponse:
        try:
            rule = save_scientific_text_rule(request.model_dump(exclude_none=True))
            return ScientificTextRuleResponse.model_validate(serialize_dataclass(rule))
        except Exception as exc:
            raise http_bad_request("scientific_text_rule_save", exc) from exc

    @router.put("/scientific-text/rules/{rule_id:path}", response_model=ScientificTextRuleResponse)
    def update_rule(rule_id: str, request: ScientificTextRulePayload) -> ScientificTextRuleResponse:
        try:
            rule = save_scientific_text_rule(request.model_dump(exclude_none=True), replacing_id=rule_id)
            return ScientificTextRuleResponse.model_validate(serialize_dataclass(rule))
        except Exception as exc:
            raise http_bad_request("scientific_text_rule_update", exc) from exc

    @router.delete("/scientific-text/rules/{rule_id:path}", response_model=StatusResponse)
    def delete_rule(rule_id: str) -> StatusResponse:
        try:
            delete_scientific_text_rule(rule_id)
            return StatusResponse(status="ok")
        except Exception as exc:
            raise http_bad_request("scientific_text_rule_delete", exc) from exc

    return router


__all__ = ["create_scientific_text_router"]
