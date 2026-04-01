from __future__ import annotations

from pathlib import Path

import pytest

from src.data_studio import template_store
from src.data_studio.ingest import preview_and_recommend
from src.data_studio.service import (
    build_data_studio_workbook,
    create_data_studio_template,
    export_data_studio_comparison,
    import_data_studio_workbook,
    normalize_session_payload,
    preview_data_studio_comparison,
)

ROOT = Path(__file__).resolve().parents[1]
FIXTURE_DIR = ROOT / "tests" / "fixtures" / "tensile_raw"


def _fixture_paths() -> list[Path]:
    return [
        FIXTURE_DIR / "BlendSet_A.csv",
        FIXTURE_DIR / "BlendSet_B.csv",
        FIXTURE_DIR / "BlendSet_bad.csv",
    ]


def test_preview_and_recommend_detects_builtin_tensile_template() -> None:
    preview, matches = preview_and_recommend(FIXTURE_DIR / "BlendSet_A.csv")

    assert preview.file_type == "csv"
    assert preview.encoding is not None
    assert {"curve_x", "curve_y"} <= {candidate.kind for candidate in preview.field_candidates}
    assert "builtin/tensile" in preview.recommended_template_ids
    assert matches
    assert matches[0].template_id == "builtin/tensile"
    assert matches[0].family == "tensile"


def test_create_template_from_candidates_persists_user_template(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    user_template_dir = tmp_path / "templates" / "user"
    monkeypatch.setattr(template_store, "USER_TEMPLATE_DIR", user_template_dir)

    preview, _ = preview_and_recommend(FIXTURE_DIR / "BlendSet_A.csv")
    candidate_ids = [candidate.id for candidate in preview.field_candidates[:3]]

    template = create_data_studio_template(
        source_path=FIXTURE_DIR / "BlendSet_A.csv",
        label="Fixture Template",
        accepted_candidate_ids=candidate_ids,
        template_id="user/fixture-template",
        description="Saved from tensile fixture preview.",
    )

    saved_path = template_store.template_path(template.id, builtin=False)
    assert saved_path.exists()
    assert template.id == "user/fixture-template"
    assert template.builtin is False
    assert template.field_bindings


def test_build_and_import_data_studio_workbook_keeps_tensile_behavior(tmp_path: Path) -> None:
    output_path = tmp_path / "blendset.xlsx"

    workbook = build_data_studio_workbook(
        file_paths=_fixture_paths(),
        output_path=output_path,
        template_id="builtin/tensile",
        group_name="BlendSet",
    )

    assert output_path.exists()
    assert workbook.template_match.template_id == "builtin/tensile"
    assert workbook.parsed_sample_count == 2
    assert workbook.failed_sample_count == 1
    assert workbook.preferred_sheet == "Representative_Curve"
    assert {metric.label for metric in workbook.metrics} == {"Strength", "Modulus", "Elongation"}

    imported = import_data_studio_workbook(output_path)
    assert imported.workbook_path == output_path
    assert imported.template_match.family == "tensile"
    assert imported.label == "BlendSet"
    assert imported.parsed_sample_count == 2


def test_preview_and_export_data_studio_comparison_uses_plot_render_pipeline(tmp_path: Path) -> None:
    workbook_paths: list[str] = []
    for index in range(2):
        workbook_path = tmp_path / f"group_{index + 1}.xlsx"
        build_data_studio_workbook(
            file_paths=_fixture_paths(),
            output_path=workbook_path,
            template_id="builtin/tensile",
            group_name=f"Group {index + 1}",
        )
        workbook_paths.append(str(workbook_path))

    comparison_set, recipe, pdf_base64 = preview_data_studio_comparison(workbook_paths, "representative_curve")

    assert comparison_set.workbook_labels == ("Group 1", "Group 2")
    assert recipe.id == "representative_curve"
    assert pdf_base64
    assert comparison_set.comparison_workbook_path.exists()

    exported_set, figure_outputs = export_data_studio_comparison(
        workbook_paths,
        tmp_path / "exports",
        selected_recipe_ids=["representative_curve", "strength_box"],
    )

    assert exported_set.comparison_workbook_path.exists()
    assert {output.recipe_id for output in figure_outputs} == {"representative_curve", "strength_box"}
    assert all(output.path.exists() for output in figure_outputs)


def test_normalize_session_payload_expands_paths() -> None:
    payload = normalize_session_payload(
        {
            "selected_template_id": "builtin/tensile",
            "selected_workbook_id": "workbook-1",
            "primary_workbook_id": "workbook-1",
            "selected_recipe_id": "representative_curve",
            "workbook_paths": ["~/tmp/prepared.xlsx"],
            "comparison_recipe_ids": ["representative_curve", "strength_box"],
            "imported_paths": ["~/tmp/raw_a.csv"],
            "template_draft_path": "~/tmp/raw_a.csv",
        }
    )

    assert payload.selected_template_id == "builtin/tensile"
    assert payload.workbook_paths[0].startswith(str(Path.home()))
    assert payload.imported_paths[0].startswith(str(Path.home()))
    assert payload.template_draft_path and payload.template_draft_path.startswith(str(Path.home()))
