from __future__ import annotations

from pathlib import Path

from src.data_studio.models import (
    DataStudioFigurePreference,
    DataStudioGroupState,
    DataStudioSessionPayload,
)


def normalize_session_payload(payload: dict[str, object]) -> DataStudioSessionPayload:
    workbook_paths = tuple(str(Path(path).expanduser()) for path in payload.get("workbook_paths", ()) or ())
    imported_paths = tuple(str(Path(path).expanduser()) for path in payload.get("imported_paths", ()) or ())
    comparison_recipe_ids = tuple(str(item) for item in payload.get("comparison_recipe_ids", ()) or ())
    raw_group_states = payload.get("group_states", ()) or ()
    group_states = tuple(
        DataStudioGroupState(
            workbook_path=str(Path(str(item.get("workbook_path", ""))).expanduser()),
            display_name=str(item.get("display_name", "")).strip()
            or Path(str(item.get("workbook_path", ""))).expanduser().stem,
            include_in_compare=bool(item.get("include_in_compare", True)),
            sort_order=int(item.get("sort_order", 0) or 0),
        )
        for item in raw_group_states
        if isinstance(item, dict) and item.get("workbook_path")
    )
    raw_figure_preferences = payload.get("figure_preferences", ()) or ()
    figure_preferences = tuple(
        DataStudioFigurePreference(
            family_id=str(item.get("family_id", "")).strip(),
            selected_template_id=(
                str(item["selected_template_id"]) if item.get("selected_template_id") is not None else None
            ),
            options_by_template={
                str(template_id): dict(options or {})
                for template_id, options in dict(item.get("options_by_template", {}) or {}).items()
            },
        )
        for item in raw_figure_preferences
        if isinstance(item, dict) and str(item.get("family_id", "")).strip()
    )
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
        selected_figure_family_id=(
            str(payload["selected_figure_family_id"])
            if payload.get("selected_figure_family_id") is not None
            else None
        ),
        selected_figure_template_id=(
            str(payload["selected_figure_template_id"])
            if payload.get("selected_figure_template_id") is not None
            else None
        ),
        group_states=group_states,
        figure_preferences=figure_preferences,
        imported_paths=imported_paths,
        template_draft_path=str(Path(template_draft_path).expanduser()) if template_draft_path is not None else None,
    )


__all__ = ["normalize_session_payload"]
