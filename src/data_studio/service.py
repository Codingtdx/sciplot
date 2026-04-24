from __future__ import annotations

from pathlib import Path

from src.data_studio.comparison import (
    comparison_recipes_for_workbooks,
    export_comparison_bundle,
    materialize_comparison_context,
    preview_comparison_recipe,
)
from src.data_studio.import_templates_v2 import create_template_definition, preview_template_apply
from src.data_studio.models import (
    TemplateFieldBinding,
    TemplateMatchCondition,
    TemplateSegmentSelector,
    TemplateSourceFormat,
)
from src.data_studio.session import normalize_session_payload
from src.data_studio.template_store import (
    delete_template,
    list_templates,
    load_template,
    rename_template,
    save_template,
)
from src.data_studio.workbooks import (
    build_workbook,
    import_workbook,
    import_workbooks,
    preview_workbook,
)


def list_data_studio_templates():
    return list_templates()


def create_data_studio_template(
    *,
    label: str,
    template_id: str | None = None,
    description: str = "",
    output_kind: str = "curve_metrics",
    source_format: dict[str, object] | None = None,
    segment_policy: str = "single_table",
    segment_selectors: list[dict[str, object]] | None = None,
    field_bindings: list[dict[str, object]] | None = None,
    match_conditions: list[dict[str, object]] | None = None,
):
    template = create_template_definition(
        label=label,
        template_id=template_id,
        description=description,
        output_kind=output_kind,
        source_format=_source_format_from_payload(source_format or {}),
        segment_policy=segment_policy,
        segment_selectors=tuple(_segment_selector_from_payload(item) for item in (segment_selectors or [])),
        field_bindings=tuple(_field_binding_from_payload(item) for item in (field_bindings or [])),
        match_conditions=tuple(_condition_from_payload(item) for item in (match_conditions or [])),
    )
    save_template(template)
    return template


def preview_data_studio_template(source_path: str | Path, *, template_payload: dict[str, object]):
    template = create_template_definition(
        label=str(template_payload.get("label", "Draft Import Template")),
        template_id=(
            str(template_payload["template_id"]) if template_payload.get("template_id") is not None else "draft/template"
        ),
        description=str(template_payload.get("description", "")),
        output_kind=str(template_payload.get("output_kind", "curve_metrics")),
        source_format=_source_format_from_payload(dict(template_payload.get("source_format", {}) or {})),
        segment_policy=str(template_payload.get("segment_policy", "single_table")),
        segment_selectors=tuple(
            _segment_selector_from_payload(item)
            for item in list(template_payload.get("segment_selectors", []) or [])
            if isinstance(item, dict)
        ),
        field_bindings=tuple(
            _field_binding_from_payload(item)
            for item in list(template_payload.get("field_bindings", []) or [])
            if isinstance(item, dict)
        ),
        match_conditions=tuple(
            _condition_from_payload(item)
            for item in list(template_payload.get("match_conditions", []) or [])
            if isinstance(item, dict)
        ),
    )
    return preview_template_apply(source_path, template)


def update_data_studio_template(template_id: str, *, new_id: str | None = None, new_label: str | None = None):
    return rename_template(template_id, new_id=new_id, new_label=new_label)


def delete_data_studio_template(template_id: str) -> None:
    delete_template(template_id)


def build_data_studio_workbook(
    *,
    file_paths: list[str | Path],
    output_path: str | Path,
    template_id: str,
    group_name: str | None = None,
):
    return build_workbook(
        file_paths=file_paths,
        output_path=output_path,
        template_id=template_id,
        group_name=group_name,
    )


def _source_format_from_payload(payload: dict[str, object]) -> TemplateSourceFormat:
    return TemplateSourceFormat(
        encoding=str(payload["encoding"]) if payload.get("encoding") is not None else None,
        delimiter=str(payload["delimiter"]) if payload.get("delimiter") is not None else None,
        sheet_name=str(payload["sheet_name"]) if payload.get("sheet_name") is not None else None,
    )


def _segment_selector_from_payload(payload: dict[str, object]) -> TemplateSegmentSelector:
    return TemplateSegmentSelector(
        id=str(payload["id"]),
        label=str(payload.get("label", payload["id"])),
        result_label=str(payload["result_label"]) if payload.get("result_label") is not None else None,
        interval_index=int(payload["interval_index"]) if payload.get("interval_index") is not None else None,
        header_row_index=int(payload["header_row_index"]) if payload.get("header_row_index") is not None else None,
        unit_row_index=int(payload["unit_row_index"]) if payload.get("unit_row_index") is not None else None,
        data_start_row_index=(
            int(payload["data_start_row_index"]) if payload.get("data_start_row_index") is not None else None
        ),
        start_row=int(payload["start_row"]) if payload.get("start_row") is not None else None,
        end_row=int(payload["end_row"]) if payload.get("end_row") is not None else None,
    )


def _field_binding_from_payload(payload: dict[str, object]) -> TemplateFieldBinding:
    return TemplateFieldBinding(
        id=str(payload["id"]),
        role=str(payload["role"]),
        label=str(payload["label"]),
        sheet_name=str(payload["sheet_name"]) if payload.get("sheet_name") is not None else None,
        block_id=str(payload["block_id"]) if payload.get("block_id") is not None else None,
        column_name=str(payload["column_name"]) if payload.get("column_name") is not None else None,
        column_index=int(payload["column_index"]) if payload.get("column_index") is not None else None,
        row_label_contains=(
            str(payload["row_label_contains"]) if payload.get("row_label_contains") is not None else None
        ),
        cell_value_contains=tuple(str(item) for item in payload.get("cell_value_contains", ()) or ()),
        unit_hint=str(payload["unit_hint"]) if payload.get("unit_hint") is not None else None,
        optional=bool(payload.get("optional", False)),
    )


def _condition_from_payload(payload: dict[str, object]) -> TemplateMatchCondition:
    return TemplateMatchCondition(
        sheet_name_contains=tuple(str(item) for item in payload.get("sheet_name_contains", ()) or ()),
        text_contains=tuple(str(item) for item in payload.get("text_contains", ()) or ()),
        field_kinds=tuple(str(item) for item in payload.get("field_kinds", ()) or ()),
        minimum_score=float(payload.get("minimum_score", 0.0) or 0.0),
    )


def import_data_studio_workbook(path: str | Path):
    return import_workbook(path)


def import_data_studio_workbooks(path: str | Path):
    return import_workbooks(path)


def preview_data_studio_workbook(path: str | Path, *, specimen_states=None):
    return preview_workbook(path, specimen_states=specimen_states)


def list_data_studio_recipes(workbook_paths: list[str | Path], *, group_states=None):
    return comparison_recipes_for_workbooks(workbook_paths, group_states=group_states)


def preview_data_studio_comparison(
    workbook_paths: list[str | Path],
    recipe_id: str,
    *,
    group_states=None,
    specimen_states=None,
):
    return preview_comparison_recipe(
        workbook_paths,
        recipe_id,
        group_states=group_states,
        specimen_states=specimen_states,
    )


def preview_data_studio_comparison_context(
    workbook_paths: list[str | Path],
    *,
    group_states=None,
    specimen_states=None,
):
    return materialize_comparison_context(
        workbook_paths,
        group_states=group_states,
        specimen_states=specimen_states,
    )


def export_data_studio_comparison(
    workbook_paths: list[str | Path],
    output_dir: str | Path,
    *,
    group_states=None,
    specimen_states=None,
    selected_recipe_ids: list[str] | None = None,
    figure_options_by_recipe_id: dict[str, dict[str, object]] | None = None,
    figure_fit_options_by_recipe_id: dict[str, dict[str, object]] | None = None,
):
    return export_comparison_bundle(
        workbook_paths,
        output_dir,
        group_states=group_states,
        specimen_states=specimen_states,
        selected_recipe_ids=selected_recipe_ids,
        figure_options_by_recipe_id=figure_options_by_recipe_id,
        figure_fit_options_by_recipe_id=figure_fit_options_by_recipe_id,
    )


__all__ = [
    "build_data_studio_workbook",
    "create_data_studio_template",
    "delete_data_studio_template",
    "export_data_studio_comparison",
    "import_data_studio_workbook",
    "import_data_studio_workbooks",
    "list_data_studio_recipes",
    "list_data_studio_templates",
    "load_template",
    "normalize_session_payload",
    "preview_data_studio_template",
    "preview_data_studio_workbook",
    "preview_data_studio_comparison",
    "preview_data_studio_comparison_context",
    "update_data_studio_template",
]
