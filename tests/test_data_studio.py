from __future__ import annotations

import time
from pathlib import Path

import pandas as pd
import pytest

from src.data_loader import load_curve_table, load_replicate_table
from src.data_studio import template_store
from src.data_studio.builtin import tensile as tensile_builtin
from src.data_studio.ingest import preview_and_recommend
from src.data_studio.models import DataStudioGroupState, DataStudioSpecimenState
from src.data_studio.service import (
    build_data_studio_workbook,
    create_data_studio_template,
    export_data_studio_comparison,
    import_data_studio_workbook,
    import_data_studio_workbooks,
    normalize_session_payload,
    preview_data_studio_comparison,
    preview_data_studio_comparison_context,
    preview_data_studio_workbook,
)
from src.data_studio.workbooks import load_workbook_specimen_bundle

ROOT = Path(__file__).resolve().parents[1]
FIXTURE_DIR = ROOT / "tests" / "fixtures" / "tensile_raw"


def _fixture_paths() -> list[Path]:
    return [
        FIXTURE_DIR / "BlendSet_A.csv",
        FIXTURE_DIR / "BlendSet_B.csv",
        FIXTURE_DIR / "BlendSet_bad.csv",
    ]


def _rewrite_workbook_sheets(workbook_path: Path, updates: dict[str, pd.DataFrame]) -> None:
    with pd.ExcelFile(workbook_path) as workbook:
        sheets = {
            sheet_name: pd.read_excel(workbook_path, sheet_name=sheet_name, header=None)
            for sheet_name in workbook.sheet_names
        }
    sheets.update(updates)
    with pd.ExcelWriter(workbook_path) as writer:
        for sheet_name, dataframe in sheets.items():
            dataframe.to_excel(writer, sheet_name=sheet_name, header=False, index=False)


def _rewrite_metadata_sheet(workbook_path: Path, rows: list[list[object]]) -> None:
    _rewrite_workbook_sheets(
        workbook_path,
        {tensile_builtin.METADATA_SHEET: pd.DataFrame(rows)},
    )


def _write_specimen_filter_workbook(path: Path, *, label: str = "Specimen Filter") -> Path:
    specimen_rows = [
        ("sample_1.csv", 80.0, 30.0, 5.0),
        ("sample_2.csv", 98.0, 48.0, 9.8),
        ("sample_3.csv", 99.0, 49.0, 9.9),
        ("sample_4.csv", 100.0, 50.0, 10.0),
        ("sample_5.csv", 101.0, 51.0, 10.1),
        ("sample_6.csv", 102.0, 52.0, 10.2),
        ("sample_7.csv", 120.0, 70.0, 15.0),
    ]
    summary_df = pd.DataFrame(
        [
            {
                "Filename": filename,
                "Strength (MPa)": strength,
                "Modulus (MPa)": modulus,
                "Elongation (%)": elongation,
            }
            for filename, strength, modulus, elongation in specimen_rows
        ]
    )
    representative_index = tensile_builtin._representative_index(summary_df)
    representative_filename = specimen_rows[representative_index][0]
    representative_curve = next(
        _curve_dataframe(scale=index + 1)
        for index, (filename, *_rest) in enumerate(specimen_rows)
        if filename == representative_filename
    )
    metrics = tensile_builtin._metric_summaries(summary_df)

    with pd.ExcelWriter(path) as writer:
        tensile_builtin._curve_table_dataframe(
            ((f"{label} representative", representative_curve),)
        ).to_excel(writer, sheet_name=tensile_builtin.REPRESENTATIVE_CURVE_SHEET, header=False, index=False)
        tensile_builtin._curve_table_dataframe(
            (Path(filename).stem, _curve_dataframe(scale=index + 1))
            for index, (filename, *_rest) in enumerate(specimen_rows)
        ).to_excel(writer, sheet_name=tensile_builtin.ALL_CURVES_SHEET, header=False, index=False)
        tensile_builtin._summary_sheet_dataframe(
            summary_df,
            representative_filename,
            metrics,
        ).to_excel(writer, sheet_name=tensile_builtin.SUMMARY_SHEET, header=False, index=False)
        tensile_builtin._plain_table_dataframe(summary_df).to_excel(
            writer,
            sheet_name=tensile_builtin.ALL_SPECIMENS_SHEET,
            header=False,
            index=False,
        )
        for metric in metrics:
            tensile_builtin._replicate_table_dataframe(
                group_name=label,
                value_label=metric.label,
                value_unit=metric.unit,
                values=summary_df[f"{metric.label} ({metric.unit})"].dropna().tolist(),
            ).to_excel(writer, sheet_name=f"{metric.label}_Replicates", header=False, index=False)
        tensile_builtin._metadata_sheet_dataframe(
            label=label,
            source_files=[path.with_name(filename) for filename, *_rest in specimen_rows],
            warnings=[],
            template_id=tensile_builtin.TENSILE_TEMPLATE_ID,
        ).to_excel(writer, sheet_name=tensile_builtin.METADATA_SHEET, header=False, index=False)
    return path


def _curve_dataframe(*, scale: int) -> pd.DataFrame:
    x_values = [0.0, 5.0, 10.0, 15.0]
    return pd.DataFrame(
        {
            "x": x_values,
            "y": [value * float(scale) for value in (0.0, 1.0, 2.0, 2.6)],
        }
    )


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


def test_preview_workbook_recovers_tensile_curves_from_source_files_when_workbook_curve_sheet_is_stale(
    tmp_path: Path,
) -> None:
    output_path = tmp_path / "blendset.xlsx"
    source_paths = [FIXTURE_DIR / "BlendSet_A.csv", FIXTURE_DIR / "BlendSet_B.csv"]
    build_data_studio_workbook(
        file_paths=source_paths,
        output_path=output_path,
        template_id="builtin/tensile",
        group_name="BlendSet",
    )

    source_max_x_by_filename = {
        path.name: float(tensile_builtin.parse_tensile_csv(path).curve["x"].max())
        for path in source_paths
    }
    original_curves = load_curve_table(output_path, sheet_name=tensile_builtin.ALL_CURVES_SHEET)
    original_representative_curve = load_curve_table(
        output_path,
        sheet_name=tensile_builtin.REPRESENTATIVE_CURVE_SHEET,
    )[0]

    _rewrite_workbook_sheets(
        output_path,
        {
            tensile_builtin.ALL_CURVES_SHEET: tensile_builtin._curve_table_dataframe(
                (
                    curve.sample,
                    curve.data.assign(x=pd.to_numeric(curve.data["x"], errors="coerce") / 2.0),
                )
                for curve in original_curves
            ),
            tensile_builtin.REPRESENTATIVE_CURVE_SHEET: tensile_builtin._curve_table_dataframe(
                (
                    (
                        original_representative_curve.sample,
                        original_representative_curve.data.assign(
                            x=pd.to_numeric(original_representative_curve.data["x"], errors="coerce") / 2.0
                        ),
                    ),
                )
            ),
        },
    )

    stored_curves = load_curve_table(output_path, sheet_name=tensile_builtin.ALL_CURVES_SHEET)
    assert max(float(curve.data["x"].max()) for curve in stored_curves) < max(source_max_x_by_filename.values())

    bundle = load_workbook_specimen_bundle(output_path)

    assert bundle.supported is True
    for specimen in bundle.specimens:
        assert specimen.curve is not None
        assert float(specimen.curve.data["x"].max()) == pytest.approx(
            source_max_x_by_filename[specimen.filename],
            rel=1e-6,
        )


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


def test_import_data_studio_workbooks_expands_tensile_comparison_bundle_exports(tmp_path: Path) -> None:
    left_path = tmp_path / "bundle_left.xlsx"
    right_path = tmp_path / "bundle_right.xlsx"
    build_data_studio_workbook(
        file_paths=_fixture_paths(),
        output_path=left_path,
        template_id="builtin/tensile",
        group_name="Bundle Left",
    )
    build_data_studio_workbook(
        file_paths=_fixture_paths(),
        output_path=right_path,
        template_id="builtin/tensile",
        group_name="Bundle Right",
    )

    bundle_dir, comparison_workbook_path, _, _ = tensile_builtin.export_tensile_comparison_bundle(
        [left_path, right_path],
        tmp_path / "bundle_exports",
    )

    imported = import_data_studio_workbooks(comparison_workbook_path)

    assert bundle_dir.exists()
    assert [workbook.workbook_path for workbook in imported] == [left_path, right_path]
    assert [workbook.label for workbook in imported] == ["Bundle Left", "Bundle Right"]


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

    exported_set, figure_outputs, filtered_workbooks = export_data_studio_comparison(
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
    assert [item.label for item in filtered_workbooks] == ["B Group", "A Group"]
    assert all(item.path.exists() for item in filtered_workbooks)


def test_preview_data_studio_workbook_keeps_five_closest_specimens_and_recomputes_summary(tmp_path: Path) -> None:
    workbook_path = _write_specimen_filter_workbook(tmp_path / "specimen_filter.xlsx")

    preview = preview_data_studio_workbook(workbook_path)

    assert preview.supported is True
    assert preview.total_specimen_count == 7
    assert preview.included_specimen_count == 7
    assert len(preview.suggested_exclusion_ids) == 2
    assert preview.suggestion_supported is True
    suggested_filenames = sorted(
        specimen.filename
        for specimen in preview.specimens
        if specimen.suggested_exclusion
    )
    assert suggested_filenames == ["sample_1.csv", "sample_7.csv"]
    score_by_filename = {specimen.filename: specimen for specimen in preview.specimens}
    assert score_by_filename["sample_1.csv"].auto_rule_role == "exclude"
    assert score_by_filename["sample_1.csv"].score_side == "low"
    assert score_by_filename["sample_1.csv"].eligible_for_auto_filter is True
    assert score_by_filename["sample_7.csv"].auto_rule_role == "exclude"
    assert score_by_filename["sample_7.csv"].score_side == "high"
    assert score_by_filename["sample_7.csv"].eligible_for_auto_filter is True
    assert score_by_filename["sample_4.csv"].auto_rule_role == "keep"
    assert score_by_filename["sample_1.csv"].distance_from_mean_score is not None
    assert score_by_filename["sample_7.csv"].distance_from_mean_score is not None
    assert (
        score_by_filename["sample_7.csv"].distance_from_mean_score
        > score_by_filename["sample_3.csv"].distance_from_mean_score
    )

    specimen_states = [
        DataStudioSpecimenState(
            workbook_path=str(workbook_path),
            specimen_id=specimen_id,
            included=False,
        )
        for specimen_id in preview.suggested_exclusion_ids
    ]
    filtered = preview_data_studio_workbook(workbook_path, specimen_states=specimen_states)

    assert filtered.included_specimen_count == 5
    assert filtered.excluded_specimen_count == 2
    assert filtered.representative_filename == "sample_4.csv"
    strength_metric = next(metric for metric in filtered.metrics if metric.label == "Strength")
    modulus_metric = next(metric for metric in filtered.metrics if metric.label == "Modulus")
    elongation_metric = next(metric for metric in filtered.metrics if metric.label == "Elongation")
    assert strength_metric.mean == pytest.approx(100.0)
    assert modulus_metric.mean == pytest.approx(50.0)
    assert elongation_metric.mean == pytest.approx(10.0)
    assert filtered.suggested_exclusion_ids == ()
    assert filtered.suggestion_supported is True
    assert filtered.suggestion_support_reason == ""
    filtered_scores = {specimen.filename: specimen for specimen in filtered.specimens}
    assert filtered_scores["sample_1.csv"].eligible_for_auto_filter is False
    assert filtered_scores["sample_1.csv"].auto_rule_role == "ineligible"


def test_export_data_studio_comparison_filters_specimens_before_replicate_bundle(tmp_path: Path) -> None:
    workbook_path = _write_specimen_filter_workbook(tmp_path / "specimen_filter_compare.xlsx")
    preview = preview_data_studio_workbook(workbook_path)
    specimen_states = [
        DataStudioSpecimenState(
            workbook_path=str(workbook_path),
            specimen_id=specimen_id,
            included=False,
        )
        for specimen_id in preview.suggested_exclusion_ids
    ]

    comparison_set, figure_outputs, filtered_workbooks = export_data_studio_comparison(
        [str(workbook_path)],
        tmp_path / "filtered_exports",
        specimen_states=specimen_states,
        selected_recipe_ids=["representative_curve", "strength_box"],
    )

    assert comparison_set.comparison_workbook_path.exists()
    assert {output.recipe_id for output in figure_outputs} == {"representative_curve", "strength_box"}
    assert len(filtered_workbooks) == 1
    assert filtered_workbooks[0].path.exists()
    strength_groups = load_replicate_table(
        comparison_set.comparison_workbook_path,
        sheet_name="Strength_Replicates",
    )
    assert len(strength_groups) == 1
    assert strength_groups[0].data.tolist() == pytest.approx([98.0, 99.0, 100.0, 101.0, 102.0])


def test_preview_data_studio_workbook_respects_manual_representative_selection(tmp_path: Path) -> None:
    workbook_path = _write_specimen_filter_workbook(tmp_path / "specimen_filter_manual_rep.xlsx")
    preview = preview_data_studio_workbook(workbook_path)
    specimen_ids_by_filename = {specimen.filename: specimen.specimen_id for specimen in preview.specimens}
    specimen_states = [
        DataStudioSpecimenState(
            workbook_path=str(workbook_path),
            specimen_id=specimen_id,
            included=False,
        )
        for specimen_id in preview.suggested_exclusion_ids
    ]
    specimen_states.append(
        DataStudioSpecimenState(
            workbook_path=str(workbook_path),
            specimen_id=specimen_ids_by_filename["sample_2.csv"],
            included=True,
            selected_as_representative=True,
        )
    )

    filtered = preview_data_studio_workbook(workbook_path, specimen_states=specimen_states)

    assert filtered.included_specimen_count == 5
    assert filtered.representative_specimen_id == specimen_ids_by_filename["sample_2.csv"]
    assert filtered.representative_filename == "sample_2.csv"


def test_export_data_studio_comparison_uses_manual_representative_curve_selection(tmp_path: Path) -> None:
    workbook_path = _write_specimen_filter_workbook(tmp_path / "specimen_filter_manual_rep_export.xlsx")
    preview = preview_data_studio_workbook(workbook_path)
    specimen_ids_by_filename = {specimen.filename: specimen.specimen_id for specimen in preview.specimens}
    specimen_states = [
        DataStudioSpecimenState(
            workbook_path=str(workbook_path),
            specimen_id=specimen_id,
            included=False,
        )
        for specimen_id in preview.suggested_exclusion_ids
    ]
    specimen_states.append(
        DataStudioSpecimenState(
            workbook_path=str(workbook_path),
            specimen_id=specimen_ids_by_filename["sample_2.csv"],
            included=True,
            selected_as_representative=True,
        )
    )

    comparison_set, figure_outputs, filtered_workbooks = export_data_studio_comparison(
        [str(workbook_path)],
        tmp_path / "manual_rep_exports",
        specimen_states=specimen_states,
        selected_recipe_ids=["representative_curve"],
    )

    assert {output.recipe_id for output in figure_outputs} == {"representative_curve"}
    assert len(filtered_workbooks) == 1
    summary_sheet = pd.read_excel(
        comparison_set.comparison_workbook_path,
        sheet_name=tensile_builtin.SUMMARY_SHEET,
        header=None,
    )
    assert summary_sheet.iloc[1, 2] == "sample_2"
    representative_curves = load_curve_table(
        comparison_set.comparison_workbook_path,
        sheet_name=tensile_builtin.REPRESENTATIVE_CURVE_SHEET,
    )
    assert len(representative_curves) == 1
    assert representative_curves[0].data["y"].tolist() == pytest.approx([0.0, 2.0, 4.0, 5.2])


def test_export_data_studio_comparison_writes_filtered_workbook_with_two_decimal_data(tmp_path: Path) -> None:
    workbook_path = _write_specimen_filter_workbook(tmp_path / "specimen_filter_filtered_workbook.xlsx")
    preview = preview_data_studio_workbook(workbook_path)
    specimen_ids_by_filename = {specimen.filename: specimen.specimen_id for specimen in preview.specimens}
    specimen_states = [
        DataStudioSpecimenState(
            workbook_path=str(workbook_path),
            specimen_id=specimen_id,
            included=False,
        )
        for specimen_id in preview.suggested_exclusion_ids
    ]
    specimen_states.append(
        DataStudioSpecimenState(
            workbook_path=str(workbook_path),
            specimen_id=specimen_ids_by_filename["sample_2.csv"],
            included=True,
            selected_as_representative=True,
        )
    )

    _comparison_set, _figure_outputs, filtered_workbooks = export_data_studio_comparison(
        [str(workbook_path)],
        tmp_path / "filtered_bundle",
        specimen_states=specimen_states,
        selected_recipe_ids=["representative_curve"],
    )

    assert len(filtered_workbooks) == 1
    filtered_workbook = filtered_workbooks[0]
    assert filtered_workbook.label == "Specimen Filter"
    assert filtered_workbook.source_workbook_path == workbook_path
    assert filtered_workbook.representative_filename == "sample_2.csv"
    assert filtered_workbook.path.exists()

    reimported = import_data_studio_workbook(filtered_workbook.path)
    assert reimported.label == "Specimen Filter"
    assert reimported.representative_filename == "sample_2.csv"
    assert reimported.parsed_sample_count == 5

    filtered_preview = preview_data_studio_workbook(filtered_workbook.path)
    assert filtered_preview.included_specimen_count == 5
    assert filtered_preview.representative_filename == "sample_2.csv"

    specimen_sheet = pd.read_excel(
        filtered_workbook.path,
        sheet_name=tensile_builtin.ALL_SPECIMENS_SHEET,
        header=None,
        dtype=str,
    ).fillna("")
    assert specimen_sheet.iloc[1:, 0].tolist() == [
        "sample_2.csv",
        "sample_3.csv",
        "sample_4.csv",
        "sample_5.csv",
        "sample_6.csv",
    ]
    assert specimen_sheet.iloc[1, 1] == "98.00"
    assert specimen_sheet.iloc[4, 3] == "10.10"

    summary_sheet = pd.read_excel(
        filtered_workbook.path,
        sheet_name=tensile_builtin.SUMMARY_SHEET,
        header=None,
        dtype=str,
    ).fillna("")
    assert summary_sheet.iloc[1, 2] == "100.00"
    assert summary_sheet.iloc[1, 3] == "1.58"
    assert summary_sheet.iloc[1, 4] == "sample_2.csv"

    representative_curve_sheet = pd.read_excel(
        filtered_workbook.path,
        sheet_name=tensile_builtin.REPRESENTATIVE_CURVE_SHEET,
        header=None,
        dtype=str,
    ).fillna("")
    assert representative_curve_sheet.iloc[3, 0] == "0.00"
    assert representative_curve_sheet.iloc[4, 1] == "2.00"

    metadata = tensile_builtin.load_metadata_sheet(filtered_workbook.path)
    assert metadata["export_mode"] == "filtered"
    assert metadata["filtered_from_workbook_path"] == str(workbook_path)
    assert metadata["representative_specimen_id"] == specimen_ids_by_filename["sample_2.csv"]
    assert set(metadata["included_specimen_ids"].split(" | ")) == {
        specimen_ids_by_filename["sample_2.csv"],
        specimen_ids_by_filename["sample_3.csv"],
        specimen_ids_by_filename["sample_4.csv"],
        specimen_ids_by_filename["sample_5.csv"],
        specimen_ids_by_filename["sample_6.csv"],
    }
    assert set(Path(item).name for item in metadata["source_files"]) == {
        "sample_2.csv",
        "sample_3.csv",
        "sample_4.csv",
        "sample_5.csv",
        "sample_6.csv",
    }


def test_preview_data_studio_workbook_disables_auto_keep_when_fewer_than_five_eligible(tmp_path: Path) -> None:
    workbook_path = _write_specimen_filter_workbook(tmp_path / "specimen_filter_under_five.xlsx")
    preview = preview_data_studio_workbook(workbook_path)
    specimen_ids_by_filename = {specimen.filename: specimen.specimen_id for specimen in preview.specimens}
    specimen_states = [
        DataStudioSpecimenState(
            workbook_path=str(workbook_path),
            specimen_id=specimen_id,
            included=False,
        )
        for specimen_id in (
            specimen_ids_by_filename["sample_1.csv"],
            specimen_ids_by_filename["sample_6.csv"],
            specimen_ids_by_filename["sample_7.csv"],
        )
    ]

    filtered = preview_data_studio_workbook(workbook_path, specimen_states=specimen_states)

    assert filtered.included_specimen_count == 4
    assert filtered.suggestion_supported is False
    assert filtered.suggested_exclusion_ids == ()
    assert "Auto Keep 5 needs at least 5 included specimens" in filtered.suggestion_support_reason


def test_preview_data_studio_comparison_context_uses_stable_cache_key_without_rendering(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    workbook_path = _write_specimen_filter_workbook(tmp_path / "specimen_filter_context.xlsx")
    preview = preview_data_studio_workbook(workbook_path)
    specimen_states = [
        DataStudioSpecimenState(
            workbook_path=str(workbook_path),
            specimen_id=specimen_id,
            included=False,
        )
        for specimen_id in preview.suggested_exclusion_ids
    ]

    def fail_render(*args: object, **kwargs: object) -> None:
        raise AssertionError("comparison-context should not render preview PDFs")

    monkeypatch.setattr("src.data_studio.comparison.build_rendered_plots", fail_render)

    first = preview_data_studio_comparison_context(
        [str(workbook_path)],
        specimen_states=specimen_states,
    )
    second = preview_data_studio_comparison_context(
        [str(workbook_path)],
        specimen_states=specimen_states,
    )
    restored = preview_data_studio_comparison_context([str(workbook_path)])

    assert first.cache_key == second.cache_key
    assert first.comparison_set.comparison_workbook_path == second.comparison_set.comparison_workbook_path
    assert first.comparison_set.comparison_workbook_path.exists()
    assert restored.cache_key != first.cache_key
    assert restored.comparison_set.comparison_workbook_path != first.comparison_set.comparison_workbook_path


def test_preview_data_studio_comparison_context_invalidates_on_workbook_mtime(tmp_path: Path) -> None:
    workbook_path = _write_specimen_filter_workbook(tmp_path / "mtime_context.xlsx")

    first = preview_data_studio_comparison_context([str(workbook_path)])
    assert first.cache_key
    time.sleep(0.01)
    workbook_path.touch()

    second = preview_data_studio_comparison_context([str(workbook_path)])
    assert second.cache_key
    assert second.cache_key != first.cache_key


def test_preview_data_studio_comparison_context_avoids_duplicate_workbook_imports(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    left = _write_specimen_filter_workbook(tmp_path / "left_import_count.xlsx", label="Left")
    right = _write_specimen_filter_workbook(tmp_path / "right_import_count.xlsx", label="Right")

    from src.data_studio import comparison as comparison_module
    from src.data_studio.workbooks import import_workbook as real_import_workbook

    call_paths: list[str] = []

    def tracked_import(path: str | Path):
        call_paths.append(str(Path(path).expanduser()))
        return real_import_workbook(path)

    monkeypatch.setattr(comparison_module, "import_workbook", tracked_import)

    preview_data_studio_comparison_context([str(left), str(right)])
    assert len(call_paths) == 2
    assert sorted(Path(path).name for path in call_paths) == [
        left.name,
        right.name,
    ]


def test_preview_data_studio_comparison_reuses_cached_pdf_for_same_context(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    workbook_path = _write_specimen_filter_workbook(tmp_path / "comparison_preview_cache.xlsx")
    first_set, first_recipe, first_pdf = preview_data_studio_comparison(
        [str(workbook_path)],
        "representative_curve",
    )

    def fail_render(*args: object, **kwargs: object) -> None:
        raise AssertionError("comparison-preview should reuse cached PDF for an unchanged context")

    monkeypatch.setattr("src.data_studio.comparison.build_rendered_plots", fail_render)

    second_set, second_recipe, second_pdf = preview_data_studio_comparison(
        [str(workbook_path)],
        "representative_curve",
    )

    assert first_recipe.id == second_recipe.id
    assert first_set.comparison_workbook_path == second_set.comparison_workbook_path
    assert second_pdf == first_pdf


def test_preview_data_studio_comparison_cache_invalidates_on_specimen_state_change(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    workbook_path = _write_specimen_filter_workbook(tmp_path / "comparison_preview_cache_invalidation.xlsx")
    workbook_preview = preview_data_studio_workbook(workbook_path)
    assert workbook_preview.suggested_exclusion_ids

    preview_data_studio_comparison(
        [str(workbook_path)],
        "representative_curve",
    )

    from src.data_studio import comparison as comparison_module

    call_count = 0
    real_build_rendered_plots = comparison_module.build_rendered_plots

    def tracked_build_rendered_plots(*args: object, **kwargs: object):
        nonlocal call_count
        call_count += 1
        return real_build_rendered_plots(*args, **kwargs)

    monkeypatch.setattr(comparison_module, "build_rendered_plots", tracked_build_rendered_plots)

    specimen_states = [
        DataStudioSpecimenState(
            workbook_path=str(workbook_path),
            specimen_id=workbook_preview.suggested_exclusion_ids[0],
            included=False,
        )
    ]
    preview_data_studio_comparison(
        [str(workbook_path)],
        "representative_curve",
        specimen_states=specimen_states,
    )

    assert call_count == 1


def test_preview_data_studio_comparison_context_cache_invalidates_on_manual_representative_change(
    tmp_path: Path,
) -> None:
    workbook_path = _write_specimen_filter_workbook(tmp_path / "comparison_manual_rep_cache.xlsx")
    preview = preview_data_studio_workbook(workbook_path)
    specimen_ids_by_filename = {specimen.filename: specimen.specimen_id for specimen in preview.specimens}

    first = preview_data_studio_comparison_context(
        [str(workbook_path)],
        specimen_states=[
            DataStudioSpecimenState(
                workbook_path=str(workbook_path),
                specimen_id=specimen_ids_by_filename["sample_2.csv"],
                selected_as_representative=True,
            )
        ],
    )
    second = preview_data_studio_comparison_context(
        [str(workbook_path)],
        specimen_states=[
            DataStudioSpecimenState(
                workbook_path=str(workbook_path),
                specimen_id=specimen_ids_by_filename["sample_3.csv"],
                selected_as_representative=True,
            )
        ],
    )

    assert first.cache_key != second.cache_key


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
            "specimen_states": [
                {
                    "workbook_path": "~/tmp/prepared.xlsx",
                    "specimen_id": "sample_1csv",
                    "included": False,
                    "selected_as_representative": True,
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
    assert payload.specimen_states[0].specimen_id == "sample_1csv"
    assert payload.specimen_states[0].included is False
    assert payload.specimen_states[0].selected_as_representative is True
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
