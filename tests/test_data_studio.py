from __future__ import annotations

from pathlib import Path

import pandas as pd
import pytest

from src.data_studio import template_store
from src.data_studio.builtin import tensile as tensile_builtin
from src.data_studio.ingest import preview_and_recommend
from src.data_studio.models import DataStudioGroupState
from src.data_studio.service import (
    build_data_studio_workbook,
    create_data_studio_template,
    export_data_studio_comparison,
    import_data_studio_workbook,
    import_data_studio_workbooks,
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


def _rewrite_metadata_sheet(workbook_path: Path, rows: list[list[object]]) -> None:
    with pd.ExcelFile(workbook_path) as workbook:
        sheets = {
            sheet_name: pd.read_excel(workbook_path, sheet_name=sheet_name, header=None)
            for sheet_name in workbook.sheet_names
        }
    sheets[tensile_builtin.METADATA_SHEET] = pd.DataFrame(rows)
    with pd.ExcelWriter(workbook_path) as writer:
        for sheet_name, dataframe in sheets.items():
            dataframe.to_excel(writer, sheet_name=sheet_name, header=False, index=False)


def test_preview_and_recommend_detects_builtin_tensile_template() -> None:
    preview, matches = preview_and_recommend(FIXTURE_DIR / "BlendSet_A.csv")

    assert preview.file_type == "csv"
    assert preview.encoding is not None
    assert {"curve_x", "curve_y"} <= {candidate.kind for candidate in preview.field_candidates}
    curve_suggestion = next(
        suggestion for suggestion in preview.binding_suggestions if suggestion.kind == "curve_pair"
    )
    assert curve_suggestion.title == "Recommended Curve"
    assert "X:" in curve_suggestion.summary
    assert "Y:" in curve_suggestion.summary
    assert {preview_range.role for preview_range in curve_suggestion.preview_ranges} >= {"x", "y"}
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
    curve_suggestion = next(
        suggestion
        for suggestion in preview.binding_suggestions
        if suggestion.kind == "curve_pair"
    )
    candidate_ids = list(curve_suggestion.candidate_ids)
    expected_curve_labels = [
        candidate.label
        for candidate in preview.field_candidates
        if candidate.id in set(candidate_ids) and candidate.kind in {"curve_x", "curve_y"}
    ]

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
    assert [
        binding.label
        for binding in template.field_bindings
        if binding.role in {"curve_x", "curve_y"}
    ] == expected_curve_labels


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


def test_import_data_studio_workbooks_expands_comparison_bundle_sources(tmp_path: Path) -> None:
    left_path = tmp_path / "left.xlsx"
    right_path = tmp_path / "right.xlsx"
    build_data_studio_workbook(
        file_paths=_fixture_paths(),
        output_path=left_path,
        template_id="builtin/tensile",
        group_name="Left Group",
    )
    build_data_studio_workbook(
        file_paths=_fixture_paths(),
        output_path=right_path,
        template_id="builtin/tensile",
        group_name="Right Group",
    )

    comparison_set, _, _ = preview_data_studio_comparison([str(left_path), str(right_path)], "representative_curve")

    imported = import_data_studio_workbooks(comparison_set.comparison_workbook_path)

    assert [workbook.workbook_path for workbook in imported] == [left_path, right_path]
    assert [workbook.label for workbook in imported] == ["Left Group", "Right Group"]


def test_import_data_studio_workbooks_expands_legacy_tensile_comparison_bundle(tmp_path: Path) -> None:
    left_path = tmp_path / "legacy_left.xlsx"
    right_path = tmp_path / "legacy_right.xlsx"
    build_data_studio_workbook(
        file_paths=_fixture_paths(),
        output_path=left_path,
        template_id="builtin/tensile",
        group_name="Legacy Left",
    )
    build_data_studio_workbook(
        file_paths=_fixture_paths(),
        output_path=right_path,
        template_id="builtin/tensile",
        group_name="Legacy Right",
    )

    bundle_dir, comparison_workbook_path, _, _ = tensile_builtin.export_tensile_comparison_bundle(
        [left_path, right_path],
        tmp_path / "legacy_exports",
    )

    imported = import_data_studio_workbooks(comparison_workbook_path)

    assert bundle_dir.exists()
    assert [workbook.workbook_path for workbook in imported] == [left_path, right_path]
    assert [workbook.label for workbook in imported] == ["Legacy Left", "Legacy Right"]


def test_import_data_studio_workbooks_recovers_groups_when_comparison_metadata_is_missing(tmp_path: Path) -> None:
    left_path = tmp_path / "missing_meta_left.xlsx"
    right_path = tmp_path / "missing_meta_right.xlsx"
    build_data_studio_workbook(
        file_paths=_fixture_paths(),
        output_path=left_path,
        template_id="builtin/tensile",
        group_name="Missing Meta Left",
    )
    build_data_studio_workbook(
        file_paths=_fixture_paths(),
        output_path=right_path,
        template_id="builtin/tensile",
        group_name="Missing Meta Right",
    )

    comparison_set, _, _ = preview_data_studio_comparison([str(left_path), str(right_path)], "representative_curve")
    comparison_workbook_path = comparison_set.comparison_workbook_path
    _rewrite_metadata_sheet(
        comparison_workbook_path,
        [["label", "Missing Metadata Compare"]],
    )

    imported = import_data_studio_workbooks(comparison_workbook_path)

    assert [workbook.label for workbook in imported] == ["Missing Meta Left", "Missing Meta Right"]
    assert all(workbook.workbook_path != left_path for workbook in imported)
    assert all(workbook.workbook_path.exists() for workbook in imported)


def test_import_data_studio_workbooks_recovers_groups_when_source_workbooks_are_unavailable(tmp_path: Path) -> None:
    left_path = tmp_path / "broken_source_left.xlsx"
    right_path = tmp_path / "broken_source_right.xlsx"
    build_data_studio_workbook(
        file_paths=_fixture_paths(),
        output_path=left_path,
        template_id="builtin/tensile",
        group_name="Broken Source Left",
    )
    build_data_studio_workbook(
        file_paths=_fixture_paths(),
        output_path=right_path,
        template_id="builtin/tensile",
        group_name="Broken Source Right",
    )

    comparison_set, _, _ = preview_data_studio_comparison([str(left_path), str(right_path)], "representative_curve")
    comparison_workbook_path = comparison_set.comparison_workbook_path
    _rewrite_metadata_sheet(
        comparison_workbook_path,
        [
            ["label", "Broken Sources Compare"],
            ["template_id", "data_studio/comparison"],
            ["source_files", "/tmp/does_not_exist_left.xlsx | /tmp/does_not_exist_right.xlsx"],
        ],
    )

    imported = import_data_studio_workbooks(comparison_workbook_path)

    assert [workbook.label for workbook in imported] == ["Broken Source Left", "Broken Source Right"]
    assert all(workbook.workbook_path.exists() for workbook in imported)


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
        group_states=[
            DataStudioGroupState(
                workbook_path=workbook_paths[1],
                display_name="B Group",
                include_in_compare=True,
                sort_order=0,
            ),
            DataStudioGroupState(
                workbook_path=workbook_paths[0],
                display_name="A Group",
                include_in_compare=True,
                sort_order=1,
            ),
        ],
        selected_recipe_ids=["representative_curve", "strength_box"],
        figure_options_by_recipe_id={
            "representative_curve": {
                "style_preset": "default",
                "palette_preset": "colorblind_safe",
                "size": "single_panel",
            }
        },
    )

    assert exported_set.comparison_workbook_path.exists()
    assert exported_set.workbook_labels == ("B Group", "A Group")
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
            "selected_figure_family_id": "representative_curve",
            "selected_figure_template_id": "curve",
            "group_states": [
                {
                    "workbook_path": "~/tmp/prepared.xlsx",
                    "display_name": "Prepared",
                    "include_in_compare": True,
                    "sort_order": 0,
                }
            ],
            "figure_preferences": [
                {
                    "family_id": "representative_curve",
                    "selected_template_id": "curve",
                    "options_by_template": {
                        "curve": {
                            "style_preset": "default",
                            "palette_preset": "colorblind_safe",
                        }
                    },
                }
            ],
            "imported_paths": ["~/tmp/raw_a.csv"],
            "template_draft_path": "~/tmp/raw_a.csv",
        }
    )

    assert payload.selected_template_id == "builtin/tensile"
    assert payload.selected_figure_family_id == "representative_curve"
    assert payload.group_states[0].display_name == "Prepared"
    assert payload.workbook_paths[0].startswith(str(Path.home()))
    assert payload.imported_paths[0].startswith(str(Path.home()))
    assert payload.template_draft_path and payload.template_draft_path.startswith(str(Path.home()))


def test_preview_and_recommend_builds_curve_pair_for_weak_headers(tmp_path: Path) -> None:
    input_path = tmp_path / "weak_header.csv"
    input_path.write_text(
        "编号,列A,列B\n"
        ",%,MPa\n"
        "s1,0,0\n"
        "s2,0.1,4.9\n"
        "s3,0.2,11.7\n"
        "s4,0.3,16.2\n",
        encoding="utf-8",
    )

    preview, _ = preview_and_recommend(input_path)

    curve_suggestion = next((item for item in preview.binding_suggestions if item.kind == "curve_pair"), None)
    assert curve_suggestion is not None
    assert curve_suggestion.title == "Recommended Curve"
    assert "X:" in curve_suggestion.summary
    assert "Y:" in curve_suggestion.summary
    assert curve_suggestion.default_selected is True
    assert {preview_range.role for preview_range in curve_suggestion.preview_ranges} == {"x", "y"}
    assert len(curve_suggestion.candidate_ids) == 2
