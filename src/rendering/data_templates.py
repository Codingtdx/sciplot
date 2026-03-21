from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from tempfile import mkdtemp

import pandas as pd

TEMPLATE_SHEET_NAME = "Template"
README_SHEET_NAME = "README"


@dataclass(frozen=True)
class DataTemplateSpec:
    id: str
    label: str
    input_model: str
    typical_families: tuple[str, ...]
    format_summary: str
    build_example: Callable[[], dict[str, pd.DataFrame]]
    build_blank: Callable[[], dict[str, pd.DataFrame]]


@dataclass(frozen=True)
class PlotTemplateFileSpec:
    chart_type: str
    label: str
    filename_stem: str
    template_id: str
    source_template_id: str


def _notes_frame(lines: list[str]) -> pd.DataFrame:
    return pd.DataFrame({"Notes": lines})


def _template_with_notes(
    rows: list[list[object]],
    *,
    notes: list[str],
) -> dict[str, pd.DataFrame]:
    return {
        TEMPLATE_SHEET_NAME: pd.DataFrame(rows),
        README_SHEET_NAME: _notes_frame(notes),
    }


def _curve_example_workbook() -> dict[str, pd.DataFrame]:
    return _template_with_notes(
        [
            ["Time", "Stress", "Time", "Stress"],
            ["s", "MPa", "s", "MPa"],
            ["Blend A", "Blend A", "Blend B", "Blend B"],
            [0.0, 0.9, 0.0, 1.2],
            [1.0, 1.3, 1.0, 1.6],
            [2.0, 1.8, 2.0, 2.0],
            [3.0, 2.0, 3.0, 2.5],
        ],
        notes=[
            "Row 1 stores axis labels in X/Y pairs.",
            "Row 2 stores axis units.",
            "Row 3 stores sample names and repeats each sample across its X/Y pair.",
            "Row 4 onward stores numeric X/Y data.",
            "Add more series by appending more X/Y column pairs.",
        ],
    )


def _curve_blank_workbook() -> dict[str, pd.DataFrame]:
    return _template_with_notes(
        [
            ["X label", "Y label"],
            ["unit", "unit"],
            ["Sample 1", "Sample 1"],
            [0.0, 0.0],
            [1.0, 1.0],
            [2.0, 2.0],
        ],
        notes=[
            "Paste your own numeric X/Y data from row 4 onward.",
            "Keep rows 1 to 3 so inspect can recognize the curve_table format.",
            "For multiple series, duplicate the X/Y column pair and repeat the sample name on row 3.",
            "This blank template is inspect-ready and can be opened in Plot as-is.",
        ],
    )


def _tensile_example_workbook() -> dict[str, pd.DataFrame]:
    return _template_with_notes(
        [
            ["Strain", "Stress", "Strain", "Stress"],
            ["%", "MPa", "%", "MPa"],
            ["Specimen A", "Specimen A", "Specimen B", "Specimen B"],
            [0.0, 0.0, 0.0, 0.0],
            [2.0, 8.2, 2.0, 7.6],
            [4.0, 15.4, 4.0, 14.5],
            [6.0, 19.8, 6.0, 18.9],
            [8.0, 17.1, 8.0, 16.4],
        ],
        notes=[
            "Use tensile stress-strain headers so inspect keeps the tensile_curve model.",
            "Tensile curves always stay on linear x/y scales in SciPlot God.",
            "Paste additional specimens as extra X/Y column pairs.",
        ],
    )


def _tensile_blank_workbook() -> dict[str, pd.DataFrame]:
    return _template_with_notes(
        [
            ["Strain", "Stress"],
            ["%", "MPa"],
            ["Specimen 1", "Specimen 1"],
            [0.0, 0.0],
            [1.0, 4.0],
            [2.0, 7.5],
        ],
        notes=[
            "Replace the placeholder values with your own tensile stress-strain data.",
            "Keep the first three rows intact so inspect recognizes the tensile_curve format.",
            "Add more specimens by appending more Strain/Stress column pairs.",
            "This blank template is inspect-ready and can be imported into Plot directly.",
        ],
    )


def _replicate_example_workbook() -> dict[str, pd.DataFrame]:
    return _template_with_notes(
        [
            ["Strength", "", ""],
            ["Blend A", "Blend B", "Blend C"],
            ["MPa", "MPa", "MPa"],
            [28.1, 31.0, 26.4],
            [27.4, 30.2, 25.7],
            [29.0, 30.8, 26.9],
            [28.4, 31.3, 26.1],
        ],
        notes=[
            "Cell A1 stores the shared y-axis label.",
            "Row 2 stores group names.",
            "Row 3 stores units.",
            "Row 4 onward stores replicate values, one group per column.",
        ],
    )


def _replicate_blank_workbook() -> dict[str, pd.DataFrame]:
    return _template_with_notes(
        [
            ["Response", ""],
            ["Group 1", "Group 2"],
            ["unit", "unit"],
            [1.0, 1.2],
            [1.1, 1.3],
            [0.9, 1.4],
        ],
        notes=[
            "Paste replicate values under each group column from row 4 onward.",
            "Keep A1 as the shared y-axis label, row 2 as group names, and row 3 as units.",
            "Add more groups by appending columns.",
            "This blank template is inspect-ready for bar, box, and violin families.",
        ],
    )


def _heatmap_example_workbook() -> dict[str, pd.DataFrame]:
    return _template_with_notes(
        [
            ["X", "Y", "Z"],
            ["Temperature", "Time", "Intensity"],
            ["degC", "min", "a.u."],
            [25.0, 0.0, 0.18],
            [25.0, 5.0, 0.31],
            [40.0, 0.0, 0.46],
            [40.0, 5.0, 0.63],
            [55.0, 0.0, 0.77],
            [55.0, 5.0, 0.92],
        ],
        notes=[
            "Row 1 must stay as semantic roles X, Y, and Z.",
            "Row 2 stores display labels.",
            "Row 3 stores units.",
            "Row 4 onward stores long-form heatmap rows.",
        ],
    )


def _heatmap_blank_workbook() -> dict[str, pd.DataFrame]:
    return _template_with_notes(
        [
            ["X", "Y", "Z"],
            ["X label", "Y label", "Z label"],
            ["unit", "unit", "unit"],
            [0.0, 0.0, 1.0],
            [0.0, 1.0, 2.0],
            [1.0, 0.0, 3.0],
            [1.0, 1.0, 4.0],
        ],
        notes=[
            "Keep row 1 exactly as X, Y, Z.",
            "Replace row 2 labels, row 3 units, and rows 4+ with your own long-form heatmap data.",
            "Each row after row 3 should contain one X/Y/Z coordinate triplet.",
            "This blank template is inspect-ready for the heatmap family.",
        ],
    )


def _frequency_example_workbook() -> dict[str, pd.DataFrame]:
    return _template_with_notes(
        [
            ["Angular Frequency", "Storage Modulus", "Loss Modulus", "Loss Factor", "Complex Viscosity"],
            ["Blend A", "", "", "", ""],
            ["rad/s", "Pa", "Pa", "", "Pa*s"],
            [0.1, 1200, 180, 0.15, 5600],
            [1.0, 2100, 320, 0.15, 2100],
            [10.0, 3900, 710, 0.18, 820],
        ],
        notes=[
            "Frequency sweep templates use 5 columns per sample block.",
            "The first column in each block is Angular Frequency.",
            "Columns 2 to 5 store Storage Modulus, Loss Modulus, Loss Factor, and Complex Viscosity.",
            "Add more sample blocks by appending another set of 5 columns.",
        ],
    )


def _frequency_blank_workbook() -> dict[str, pd.DataFrame]:
    return _template_with_notes(
        [
            ["Angular Frequency", "Storage Modulus", "Loss Modulus", "Loss Factor", "Complex Viscosity"],
            ["Sample 1", "", "", "", ""],
            ["rad/s", "Pa", "Pa", "", "Pa*s"],
            [0.1, 1000, 120, 0.12, 4800],
            [1.0, 1800, 220, 0.12, 1800],
            [10.0, 3200, 520, 0.16, 650],
        ],
        notes=[
            "Replace the placeholder numeric rows with your own frequency sweep export values.",
            "Keep the first three rows intact so inspect recognizes the frequency_sweep bundle.",
            "Add more samples by appending another 5-column block.",
            "This blank template is inspect-ready for point_line and curve families.",
        ],
    )


def _temperature_example_workbook() -> dict[str, pd.DataFrame]:
    return _template_with_notes(
        [
            ["Temperature", "Storage Modulus", "Loss Modulus", "Loss Factor", "Complex Viscosity"],
            ["Blend A", "", "", "", ""],
            ["degC", "Pa", "Pa", "", "Pa*s"],
            [25.0, 5200, 640, 0.12, 8100],
            [50.0, 3600, 500, 0.14, 4200],
            [75.0, 2200, 380, 0.17, 2100],
        ],
        notes=[
            "Temperature sweep templates also use 5 columns per sample block.",
            "The first column in each block is Temperature.",
            "SciPlot God currently exports Storage Modulus and Complex Viscosity from this bundle.",
        ],
    )


def _temperature_blank_workbook() -> dict[str, pd.DataFrame]:
    return _template_with_notes(
        [
            ["Temperature", "Storage Modulus", "Loss Modulus", "Loss Factor", "Complex Viscosity"],
            ["Sample 1", "", "", "", ""],
            ["degC", "Pa", "Pa", "", "Pa*s"],
            [25.0, 5000, 620, 0.12, 7900],
            [50.0, 3300, 490, 0.15, 3900],
            [75.0, 2100, 360, 0.17, 1900],
        ],
        notes=[
            "Replace the placeholder numeric rows with your own temperature sweep export values.",
            "Keep the first three rows intact so inspect recognizes the temperature_sweep bundle.",
            "Add more samples by appending another 5-column block.",
            "This blank template is inspect-ready for point_line and curve families.",
        ],
    )


def _stress_relaxation_example_workbook() -> dict[str, pd.DataFrame]:
    return _template_with_notes(
        [
            ["Time", "Strain", "Stress", "sigma/sigma0"],
            ["Blend A", "", "", ""],
            ["s", "%", "Pa", ""],
            [0.0, 5.0, 2200, 1.0],
            [10.0, 5.0, 1800, 0.82],
            [20.0, 5.0, 1500, 0.68],
            [40.0, 5.0, 1200, 0.55],
        ],
        notes=[
            "Stress relaxation templates use 4 columns per sample block.",
            "The fourth column should stay as the normalized stress metric.",
            "SciPlot God reads the sigma/sigma0 metric for both point_line and curve outputs.",
        ],
    )


def _stress_relaxation_blank_workbook() -> dict[str, pd.DataFrame]:
    return _template_with_notes(
        [
            ["Time", "Strain", "Stress", "sigma/sigma0"],
            ["Sample 1", "", "", ""],
            ["s", "%", "Pa", ""],
            [0.0, 5.0, 2000, 1.0],
            [10.0, 5.0, 1650, 0.83],
            [20.0, 5.0, 1400, 0.70],
        ],
        notes=[
            "Replace the placeholder numeric rows with your own stress relaxation export values.",
            "Keep the first three rows intact so inspect recognizes the stress_relaxation bundle.",
            "Add more samples by appending another 4-column block.",
            "This blank template is inspect-ready for point_line and curve families.",
        ],
    )


DATA_TEMPLATE_SPECS: tuple[DataTemplateSpec, ...] = (
    DataTemplateSpec(
        id="curve_table",
        label="Curve Table",
        input_model="curve_table",
        typical_families=("curve", "point_line", "stacked_curve", "segmented_stacked_curve", "scatter"),
        format_summary="Rows 1 to 3 define labels, units, and sample names; row 4 onward stores numeric X/Y pairs.",
        build_example=_curve_example_workbook,
        build_blank=_curve_blank_workbook,
    ),
    DataTemplateSpec(
        id="tensile_curve",
        label="Tensile Curve",
        input_model="tensile_curve",
        typical_families=("curve", "point_line", "stacked_curve", "segmented_stacked_curve", "scatter"),
        format_summary=(
            "Rows 1 to 3 define tensile Strain/Stress headers; row 4 onward stores "
            "numeric stress-strain pairs."
        ),
        build_example=_tensile_example_workbook,
        build_blank=_tensile_blank_workbook,
    ),
    DataTemplateSpec(
        id="replicate_table",
        label="Replicate Table",
        input_model="replicate_table",
        typical_families=("bar", "box", "violin"),
        format_summary=(
            "Cell A1 stores the shared value label, row 2 groups, row 3 units, "
            "and row 4 onward replicate values."
        ),
        build_example=_replicate_example_workbook,
        build_blank=_replicate_blank_workbook,
    ),
    DataTemplateSpec(
        id="heatmap_table",
        label="Heatmap Table",
        input_model="heatmap_table",
        typical_families=("heatmap",),
        format_summary="Row 1 must stay X/Y/Z, row 2 labels, row 3 units, and row 4 onward long-form XYZ rows.",
        build_example=_heatmap_example_workbook,
        build_blank=_heatmap_blank_workbook,
    ),
    DataTemplateSpec(
        id="frequency_sweep",
        label="Frequency Sweep Bundle",
        input_model="frequency_sweep",
        typical_families=("point_line", "curve"),
        format_summary=(
            "Each sample uses 5 columns: frequency, storage modulus, loss modulus, "
            "loss factor, and complex viscosity."
        ),
        build_example=_frequency_example_workbook,
        build_blank=_frequency_blank_workbook,
    ),
    DataTemplateSpec(
        id="temperature_sweep",
        label="Temperature Sweep Bundle",
        input_model="temperature_sweep",
        typical_families=("point_line", "curve"),
        format_summary=(
            "Each sample uses 5 columns: temperature, storage modulus, loss "
            "modulus, loss factor, and complex viscosity."
        ),
        build_example=_temperature_example_workbook,
        build_blank=_temperature_blank_workbook,
    ),
    DataTemplateSpec(
        id="stress_relaxation",
        label="Stress Relaxation Bundle",
        input_model="stress_relaxation",
        typical_families=("point_line", "curve"),
        format_summary="Each sample uses 4 columns: time, strain, stress, and normalized stress.",
        build_example=_stress_relaxation_example_workbook,
        build_blank=_stress_relaxation_blank_workbook,
    ),
)

PLOT_TEMPLATE_FILE_SPECS: tuple[PlotTemplateFileSpec, ...] = (
    PlotTemplateFileSpec(
        chart_type="curve",
        label="Curve",
        filename_stem="curve",
        template_id="curve",
        source_template_id="curve_table",
    ),
    PlotTemplateFileSpec(
        chart_type="point_line",
        label="Point line",
        filename_stem="point_line",
        template_id="point_line",
        source_template_id="curve_table",
    ),
    PlotTemplateFileSpec(
        chart_type="scatter",
        label="Scatter",
        filename_stem="scatter",
        template_id="scatter",
        source_template_id="curve_table",
    ),
    PlotTemplateFileSpec(
        chart_type="stacked_curve",
        label="Stacked curve",
        filename_stem="stacked_curve",
        template_id="stacked_curve",
        source_template_id="curve_table",
    ),
    PlotTemplateFileSpec(
        chart_type="segmented_stacked_curve",
        label="Segmented stacked curve",
        filename_stem="segmented_stacked_curve",
        template_id="segmented_stacked_curve",
        source_template_id="curve_table",
    ),
    PlotTemplateFileSpec(
        chart_type="bar",
        label="Bar",
        filename_stem="bar",
        template_id="bar",
        source_template_id="replicate_table",
    ),
    PlotTemplateFileSpec(
        chart_type="boxplot",
        label="Boxplot",
        filename_stem="boxplot",
        template_id="box",
        source_template_id="replicate_table",
    ),
    PlotTemplateFileSpec(
        chart_type="violin",
        label="Violin",
        filename_stem="violin",
        template_id="violin",
        source_template_id="replicate_table",
    ),
    PlotTemplateFileSpec(
        chart_type="heatmap",
        label="Heatmap",
        filename_stem="heatmap",
        template_id="heatmap",
        source_template_id="heatmap_table",
    ),
)


def data_template_catalog() -> list[dict[str, object]]:
    return [
        {
            "id": spec.id,
            "label": spec.label,
            "input_model": spec.input_model,
            "typical_families": list(spec.typical_families),
            "format_summary": spec.format_summary,
            "supports_example": True,
            "supports_blank": True,
        }
        for spec in DATA_TEMPLATE_SPECS
    ]


def _resolve_spec(template_id: str) -> DataTemplateSpec:
    for spec in DATA_TEMPLATE_SPECS:
        if spec.id == template_id:
            return spec
    raise ValueError(f"Unknown data template: {template_id}")


def _normalize_variant(variant: str) -> str:
    normalized_variant = variant.strip().lower()
    if normalized_variant not in {"example", "blank"}:
        raise ValueError(f"Unsupported data template variant: {variant}")
    return normalized_variant


def _write_workbook(output_path: Path, workbook: dict[str, pd.DataFrame]) -> None:
    with pd.ExcelWriter(output_path, engine="openpyxl") as writer:
        for sheet_name, frame in workbook.items():
            frame.to_excel(writer, index=False, header=False, sheet_name=sheet_name)


def _validate_materialized_workbook(output_path: Path) -> None:
    if not output_path.exists() or not output_path.is_file():
        raise FileNotFoundError(f"Template file generation failed: {output_path}")

    workbook = pd.ExcelFile(output_path)
    try:
        missing_sheets = [
            sheet_name
            for sheet_name in (TEMPLATE_SHEET_NAME, README_SHEET_NAME)
            if sheet_name not in workbook.sheet_names
        ]
    except Exception as exc:  # pragma: no cover - defensive readback guard
        raise ValueError(f"Template workbook is unreadable: {output_path}") from exc
    finally:
        workbook.close()

    if missing_sheets:
        missing_text = ", ".join(missing_sheets)
        raise ValueError(
            f"Template workbook is missing required sheets ({missing_text}): {output_path}"
        )


def _validate_materialized_folder(folder_path: Path, output_paths: list[Path]) -> None:
    if not folder_path.exists() or not folder_path.is_dir():
        raise FileNotFoundError(f"Template folder path is invalid: {folder_path}")
    if not output_paths:
        raise FileNotFoundError(
            f"Template file generation failed: no workbook files were created in {folder_path}"
        )
    for output_path in output_paths:
        _validate_materialized_workbook(output_path)


def materialize_data_template(
    template_id: str,
    *,
    variant: str,
) -> dict[str, object]:
    spec = _resolve_spec(template_id)
    normalized_variant = _normalize_variant(variant)
    workbook_factory = spec.build_example if normalized_variant == "example" else spec.build_blank
    workbook = workbook_factory()
    output_dir = Path(mkdtemp(prefix="codegod-data-template-"))
    output_path = output_dir / f"{spec.id}_{normalized_variant}_template.xlsx"
    _write_workbook(output_path, workbook)
    _validate_materialized_folder(output_dir, [output_path])

    return {
        "template_id": spec.id,
        "variant": normalized_variant,
        "label": spec.label,
        "input_model": spec.input_model,
        "typical_families": list(spec.typical_families),
        "format_summary": spec.format_summary,
        "file_path": str(output_path),
        "filename": output_path.name,
        "sheet_name": TEMPLATE_SHEET_NAME,
    }


def plot_template_folder_catalog() -> list[dict[str, object]]:
    entries: list[dict[str, object]] = []
    for spec in PLOT_TEMPLATE_FILE_SPECS:
        source = _resolve_spec(spec.source_template_id)
        entries.append(
            {
                "chart_type": spec.chart_type,
                "label": spec.label,
                "filename_stem": spec.filename_stem,
                "template_id": spec.template_id,
                "input_model": source.input_model,
                "source_template_id": source.id,
                "format_summary": source.format_summary,
            }
        )
    return entries


def materialize_data_template_folder(
    *,
    variant: str,
) -> dict[str, object]:
    normalized_variant = _normalize_variant(variant)
    folder_path = Path(mkdtemp(prefix=f"codegod-{normalized_variant}-template-folder-"))
    files: list[dict[str, object]] = []
    output_paths: list[Path] = []
    for spec in PLOT_TEMPLATE_FILE_SPECS:
        source = _resolve_spec(spec.source_template_id)
        workbook_factory = source.build_example if normalized_variant == "example" else source.build_blank
        output_path = folder_path / f"{spec.filename_stem}_{normalized_variant}.xlsx"
        _write_workbook(output_path, workbook_factory())
        output_paths.append(output_path)
        files.append(
            {
                "chart_type": spec.chart_type,
                "label": spec.label,
                "template_id": spec.template_id,
                "filename": output_path.name,
                "file_path": str(output_path),
                "input_model": source.input_model,
                "source_template_id": source.id,
                "format_summary": source.format_summary,
            }
        )
    _validate_materialized_folder(folder_path, output_paths)
    return {
        "variant": normalized_variant,
        "folder_path": str(folder_path),
        "folder_name": folder_path.name,
        "chart_types": [spec.chart_type for spec in PLOT_TEMPLATE_FILE_SPECS],
        "files": files,
    }


__all__ = [
    "DATA_TEMPLATE_SPECS",
    "PLOT_TEMPLATE_FILE_SPECS",
    "README_SHEET_NAME",
    "TEMPLATE_SHEET_NAME",
    "data_template_catalog",
    "materialize_data_template",
    "materialize_data_template_folder",
    "plot_template_folder_catalog",
]
