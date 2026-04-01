from __future__ import annotations

from pathlib import Path

from src.data_studio.models import DataStudioSessionPayload


def normalize_session_payload(payload: dict[str, object]) -> DataStudioSessionPayload:
    workbook_paths = tuple(str(Path(path).expanduser()) for path in payload.get("workbook_paths", ()) or ())
    imported_paths = tuple(str(Path(path).expanduser()) for path in payload.get("imported_paths", ()) or ())
    comparison_recipe_ids = tuple(str(item) for item in payload.get("comparison_recipe_ids", ()) or ())
    template_draft_path = payload.get("template_draft_path")
    return DataStudioSessionPayload(
        version=int(payload.get("version", 1)),
        selected_template_id=(
            str(payload["selected_template_id"]) if payload.get("selected_template_id") is not None else None
        ),
        selected_workbook_id=(
            str(payload["selected_workbook_id"]) if payload.get("selected_workbook_id") is not None else None
        ),
        primary_workbook_id=(
            str(payload["primary_workbook_id"]) if payload.get("primary_workbook_id") is not None else None
        ),
        selected_recipe_id=(
            str(payload["selected_recipe_id"]) if payload.get("selected_recipe_id") is not None else None
        ),
        workbook_paths=workbook_paths,
        comparison_recipe_ids=comparison_recipe_ids,
        imported_paths=imported_paths,
        template_draft_path=str(Path(template_draft_path).expanduser()) if template_draft_path is not None else None,
    )


__all__ = ["normalize_session_payload"]
