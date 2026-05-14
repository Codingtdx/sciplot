from __future__ import annotations

from pydantic import Field

from app.sidecar.schemas_common import StrictModel


class ScientificTextRulePayload(StrictModel):
    id: str | None = None
    kind: str
    input: str
    output: str
    enabled: bool = True
    canonical_input: str | None = None


class ScientificTextRuleResponse(StrictModel):
    id: str
    kind: str
    input: str
    output: str
    enabled: bool
    canonical_input: str


class ScientificTextRuleListResponse(StrictModel):
    rules: list[ScientificTextRuleResponse] = Field(default_factory=list)


class ScientificTextRulePreviewResponse(StrictModel):
    rule: ScientificTextRuleResponse
    automatic_output: str
    effective_output: str
    errors: list[str] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)


__all__ = [
    "ScientificTextRuleListResponse",
    "ScientificTextRulePayload",
    "ScientificTextRulePreviewResponse",
    "ScientificTextRuleResponse",
]
