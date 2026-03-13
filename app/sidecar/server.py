from __future__ import annotations

from base64 import b64encode
from pathlib import Path
from tempfile import NamedTemporaryFile

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from app.sidecar.schemas import (
    ComposerImportRequest,
    ComposerPreviewResponse,
    ComposerProjectResponse,
    ComposerRequest,
    ExportRenderRequest,
    ExportRenderResponse,
    FileRequest,
    HealthResponse,
    InspectFileResponse,
    MetaResponse,
    OpenProjectRequest,
    OpenProjectResponse,
    PanelThumbnailResponse,
    PathResponse,
    PlotContractResponse,
    PreflightRenderResponse,
    ProjectPathResponse,
    RenderOptionsPayload,
    RenderPreviewResponse,
    RenderRequest,
    SaveProjectRequest,
    TensileReplicateRequest,
    TensileReplicateResponseModel,
    ThumbnailRequest,
    composer_project_from_request,
    load_project_document,
    rendered_plots_to_preview_payload,
    save_project_document,
    serialize_dataclass,
)
from src import plot_style
from src.composer import (
    compose_export_pdf,
    compose_preview_png,
    import_panels_from_paths,
    panel_thumbnail_png,
    three_up_panels_from_paths,
    two_up_editorial_panels_from_paths,
    validate_non_overlapping_panels,
)
from src.plot_contract import meta_payload, plot_contract_dict
from src.rendering import (
    DEFAULT_SIZE_BY_TEMPLATE,
    PALETTE_PRESET_CHOICES,
    SIZE_CHOICES,
    TEMPLATE_CHOICES,
    build_rendered_plots,
    close_rendered_plots,
    coerce_sheet,
    ensure_input_path,
    export_rendered_plots,
    inspect_input_file,
    list_sheet_names,
    normalize_input_path_text,
    preflight_render_request,
    resolve_render_options,
    validate_template_name,
)
from src.tensile_replicates import export_tensile_replicate_workbook


def _normalize_path(path_text: str) -> Path:
    return ensure_input_path(normalize_input_path_text(path_text))


def _options_from_payload(template: str, payload: RenderOptionsPayload):
    return resolve_render_options(
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


app = FastAPI(title="CodeGod 5.0 Sidecar", version="5.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse(status="ok", version="5.0.0")


@app.get("/meta", response_model=MetaResponse)
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


@app.get("/plot-contract", response_model=PlotContractResponse)
def plot_contract() -> PlotContractResponse:
    return PlotContractResponse.model_validate(plot_contract_dict())


@app.post("/inspect-file", response_model=InspectFileResponse)
def inspect_file(request: FileRequest) -> InspectFileResponse:
    try:
        input_path = _normalize_path(request.input_path)
        sheet = coerce_sheet(str(request.sheet))
        inspection = inspect_input_file(input_path, sheet)
        return InspectFileResponse.model_validate(
            {
                "input_path": str(input_path),
                "sheet": sheet,
                "sheet_names": list_sheet_names(input_path),
                "inspection": serialize_dataclass(inspection),
            }
        )
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/recommend-render", response_model=InspectFileResponse)
def recommend_render(request: FileRequest) -> InspectFileResponse:
    return inspect_file(request)


@app.post("/preflight-render", response_model=PreflightRenderResponse)
def preflight_render(request: RenderRequest) -> PreflightRenderResponse:
    try:
        input_path = _normalize_path(request.input_path)
        template = validate_template_name(request.template)
        sheet = coerce_sheet(str(request.sheet))
        options = _options_from_payload(template, request.options)
        preflight = preflight_render_request(template, input_path, sheet, options)
        return PreflightRenderResponse.model_validate(
            {
                "input_path": str(input_path),
                "template": template,
                "sheet": sheet,
                "options": request.options.model_dump(),
                "preflight": serialize_dataclass(preflight),
            }
        )
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/render-preview", response_model=RenderPreviewResponse)
def render_preview(request: RenderRequest) -> RenderPreviewResponse:
    try:
        input_path = _normalize_path(request.input_path)
        template = validate_template_name(request.template)
        sheet = coerce_sheet(str(request.sheet))
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
        try:
            previews = rendered_plots_to_preview_payload(rendered_plots)
        finally:
            close_rendered_plots(rendered_plots)
        return RenderPreviewResponse(template=template, sheet=sheet, previews=previews)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/export-render", response_model=ExportRenderResponse)
def export_render(request: ExportRenderRequest) -> ExportRenderResponse:
    try:
        input_path = _normalize_path(request.input_path)
        template = validate_template_name(request.template)
        sheet = coerce_sheet(str(request.sheet))
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
        return ExportRenderResponse(outputs=[str(path) for path in outputs])
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/preprocess-tensile-replicates", response_model=TensileReplicateResponseModel)
def preprocess_tensile_replicates(request: TensileReplicateRequest) -> TensileReplicateResponseModel:
    try:
        result = export_tensile_replicate_workbook(
            request.file_paths,
            request.output_path,
            group_name=request.group_name,
        )
        return TensileReplicateResponseModel.model_validate(serialize_dataclass(result))
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/panel-thumbnail", response_model=PanelThumbnailResponse)
def panel_thumbnail(request: ThumbnailRequest) -> PanelThumbnailResponse:
    try:
        input_path = _normalize_path(request.file_path)
        png_bytes = panel_thumbnail_png(input_path, request.page_index, max_side_px=request.max_side_px)
        return PanelThumbnailResponse(png_base64=b64encode(png_bytes).decode("ascii"))
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/compose-preview", response_model=ComposerPreviewResponse)
def compose_preview(request: ComposerRequest) -> ComposerPreviewResponse:
    try:
        project = composer_project_from_request(request)
        ok, reason = validate_non_overlapping_panels(project)
        png_bytes = compose_preview_png(project)
        return ComposerPreviewResponse(
            valid=ok,
            validation_error=reason,
            png_base64=b64encode(png_bytes).decode("ascii"),
        )
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/compose-export", response_model=PathResponse)
def compose_export(request: ComposerRequest) -> PathResponse:
    try:
        project = composer_project_from_request(request)
        ok, reason = validate_non_overlapping_panels(project)
        if not ok:
            raise ValueError(reason)
        with NamedTemporaryFile(delete=False, suffix=".pdf") as handle:
            output_path = Path(handle.name)
        exported = compose_export_pdf(project, output_path)
        return PathResponse(output_path=str(exported))
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/save-project", response_model=ProjectPathResponse)
def save_project(request: SaveProjectRequest) -> ProjectPathResponse:
    try:
        project_path = save_project_document(request.project_path, request.data)
        return ProjectPathResponse(project_path=str(project_path))
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/open-project", response_model=OpenProjectResponse)
def open_project(request: OpenProjectRequest) -> OpenProjectResponse:
    try:
        payload = load_project_document(request.project_path)
        return OpenProjectResponse(project_path=str(Path(request.project_path).expanduser()), data=payload)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/composer/three-up", response_model=ComposerProjectResponse)
def composer_three_up(request: list[str]) -> ComposerProjectResponse:
    try:
        project = three_up_panels_from_paths(request)
        return ComposerProjectResponse.model_validate(serialize_dataclass(project))
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/composer/two-up-editorial", response_model=ComposerProjectResponse)
def composer_two_up_editorial(request: list[str]) -> ComposerProjectResponse:
    try:
        project = two_up_editorial_panels_from_paths(request)
        return ComposerProjectResponse.model_validate(serialize_dataclass(project))
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/composer/import-panels", response_model=ComposerProjectResponse)
def composer_import_panels(request: ComposerImportRequest) -> ComposerProjectResponse:
    try:
        project = composer_project_from_request(request.project)
        file_paths = [str(Path(path).expanduser()) for path in request.file_paths]
        next_project = import_panels_from_paths(project, file_paths, kind=request.kind)
        return ComposerProjectResponse.model_validate(serialize_dataclass(next_project))
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


def main() -> None:
    import uvicorn

    uvicorn.run("app.sidecar.server:app", host="127.0.0.1", port=8765, reload=False)


if __name__ == "__main__":
    main()
