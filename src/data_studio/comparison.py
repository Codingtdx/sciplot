from __future__ import annotations

import base64
import tempfile
from dataclasses import dataclass
from io import BytesIO
from pathlib import Path

import pandas as pd

from src.data_loader import CurveSeries, ReplicateGroup, load_curve_table, load_replicate_table
from src.data_studio.builtin import tensile as tensile_builtin
from src.data_studio.io_utils import list_sheet_names
from src.data_studio.models import (
    ComparisonRecipe,
    ComparisonSet,
    DataStudioFigureOutput,
    WorkbookMetricSummary,
)
from src.data_studio.workbooks import import_workbook
from src.plot_style import DEFAULT_PALETTE_PRESET, DEFAULT_STYLE_PRESET
from src.rendering.render_service import build_rendered_plots, close_rendered_plots, export_rendered_plots


@dataclass(frozen=True)
class LoadedComparisonWorkbook:
    workbook_path: Path
    label: str
    representative_curve: CurveSeries
    metric_summaries: tuple[WorkbookMetricSummary, ...]
    replicate_groups: dict[str, ReplicateGroup]


def load_comparison_workbook(path: str | Path) -> LoadedComparisonWorkbook:
    workbook = import_workbook(path)
    representative_curves = load_curve_table(workbook.workbook_path, sheet_name=tensile_builtin.REPRESENTATIVE_CURVE_SHEET)
    if len(representative_curves) != 1:
        raise ValueError(
            f"{workbook.workbook_path.name} must contain exactly one representative curve in "
            f"{tensile_builtin.REPRESENTATIVE_CURVE_SHEET}."
        )
    replicate_groups: dict[str, ReplicateGroup] = {}
    for sheet_name in list_sheet_names(workbook.workbook_path):
        if not sheet_name.endswith("_Replicates"):
            continue
        groups = load_replicate_table(workbook.workbook_path, sheet_name=sheet_name)
        if len(groups) != 1:
            raise ValueError(f"{workbook.workbook_path.name} must contain exactly one replicate group in {sheet_name}.")
        group = groups[0]
        replicate_groups[group.value_label] = group
    return LoadedComparisonWorkbook(
        workbook_path=workbook.workbook_path,
        label=workbook.label,
        representative_curve=representative_curves[0],
        metric_summaries=workbook.metrics,
        replicate_groups=replicate_groups,
    )


def comparison_recipes_for_workbooks(workbook_paths: list[str | Path]) -> tuple[ComparisonRecipe, ...]:
    loaded = [load_comparison_workbook(path) for path in workbook_paths]
    metric_ids = [metric.label for metric in loaded[0].metric_summaries]
    recipes: list[ComparisonRecipe] = [
        ComparisonRecipe(
            id="representative_curve",
            label="Representative Curve Compare",
            category="curve",
            template_id="curve",
            sheet_name=tensile_builtin.REPRESENTATIVE_CURVE_SHEET,
        )
    ]
    for metric_id in metric_ids:
        min_points = min(len(workbook.replicate_groups[metric_id].data.index) for workbook in loaded)
        recipes.extend(
            [
                ComparisonRecipe(
                    id=f"{metric_id.lower()}_bar",
                    label=f"{metric_id} Bar Compare",
                    category="metric",
                    template_id="bar",
                    sheet_name=f"{metric_id}_Replicates",
                    metric_id=metric_id,
                ),
                ComparisonRecipe(
                    id=f"{metric_id.lower()}_box",
                    label=f"{metric_id} Box Compare",
                    category="metric",
                    template_id="box",
                    sheet_name=f"{metric_id}_Replicates",
                    metric_id=metric_id,
                ),
                ComparisonRecipe(
                    id=f"{metric_id.lower()}_violin",
                    label=f"{metric_id} Violin Compare",
                    category="metric",
                    template_id="violin",
                    sheet_name=f"{metric_id}_Replicates",
                    metric_id=metric_id,
                ),
                ComparisonRecipe(
                    id=f"{metric_id.lower()}_distribution",
                    label=f"{metric_id} Distribution Compare",
                    category="metric",
                    template_id="distribution_compare",
                    sheet_name=f"{metric_id}_Replicates",
                    metric_id=metric_id,
                    supported=min_points >= 3,
                    support_reason="" if min_points >= 3 else "Distribution compare needs at least 3 replicates per workbook.",
                ),
            ]
        )
    return tuple(recipes)


def build_comparison_set(
    workbook_paths: list[str | Path],
    output_dir: str | Path,
) -> ComparisonSet:
    loaded = [load_comparison_workbook(path) for path in workbook_paths]
    if len(loaded) < 2:
        raise ValueError("Data Studio comparison requires at least two workbooks.")
    _validate_loaded_workbooks(loaded)
    labels = tensile_builtin.dedupe_labels(workbook.label for workbook in loaded)
    bundle_dir = Path(output_dir).expanduser() / tensile_builtin.bundle_dir_name(labels)
    bundle_dir.mkdir(parents=True, exist_ok=True)
    comparison_workbook_path = bundle_dir / f"{bundle_dir.name}.xlsx"
    with pd.ExcelWriter(comparison_workbook_path) as writer:
        tensile_builtin.representative_curve_dataframe(
            [
                tensile_builtin.LoadedTensileWorkbookData(
                    workbook_path=workbook.workbook_path,
                    base_label=workbook.label,
                    sheet_names=tuple(list_sheet_names(workbook.workbook_path)),
                    sample_count=0,
                    representative_filename=workbook.representative_curve.sample,
                    representative_curve=workbook.representative_curve,
                    metrics=tuple(
                        tensile_builtin.TensileMetricSummary(
                            label=metric.label,
                            unit=metric.unit,
                            mean=metric.mean,
                            std=metric.std,
                        )
                        for metric in workbook.metric_summaries
                    ),
                    replicate_groups=workbook.replicate_groups,
                    warnings=(),
                    source_files=(),
                )
                for workbook in loaded
            ],
            labels,
        ).to_excel(writer, sheet_name=tensile_builtin.REPRESENTATIVE_CURVE_SHEET, header=False, index=False)
        for metric_id in [metric.label for metric in loaded[0].metric_summaries]:
            unit = _metric_unit(loaded, metric_id)
            tensile_builtin.comparison_replicate_dataframe(
                metric_id,
                unit,
                [
                    tensile_builtin.LoadedTensileWorkbookData(
                        workbook_path=workbook.workbook_path,
                        base_label=workbook.label,
                        sheet_names=tuple(list_sheet_names(workbook.workbook_path)),
                        sample_count=0,
                        representative_filename=workbook.representative_curve.sample,
                        representative_curve=workbook.representative_curve,
                        metrics=tuple(
                            tensile_builtin.TensileMetricSummary(
                                label=metric.label,
                                unit=metric.unit,
                                mean=metric.mean,
                                std=metric.std,
                            )
                            for metric in workbook.metric_summaries
                        ),
                        replicate_groups=workbook.replicate_groups,
                        warnings=(),
                        source_files=(),
                    )
                    for workbook in loaded
                ],
                labels,
            ).to_excel(writer, sheet_name=f"{metric_id}_Replicates", header=False, index=False)
        _comparison_summary_dataframe(loaded, labels).to_excel(
            writer,
            sheet_name=tensile_builtin.SUMMARY_SHEET,
            header=False,
            index=False,
        )
        pd.DataFrame(
            [
                ["label", " vs ".join(labels)],
                ["template_id", "data_studio/comparison"],
                ["source_files", " | ".join(str(path) for path in workbook_paths)],
            ]
        ).to_excel(writer, sheet_name=tensile_builtin.METADATA_SHEET, header=False, index=False)
    recipes = comparison_recipes_for_workbooks(workbook_paths)
    return ComparisonSet(
        id=bundle_dir.name,
        label=" vs ".join(labels),
        workbook_paths=tuple(Path(path).expanduser() for path in workbook_paths),
        workbook_labels=tuple(labels),
        comparison_workbook_path=comparison_workbook_path,
        recipes=recipes,
    )


def preview_comparison_recipe(
    workbook_paths: list[str | Path],
    recipe_id: str,
) -> tuple[ComparisonSet, ComparisonRecipe, str]:
    temp_dir = Path(tempfile.mkdtemp(prefix="data_studio_preview_"))
    comparison_set = build_comparison_set(workbook_paths, temp_dir)
    recipe = _find_recipe(comparison_set.recipes, recipe_id)
    rendered = build_rendered_plots(
        recipe.template_id,
        comparison_set.comparison_workbook_path,
        recipe.sheet_name,
        style_preset=DEFAULT_STYLE_PRESET,
        palette_preset=DEFAULT_PALETTE_PRESET,
    )
    try:
        if not rendered:
            raise ValueError("The selected comparison recipe did not render any previews.")
        buffer = BytesIO()
        rendered[0].figure.savefig(buffer, format="pdf", facecolor="white", bbox_inches=None)
        pdf_base64 = base64.b64encode(buffer.getvalue()).decode("ascii")
    finally:
        close_rendered_plots(rendered)
    return comparison_set, recipe, pdf_base64


def export_comparison_bundle(
    workbook_paths: list[str | Path],
    output_dir: str | Path,
    *,
    selected_recipe_ids: list[str] | None = None,
) -> tuple[ComparisonSet, tuple[DataStudioFigureOutput, ...]]:
    comparison_set = build_comparison_set(workbook_paths, output_dir)
    selected_ids = set(selected_recipe_ids or [recipe.id for recipe in comparison_set.recipes if recipe.enabled_by_default])
    figure_outputs: list[DataStudioFigureOutput] = []
    bundle_dir = comparison_set.comparison_workbook_path.parent
    for recipe in comparison_set.recipes:
        if recipe.id not in selected_ids or not recipe.supported:
            continue
        rendered = build_rendered_plots(
            recipe.template_id,
            comparison_set.comparison_workbook_path,
            recipe.sheet_name,
            style_preset=DEFAULT_STYLE_PRESET,
            palette_preset=DEFAULT_PALETTE_PRESET,
        )
        try:
            output_paths = export_rendered_plots(rendered, bundle_dir, close=False)
            for output_path, rendered_plot in zip(output_paths, rendered, strict=True):
                figure_outputs.append(
                    DataStudioFigureOutput(
                        path=output_path,
                        label=recipe.label,
                        category=recipe.category,
                        template_id=recipe.template_id,
                        sheet_name=recipe.sheet_name,
                        metric_id=recipe.metric_id,
                        recipe_id=recipe.id,
                    )
                )
        finally:
            close_rendered_plots(rendered)
    return comparison_set, tuple(figure_outputs)


def _find_recipe(recipes: tuple[ComparisonRecipe, ...], recipe_id: str) -> ComparisonRecipe:
    for recipe in recipes:
        if recipe.id == recipe_id:
            if not recipe.supported:
                raise ValueError(recipe.support_reason or f"The recipe {recipe.label!r} is not available.")
            return recipe
    raise ValueError(f"Unknown comparison recipe: {recipe_id}")


def _metric_unit(loaded: list[LoadedComparisonWorkbook], metric_id: str) -> str:
    units = {metric.unit for workbook in loaded for metric in workbook.metric_summaries if metric.label == metric_id}
    if len(units) != 1:
        raise ValueError(f"{metric_id} does not share a single comparable unit.")
    return units.pop()


def _validate_loaded_workbooks(loaded: list[LoadedComparisonWorkbook]) -> None:
    first_curve = loaded[0].representative_curve
    first_metric_ids = {metric.label: metric.unit for metric in loaded[0].metric_summaries}
    for workbook in loaded[1:]:
        curve = workbook.representative_curve
        if (
            curve.x_label != first_curve.x_label
            or curve.y_label != first_curve.y_label
            or curve.x_unit != first_curve.x_unit
            or curve.y_unit != first_curve.y_unit
        ):
            raise ValueError("Representative curve axes do not match across the selected workbooks.")
        metric_map = {metric.label: metric.unit for metric in workbook.metric_summaries}
        if metric_map != first_metric_ids:
            raise ValueError("Workbook metric labels or units do not match across the comparison set.")


def _comparison_summary_dataframe(
    loaded: list[LoadedComparisonWorkbook],
    labels: list[str],
) -> pd.DataFrame:
    rows: list[list[object]] = [["Label", "Workbook Path", "Representative File"]]
    metric_ids = [metric.label for metric in loaded[0].metric_summaries]
    header_row = rows[0]
    for metric_id in metric_ids:
        unit = _metric_unit(loaded, metric_id)
        header_row.extend([f"{metric_id} Mean ({unit})", f"{metric_id} Std ({unit})"])
    for label, workbook in zip(labels, loaded, strict=True):
        row: list[object] = [label, str(workbook.workbook_path), workbook.representative_curve.sample]
        metric_map = {metric.label: metric for metric in workbook.metric_summaries}
        for metric_id in metric_ids:
            metric = metric_map[metric_id]
            row.extend([metric.mean, metric.std])
        rows.append(row)
    return pd.DataFrame(rows)


__all__ = [
    "build_comparison_set",
    "comparison_recipes_for_workbooks",
    "export_comparison_bundle",
    "load_comparison_workbook",
    "preview_comparison_recipe",
]
