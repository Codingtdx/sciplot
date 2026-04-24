from __future__ import annotations

from pathlib import Path

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
from src.data_studio.service import build_data_studio_workbook
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
    curves = load_curve_table(workbook.workbook_path, sheet_name="Representative_Curve")
    assert curves[0].x_label == "ω"
    assert curves[0].y_label == "G'"
    assert curves[0].x_unit == r"rad$\cdot$s$^{-1}$"
    assert curves[0].y_unit == "Pa"


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
    recipes = comparison_recipes_for_workbooks([workbook.workbook_path])
    unsupported = {recipe.id: recipe for recipe in recipes if not recipe.supported}
    assert unsupported["representative_curve"].support_reason
    assert unsupported["metric_bar"].support_reason
