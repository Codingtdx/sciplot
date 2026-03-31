from __future__ import annotations

from dataclasses import asdict, is_dataclass
from pathlib import Path
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class QAIssueResponse(StrictModel):
    id: str
    severity: str
    metric_value: float | str | None = None
    target: float | str | None = None
    message: str


class QAReportResponse(StrictModel):
    score: float
    grade: Literal["excellent", "solid", "needs_cleanup"]
    issues: list[QAIssueResponse] = Field(default_factory=list)
    autofixes_applied: list[str] = Field(default_factory=list)


class SubmissionCheckResponse(StrictModel):
    id: str
    status: str
    message: str
    metric_value: float | str | None = None
    target: float | str | None = None
    source: str | None = None


class SubmissionReportResponse(StrictModel):
    context: str
    readiness: str
    summary: str
    template: str | None = None
    style_preset: str | None = None
    palette_preset: str | None = None
    output_count: int = 0
    output_filenames: list[str] = Field(default_factory=list)
    blockers: list[str] = Field(default_factory=list)
    checks: list[SubmissionCheckResponse] = Field(default_factory=list)


class PreviewItemResponse(StrictModel):
    filename: str
    pdf_base64: str
    qa: QAReportResponse | None = None


class HealthResponse(StrictModel):
    status: str
    version: str


class PathResponse(StrictModel):
    output_path: str


def serialize_dataclass(value: Any) -> Any:
    if is_dataclass(value) and not isinstance(value, type):
        return {key: serialize_dataclass(item) for key, item in asdict(value).items()}
    if isinstance(value, Path):
        return str(value)
    if isinstance(value, dict):
        return {key: serialize_dataclass(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [serialize_dataclass(item) for item in value]
    return value


__all__ = [
    "HealthResponse",
    "PathResponse",
    "PreviewItemResponse",
    "QAReportResponse",
    "QAIssueResponse",
    "StrictModel",
    "SubmissionCheckResponse",
    "SubmissionReportResponse",
    "serialize_dataclass",
]
