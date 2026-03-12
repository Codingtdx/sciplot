from __future__ import annotations

from base64 import b64encode
from dataclasses import asdict, is_dataclass
from io import BytesIO
import json
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import Any

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from make_plot import (
    DEFAULT_SIZE_BY_TEMPLATE,
    PALETTE_PRESET_CHOICES,
    SIZE_CHOICES,
    TEMPLATE_CHOICES,
    build_rendered_plots,
    close_rendered_plots,
    export_rendered_plots,
    inspect_input_file,
    list_sheet_names,
    normalize_input_path_text,
    preflight_render_request,
    _coerce_sheet,
    _ensure_input_path,
    _resolve_render_options,
)
from src import plot_style
from src.plot_contract import meta_payload, plot_contract_dict
from src.composer import (
    ComposerPanel,
    ComposerProject,
    ComposerText,
    compose_export_pdf,
    compose_preview_png,
    import_panels_from_paths,
    two_up_editorial_panels_from_paths,
    panel_thumbnail_png,
    project_from_dict,
    three_up_panels_from_paths,
    validate_non_overlapping_panels,
)
from src.tensile_replicates import export_tensile_replicate_workbook


class RenderOptionsPayload(BaseModel):
    size: str | None = None
    xscale: str | None = None
    yscale: str | None = None
    reverse_x: bool = False
    baseline: str | None = None
    show_colorbar: bool | None = None
    palette_preset: str = plot_style.DEFAULT_PALETTE_PRESET
    use_sidecar: bool | None = None


class FileRequest(BaseModel):
    input_path: str
    sheet: str | int = 0


class RenderRequest(FileRequest):
    template: str
    options: RenderOptionsPayload = Field(default_factory=RenderOptionsPayload)


class ExportRenderRequest(RenderRequest):
    output_dir: str | None = None


class TensileReplicateRequest(BaseModel):
    file_paths: list[str]
    output_path: str
    group_name: str | None = None


class ComposerPanelPayload(BaseModel):
    id: str
    file_path: str
    page_index: int = 0
    x_mm: float
    y_mm: float
    w_mm: float
    h_mm: float
    locked: bool = False
    label: str | None = None
    kind: str = "graph"


class ComposerTextPayload(BaseModel):
    id: str
    text: str
    x_mm: float
    y_mm: float
    font_size_pt: float = 8.0
    align: str = "left"


class ComposerRequest(BaseModel):
    version: int = 1
    mode: str = "composer"
    canvas_width_mm: float = 180.0
    canvas_height_mm: float = 170.0
    grid_mm: float = 0.5
    panels: list[ComposerPanelPayload] = Field(default_factory=list)
    texts: list[ComposerTextPayload] = Field(default_factory=list)
    auto_labels: bool = True


class ComposerImportRequest(BaseModel):
    project: ComposerRequest
    file_paths: list[str]
    kind: str = "graph"


class SaveProjectRequest(BaseModel):
    project_path: str
    data: dict[str, Any]


class OpenProjectRequest(BaseModel):
    project_path: str


class ThumbnailRequest(BaseModel):
    file_path: str
    page_index: int = 0
    max_side_px: int = 640


def _normalize_path(path_text: str) -> Path:
    return _ensure_input_path(normalize_input_path_text(path_text))


def _serialize(value: Any) -> Any:
    if is_dataclass(value):
        return {key: _serialize(item) for key, item in asdict(value).items()}
    if isinstance(value, dict):
        return {key: _serialize(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_serialize(item) for item in value]
    return value


def _options_from_payload(template: str, payload: RenderOptionsPayload):
    return _resolve_render_options(
        template=template,
        size=payload.size or DEFAULT_SIZE_BY_TEMPLATE[template],
        xscale=payload.xscale,
        yscale=payload.yscale,
        reverse_x=payload.reverse_x,
        baseline=payload.baseline,
        show_colorbar=payload.show_colorbar,
        style_preset=plot_style.DEFAULT_STYLE_PRESET,
        palette_preset=payload.palette_preset,
        use_sidecar=payload.use_sidecar,
    )


def _rendered_plots_to_preview_payload(rendered_plots, *, dpi: int = 160) -> list[dict[str, str]]:
    previews: list[dict[str, str]] = []
    try:
        for rendered in rendered_plots:
            buffer = BytesIO()
            rendered.figure.savefig(
                buffer,
                format="png",
                dpi=dpi,
                facecolor="white",
                bbox_inches=None,
            )
            previews.append(
                {
                    "filename": rendered.filename,
                    "png_base64": b64encode(buffer.getvalue()).decode("ascii"),
                }
            )
    finally:
        close_rendered_plots(rendered_plots)
    return previews


def _build_composer_project(request: ComposerRequest) -> ComposerProject:
    return ComposerProject(
        version=request.version,
        mode=request.mode,
        canvas_width_mm=request.canvas_width_mm,
        canvas_height_mm=request.canvas_height_mm,
        grid_mm=request.grid_mm,
        panels=[ComposerPanel(**panel.model_dump()) for panel in request.panels],
        texts=[ComposerText(**text.model_dump()) for text in request.texts],
        auto_labels=request.auto_labels,
    )


app = FastAPI(title="CodeGod 4.0 Sidecar", version="4.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "version": "4.0.0"}


@app.get("/meta")
def meta() -> dict[str, Any]:
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
    return payload


@app.get("/plot-contract")
def plot_contract() -> dict[str, Any]:
    return plot_contract_dict()


@app.post("/inspect-file")
def inspect_file(request: FileRequest) -> dict[str, Any]:
    try:
        input_path = _normalize_path(request.input_path)
        sheet = _coerce_sheet(str(request.sheet))
        inspection = inspect_input_file(input_path, sheet)
        return {
            "input_path": str(input_path),
            "sheet": sheet,
            "sheet_names": list_sheet_names(input_path),
            "inspection": _serialize(inspection),
        }
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/recommend-render")
def recommend_render(request: FileRequest) -> dict[str, Any]:
    return inspect_file(request)


@app.post("/preflight-render")
def preflight_render(request: RenderRequest) -> dict[str, Any]:
    try:
        input_path = _normalize_path(request.input_path)
        template = request.template
        if template not in TEMPLATE_CHOICES:
            raise ValueError(f"Unsupported template: {template}")
        sheet = _coerce_sheet(str(request.sheet))
        options = _options_from_payload(template, request.options)
        preflight = preflight_render_request(template, input_path, sheet, options)
        return {
            "input_path": str(input_path),
            "template": template,
            "sheet": sheet,
            "options": request.options.model_dump(),
            "preflight": _serialize(preflight),
        }
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/render-preview")
def render_preview(request: RenderRequest) -> dict[str, Any]:
    try:
        input_path = _normalize_path(request.input_path)
        template = request.template
        sheet = _coerce_sheet(str(request.sheet))
        options = request.options
        rendered_plots = build_rendered_plots(
            template,
            input_path,
            sheet,
            size=options.size,
            xscale=options.xscale,
            yscale=options.yscale,
            reverse_x=options.reverse_x,
            baseline=options.baseline,
            show_colorbar=options.show_colorbar,
            palette_preset=options.palette_preset,
            use_sidecar=options.use_sidecar,
        )
        return {
            "template": template,
            "sheet": sheet,
            "previews": _rendered_plots_to_preview_payload(rendered_plots),
        }
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/export-render")
def export_render(request: ExportRenderRequest) -> dict[str, Any]:
    try:
        input_path = _normalize_path(request.input_path)
        template = request.template
        sheet = _coerce_sheet(str(request.sheet))
        options = request.options
        output_dir = Path(request.output_dir).expanduser() if request.output_dir else (input_path.parent / "plots")
        rendered_plots = build_rendered_plots(
            template,
            input_path,
            sheet,
            size=options.size,
            xscale=options.xscale,
            yscale=options.yscale,
            reverse_x=options.reverse_x,
            baseline=options.baseline,
            show_colorbar=options.show_colorbar,
            palette_preset=options.palette_preset,
            use_sidecar=options.use_sidecar,
        )
        outputs = export_rendered_plots(rendered_plots, output_dir, close=True)
        return {"outputs": [str(path) for path in outputs]}
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/preprocess-tensile-replicates")
def preprocess_tensile_replicates(request: TensileReplicateRequest) -> dict[str, Any]:
    try:
        result = export_tensile_replicate_workbook(
            request.file_paths,
            request.output_path,
            group_name=request.group_name,
        )
        return _serialize(result)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/panel-thumbnail")
def panel_thumbnail(request: ThumbnailRequest) -> dict[str, Any]:
    try:
        input_path = _normalize_path(request.file_path)
        png_bytes = panel_thumbnail_png(input_path, request.page_index, max_side_px=request.max_side_px)
        return {"png_base64": b64encode(png_bytes).decode("ascii")}
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/compose-preview")
def compose_preview(request: ComposerRequest) -> dict[str, Any]:
    try:
        project = _build_composer_project(request)
        ok, reason = validate_non_overlapping_panels(project)
        png_bytes = compose_preview_png(project)
        return {
            "valid": ok,
            "validation_error": reason,
            "png_base64": b64encode(png_bytes).decode("ascii"),
        }
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/compose-export")
def compose_export(request: ComposerRequest) -> dict[str, Any]:
    try:
        project = _build_composer_project(request)
        ok, reason = validate_non_overlapping_panels(project)
        if not ok:
            raise ValueError(reason)
        with NamedTemporaryFile(delete=False, suffix=".pdf") as handle:
            output_path = Path(handle.name)
        exported = compose_export_pdf(project, output_path)
        return {"output_path": str(exported)}
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/save-project")
def save_project(request: SaveProjectRequest) -> dict[str, Any]:
    try:
        project_path = Path(request.project_path).expanduser()
        project_path.parent.mkdir(parents=True, exist_ok=True)
        project_path.write_text(json.dumps(request.data, ensure_ascii=False, indent=2), encoding="utf-8")
        return {"project_path": str(project_path)}
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/open-project")
def open_project(request: OpenProjectRequest) -> dict[str, Any]:
    try:
        project_path = Path(request.project_path).expanduser()
        data = json.loads(project_path.read_text(encoding="utf-8"))
        return {"project_path": str(project_path), "data": data}
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/composer/three-up")
def composer_three_up(request: list[str]) -> dict[str, Any]:
    try:
        panels = [asdict(panel) for panel in three_up_panels_from_paths(request)]
        return {"panels": panels}
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/composer/two-up-editorial")
def composer_two_up_editorial(request: list[str]) -> dict[str, Any]:
    try:
        panels = [asdict(panel) for panel in two_up_editorial_panels_from_paths(request)]
        return {"panels": panels}
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/composer/import-panels")
def composer_import_panels(request: ComposerImportRequest) -> dict[str, Any]:
    try:
        project = _build_composer_project(request.project)
        file_paths = [str(Path(path).expanduser()) for path in request.file_paths]
        panels = [asdict(panel) for panel in import_panels_from_paths(project, file_paths, kind=request.kind)]
        return {"panels": panels}
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


def main() -> None:
    import uvicorn

    uvicorn.run("app.sidecar.server:app", host="127.0.0.1", port=8765, reload=False)


if __name__ == "__main__":
    main()
