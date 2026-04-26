from __future__ import annotations

from pathlib import Path

import pandas as pd
import pytest

from src.data_loader import load_curve_table, load_replicate_table
from src.data_studio.comparison import comparison_recipes_for_workbooks
from src.data_studio.import_templates_v2 import preview_template_apply
from src.data_studio.models import (
    TemplateDefinition,
    TemplateFieldBinding,
    TemplateSegmentSelector,
    TemplateSourceFormat,
)
from src.data_studio.service import build_data_studio_workbook, list_data_studio_template_recommendations
from src.data_studio.template_store import save_template
from src.rendering.source_table_preview import source_table_preview

FIXTURE_ROOT = Path(__file__).resolve().parent / "fixtures" / "data_studio_import_v2"
RHEOLOGY_ROOT = FIXTURE_ROOT / "rheology"


def _rheology_template(
    *,
    template_id: str,
    label: str,
    result_label: str,
    x_label: str,
    y_labels: tuple[str, ...],
    output_kind: str = "curve_metrics",
    comparison_enabled: bool = True,
) -> TemplateDefinition:
    return TemplateDefinition(
        version=2,
        id=template_id,
        label=label,
        family="table_import",
        builtin=False,
        description="Fixture import template.",
        file_types=("csv",),
        parse_strategy="table_template_v2",
        field_bindings=(
            TemplateFieldBinding(
                id="x",
                role="curve_x",
                label=x_label,
                column_name=x_label,
            ),
            *(
                TemplateFieldBinding(
                    id=f"y_{index}",
                    role="curve_y",
                    label=y_label,
                    column_name=y_label,
                    optional=index > 0,
                )
                for index, y_label in enumerate(y_labels)
            ),
        ),
        output_kind=output_kind,
        comparison_enabled=comparison_enabled,
        source_format=TemplateSourceFormat(encoding="utf-16", delimiter="\t", sheet_name="Sheet1"),
        segment_policy="series_per_segment",
        segment_selectors=(
            TemplateSegmentSelector(
                id="Sheet1::segment1",
                label=result_label,
                result_label=result_label,
                interval_index=1,
            ),
        ),
    )


@pytest.mark.parametrize(
    ("filename", "segment_count", "x_label", "y_label"),
    [
        ("PA_240.csv", 1, "Angular Frequency", "Storage Modulus"),
        ("S-PA.csv", 2, "Temperature", "Storage Modulus"),
        ("SD-PA_240.csv", 1, "Time", "Relaxation Modulus"),
        ("D-PA.csv", 4, "Time", "Creep Compliance"),
    ],
)
def test_source_table_preview_detects_utf16_tab_rheology_segments(
    filename: str,
    segment_count: int,
    x_label: str,
    y_label: str,
) -> None:
    preview = source_table_preview(RHEOLOGY_ROOT / filename)

    assert preview.encoding == "utf-16"
    assert preview.delimiter == "\t"
    assert len(preview.segments) == segment_count

    segment_preview = source_table_preview(
        RHEOLOGY_ROOT / filename,
        segment_id=preview.segments[0].id,
    )
    assert x_label in segment_preview.candidate_roles.x
    assert y_label in segment_preview.candidate_roles.y


def test_template_preview_parses_frequency_sweep_standard_roles() -> None:
    template = _rheology_template(
        template_id="user/rheology_frequency",
        label="Rheology Frequency",
        result_label="Frequency sweep 1",
        x_label="Angular Frequency",
        y_labels=("Storage Modulus", "Loss Modulus"),
        comparison_enabled=False,
    )

    preview = preview_template_apply(RHEOLOGY_ROOT / "PA_240.csv", template)

    assert preview.errors == ()
    assert preview.series_count == 2
    assert preview.segments[0].label == "Frequency sweep 1 / Interval 1"


def test_template_preview_reports_missing_required_roles() -> None:
    template = _rheology_template(
        template_id="user/bad",
        label="Bad",
        result_label="Frequency sweep 1",
        x_label="Angular Frequency",
        y_labels=(),
        comparison_enabled=False,
    )

    preview = preview_template_apply(RHEOLOGY_ROOT / "PA_240.csv", template)

    assert preview.missing_roles == ("curve_y",)
    assert preview.errors


def test_v2_template_builds_curve_workbook_from_rheology_fixture(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from src.data_studio import template_store

    monkeypatch.setattr(template_store, "USER_TEMPLATE_DIR", tmp_path / "templates" / "user")
    template = _rheology_template(
        template_id="user/rheology_frequency",
        label="Rheology Frequency",
        result_label="Frequency sweep 1",
        x_label="Angular Frequency",
        y_labels=("Storage Modulus", "Loss Modulus"),
    )
    save_template(template)

    workbook = build_data_studio_workbook(
        file_paths=[RHEOLOGY_ROOT / "PA_240.csv"],
        output_path=tmp_path / "frequency.xlsx",
        template_id=template.id,
        group_name="Frequency",
    )

    assert workbook.template_match.template_id == template.id
    assert workbook.parsed_sample_count == 1
    assert "DataStudio_Metadata" not in workbook.sheet_names
    curves = load_curve_table(workbook.workbook_path, sheet_name="Representative_Curve")
    assert curves[0].sample == "PA_240"
    assert curves[0].x_label == "ω"
    assert curves[0].y_label == "G'"
    assert curves[0].x_unit == r"rad$\cdot$s$^{-1}$"
    assert curves[0].y_unit == "Pa"


def test_v2_template_builds_curve_only_workbook_when_comparison_disabled(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from src.data_studio import template_store

    monkeypatch.setattr(template_store, "USER_TEMPLATE_DIR", tmp_path / "templates" / "user")
    template = _rheology_template(
        template_id="user/rheology_curve_only",
        label="Rheology Curve Only",
        result_label="Frequency sweep 1",
        x_label="Angular Frequency",
        y_labels=("Storage Modulus", "Loss Modulus"),
        comparison_enabled=False,
    )
    save_template(template)

    workbook = build_data_studio_workbook(
        file_paths=[RHEOLOGY_ROOT / "PA_240.csv"],
        output_path=tmp_path / "curve_only.xlsx",
        template_id=template.id,
        group_name="Curve Only",
    )

    assert workbook.preferred_sheet == "All_Curves"
    assert "DataStudio_Metadata" not in workbook.sheet_names
    assert "All_Curves" in workbook.sheet_names
    assert "Representative_Curve" not in workbook.sheet_names
    assert "All_Specimens" not in workbook.sheet_names
    assert not workbook.metrics
    all_curves = load_curve_table(workbook.workbook_path, sheet_name="All_Curves")
    assert len(all_curves) == 2

    recipes = comparison_recipes_for_workbooks([workbook.workbook_path])
    unsupported = {recipe.id: recipe for recipe in recipes if not recipe.supported}
    assert unsupported["representative_curve"].support_reason
    assert unsupported["metric_bar"].support_reason


def test_v2_template_builds_metric_only_workbook(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from src.data_studio import template_store

    monkeypatch.setattr(template_store, "USER_TEMPLATE_DIR", tmp_path / "templates" / "user")
    template = TemplateDefinition(
        version=2,
        id="user/rheology_frequency_metric",
        label="Rheology Frequency Metric",
        family="table_import",
        builtin=False,
        description="Fixture metric import template.",
        file_types=("csv",),
        parse_strategy="table_template_v2",
        field_bindings=(
            TemplateFieldBinding(
                id="metric_complex_viscosity",
                role="metric",
                label="Complex Viscosity (mPa·s)",
                column_name="Complex Viscosity",
            ),
        ),
        output_kind="metric_table",
        source_format=TemplateSourceFormat(encoding="utf-16", delimiter="\t", sheet_name="Sheet1"),
        segment_policy="series_per_segment",
        segment_selectors=(
            TemplateSegmentSelector(
                id="Sheet1::segment1",
                label="Frequency sweep 1",
                result_label="Frequency sweep 1",
                interval_index=1,
            ),
        ),
    )
    save_template(template)

    workbook = build_data_studio_workbook(
        file_paths=[RHEOLOGY_ROOT / "PA_240.csv"],
        output_path=tmp_path / "metric.xlsx",
        template_id=template.id,
        group_name="Frequency Metric",
    )

    assert "Representative_Curve" not in workbook.sheet_names
    assert "Complex Viscosity_Replicates" in workbook.sheet_names
    assert "DataStudio_Metadata" not in workbook.sheet_names
    replicate = load_replicate_table(workbook.workbook_path, sheet_name="Complex Viscosity_Replicates")[0]
    assert replicate.value_label == "|η*|"
    assert replicate.value_unit == r"mPa$\cdot$s"


def test_v2_template_builds_matrix_heatmap_workbook_with_disabled_compare_recipes(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from src.data_studio import template_store

    matrix_path = tmp_path / "heatmap.csv"
    matrix_path.write_text(
        "Temperature,Frequency,Intensity\n"
        "180,1,0.12\n"
        "180,10,0.24\n"
        "200,1,0.18\n"
        "200,10,0.35\n",
        encoding="utf-8",
    )
    monkeypatch.setattr(template_store, "USER_TEMPLATE_DIR", tmp_path / "templates" / "user")
    template = TemplateDefinition(
        version=2,
        id="user/matrix_heatmap",
        label="Matrix Heatmap",
        family="table_import",
        builtin=False,
        description="Fixture matrix import template.",
        file_types=("csv",),
        parse_strategy="table_template_v2",
        field_bindings=(
            TemplateFieldBinding(
                id="matrix_x",
                role="matrix_x",
                label="Temperature",
                column_name="Temperature",
            ),
            TemplateFieldBinding(
                id="matrix_y",
                role="matrix_y",
                label="Frequency",
                column_name="Frequency",
            ),
            TemplateFieldBinding(
                id="matrix_z",
                role="matrix_z",
                label="Intensity",
                column_name="Intensity",
            ),
        ),
        output_kind="matrix_heatmap",
        source_format=TemplateSourceFormat(encoding="utf-8", delimiter=",", sheet_name="Sheet1"),
        segment_policy="single_table",
    )
    save_template(template)

    workbook = build_data_studio_workbook(
        file_paths=[matrix_path],
        output_path=tmp_path / "heatmap.xlsx",
        template_id=template.id,
        group_name="Heatmap",
    )

    assert workbook.preferred_sheet == "Heatmap"
    assert "Heatmap" in workbook.sheet_names
    assert "DataStudio_Metadata" not in workbook.sheet_names
    recipes = comparison_recipes_for_workbooks([workbook.workbook_path])
    unsupported = {recipe.id: recipe for recipe in recipes if not recipe.supported}
    assert unsupported["representative_curve"].support_reason
    assert unsupported["metric_bar"].support_reason


def test_excel_multi_sheet_template_preview_builds_selected_sheet(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from src.data_studio import template_store

    workbook_path = tmp_path / "multi_sheet.xlsx"
    with pd.ExcelWriter(workbook_path) as writer:
        pd.DataFrame(
            [
                ["Ignore", "Noise"],
                [1, 100],
                [2, 200],
            ]
        ).to_excel(writer, sheet_name="Metadata", header=False, index=False)
        pd.DataFrame(
            [
                ["Time", "Signal", "Peak Force"],
                ["s", "a.u.", "N"],
                [0, 1.0, 10.0],
                [1, 1.5, 12.0],
                [2, 2.0, 15.0],
            ]
        ).to_excel(writer, sheet_name="Signal", header=False, index=False)

    template = TemplateDefinition(
        version=2,
        id="user/excel_signal",
        label="Excel Signal",
        family="table_import",
        builtin=False,
        description="Excel selected-sheet fixture.",
        file_types=("xlsx",),
        parse_strategy="table_template_v2",
        field_bindings=(
            TemplateFieldBinding(id="x", role="curve_x", label="Time", column_name="Time", unit_hint="s"),
            TemplateFieldBinding(id="y", role="curve_y", label="Signal", column_name="Signal", unit_hint="a.u."),
            TemplateFieldBinding(
                id="metric_peak",
                role="metric",
                label="Peak Force (N)",
                column_name="Peak Force",
                unit_hint="N",
            ),
        ),
        output_kind="curve_metrics",
        comparison_enabled=True,
        source_format=TemplateSourceFormat(sheet_name="Signal"),
        segment_policy="single_table",
    )

    preview = preview_template_apply(workbook_path, template)
    assert preview.errors == ()
    assert preview.parsed_sample_count == 1
    assert preview.series_count == 1
    assert preview.metric_count == 1
    assert preview.segments[0].id == "Signal::table"

    monkeypatch.setattr(template_store, "USER_TEMPLATE_DIR", tmp_path / "templates" / "user")
    save_template(template)
    workbook = build_data_studio_workbook(
        file_paths=[workbook_path],
        output_path=tmp_path / "selected_sheet.xlsx",
        template_id=template.id,
        group_name="Excel Signal",
    )

    assert workbook.preferred_sheet == "Representative_Curve"
    assert workbook.parsed_sample_count == 1
    curves = load_curve_table(workbook.workbook_path, sheet_name="Representative_Curve")
    assert curves[0].x_label == "Time"
    assert curves[0].y_label == "Signal"
    assert workbook.metrics[0].label == "Peak Force"


def test_v2_template_builds_multi_segment_curve_only_workbook_without_explicit_segment_selectors(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from src.data_studio import template_store

    monkeypatch.setattr(template_store, "USER_TEMPLATE_DIR", tmp_path / "templates" / "user")
    template = TemplateDefinition(
        version=2,
        id="user/rheology_multi_segment_curve_only",
        label="Rheology Multi Segment Curve Only",
        family="table_import",
        builtin=False,
        description="Fixture multi-segment import template.",
        file_types=("csv",),
        parse_strategy="table_template_v2",
        field_bindings=(
            TemplateFieldBinding(id="x", role="curve_x", label="Temperature", column_name="Temperature"),
            TemplateFieldBinding(id="y1", role="curve_y", label="Storage Modulus", column_name="Storage Modulus"),
            TemplateFieldBinding(
                id="y2",
                role="curve_y",
                label="Loss Modulus",
                column_name="Loss Modulus",
                optional=True,
            ),
        ),
        output_kind="curve_metrics",
        comparison_enabled=False,
        source_format=TemplateSourceFormat(encoding="utf-16", delimiter="\t", sheet_name="Sheet1"),
        segment_policy="series_per_segment",
        segment_selectors=(),
    )
    save_template(template)

    preview = preview_template_apply(RHEOLOGY_ROOT / "S-PA.csv", template)
    assert preview.errors == ()
    assert preview.series_count == 4
    assert len(preview.segments) == 2

    workbook = build_data_studio_workbook(
        file_paths=[RHEOLOGY_ROOT / "S-PA.csv"],
        output_path=tmp_path / "multi_segment.xlsx",
        template_id=template.id,
        group_name="Multi Segment",
    )

    assert workbook.preferred_sheet == "All_Curves"
    curves = load_curve_table(workbook.workbook_path, sheet_name="All_Curves")
    assert len(curves) == 4
    assert {curve.sample for curve in curves} == {"S-PA"}
    assert {curve.x_label for curve in curves} == {"Temperature"}
    assert {curve.y_label for curve in curves} == {"G'", 'G"'}


def test_unknown_source_does_not_default_to_unmatched_user_template(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from src.data_studio import template_store

    unknown_path = tmp_path / "notes.csv"
    unknown_path.write_text("note,value\nalpha,beta\n", encoding="utf-8")

    monkeypatch.setattr(template_store, "USER_TEMPLATE_DIR", tmp_path / "templates" / "user")
    template = TemplateDefinition(
        version=2,
        id="user/manual_only",
        label="Manual Only",
        family="table_import",
        builtin=False,
        description="Should not be recommended without match conditions.",
        file_types=("csv",),
        parse_strategy="table_template_v2",
        field_bindings=(
            TemplateFieldBinding(id="x", role="curve_x", label="Time", column_name="Time"),
            TemplateFieldBinding(id="y", role="curve_y", label="Signal", column_name="Signal"),
        ),
        output_kind="curve_metrics",
        comparison_enabled=False,
        source_format=TemplateSourceFormat(encoding="utf-8", delimiter=","),
        segment_policy="single_table",
        match_conditions=(),
    )
    save_template(template)

    assert list_data_studio_template_recommendations(unknown_path) == ()
