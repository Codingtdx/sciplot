from __future__ import annotations

from fastapi import APIRouter

from app.sidecar.schemas import (
    DataStudioBuildWorkbookRequest,
    DataStudioComparisonContextResponse,
    DataStudioComparisonExportResponse,
    DataStudioComparisonPreviewResponse,
    DataStudioComparisonRequest,
    DataStudioCreateTemplateRequest,
    DataStudioExportComparisonRequest,
    DataStudioImportWorkbookRequest,
    DataStudioImportWorkbookResponse,
    DataStudioPreviewComparisonRequest,
    DataStudioSessionNormalizeRequest,
    DataStudioSessionResponse,
    DataStudioSourcePreviewRequest,
    DataStudioSourcePreviewResponse,
    DataStudioTemplateListResponse,
    DataStudioTemplateResponse,
    DataStudioUpdateTemplateRequest,
    DataStudioWorkbookPreviewRequest,
    DataStudioWorkbookPreviewResponse,
    DataStudioWorkbookResponse,
    PreviewItemResponse,
    StatusResponse,
    serialize_dataclass,
)
from app.sidecar.server_utils import http_bad_request
from src.data_studio.service import (
    build_data_studio_workbook,
    create_data_studio_template,
    delete_data_studio_template,
    export_data_studio_comparison,
    import_data_studio_workbooks,
    list_data_studio_templates,
    normalize_session_payload,
    preview_data_studio_comparison,
    preview_data_studio_comparison_context,
    preview_data_studio_source,
    preview_data_studio_workbook,
    update_data_studio_template,
)


def create_data_studio_router() -> APIRouter:
    router = APIRouter()

    @router.get("/data-studio/templates", response_model=DataStudioTemplateListResponse)
    def list_templates() -> DataStudioTemplateListResponse:
        try:
            templates = list_data_studio_templates()
            return DataStudioTemplateListResponse.model_validate(
                {"templates": [serialize_dataclass(template) for template in templates]}
            )
        except Exception as exc:
            raise http_bad_request("data_studio_templates", exc) from exc

    @router.post("/data-studio/source-preview", response_model=DataStudioSourcePreviewResponse)
    def preview_source(request: DataStudioSourcePreviewRequest) -> DataStudioSourcePreviewResponse:
        try:
            preview, matches = preview_data_studio_source(request.input_path)
            return DataStudioSourcePreviewResponse.model_validate(
                {
                    "preview": serialize_dataclass(preview),
                    "matches": [serialize_dataclass(match) for match in matches],
                }
            )
        except Exception as exc:
            raise http_bad_request("data_studio_source_preview", exc) from exc

    @router.post("/data-studio/templates", response_model=DataStudioTemplateResponse)
    def create_template(request: DataStudioCreateTemplateRequest) -> DataStudioTemplateResponse:
        try:
            template = create_data_studio_template(
                source_path=request.source_path,
                label=request.label,
                accepted_candidate_ids=request.accepted_candidate_ids,
                template_id=request.template_id,
                description=request.description,
            )
            return DataStudioTemplateResponse.model_validate(serialize_dataclass(template))
        except Exception as exc:
            raise http_bad_request("data_studio_template_create", exc) from exc

    @router.put("/data-studio/templates/{template_id:path}", response_model=DataStudioTemplateResponse)
    def update_template(template_id: str, request: DataStudioUpdateTemplateRequest) -> DataStudioTemplateResponse:
        try:
            template = update_data_studio_template(template_id, new_id=request.new_id, new_label=request.new_label)
            return DataStudioTemplateResponse.model_validate(serialize_dataclass(template))
        except Exception as exc:
            raise http_bad_request("data_studio_template_update", exc) from exc

    @router.delete("/data-studio/templates/{template_id:path}", response_model=StatusResponse)
    def delete_template(template_id: str) -> StatusResponse:
        try:
            delete_data_studio_template(template_id)
            return StatusResponse(status="ok")
        except Exception as exc:
            raise http_bad_request("data_studio_template_delete", exc) from exc

    @router.post("/data-studio/build-workbook", response_model=DataStudioWorkbookResponse)
    def build_workbook(request: DataStudioBuildWorkbookRequest) -> DataStudioWorkbookResponse:
        try:
            workbook = build_data_studio_workbook(
                file_paths=request.file_paths,
                output_path=request.output_path,
                template_id=request.template_id,
                group_name=request.group_name,
            )
            return DataStudioWorkbookResponse.model_validate(serialize_dataclass(workbook))
        except Exception as exc:
            raise http_bad_request("data_studio_build_workbook", exc) from exc

    @router.post("/data-studio/import-workbook", response_model=DataStudioImportWorkbookResponse)
    def import_workbook(request: DataStudioImportWorkbookRequest) -> DataStudioImportWorkbookResponse:
        try:
            workbooks = import_data_studio_workbooks(request.workbook_path)
            return DataStudioImportWorkbookResponse.model_validate(
                {"workbooks": [serialize_dataclass(workbook) for workbook in workbooks]}
            )
        except Exception as exc:
            raise http_bad_request("data_studio_import_workbook", exc) from exc

    @router.post("/data-studio/workbook-preview", response_model=DataStudioWorkbookPreviewResponse)
    def workbook_preview(request: DataStudioWorkbookPreviewRequest) -> DataStudioWorkbookPreviewResponse:
        try:
            preview = preview_data_studio_workbook(
                request.workbook_path,
                specimen_states=request.specimen_states,
            )
            return DataStudioWorkbookPreviewResponse.model_validate(serialize_dataclass(preview))
        except Exception as exc:
            raise http_bad_request("data_studio_workbook_preview", exc) from exc

    @router.post("/data-studio/comparison-context", response_model=DataStudioComparisonContextResponse)
    def comparison_context(request: DataStudioComparisonRequest) -> DataStudioComparisonContextResponse:
        try:
            context = preview_data_studio_comparison_context(
                request.workbook_paths,
                group_states=request.group_states,
                specimen_states=request.specimen_states,
            )
            return DataStudioComparisonContextResponse.model_validate(
                {
                    "comparison_set": serialize_dataclass(context.comparison_set),
                    "cache_key": context.cache_key,
                    "materialized_at": context.materialized_at,
                }
            )
        except Exception as exc:
            raise http_bad_request("data_studio_comparison_context", exc) from exc

    @router.post("/data-studio/comparison-preview", response_model=DataStudioComparisonPreviewResponse)
    def comparison_preview(request: DataStudioPreviewComparisonRequest) -> DataStudioComparisonPreviewResponse:
        try:
            comparison_set, recipe, pdf_base64 = preview_data_studio_comparison(
                request.workbook_paths,
                request.recipe_id,
                group_states=request.group_states,
                specimen_states=request.specimen_states,
            )
            return DataStudioComparisonPreviewResponse.model_validate(
                {
                    "comparison_set": serialize_dataclass(comparison_set),
                    "recipe": serialize_dataclass(recipe),
                    "preview": PreviewItemResponse(
                        filename=f"{recipe.id}.pdf",
                        pdf_base64=pdf_base64,
                    ).model_dump(),
                }
            )
        except Exception as exc:
            raise http_bad_request("data_studio_comparison_preview", exc) from exc

    @router.post("/data-studio/comparison-export", response_model=DataStudioComparisonExportResponse)
    def comparison_export(request: DataStudioExportComparisonRequest) -> DataStudioComparisonExportResponse:
        try:
            comparison_set, figure_outputs, filtered_workbooks = export_data_studio_comparison(
                request.workbook_paths,
                request.output_dir,
                group_states=request.group_states,
                specimen_states=request.specimen_states,
                selected_recipe_ids=request.selected_recipe_ids,
                figure_options_by_recipe_id={
                    recipe_id: options.model_dump()
                    for recipe_id, options in request.figure_options_by_recipe_id.items()
                },
                figure_fit_options_by_recipe_id={
                    recipe_id: options.model_dump()
                    for recipe_id, options in request.figure_fit_options_by_recipe_id.items()
                },
            )
            return DataStudioComparisonExportResponse.model_validate(
                {
                    "comparison_set": serialize_dataclass(comparison_set),
                    "figure_outputs": [serialize_dataclass(item) for item in figure_outputs],
                    "filtered_workbooks": [serialize_dataclass(item) for item in filtered_workbooks],
                }
            )
        except Exception as exc:
            raise http_bad_request("data_studio_comparison_export", exc) from exc

    @router.post("/data-studio/session/normalize", response_model=DataStudioSessionResponse)
    def normalize_session(request: DataStudioSessionNormalizeRequest) -> DataStudioSessionResponse:
        try:
            payload = normalize_session_payload(request.payload)
            return DataStudioSessionResponse.model_validate(serialize_dataclass(payload))
        except Exception as exc:
            raise http_bad_request("data_studio_session_normalize", exc) from exc

    return router


__all__ = ["create_data_studio_router"]
