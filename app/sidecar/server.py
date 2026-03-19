from __future__ import annotations

import json
import os
import subprocess
import sys
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
    OpenPathRequest,
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
    TensileComparisonExportRequest,
    TensileComparisonExportResponse,
    TensileReplicateRequest,
    TensileReplicateResponseModel,
    TensileWorkbookRequest,
    TensileWorkbookSummaryResponse,
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
from src.composer_qa import analyze_composer_project
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
    export_tensile_comparison_bundle,
    inspect_input_file,
    inspect_tensile_workbook,
    list_sheet_names,
    normalize_input_path_text,
    preflight_render_request,
    resolve_render_options,
    validate_template_name,
)
from src.submission import build_composer_submission_report, build_render_submission_report
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
        style_preset=payload.style_preset or plot_style.DEFAULT_STYLE_PRESET,
        palette_preset=payload.palette_preset,
        use_sidecar=payload.use_sidecar,
    )


def _preview_artifact_path(output_dir: Path, filename: str) -> Path:
    return output_dir / f"{Path(filename).stem}.preview.png"


def _write_json_artifact(output_dir: Path, filename: str, payload: object) -> Path:
    path = output_dir / filename
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return path


def _contextual_error_message(context: str, exc: Exception) -> str:
    message = str(exc).strip() or "Unexpected error."
    lower = message.lower()
    if message in {
        "The project file is not valid JSON.",
        "This is not a recognizable CodeGod project file.",
    }:
        return message
    if message.startswith("Invalid project file field:"):
        return message
    if "only support version: 2" in message:
        return message
    if "no such file or directory" in lower or "does not exist" in lower:
        return (
            f"{message} Confirm that the selected file or folder still exists and that the desktop app "
            "can access it."
        )
    if "not valid json" in lower:
        return message
    if "template `" in message and "does not support" in message:
        return message
    if "non-numeric values" in lower:
        return f"{message} Keep notes outside the plotted data region and leave only numeric values inside it."
    prefixes = {
        "inspect": "Could not inspect this input file.",
        "preflight": "Could not finish the export preflight.",
        "preview": "Could not render the live preview.",
        "export": "Could not export the submission bundle.",
        "open_path": "Could not open the selected folder.",
        "save_project": "Could not save this CodeGod project.",
        "open_project": "Could not open this CodeGod project.",
        "tensile_preprocess": "Could not build the tensile workbook.",
        "tensile_workbook": "Could not inspect this tensile workbook.",
        "tensile_compare": "Could not export the tensile comparison bundle.",
    }
    prefix = prefixes.get(context)
    if prefix is None:
        return message
    return f"{prefix} {message}"


def _http_bad_request(context: str, exc: Exception) -> HTTPException:
    return HTTPException(status_code=400, detail=_contextual_error_message(context, exc))


def _open_path_with_host(target: Path) -> None:
    if sys.platform == "darwin":
        subprocess.run(["open", str(target)], check=True)
        return
    if os.name == "nt" and hasattr(os, "startfile"):
        os.startfile(str(target))
        return
    subprocess.run(["xdg-open", str(target)], check=True)


def _bundle_manifest_payload(
    *,
    input_path: Path,
    sheet: str | int,
    template: str,
    output_dir: Path,
    outputs: list[Path],
    preview_outputs: list[Path],
    artifact_paths: list[Path],
    submission_report: object,
    inspection: object,
    options: object,
) -> dict[str, object]:
    return {
        "input_path": str(input_path),
        "sheet": sheet,
        "template": template,
        "output_dir": str(output_dir),
        "outputs": [str(path) for path in outputs],
        "preview_outputs": [str(path) for path in preview_outputs],
        "artifact_paths": [str(path) for path in artifact_paths],
        "normalized_options": options,
        "inspection": inspection,
        "submission_report": submission_report,
    }


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
        raise _http_bad_request("inspect", exc) from exc


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
        raise _http_bad_request("preflight", exc) from exc


@app.post("/render-preview", response_model=RenderPreviewResponse)
def render_preview(request: RenderRequest) -> RenderPreviewResponse:
    try:
        input_path = _normalize_path(request.input_path)
        template = validate_template_name(request.template)
        sheet = coerce_sheet(str(request.sheet))
        payload_options = request.options
        resolved_options = _options_from_payload(template, payload_options)
        rendered_plots = build_rendered_plots(
            template,
            input_path,
            sheet,
            size=payload_options.size,
            xscale=payload_options.xscale,
            yscale=payload_options.yscale,
            reverse_x=payload_options.reverse_x,
            baseline=payload_options.baseline,
            show_colorbar=payload_options.show_colorbar,
            style_preset=payload_options.style_preset,
            palette_preset=payload_options.palette_preset,
            use_sidecar=payload_options.use_sidecar,
        )
        try:
            previews = rendered_plots_to_preview_payload(rendered_plots)
            submission_report = build_render_submission_report(
                context="preview",
                template=template,
                options=resolved_options,
                output_filenames=[rendered.filename for rendered in rendered_plots],
                qa_reports=[rendered.qa_report for rendered in rendered_plots],
            )
        finally:
            close_rendered_plots(rendered_plots)
        return RenderPreviewResponse(
            template=template,
            sheet=sheet,
            previews=previews,
            submission_report=serialize_dataclass(submission_report),
        )
    except Exception as exc:
        raise _http_bad_request("preview", exc) from exc


@app.post("/export-render", response_model=ExportRenderResponse)
def export_render(request: ExportRenderRequest) -> ExportRenderResponse:
    try:
        input_path = _normalize_path(request.input_path)
        template = validate_template_name(request.template)
        sheet = coerce_sheet(str(request.sheet))
        payload_options = request.options
        output_dir = Path(request.output_dir).expanduser() if request.output_dir else (input_path.parent / "plots")
        output_dir.mkdir(parents=True, exist_ok=True)
        resolved_options = _options_from_payload(template, payload_options)
        inspection = inspect_input_file(input_path, sheet)
        preflight = preflight_render_request(template, input_path, sheet, resolved_options)
        if preflight.errors:
            raise ValueError("\n".join(preflight.errors))
        created_paths: list[Path] = []
        expected_output_existence = {
            output_dir / filename: (output_dir / filename).exists()
            for filename in preflight.output_filenames
        }
        rendered_plots = build_rendered_plots(
            template,
            input_path,
            sheet,
            size=payload_options.size,
            xscale=payload_options.xscale,
            yscale=payload_options.yscale,
            reverse_x=payload_options.reverse_x,
            baseline=payload_options.baseline,
            show_colorbar=payload_options.show_colorbar,
            style_preset=payload_options.style_preset,
            palette_preset=payload_options.palette_preset,
            use_sidecar=payload_options.use_sidecar,
        )
        try:
            outputs = export_rendered_plots(rendered_plots, output_dir, close=False)
            for path in outputs:
                if not expected_output_existence.get(path, False):
                    created_paths.append(path)
            preview_outputs: list[Path] = []
            for rendered in rendered_plots:
                preview_path = _preview_artifact_path(output_dir, rendered.filename)
                existed_before = preview_path.exists()
                rendered.figure.savefig(
                    preview_path,
                    format="png",
                    dpi=220,
                    facecolor="white",
                    bbox_inches=None,
                )
                preview_outputs.append(preview_path)
                if not existed_before:
                    created_paths.append(preview_path)

            submission_report = build_render_submission_report(
                context="export",
                template=template,
                options=resolved_options,
                output_filenames=[path.name for path in outputs],
                qa_reports=[rendered.qa_report for rendered in rendered_plots],
                blockers=preflight.errors,
                warnings=preflight.warnings,
            )
            normalized_options_payload = serialize_dataclass(resolved_options)
            inspection_payload = serialize_dataclass(inspection)
            submission_payload = serialize_dataclass(submission_report)
            artifact_paths: list[Path] = []
            for filename, payload in (
                ("codegod_normalized_options.json", normalized_options_payload),
                ("codegod_inspection.json", inspection_payload),
                ("codegod_preflight.json", serialize_dataclass(preflight)),
                ("codegod_submission_report.json", submission_payload),
            ):
                artifact_path = output_dir / filename
                existed_before = artifact_path.exists()
                artifact_paths.append(_write_json_artifact(output_dir, filename, payload))
                if not existed_before:
                    created_paths.append(artifact_path)
            manifest_path = output_dir / "codegod_manifest.json"
            manifest_existed_before = manifest_path.exists()
            manifest_payload = _bundle_manifest_payload(
                input_path=input_path,
                sheet=sheet,
                template=template,
                output_dir=output_dir,
                outputs=outputs,
                preview_outputs=preview_outputs,
                artifact_paths=artifact_paths,
                submission_report=submission_payload,
                inspection=inspection_payload,
                options=normalized_options_payload,
            )
            manifest_path = _write_json_artifact(output_dir, "codegod_manifest.json", manifest_payload)
            artifact_paths.append(manifest_path)
            if not manifest_existed_before:
                created_paths.append(manifest_path)
        finally:
            close_rendered_plots(rendered_plots)
        return ExportRenderResponse(
            outputs=[str(path) for path in outputs],
            output_dir=str(output_dir),
            preview_outputs=[str(path) for path in preview_outputs],
            artifact_paths=[str(path) for path in artifact_paths],
            manifest_path=str(manifest_path),
            submission_report=serialize_dataclass(submission_report),
        )
    except Exception as exc:
        for path in reversed(locals().get("created_paths", [])):
            try:
                path.unlink(missing_ok=True)
            except OSError:
                pass
        raise _http_bad_request("export", exc) from exc


@app.post("/open-path", response_model=PathResponse)
def open_path(request: OpenPathRequest) -> PathResponse:
    try:
        target = Path(request.output_path).expanduser()
        if not target.exists():
            raise FileNotFoundError(str(target))
        _open_path_with_host(target)
        return PathResponse(output_path=str(target))
    except Exception as exc:
        raise _http_bad_request("open_path", exc) from exc


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
        raise _http_bad_request("tensile_preprocess", exc) from exc


@app.post("/inspect-tensile-workbook", response_model=TensileWorkbookSummaryResponse)
def inspect_tensile_workbook_endpoint(
    request: TensileWorkbookRequest,
) -> TensileWorkbookSummaryResponse:
    try:
        summary = inspect_tensile_workbook(request.workbook_path)
        return TensileWorkbookSummaryResponse.model_validate(serialize_dataclass(summary))
    except Exception as exc:
        raise _http_bad_request("tensile_workbook", exc) from exc


@app.post("/export-tensile-comparison", response_model=TensileComparisonExportResponse)
def export_tensile_comparison(
    request: TensileComparisonExportRequest,
) -> TensileComparisonExportResponse:
    try:
        exported = export_tensile_comparison_bundle(
            [Path(path).expanduser() for path in request.workbook_paths],
            request.output_dir,
        )
        return TensileComparisonExportResponse.model_validate(serialize_dataclass(exported))
    except Exception as exc:
        raise _http_bad_request("tensile_compare", exc) from exc


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
        qa_report, suggested_patch = analyze_composer_project(project)
        submission_report = build_composer_submission_report(
            project=project,
            qa_report=qa_report,
            valid=ok,
            validation_error=reason,
        )
        return ComposerPreviewResponse(
            valid=ok,
            validation_error=reason,
            png_base64=b64encode(png_bytes).decode("ascii"),
            qa=serialize_dataclass(qa_report),
            submission_report=serialize_dataclass(submission_report),
            suggested_project_patch=serialize_dataclass(suggested_patch),
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
