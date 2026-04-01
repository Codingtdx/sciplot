from __future__ import annotations

from pathlib import Path

from src.data_studio.comparison import (
    comparison_recipes_for_workbooks,
    export_comparison_bundle,
    preview_comparison_recipe,
)
from src.data_studio.ingest import preview_and_recommend
from src.data_studio.session import normalize_session_payload
from src.data_studio.template_store import (
    delete_template,
    list_templates,
    load_template,
    rename_template,
    save_template,
)
from src.data_studio.workbooks import build_workbook, create_template_from_candidates, import_workbook


def list_data_studio_templates():
    return list_templates()


def preview_data_studio_source(path: str | Path):
    return preview_and_recommend(path)


def create_data_studio_template(
    *,
    source_path: str | Path,
    label: str,
    accepted_candidate_ids: list[str] | None = None,
    template_id: str | None = None,
    description: str = "",
):
    template = create_template_from_candidates(
        source_path=source_path,
        label=label,
        accepted_candidate_ids=accepted_candidate_ids,
        template_id=template_id,
        description=description,
    )
    save_template(template)
    return template


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


def import_data_studio_workbook(path: str | Path):
    return import_workbook(path)


def list_data_studio_recipes(workbook_paths: list[str | Path]):
    return comparison_recipes_for_workbooks(workbook_paths)


def preview_data_studio_comparison(workbook_paths: list[str | Path], recipe_id: str):
    return preview_comparison_recipe(workbook_paths, recipe_id)


def export_data_studio_comparison(
    workbook_paths: list[str | Path],
    output_dir: str | Path,
    *,
    selected_recipe_ids: list[str] | None = None,
):
    return export_comparison_bundle(workbook_paths, output_dir, selected_recipe_ids=selected_recipe_ids)


__all__ = [
    "build_data_studio_workbook",
    "create_data_studio_template",
    "delete_data_studio_template",
    "export_data_studio_comparison",
    "import_data_studio_workbook",
    "list_data_studio_recipes",
    "list_data_studio_templates",
    "load_template",
    "normalize_session_payload",
    "preview_data_studio_comparison",
    "preview_data_studio_source",
    "update_data_studio_template",
]
