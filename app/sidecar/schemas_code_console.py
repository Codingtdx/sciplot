from __future__ import annotations

from typing import Literal

from pydantic import Field

from app.sidecar.schemas_common import StrictModel
from app.sidecar.schemas_render import (
    DataContainerPayload,
    InputInspectionResponse,
    NotebookArtifactPayload,
    NotebookOutputPayload,
    PlotDatasetPreviewResponse,
    RenderOptionsPayload,
)


class CodeConsoleContextRequest(StrictModel):
    input_path: str
    sheet: str | int = 0
    template: str | None = None
    options: RenderOptionsPayload = Field(default_factory=RenderOptionsPayload)
    source_kind: str | None = None
    source_label: str | None = None


class CodeConsoleContextResponse(StrictModel):
    context_id: str
    input_path: str
    sheet: str | int
    sheet_names: list[str]
    inspection: InputInspectionResponse
    dataset: PlotDatasetPreviewResponse | None = None
    template: str
    options: RenderOptionsPayload
    prompt_text: str
    starter_code: str
    source_kind: str | None = None
    source_label: str | None = None


class CodeConsoleRunRequest(StrictModel):
    context_id: str | None = None
    context: CodeConsoleContextRequest | None = None
    code: str
    timeout_seconds: int = Field(default=90, ge=1, le=600)


class CodeConsoleGeneratedFileResponse(StrictModel):
    path: str
    name: str
    file_type: str
    size_bytes: int


class CodeConsoleRunResponse(StrictModel):
    status: Literal["succeeded", "failed", "timed_out"]
    exit_code: int | None = None
    duration_seconds: float
    stdout: str = ""
    stderr: str = ""
    run_dir: str
    output_dir: str
    script_path: str
    prompt_path: str
    context_path: str
    stdout_path: str
    stderr_path: str
    generated_files: list[CodeConsoleGeneratedFileResponse] = Field(default_factory=list)
    notebook_outputs: list[NotebookOutputPayload] = Field(default_factory=list)
    notebook_artifacts: list[NotebookArtifactPayload] = Field(default_factory=list)
    data_containers: list[DataContainerPayload] = Field(default_factory=list)


__all__ = [
    "CodeConsoleContextRequest",
    "CodeConsoleContextResponse",
    "CodeConsoleGeneratedFileResponse",
    "CodeConsoleRunRequest",
    "CodeConsoleRunResponse",
]
