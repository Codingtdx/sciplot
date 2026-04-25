from __future__ import annotations

from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import pytest
from matplotlib import rcParams
from matplotlib.collections import PathCollection, PolyCollection
from matplotlib.colors import to_hex

from src import plot_style
from src.plot_contract import lint_public_template_contract
from src.rendering import (
    build_normalized_dataset,
    build_rendered_plots,
    close_rendered_plots,
    inspect_input_file,
    preflight_render_request,
    resolve_render_options,
)
from src.rendering import themes as rendering_themes
from src.rendering.render_curve_support import _apply_compact_inside_legend
from src.rendering.style_composer import DEFAULT_STYLE_COMPOSER
from src.rendering.themes import (
    VisualThemeSpec,
    publication_profile_protected_rcparams,
    visual_theme_ids,
    visual_theme_soft_overrides,
)


def _path_collections(ax) -> list[PathCollection]:
    return [collection for collection in ax.collections if isinstance(collection, PathCollection)]


def _has_marker_lines(ax) -> bool:
    return any(line.get_marker() not in {None, "", "None", " "} for line in ax.lines)


def _primary_and_secondary_axes(plot) -> list[object]:
    primary = plot.figure.axes[0]
    axes: list[object] = [primary]
    for axis in list(plot.figure.axes[1:]) + list(primary.child_axes):
        if axis not in axes:
            axes.append(axis)
    return axes


def _write_curve_table(path: Path) -> Path:
    rows = [
        ["Time", "Stress", "Time", "Stress"],
        ["s", "MPa", "s", "MPa"],
        ["Sample A", "Sample A", "Sample B", "Sample B"],
        [0, 1.0, 0, 2.0],
        [1, 1.3, 1, 2.4],
        [2, 1.5, 2, 2.8],
    ]
    pd.DataFrame(rows).to_csv(path, header=False, index=False)
    return path


def _write_multi_curve_table(path: Path) -> Path:
    rows = [
        ["Time", "Stress", "Time", "Stress", "Time", "Stress", "Time", "Stress"],
        ["s", "MPa", "s", "MPa", "s", "MPa", "s", "MPa"],
        ["Sample A", "Sample A", "Sample B", "Sample B", "Sample C", "Sample C", "Sample D", "Sample D"],
        [0, 1.0, 0, 2.0, 0, 2.2, 0, 2.4],
        [1, 1.3, 1, 2.4, 1, 2.5, 1, 2.6],
        [2, 1.5, 2, 2.8, 2, 2.9, 2, 3.1],
    ]
    pd.DataFrame(rows).to_csv(path, header=False, index=False)
    return path


def _write_dense_curve_table(path: Path) -> Path:
    import numpy as np

    x = np.linspace(0.5, 10.0, 80)
    y_a = np.sin(x / 2.0) + 2.1
    y_b = np.cos(x / 3.0) + 3.2
    rows = [
        ["Strain", "Stress", "Strain", "Stress"],
        ["%", "MPa", "%", "MPa"],
        ["Sample A", "Sample A", "Sample B", "Sample B"],
    ]
    for x_value, y_value_a, y_value_b in zip(x, y_a, y_b, strict=True):
        rows.append([x_value, y_value_a, x_value, y_value_b])
    pd.DataFrame(rows).to_csv(path, header=False, index=False)
    return path


def _write_monotonic_curve_table(path: Path) -> Path:
    import numpy as np

    x = np.linspace(25.0, 220.0, 120)
    rows = [
        ["Temperature", "E'", "Temperature", "E'"],
        ["°C", "MPa", "°C", "MPa"],
        ["Sample A", "Sample A", "Sample B", "Sample B"],
    ]
    for value in x:
        rows.append(
            [
                value,
                3200 * np.exp(-value / 140.0) + 180.0,
                value,
                2800 * np.exp(-value / 150.0) + 220.0,
            ]
        )
    pd.DataFrame(rows).to_csv(path, header=False, index=False)
    return path


def _write_tensile_curve_table(path: Path) -> Path:
    rows = [
        ["Strain", "Stress", "Strain", "Stress"],
        ["%", "MPa", "%", "MPa"],
        ["Sample A", "Sample A", "Sample B", "Sample B"],
        [0.1, 1.0, 0.1, 1.4],
        [10.0, 120.0, 12.0, 160.0],
        [1000.0, 12000.0, 1200.0, 14500.0],
    ]
    pd.DataFrame(rows).to_csv(path, header=False, index=False)
    return path


def _write_replicate_table(path: Path) -> Path:
    rows = [
        ["Tensile modulus", "", ""],
        ["Blend A", "Blend B", "Blend C"],
        ["MPa", "MPa", "MPa"],
        [510.13, 567.91, 544.10],
        [501.10, 501.49, 549.54],
        [549.61, 549.61, 562.07],
    ]
    pd.DataFrame(rows).to_csv(path, header=False, index=False)
    return path


def _write_dense_replicate_table(path: Path) -> Path:
    rows = [
        ["Storage modulus", "", ""],
        ["Blend A", "Blend B", "Blend C"],
        ["MPa", "MPa", "MPa"],
        [480, 520, 500],
        [495, 534, 512],
        [502, 541, 521],
        [510, 548, 529],
        [517, 553, 536],
        [523, 559, 541],
        [530, 565, 548],
        [538, 571, 552],
    ]
    pd.DataFrame(rows).to_csv(path, header=False, index=False)
    return path


def _write_many_group_replicate_table(path: Path) -> Path:
    rows = [
        ["Storage modulus", "", "", "", "", ""],
        ["A", "B", "C", "D", "E", "F"],
        ["MPa", "MPa", "MPa", "MPa", "MPa", "MPa"],
        [420, 438, 455, 462, 470, 482],
        [426, 445, 461, 468, 476, 488],
        [431, 451, 466, 473, 481, 492],
        [435, 456, 471, 478, 486, 497],
    ]
    pd.DataFrame(rows).to_csv(path, header=False, index=False)
    return path


def _write_discrete_replicate_table(path: Path) -> Path:
    rows = [
        ["Hardness", "", ""],
        ["Blend A", "Blend B", "Blend C"],
        ["a.u.", "a.u.", "a.u."],
        [0, 0, 1],
        [0, 1, 1],
        [1, 1, 1],
        [1, 1, 2],
        [2, 2, 2],
        [2, 2, 2],
        [2, 3, 3],
        [3, 3, 3],
        [3, 3, 3],
    ]
    pd.DataFrame(rows).to_csv(path, header=False, index=False)
    return path


def _write_poorly_aligned_curve_table(path: Path) -> Path:
    rows = [
        ["Time", "Stress", "Time", "Stress"],
        ["s", "MPa", "s", "MPa"],
        ["Sample A", "Sample A", "Sample B", "Sample B"],
        [0.0, 1.0, 0.0, 1.2],
        [0.0, 1.1, 0.0, 1.4],
    ]
    pd.DataFrame(rows).to_csv(path, header=False, index=False)
    return path


def _write_heatmap_table(path: Path) -> Path:
    rows = [
        ["X", "Y", "Z"],
        ["mm", "mm", "a.u."],
        ["Sample A", "Sample A", "Sample A"],
        [0, 0, 0.1],
        [0, 1, 0.2],
        [1, 0, 0.3],
        [1, 1, 0.4],
    ]
    pd.DataFrame(rows).to_csv(path, header=False, index=False)
    return path


def _write_contour_field_table(path: Path) -> Path:
    rows = [["X", "Y", "Z"], ["mm", "mm", "a.u."], ["field", "field", "field"]]
    for x_value in np.linspace(-1.0, 1.0, 5):
        for y_value in np.linspace(-1.0, 1.0, 5):
            rows.append([x_value, y_value, x_value**2 + y_value**2])
    pd.DataFrame(rows).to_csv(path, header=False, index=False)
    return path


def _write_polar_curve_table(path: Path) -> Path:
    rows = [["Theta", "Radius"], ["rad", "a.u."], ["rose", "rose"]]
    for theta in np.linspace(0.0, 2 * np.pi, 32):
        rows.append([theta, 1.0 + 0.35 * np.cos(3 * theta)])
    pd.DataFrame(rows).to_csv(path, header=False, index=False)
    return path


def _write_small_table(path: Path) -> Path:
    pd.DataFrame(
        [
            ["Metric", "Blend A", "Blend B"],
            ["Strength", 42.1, 45.3],
            ["Modulus", 510.2, 566.7],
            ["Elongation", 9.5, 10.1],
        ]
    ).to_csv(path, header=False, index=False)
    return path


def _write_multi_tensile_curve_table(path: Path) -> Path:
    x = np.linspace(0.0, 60.0, 90)
    rows = [
        ["Strain", "Stress", "Strain", "Stress", "Strain", "Stress", "Strain", "Stress"],
        ["%", "MPa", "%", "MPa", "%", "MPa", "%", "MPa"],
        ["Group A", "Group A", "Group B", "Group B", "Group C", "Group C", "Group D", "Group D"],
    ]
    for value in x:
        rows.append(
            [
                value,
                24.0 * (1.0 - np.exp(-value / 4.8)) - 0.015 * max(value - 48.0, 0.0) ** 2,
                value,
                26.0 * (1.0 - np.exp(-value / 5.6)) - 0.013 * max(value - 50.0, 0.0) ** 2,
                value,
                22.0 * (1.0 - np.exp(-value / 6.2)) - 0.011 * max(value - 52.0, 0.0) ** 2,
                value,
                25.5 * (1.0 - np.exp(-value / 5.1)) - 0.014 * max(value - 49.0, 0.0) ** 2,
            ]
        )
    pd.DataFrame(rows).to_csv(path, header=False, index=False)
    return path


def _write_frequency_sweep_table(path: Path) -> Path:
    rows = [
        [
            "Angular Frequency",
            "Storage Modulus",
            "Loss Modulus",
            "Loss Factor",
            "Complex Viscosity",
        ],
        ["Sample A", "Sample A", "Sample A", "Sample A", "Sample A"],
        ["rad/s", "Pa", "Pa", "", "Pa.s"],
        [0.1, 1000, 200, 0.2, 500],
        [1.0, 2000, 400, 0.2, 250],
        [10.0, 4000, 800, 0.2, 120],
    ]
    pd.DataFrame(rows).to_excel(path, header=False, index=False)
    return path


def _write_stress_relaxation_table(path: Path) -> Path:
    rows = [
        [
            "Time",
            "Shear Strain",
            "Shear Stress",
            "σ/σ0",
            "Time",
            "Shear Strain",
            "Shear Stress",
            "σ/σ0",
        ],
        ["PA", "PA", "PA", "PA", "D-PA", "D-PA", "D-PA", "D-PA"],
        ["s", "%", "Pa", "", "s", "%", "Pa", ""],
        [0.01, 1.0, 1000, 1.0, 0.01, 1.1, 1200, 1.0],
        [0.1, 1.2, 600, 0.65, 0.1, 1.3, 820, 0.68],
        [1.0, 1.4, 320, 0.32, 1.0, 1.6, 460, 0.38],
        [10.0, 1.5, 180, 0.18, 10.0, 1.8, 290, 0.24],
        [100.0, 1.6, 120, 0.12, 100.0, 2.0, 210, 0.17],
    ]
    pd.DataFrame(rows).to_excel(path, header=False, index=False)
    return path


def _write_temperature_sweep_table(path: Path) -> Path:
    rows = [
        [
            "Temperature",
            "Storage Modulus",
            "Loss Modulus",
            "Loss Factor",
            "Complex Viscosity",
            "Temperature",
            "Storage Modulus",
            "Loss Modulus",
            "Loss Factor",
            "Complex Viscosity",
        ],
        [
            "Sample A",
            "Sample A",
            "Sample A",
            "Sample A",
            "Sample A",
            "Sample B",
            "Sample B",
            "Sample B",
            "Sample B",
            "Sample B",
        ],
        ["°C", "Pa", "Pa", "", "Pa.s", "°C", "Pa", "Pa", "", "Pa.s"],
        [30, 1200, 200, 0.17, 550, 30, 980, 180, 0.18, 630],
        [60, 900, 190, 0.21, 360, 60, 760, 150, 0.20, 420],
        [90, 660, 150, 0.23, 210, 90, 580, 120, 0.21, 270],
    ]
    pd.DataFrame(rows).to_excel(path, header=False, index=False)
    return path


def test_curve_inspect_preflight_and_render_filenames_match(tmp_path: Path) -> None:
    input_path = _write_curve_table(tmp_path / "curve.csv")

    inspection = inspect_input_file(input_path)
    assert inspection.recommendations[0].template_id == "curve"
    assert len(inspection.recommendations) == 10
    assert inspection.recommendations[0].template_id == "curve"
    assert inspection.recommendations[1].template_id == "point_line"
    assert inspection.recommendations[0].rank == 1
    assert inspection.recommendations[0].reason
    assert inspection.recommendations[0].suitability_hint
    assert inspection.recommendations[0].why_soft_prior
    assert inspection.recommendations[0].canonical_id == "curve"
    assert inspection.recommendations[0].role == "canonical"
    assert inspection.recommendations[0].implementation_id == "curve"
    assert inspection.recommendation_confidence >= inspection.recommendations[0].score
    assert "curve" in inspection.recommendation_summary
    assert [item.template_id for item in inspection.primary_recommendation] == ["curve"]
    assert [item.template_id for item in inspection.alternative_recommendations] == [
        "point_line",
        "area_curve",
        "scatter_fit",
    ]
    advanced_template_ids = [item.template_id for item in inspection.advanced_templates]
    assert "bubble_scatter" in advanced_template_ids
    assert "stacked_area" in [item.template_id for item in inspection.recommendations]

    options = resolve_render_options(template="curve")
    preflight = preflight_render_request("curve", input_path, 0, options)
    assert preflight.errors == ()
    assert preflight.requested_template_id == "curve"
    assert preflight.canonical_id == "curve"
    assert preflight.role == "canonical"
    assert preflight.implementation_id == "curve"
    assert preflight.submission_report is not None
    assert preflight.submission_report.context == "preflight"
    assert preflight.submission_report.style_preset == "nature"

    rendered = build_rendered_plots("curve", input_path)
    try:
        assert tuple(plot.filename for plot in rendered) == preflight.output_filenames
    finally:
        close_rendered_plots(rendered)


def test_resolve_render_options_accepts_public_style_preset(tmp_path: Path) -> None:
    input_path = _write_curve_table(tmp_path / "curve.csv")

    options = resolve_render_options(
        template="curve",
        style_preset="editorial",
        palette_preset="colorblind_safe",
    )
    preflight = preflight_render_request("curve", input_path, 0, options)

    assert options.style_preset == "editorial"
    assert preflight.submission_report is not None
    assert preflight.submission_report.style_preset == "editorial"


@pytest.mark.parametrize(
    ("writer", "filename", "expected_model", "expected_shapes"),
    [
        (_write_curve_table, "curve.csv", "curve_table", ("curve_like",)),
        (_write_tensile_curve_table, "tensile.csv", "tensile_curve", ("curve_like",)),
        (_write_replicate_table, "replicates.csv", "replicate_table", ("replicate_table", "distribution")),
        (_write_frequency_sweep_table, "frequency.xlsx", "frequency_sweep", ("curve_like",)),
        (_write_heatmap_table, "heatmap.csv", "heatmap_table", ("matrix", "scalar_field")),
    ],
)
def test_normalized_dataset_builder_reuses_model_and_shape_signals(
    tmp_path: Path,
    writer,
    filename: str,
    expected_model: str,
    expected_shapes: tuple[str, ...],
) -> None:
    input_path = writer(tmp_path / filename)

    dataset = build_normalized_dataset(input_path)

    assert dataset.model == expected_model
    assert dataset.data_shapes == expected_shapes
    assert dataset.raw_rows > 0
    assert dataset.raw_cols > 0


def test_style_composer_uses_contract_backed_protected_keys() -> None:
    default_bundle = DEFAULT_STYLE_COMPOSER.compose("default", None)
    bundle = DEFAULT_STYLE_COMPOSER.compose("default", "soft_grid")

    assert default_bundle.resolved_soft == {}
    assert bundle.publication_profile_id == "nature"
    assert bundle.protected_keys
    assert any(key.startswith("typography.") for key in bundle.protected_keys)
    assert "typography.font_size_pt" in bundle.protected_keys
    assert bundle.visual_theme_id == "soft_grid"
    assert bundle.resolved_soft == visual_theme_soft_overrides("soft_grid")


def test_style_composer_filters_contract_protected_theme_overrides(monkeypatch: pytest.MonkeyPatch) -> None:
    theme_id = "__test_protected_theme__"
    monkeypatch.setitem(
        rendering_themes._VISUAL_THEMES,
        theme_id,
        VisualThemeSpec(
            label="Test Protected",
            description="Inject protected and unprotected overrides.",
            soft_overrides={
                "lines.linewidth": 9.9,
                "axes.facecolor": "#f7f7f7",
            },
        ),
    )

    bundle = DEFAULT_STYLE_COMPOSER.compose("default", theme_id)

    assert bundle.resolved_soft == {"axes.facecolor": "#f7f7f7"}
    assert bundle.blocked_soft_keys == ("lines.linewidth",)


def test_visual_theme_soft_overrides_layer_on_top_of_publication_profile() -> None:
    try:
        plot_style.apply_style(
            "nature",
            "colorblind_safe",
            soft_overrides=visual_theme_soft_overrides("soft_grid"),
        )
        assert rcParams["axes.grid"] is True
        assert rcParams["legend.frameon"] is True
        assert to_hex(rcParams["figure.facecolor"]) == "#f5f8fb"
    finally:
        plot_style.apply_style(plot_style.DEFAULT_STYLE_PRESET, plot_style.DEFAULT_PALETTE_PRESET)


def test_visual_themes_do_not_mutate_protected_publication_typography_defaults() -> None:
    protected_font_size = DEFAULT_STYLE_COMPOSER.compose("nature", None).resolved_hard["typography"]["font_size_pt"]
    protected_legend_size = DEFAULT_STYLE_COMPOSER.compose("nature", None).resolved_hard["typography"][
        "legend_font_size_pt"
    ]

    try:
        for theme_id in visual_theme_ids():
            overrides = visual_theme_soft_overrides(theme_id)
            assert "font.size" not in overrides
            assert "legend.fontsize" not in overrides
            plot_style.apply_style("nature", "colorblind_safe", soft_overrides=overrides)
            assert rcParams["font.size"] == protected_font_size
            assert rcParams["legend.fontsize"] == protected_legend_size
    finally:
        plot_style.apply_style(plot_style.DEFAULT_STYLE_PRESET, plot_style.DEFAULT_PALETTE_PRESET)


def test_visual_themes_never_override_protected_publication_rcparams() -> None:
    def _snapshot(keys: tuple[str, ...]) -> dict[str, object]:
        snapshot: dict[str, object] = {}
        for key in keys:
            value = rcParams[key]
            if isinstance(value, list):
                snapshot[key] = tuple(value)
            else:
                snapshot[key] = value
        return snapshot

    try:
        for style_id in plot_style.list_public_style_presets():
            protected_keys = publication_profile_protected_rcparams(style_id)
            plot_style.apply_style(style_id, "colorblind_safe")
            baseline = _snapshot(protected_keys)
            for theme_id in visual_theme_ids():
                overrides = visual_theme_soft_overrides(theme_id)
                assert not (set(overrides) & set(protected_keys))
                plot_style.apply_style(style_id, "colorblind_safe", soft_overrides=overrides)
                assert _snapshot(protected_keys) == baseline
    finally:
        plot_style.apply_style(plot_style.DEFAULT_STYLE_PRESET, plot_style.DEFAULT_PALETTE_PRESET)


def test_public_template_contract_lint_passes() -> None:
    assert lint_public_template_contract() == ()


def test_public_styles_can_change_hard_typography_and_stroke_metrics() -> None:
    try:
        plot_style.apply_style("nature", "colorblind_safe")
        nature_font_size = float(rcParams["font.size"])
        nature_line_width = float(rcParams["lines.linewidth"])

        plot_style.apply_style("presentation", "colorblind_safe")
        presentation_font_size = float(rcParams["font.size"])
        presentation_line_width = float(rcParams["lines.linewidth"])
    finally:
        plot_style.apply_style(plot_style.DEFAULT_STYLE_PRESET, plot_style.DEFAULT_PALETTE_PRESET)

    assert presentation_font_size > nature_font_size
    assert presentation_line_width > nature_line_width


def test_resolve_render_options_accepts_visual_theme_id(tmp_path: Path) -> None:
    options = resolve_render_options(template="curve", visual_theme_id="presentation_like")

    assert options.visual_theme_id == "presentation_like"

    with pytest.raises(ValueError, match="Unknown visual theme"):
        resolve_render_options(template="curve", visual_theme_id="not-a-theme")


def test_resolve_render_options_uses_template_recommended_theme_and_palette_defaults() -> None:
    options = resolve_render_options(template="curve")

    assert options.palette_preset == "colorblind_safe"
    assert options.visual_theme_id == "clean_light"

    heatmap_options = resolve_render_options(template="heatmap")
    assert heatmap_options.palette_preset == "colorblind_safe"
    assert heatmap_options.visual_theme_id == "clean_light"


def test_resolve_render_options_uses_style_recommended_theme_and_palette_when_style_changes() -> None:
    options = resolve_render_options(template="curve", style_preset="poster")

    assert options.style_preset == "poster"
    assert options.palette_preset == "shine"
    assert options.visual_theme_id == "shine"


def test_resolve_render_options_accepts_extra_axes_payloads() -> None:
    options = resolve_render_options(
        template="curve",
        extra_x_axis={
            "enabled": True,
            "position": "top",
            "title": "Gallons",
            "data_value": 3.78541,
            "display_value": 1.0,
        },
        extra_y_axis={
            "enabled": True,
            "position": "right",
            "title": "Half Stress",
            "data_value": 2.0,
            "display_value": 1.0,
        },
    )

    assert options.extra_x_axis is not None
    assert options.extra_x_axis["position"] == "top"
    assert options.extra_x_axis["binding_mode"] == "conversion"
    assert options.extra_x_axis["series_ids"] == ()
    assert options.extra_x_axis["data_value"] == pytest.approx(3.78541)
    assert options.extra_y_axis is not None
    assert options.extra_y_axis["position"] == "right"
    assert options.extra_y_axis["binding_mode"] == "conversion"
    assert options.extra_y_axis["series_ids"] == ()
    assert options.extra_y_axis["display_value"] == pytest.approx(1.0)


def test_resolve_render_options_rejects_invalid_extra_axis_position() -> None:
    with pytest.raises(ValueError, match="must be one of"):
        resolve_render_options(
            template="curve",
            extra_x_axis={"enabled": True, "position": "right"},
        )


def test_resolve_render_options_rejects_extra_x_axis_series_assignment_mode() -> None:
    with pytest.raises(ValueError, match="only supports `conversion`"):
        resolve_render_options(
            template="curve",
            extra_x_axis={
                "enabled": True,
                "binding_mode": "series_assignment",
                "series_ids": ["Sample B"],
            },
        )


def test_resolve_render_options_accepts_axis_break_payloads() -> None:
    options = resolve_render_options(
        template="curve",
        x_axis_breaks=[
            {
                "id": "x-gap",
                "enabled": True,
                "start": 0.8,
                "end": 1.2,
                "display_mode": "split",
            }
        ],
        y_axis_breaks=[
            {
                "id": "y-gap",
                "enabled": False,
                "start": 1.4,
                "end": 2.2,
            }
        ],
    )

    assert options.x_axis_breaks is not None
    assert options.x_axis_breaks[0]["id"] == "x-gap"
    assert options.x_axis_breaks[0]["start"] == pytest.approx(0.8)
    assert options.x_axis_breaks[0]["display_mode"] == "split"
    assert options.y_axis_breaks is not None
    assert options.y_axis_breaks[0]["end"] == pytest.approx(2.2)
    assert options.y_axis_breaks[0]["display_mode"] == "compress"


def test_resolve_render_options_accepts_shape_annotations_payloads() -> None:
    options = resolve_render_options(
        template="curve",
        shape_annotations=[
            {
                "id": "focus-window",
                "enabled": True,
                "kind": "rectangle",
                "x_start": 0.5,
                "x_end": 1.5,
                "y_start": 2.0,
                "y_end": 3.0,
                "label": "Window",
            },
            {
                "id": "significance",
                "enabled": True,
                "kind": "bracket",
                "bracket_orientation": "horizontal",
                "x_start": 0.8,
                "x_end": 1.4,
                "y_start": 3.2,
                "y_end": 3.2,
                "label": "p < 0.05",
            },
        ],
    )

    assert options.shape_annotations is not None
    assert options.shape_annotations[0]["kind"] == "rectangle"
    assert options.shape_annotations[0]["label"] == "Window"
    assert options.shape_annotations[1]["kind"] == "bracket"
    assert options.shape_annotations[1]["bracket_orientation"] == "horizontal"


def test_resolve_render_options_rejects_axis_breaks_on_log_axes_or_with_extra_axes() -> None:
    with pytest.raises(ValueError, match="linear X axes only"):
        resolve_render_options(
            template="curve",
            xscale="log",
            x_axis_breaks=[{"id": "x-gap", "enabled": True, "start": 0.8, "end": 1.2}],
        )

    with pytest.raises(ValueError, match="cannot be combined with extra axes"):
        resolve_render_options(
            template="curve",
            x_axis_breaks=[{"id": "x-gap", "enabled": True, "start": 0.8, "end": 1.2}],
            extra_y_axis={
                "enabled": True,
                "position": "right",
                "title": "Half Stress",
                "data_value": 2.0,
                "display_value": 1.0,
            },
        )

    with pytest.raises(ValueError, match="single `display_mode`"):
        resolve_render_options(
            template="curve",
            x_axis_breaks=[
                {"id": "x-gap-1", "enabled": True, "start": 0.8, "end": 1.2, "display_mode": "compress"},
                {"id": "x-gap-2", "enabled": True, "start": 1.8, "end": 2.2, "display_mode": "split"},
            ],
        )

    with pytest.raises(ValueError, match="Split broken X axes cannot be combined"):
        resolve_render_options(
            template="curve",
            x_axis_breaks=[
                {"id": "x-gap", "enabled": True, "start": 0.8, "end": 1.2, "display_mode": "split"}
            ],
            y_axis_breaks=[
                {"id": "y-gap", "enabled": True, "start": 1.4, "end": 2.2, "display_mode": "compress"}
            ],
        )


def test_resolve_render_options_accepts_tick_label_preferences_for_supported_templates() -> None:
    options = resolve_render_options(
        template="curve",
        x_tick_density="sparse",
        y_tick_density="dense",
        x_tick_edge_labels="hide_min",
        y_tick_edge_labels="hide_both",
    )

    assert options.x_tick_density == "sparse"
    assert options.y_tick_density == "dense"
    assert options.x_tick_edge_labels == "hide_min"
    assert options.y_tick_edge_labels == "hide_both"

    with pytest.raises(ValueError, match="does not support option `x_tick_density`"):
        resolve_render_options(template="box", x_tick_density="sparse")


def test_resolve_render_options_uses_contract_reverse_x_default_when_unspecified() -> None:
    options = resolve_render_options(template="segmented_stacked_curve")

    assert options.reverse_x is True


def test_tensile_curve_defaults_to_linear_but_allows_log_override(tmp_path: Path) -> None:
    input_path = _write_tensile_curve_table(tmp_path / "tensile_curve.csv")

    inspection = inspect_input_file(input_path)
    assert inspection.model == "tensile_curve"
    assert inspection.recommendations[0].template_id == "curve"
    assert inspection.recommendations[0].preview_config_summary.get("size") == "60x55"
    assert inspection.recommendations[0].preview_config_summary.get("xscale") == "linear"
    assert inspection.recommendations[0].preview_config_summary.get("yscale") == "linear"

    linear_options = resolve_render_options(template="curve", xscale="linear", yscale="linear")
    linear_preflight = preflight_render_request("curve", input_path, 0, linear_options)
    assert linear_preflight.errors == ()

    log_options = resolve_render_options(template="curve", xscale="log", yscale="linear")
    log_preflight = preflight_render_request("curve", input_path, 0, log_options)
    assert log_preflight.errors == ()

    rendered = build_rendered_plots("curve", input_path, xscale="log", yscale="linear")
    try:
        assert tuple(plot.filename for plot in rendered) == linear_preflight.output_filenames
        assert rendered[0].figure.axes[0].get_ylabel() == "Stress (MPa)"
    finally:
        close_rendered_plots(rendered)


def test_curve_axis_label_overrides_replace_normalized_display_labels(tmp_path: Path) -> None:
    input_path = _write_curve_table(tmp_path / "curve.csv")

    rendered = build_rendered_plots(
        "curve",
        input_path,
        x_label_override="Elapsed Time",
        y_label_override="Load",
    )
    try:
        ax = rendered[0].figure.axes[0]
        assert ax.get_xlabel() == "Elapsed Time (s)"
        assert ax.get_ylabel() == "Load (MPa)"
    finally:
        close_rendered_plots(rendered)


def test_frequency_bundle_preflight_matches_multi_output_render(tmp_path: Path) -> None:
    input_path = _write_frequency_sweep_table(tmp_path / "frequency.xlsx")

    inspection = inspect_input_file(input_path)
    assert inspection.model == "frequency_sweep"
    assert inspection.recommendations[0].template_id == "point_line"

    options = resolve_render_options(template="point_line", xscale="log", yscale="log")
    preflight = preflight_render_request("point_line", input_path, 0, options)
    assert preflight.errors == ()
    assert len(preflight.output_filenames) == 4

    rendered = build_rendered_plots("point_line", input_path, xscale="log", yscale="log")
    try:
        assert tuple(plot.filename for plot in rendered) == preflight.output_filenames
    finally:
        close_rendered_plots(rendered)

    curve_options = resolve_render_options(template="curve", xscale="log", yscale="log")
    curve_preflight = preflight_render_request("curve", input_path, 0, curve_options)
    assert curve_preflight.errors == ()
    assert curve_preflight.output_filenames == (
        "freq_storage_modulus_curve.pdf",
        "freq_loss_modulus_curve.pdf",
        "freq_loss_factor_curve.pdf",
        "freq_complex_viscosity_curve.pdf",
    )

    rendered_curve = build_rendered_plots("curve", input_path, xscale="log", yscale="log")
    try:
        assert tuple(plot.filename for plot in rendered_curve) == curve_preflight.output_filenames
    finally:
        close_rendered_plots(rendered_curve)


def test_stress_relaxation_defaults_to_log_linear_and_curve_also_renders(tmp_path: Path) -> None:
    input_path = _write_stress_relaxation_table(tmp_path / "relaxation.xlsx")

    inspection = inspect_input_file(input_path)
    assert inspection.model == "stress_relaxation"
    assert inspection.recommendations[0].template_id == "point_line"
    assert inspection.recommendations[0].preview_config_summary.get("xscale") == "log"
    assert inspection.recommendations[0].preview_config_summary.get("yscale") == "linear"

    point_options = resolve_render_options(template="point_line", xscale="log", yscale="linear")
    point_preflight = preflight_render_request("point_line", input_path, 0, point_options)
    assert point_preflight.errors == ()

    curve_options = resolve_render_options(template="curve", xscale="log", yscale="linear")
    curve_preflight = preflight_render_request("curve", input_path, 0, curve_options)
    assert curve_preflight.errors == ()
    assert curve_preflight.output_filenames == ("stress_relaxation_sigma_over_sigma0_curve.pdf",)

    rendered = build_rendered_plots("curve", input_path, xscale="log", yscale="linear")
    try:
        assert tuple(plot.filename for plot in rendered) == curve_preflight.output_filenames
    finally:
        close_rendered_plots(rendered)


def test_temperature_bundle_curve_preflight_matches_multi_output_render(tmp_path: Path) -> None:
    input_path = _write_temperature_sweep_table(tmp_path / "temperature.xlsx")

    inspection = inspect_input_file(input_path)
    assert inspection.model == "temperature_sweep"
    assert inspection.recommendations[0].template_id == "point_line"

    curve_options = resolve_render_options(template="curve", xscale="linear", yscale="log")
    curve_preflight = preflight_render_request("curve", input_path, 0, curve_options)
    assert curve_preflight.errors == ()
    assert curve_preflight.output_filenames == (
        "temp_storage_modulus_curve.pdf",
        "temp_complex_viscosity_curve.pdf",
    )

    rendered = build_rendered_plots("curve", input_path, xscale="linear", yscale="log")
    try:
        assert tuple(plot.filename for plot in rendered) == curve_preflight.output_filenames
    finally:
        close_rendered_plots(rendered)


def test_bar_preflight_matches_render_filename(tmp_path: Path) -> None:
    input_path = _write_replicate_table(tmp_path / "replicates.csv")

    options = resolve_render_options(template="bar")
    preflight = preflight_render_request("bar", input_path, 0, options)
    assert preflight.errors == ()

    rendered = build_rendered_plots("bar", input_path)
    try:
        assert tuple(plot.filename for plot in rendered) == preflight.output_filenames
    finally:
        close_rendered_plots(rendered)


def test_replicate_inspection_keeps_single_recommendation_compatibility_default(tmp_path: Path) -> None:
    input_path = _write_replicate_table(tmp_path / "replicates.csv")

    inspection = inspect_input_file(input_path)

    assert inspection.model == "replicate_table"
    assert inspection.recommendations[0].template_id == "box"
    assert inspection.recommendations
    assert inspection.recommendations[0].template_id == "box"
    assert {"bar", "point_error", "box_strip"}.issubset(
        {item.template_id for item in inspection.recommendations}
    )
    assert "grouped_bar_error" not in {item.template_id for item in inspection.recommendations}
    assert "distribution_compare" not in {item.template_id for item in inspection.recommendations}
    assert "lollipop_error" in {item.template_id for item in inspection.advanced_templates}


def test_grouped_bar_compare_preflight_matches_render_filename(tmp_path: Path) -> None:
    input_path = _write_replicate_table(tmp_path / "replicates.csv")

    options = resolve_render_options(template="grouped_bar_compare")
    preflight = preflight_render_request("grouped_bar_compare", input_path, 0, options)
    assert preflight.errors == ()
    assert preflight.requested_template_id == "grouped_bar_compare"
    assert preflight.canonical_id == "bar"
    assert preflight.output_filenames == ("tensile_modulus_bar.pdf",)

    rendered = build_rendered_plots("grouped_bar_compare", input_path)
    try:
        assert tuple(plot.filename for plot in rendered) == preflight.output_filenames
        assert rendered[0].qa_report is not None
        assert "bar_capsize_profile" in rendered[0].qa_report.autofixes_applied
        assert "bar_raw_points_overlay" not in rendered[0].qa_report.autofixes_applied
        assert not _path_collections(rendered[0].figure.axes[0])
    finally:
        close_rendered_plots(rendered)


def test_grouped_bar_error_preflight_matches_render_filename(tmp_path: Path) -> None:
    input_path = _write_replicate_table(tmp_path / "replicates.csv")

    options = resolve_render_options(template="grouped_bar_error")
    preflight = preflight_render_request("grouped_bar_error", input_path, 0, options)
    assert preflight.errors == ()
    assert preflight.canonical_id == "bar"
    assert preflight.output_filenames == ("tensile_modulus_bar.pdf",)

    rendered = build_rendered_plots("grouped_bar_error", input_path)
    try:
        assert tuple(plot.filename for plot in rendered) == preflight.output_filenames
        assert rendered[0].qa_report is not None
        assert "bar_capsize_profile" in rendered[0].qa_report.autofixes_applied
        assert "bar_raw_points_overlay" not in rendered[0].qa_report.autofixes_applied
        assert not _path_collections(rendered[0].figure.axes[0])
    finally:
        close_rendered_plots(rendered)


def test_grouped_bar_error_alias_renders_identically_to_bar(tmp_path: Path) -> None:
    input_path = _write_replicate_table(tmp_path / "replicates.csv")

    canonical = build_rendered_plots("bar", input_path)
    legacy = build_rendered_plots("grouped_bar_error", input_path)
    try:
        canonical[0].figure.canvas.draw()
        legacy[0].figure.canvas.draw()

        canonical_pixels = np.asarray(canonical[0].figure.canvas.buffer_rgba())
        legacy_pixels = np.asarray(legacy[0].figure.canvas.buffer_rgba())

        assert canonical[0].filename == "tensile_modulus_bar.pdf"
        assert legacy[0].filename == canonical[0].filename
        assert canonical_pixels.shape == legacy_pixels.shape
        assert np.array_equal(canonical_pixels, legacy_pixels)
    finally:
        close_rendered_plots(canonical)
        close_rendered_plots(legacy)


def test_point_error_preflight_matches_render_filename(tmp_path: Path) -> None:
    input_path = _write_replicate_table(tmp_path / "replicates.csv")

    options = resolve_render_options(template="point_error")
    preflight = preflight_render_request("point_error", input_path, 0, options)
    assert preflight.errors == ()
    assert preflight.output_filenames == ("tensile_modulus_point_error.pdf",)

    rendered = build_rendered_plots("point_error", input_path)
    try:
        assert tuple(plot.filename for plot in rendered) == preflight.output_filenames
        assert rendered[0].qa_report is not None
        assert "point_error_profile" in rendered[0].qa_report.autofixes_applied
    finally:
        close_rendered_plots(rendered)


def test_lollipop_error_preflight_matches_render_filename(tmp_path: Path) -> None:
    input_path = _write_replicate_table(tmp_path / "replicates.csv")

    options = resolve_render_options(template="lollipop_error")
    preflight = preflight_render_request("lollipop_error", input_path, 0, options)
    assert preflight.errors == ()
    assert preflight.output_filenames == ("tensile_modulus_lollipop_error.pdf",)

    rendered = build_rendered_plots("lollipop_error", input_path)
    try:
        assert tuple(plot.filename for plot in rendered) == preflight.output_filenames
        assert rendered[0].qa_report is not None
        assert "lollipop_stem_overlay" in rendered[0].qa_report.autofixes_applied
        assert "lollipop_error_profile" in rendered[0].qa_report.autofixes_applied
    finally:
        close_rendered_plots(rendered)


def test_violin_box_preflight_matches_render_filename(tmp_path: Path) -> None:
    input_path = _write_replicate_table(tmp_path / "replicates.csv")

    options = resolve_render_options(template="violin_box")
    preflight = preflight_render_request("violin_box", input_path, 0, options)
    assert preflight.errors == ()
    assert preflight.output_filenames == ("tensile_modulus_violin_box.pdf",)

    rendered = build_rendered_plots("violin_box", input_path)
    try:
        assert tuple(plot.filename for plot in rendered) == preflight.output_filenames
        assert rendered[0].qa_report is not None
        assert "violin_box_profile" in rendered[0].qa_report.autofixes_applied
        assert not _has_marker_lines(rendered[0].figure.axes[0])
    finally:
        close_rendered_plots(rendered)


def test_box_strip_preflight_matches_render_filename(tmp_path: Path) -> None:
    input_path = _write_replicate_table(tmp_path / "replicates.csv")

    options = resolve_render_options(template="box_strip")
    preflight = preflight_render_request("box_strip", input_path, 0, options)
    assert preflight.errors == ()
    assert preflight.output_filenames == ("tensile_modulus_box_strip.pdf",)

    rendered = build_rendered_plots("box_strip", input_path)
    try:
        assert tuple(plot.filename for plot in rendered) == preflight.output_filenames
        assert rendered[0].qa_report is not None
        assert "box_strip_profile" in rendered[0].qa_report.autofixes_applied
        assert "strip_point_overlay_emphasis" in rendered[0].qa_report.autofixes_applied
        collections = _path_collections(rendered[0].figure.axes[0])
        assert collections
        assert all(collection.get_edgecolors().size == 0 for collection in collections)
        assert not _has_marker_lines(rendered[0].figure.axes[0])
    finally:
        close_rendered_plots(rendered)


def test_distribution_compare_preflight_matches_render_filename(tmp_path: Path) -> None:
    input_path = _write_replicate_table(tmp_path / "replicates.csv")

    options = resolve_render_options(template="distribution_compare")
    preflight = preflight_render_request("distribution_compare", input_path, 0, options)
    assert preflight.errors == ()
    assert preflight.requested_template_id == "distribution_compare"
    assert preflight.canonical_id == "box_strip"
    assert preflight.output_filenames == ("tensile_modulus_box_strip.pdf",)

    rendered = build_rendered_plots("distribution_compare", input_path)
    try:
        assert tuple(plot.filename for plot in rendered) == preflight.output_filenames
        assert rendered[0].qa_report is not None
        assert "box_strip_profile" in rendered[0].qa_report.autofixes_applied
        assert "strip_point_overlay_emphasis" in rendered[0].qa_report.autofixes_applied
        collections = _path_collections(rendered[0].figure.axes[0])
        assert collections
        assert all(collection.get_edgecolors().size == 0 for collection in collections)
        assert not _has_marker_lines(rendered[0].figure.axes[0])
    finally:
        close_rendered_plots(rendered)


def test_histogram_density_preflight_matches_render_filename(tmp_path: Path) -> None:
    input_path = _write_replicate_table(tmp_path / "replicates.csv")

    options = resolve_render_options(template="histogram_density")
    preflight = preflight_render_request("histogram_density", input_path, 0, options)
    assert preflight.errors == ()
    assert preflight.output_filenames == ("tensile_modulus_histogram_density.pdf",)

    rendered = build_rendered_plots("histogram_density", input_path)
    try:
        assert tuple(plot.filename for plot in rendered) == preflight.output_filenames
        assert rendered[0].qa_report is not None
        assert "histogram_density_overlay" in rendered[0].qa_report.autofixes_applied
    finally:
        close_rendered_plots(rendered)


def test_histogram_density_preflight_warns_on_sparse_replicates(tmp_path: Path) -> None:
    input_path = _write_replicate_table(tmp_path / "replicates.csv")

    options = resolve_render_options(template="histogram_density")
    preflight = preflight_render_request("histogram_density", input_path, 0, options)

    assert preflight.errors == ()
    assert any("less stable with sparse replicates" in warning for warning in preflight.warnings)


def test_histogram_density_render_uses_discrete_binning_autofix_for_discrete_values(tmp_path: Path) -> None:
    input_path = _write_discrete_replicate_table(tmp_path / "discrete_replicates.csv")

    rendered = build_rendered_plots("histogram_density", input_path)
    try:
        assert len(rendered) == 1
        assert rendered[0].qa_report is not None
        assert "histogram_discrete_binning" in rendered[0].qa_report.autofixes_applied
    finally:
        close_rendered_plots(rendered)


def test_density_area_preflight_matches_render_filename(tmp_path: Path) -> None:
    input_path = _write_replicate_table(tmp_path / "replicates.csv")

    options = resolve_render_options(template="density_area")
    preflight = preflight_render_request("density_area", input_path, 0, options)
    assert preflight.errors == ()
    assert preflight.output_filenames == ("tensile_modulus_density_area.pdf",)

    rendered = build_rendered_plots("density_area", input_path)
    try:
        assert tuple(plot.filename for plot in rendered) == preflight.output_filenames
        assert rendered[0].qa_report is not None
        assert "density_area_overlay" in rendered[0].qa_report.autofixes_applied
        ax = rendered[0].figure.axes[0]
        assert any(isinstance(collection, PolyCollection) for collection in ax.collections)
    finally:
        close_rendered_plots(rendered)


def test_density_area_preflight_warns_on_sparse_replicates(tmp_path: Path) -> None:
    input_path = _write_replicate_table(tmp_path / "replicates.csv")

    options = resolve_render_options(template="density_area")
    preflight = preflight_render_request("density_area", input_path, 0, options)

    assert preflight.errors == ()
    assert any("less stable with sparse replicates" in warning for warning in preflight.warnings)


def test_distribution_compare_uses_violin_variant_when_groups_are_few_and_dense(tmp_path: Path) -> None:
    input_path = _write_dense_replicate_table(tmp_path / "dense_replicates.csv")

    rendered = build_rendered_plots("distribution_compare", input_path)
    try:
        assert len(rendered) == 1
        assert rendered[0].qa_report is not None
        assert rendered[0].filename.endswith("_violin.pdf")
    finally:
        close_rendered_plots(rendered)


def test_distribution_compare_uses_box_variant_when_group_count_is_large(tmp_path: Path) -> None:
    input_path = _write_many_group_replicate_table(tmp_path / "many_groups.csv")

    rendered = build_rendered_plots("distribution_compare", input_path)
    try:
        assert len(rendered) == 1
        assert rendered[0].qa_report is not None
        assert rendered[0].filename.endswith("_box.pdf")
        assert not _path_collections(rendered[0].figure.axes[0])
        assert not _has_marker_lines(rendered[0].figure.axes[0])
    finally:
        close_rendered_plots(rendered)


def test_box_render_is_summary_only_and_hides_fliers(tmp_path: Path) -> None:
    input_path = _write_replicate_table(tmp_path / "replicates.csv")

    rendered = build_rendered_plots("box", input_path)
    try:
        assert len(rendered) == 1
        plot = rendered[0]
        assert plot.qa_report is not None
        ax = plot.figure.axes[0]
        assert not _path_collections(ax)
        assert not _has_marker_lines(ax)
    finally:
        close_rendered_plots(rendered)


def test_scatter_with_fit_preflight_matches_render_filename(tmp_path: Path) -> None:
    input_path = _write_curve_table(tmp_path / "curve.csv")

    options = resolve_render_options(template="scatter_with_fit")
    preflight = preflight_render_request("scatter_with_fit", input_path, 0, options)
    assert preflight.errors == ()
    assert preflight.requested_template_id == "scatter_with_fit"
    assert preflight.canonical_id == "scatter_fit"
    assert preflight.role == "alias"
    assert preflight.lifecycle_policy == "deprecated_in_practice"
    assert preflight.implementation_id == "scatter_fit"
    assert preflight.output_filenames == ("curve_scatter_fit.pdf",)

    rendered = build_rendered_plots("scatter_with_fit", input_path)
    try:
        assert tuple(plot.filename for plot in rendered) == preflight.output_filenames
        assert rendered[0].qa_report is not None
        assert "deterministic_linear_fit_overlay" in rendered[0].qa_report.autofixes_applied
    finally:
        close_rendered_plots(rendered)


def test_scatter_fit_preflight_matches_render_filename(tmp_path: Path) -> None:
    input_path = _write_curve_table(tmp_path / "curve.csv")

    options = resolve_render_options(template="scatter_fit")
    preflight = preflight_render_request("scatter_fit", input_path, 0, options)
    assert preflight.errors == ()
    assert preflight.output_filenames == ("curve_scatter_fit.pdf",)

    rendered = build_rendered_plots("scatter_fit", input_path)
    try:
        assert tuple(plot.filename for plot in rendered) == preflight.output_filenames
        assert rendered[0].qa_report is not None
        assert "deterministic_linear_fit_overlay" in rendered[0].qa_report.autofixes_applied
    finally:
        close_rendered_plots(rendered)


def test_reference_guides_overlay_line_and_band_on_curve(tmp_path: Path) -> None:
    input_path = _write_curve_table(tmp_path / "curve.csv")

    rendered = build_rendered_plots(
        "curve",
        input_path,
        reference_guides=[
            {
                "id": "target-line",
                "enabled": True,
                "kind": "line",
                "axis_target": "y_primary",
                "value": 2.5,
                "label": "Target",
            },
            {
                "id": "window-region",
                "enabled": True,
                "kind": "band",
                "axis_target": "x",
                "start": 0.5,
                "end": 1.5,
                "label": "Window",
            },
        ],
    )
    try:
        plot = rendered[0]
        assert plot.qa_report is not None
        assert "reference_line_overlay" in plot.qa_report.autofixes_applied
        assert "reference_band_overlay" in plot.qa_report.autofixes_applied
        ax = plot.figure.axes[0]
        assert any(line.get_linestyle() == "--" for line in ax.lines)
        assert ax.patches
        assert {"Target", "Window"} <= {text.get_text() for text in ax.texts}
    finally:
        close_rendered_plots(rendered)


def test_reference_line_rejects_non_positive_value_on_log_axis(tmp_path: Path) -> None:
    input_path = _write_dense_curve_table(tmp_path / "curve.csv")

    with pytest.raises(ValueError, match="positive value"):
        build_rendered_plots(
            "curve",
            input_path,
            xscale="log",
            reference_guides=[
                {
                    "id": "bad-line",
                    "enabled": True,
                    "kind": "line",
                    "axis_target": "x",
                    "value": 0.0,
                }
            ],
        )


def test_reference_guides_support_secondary_y_axis_targets(tmp_path: Path) -> None:
    input_path = _write_curve_table(tmp_path / "curve.csv")

    rendered = build_rendered_plots(
        "curve",
        input_path,
        extra_y_axis={
            "enabled": True,
            "position": "right",
            "title": "Half Stress",
            "data_value": 2.0,
            "display_value": 1.0,
        },
        reference_guides=[
            {
                "id": "secondary-line",
                "enabled": True,
                "kind": "line",
                "axis_target": "y_secondary",
                "value": 1.0,
                "label": "Half target",
            }
        ],
    )
    try:
        axes = _primary_and_secondary_axes(rendered[0])
        secondary_axes = [axis for axis in axes[1:] if axis.get_ylabel() == "Half Stress"]
        assert secondary_axes
        assert any(line.get_linestyle() == "--" for line in axes[0].lines)
        assert "Half target" in {
            text.get_text()
            for axis in axes
            for text in axis.texts
        }
    finally:
        close_rendered_plots(rendered)


def test_text_annotations_overlay_can_place_multiple_labels_and_callouts(tmp_path: Path) -> None:
    input_path = _write_curve_table(tmp_path / "curve.csv")

    rendered = build_rendered_plots(
        "curve",
        input_path,
        text_annotations=[
            {
                "id": "frame-note",
                "enabled": True,
                "text": "Frame note",
                "coordinate_space": "axes_fraction",
                "x": 0.04,
                "y": 0.96,
                "display_style": "callout",
                "connector_enabled": True,
                "target_x": 2.0,
                "target_y": 2.8,
                "horizontal_alignment": "left",
                "vertical_alignment": "top",
            },
            {
                "id": "data-note",
                "enabled": True,
                "text": "Peak",
                "coordinate_space": "data",
                "x": 2.0,
                "y": 5.0,
                "y_axis_target": "y_primary",
                "horizontal_alignment": "right",
                "vertical_alignment": "bottom",
            },
        ],
    )
    try:
        plot = rendered[0]
        assert plot.qa_report is not None
        assert "text_annotation_overlay" in plot.qa_report.autofixes_applied
        assert {"Frame note", "Peak"} <= {text.get_text() for text in plot.figure.axes[0].texts}
    finally:
        close_rendered_plots(rendered)


def test_shape_annotations_overlay_regions_and_secondary_y_brackets(tmp_path: Path) -> None:
    input_path = _write_curve_table(tmp_path / "curve.csv")

    rendered = build_rendered_plots(
        "curve",
        input_path,
        extra_y_axis={
            "enabled": True,
            "position": "right",
            "title": "Half Stress",
            "data_value": 2.0,
            "display_value": 1.0,
        },
        shape_annotations=[
            {
                "id": "focus-window",
                "enabled": True,
                "kind": "rectangle",
                "x_start": 0.5,
                "x_end": 1.5,
                "y_start": 2.0,
                "y_end": 3.0,
                "label": "Window",
            },
            {
                "id": "secondary-bracket",
                "enabled": True,
                "kind": "bracket",
                "bracket_orientation": "horizontal",
                "x_start": 1.2,
                "x_end": 2.6,
                "y_start": 1.1,
                "y_end": 1.1,
                "y_axis_target": "y_secondary",
                "label": "Half target",
            },
        ],
    )
    try:
        plot = rendered[0]
        assert plot.qa_report is not None
        assert "shape_annotation_overlay" in plot.qa_report.autofixes_applied
        axes = _primary_and_secondary_axes(plot)
        assert any(ax.patches for ax in axes)
        assert {"Window", "Half target"} <= {
            text.get_text()
            for axis in axes
            for text in axis.texts
        }
    finally:
        close_rendered_plots(rendered)


def test_text_annotation_rejects_non_positive_data_coordinate_on_log_axis(tmp_path: Path) -> None:
    input_path = _write_dense_curve_table(tmp_path / "curve.csv")

    with pytest.raises(ValueError, match="positive x value"):
        build_rendered_plots(
            "curve",
            input_path,
            xscale="log",
            text_annotations=[
                {
                    "id": "bad-note",
                    "enabled": True,
                    "text": "Bad",
                    "coordinate_space": "data",
                    "x": 0.0,
                    "y": 1.0,
                    "connector_enabled": True,
                    "target_x": 1.0,
                    "target_y": 1.0,
                    "horizontal_alignment": "center",
                    "vertical_alignment": "top",
                }
            ],
        )


def test_extra_axes_overlay_can_add_secondary_converted_axes(tmp_path: Path) -> None:
    input_path = _write_curve_table(tmp_path / "curve.csv")

    rendered = build_rendered_plots(
        "curve",
        input_path,
        extra_x_axis={
            "enabled": True,
            "position": "top",
            "title": "Gallons",
            "data_value": 3.78541,
            "display_value": 1.0,
        },
        extra_y_axis={
            "enabled": True,
            "position": "right",
            "title": "Half Stress",
            "data_value": 2.0,
            "display_value": 1.0,
        },
    )
    try:
        plot = rendered[0]
        assert plot.qa_report is not None
        assert "extra_axis_overlay" in plot.qa_report.autofixes_applied
        assert len(plot.figure.axes[0].child_axes) >= 2
        labels = {
            axis.get_xlabel()
            for axis in _primary_and_secondary_axes(plot)
            if axis.get_xlabel()
        } | {
            axis.get_ylabel()
            for axis in _primary_and_secondary_axes(plot)
            if axis.get_ylabel()
        }
        assert "Gallons" in labels
        assert "Half Stress" in labels
    finally:
        close_rendered_plots(rendered)


def test_extra_axes_overlay_supports_log_parent_axis(tmp_path: Path) -> None:
    input_path = _write_dense_curve_table(tmp_path / "curve.csv")

    rendered = build_rendered_plots(
        "curve",
        input_path,
        xscale="log",
        extra_x_axis={
            "enabled": True,
            "position": "top",
            "title": "Scaled X",
            "data_value": 10.0,
            "display_value": 1.0,
        },
    )
    try:
        labels = [
            axis.get_xlabel()
            for axis in _primary_and_secondary_axes(rendered[0])
            if axis.get_xlabel()
        ]
        assert "Scaled X" in labels
    finally:
        close_rendered_plots(rendered)


def test_extra_y_axis_series_assignment_moves_selected_curve_series_to_secondary_axis(tmp_path: Path) -> None:
    input_path = _write_multi_curve_table(tmp_path / "curve.csv")

    rendered = build_rendered_plots(
        "curve",
        input_path,
        extra_y_axis={
            "enabled": True,
            "position": "right",
            "binding_mode": "series_assignment",
            "series_ids": ["Sample C", "Sample D"],
            "title": "Secondary Stress",
        },
    )
    try:
        plot = rendered[0]
        assert plot.qa_report is not None
        assert "extra_axis_series_assignment" in plot.qa_report.autofixes_applied
        axes = plot.figure.axes
        assert len(axes) >= 2
        primary_ax, secondary_ax = axes[0], axes[1]
        assert [line.get_label() for line in primary_ax.lines] == ["Sample A", "Sample B"]
        assert [line.get_label() for line in secondary_ax.lines] == ["Sample C", "Sample D"]
        assert secondary_ax.get_ylabel() == "Secondary Stress"
    finally:
        close_rendered_plots(rendered)


def test_extra_y_axis_series_assignment_routes_scatter_fit_overlay_to_secondary_axis(tmp_path: Path) -> None:
    input_path = _write_multi_curve_table(tmp_path / "curve.csv")

    rendered = build_rendered_plots(
        "scatter",
        input_path,
        fit_options={"enabled": True, "model_id": "linear"},
        extra_y_axis={
            "enabled": True,
            "position": "right",
            "binding_mode": "series_assignment",
            "series_ids": ["Sample D"],
            "title": "Secondary Stress",
        },
    )
    try:
        axes = rendered[0].figure.axes
        assert len(axes) >= 2
        primary_ax, secondary_ax = axes[0], axes[1]
        primary_overlay_count = sum(1 for line in primary_ax.lines if line.get_linestyle() == "--")
        secondary_overlay_count = sum(1 for line in secondary_ax.lines if line.get_linestyle() == "--")
        assert primary_overlay_count == 3
        assert secondary_overlay_count == 1
    finally:
        close_rendered_plots(rendered)


def test_axis_breaks_overlay_compresses_curve_and_reuses_reference_guides_and_annotations(tmp_path: Path) -> None:
    input_path = _write_curve_table(tmp_path / "curve.csv")

    rendered = build_rendered_plots(
        "curve",
        input_path,
        x_axis_breaks=[
            {
                "id": "x-gap",
                "enabled": True,
                "start": 0.8,
                "end": 1.2,
            }
        ],
        y_axis_breaks=[
            {
                "id": "y-gap",
                "enabled": True,
                "start": 1.4,
                "end": 2.2,
            }
        ],
        reference_guides=[
            {
                "id": "target-line",
                "enabled": True,
                "kind": "line",
                "axis_target": "y_primary",
                "value": 2.4,
                "label": "Target",
            },
            {
                "id": "window-region",
                "enabled": True,
                "kind": "band",
                "axis_target": "x",
                "start": 0.5,
                "end": 1.5,
                "label": "Window",
            },
        ],
        text_annotations=[
            {
                "id": "visible-note",
                "enabled": True,
                "text": "Peak",
                "coordinate_space": "data",
                "x": 2.0,
                "y": 2.8,
                "y_axis_target": "y_primary",
                "horizontal_alignment": "right",
                "vertical_alignment": "bottom",
                "connector_enabled": True,
                "target_x": 1.5,
                "target_y": 2.4,
                "target_y_axis_target": "y_primary",
            },
            {
                "id": "hidden-note",
                "enabled": True,
                "text": "Hidden",
                "coordinate_space": "data",
                "x": 1.0,
                "y": 2.0,
                "y_axis_target": "y_primary",
                "horizontal_alignment": "center",
                "vertical_alignment": "top",
            },
        ],
    )
    try:
        plot = rendered[0]
        assert plot.qa_report is not None
        assert "axis_break_overlay" in plot.qa_report.autofixes_applied
        assert "reference_line_overlay" in plot.qa_report.autofixes_applied
        assert "reference_band_overlay" in plot.qa_report.autofixes_applied
        assert "text_annotation_overlay" in plot.qa_report.autofixes_applied

        ax = plot.figure.axes[0]
        assert ax.get_xlim()[1] < 2.0
        assert ax.get_ylim()[1] < 2.8
        assert any(
            np.isnan(np.asarray(line.get_xdata(), dtype=float)).any()
            for line in ax.lines
            if line.get_label() != "_nolegend_"
        )
        assert len(ax.patches) >= 2

        visible_texts = {text.get_text() for text in ax.texts if text.get_visible()}
        assert "Peak" in visible_texts
        assert "Hidden" not in visible_texts
        assert "Target" in visible_texts
        assert "Window" in visible_texts
    finally:
        close_rendered_plots(rendered)


def test_axis_breaks_filter_scatter_points_inside_hidden_span(tmp_path: Path) -> None:
    input_path = _write_curve_table(tmp_path / "curve.csv")

    rendered = build_rendered_plots(
        "scatter",
        input_path,
        x_axis_breaks=[
            {
                "id": "x-gap",
                "enabled": True,
                "start": 0.8,
                "end": 1.2,
            }
        ],
    )
    try:
        ax = rendered[0].figure.axes[0]
        collections = _path_collections(ax)
        assert collections
        total_points = sum(np.asarray(collection.get_offsets()).shape[0] for collection in collections)
        assert total_points == 4
    finally:
        close_rendered_plots(rendered)


def test_axis_breaks_split_layout_reuses_guides_and_annotations(tmp_path: Path) -> None:
    input_path = _write_curve_table(tmp_path / "curve.csv")

    rendered = build_rendered_plots(
        "curve",
        input_path,
        x_axis_breaks=[
            {
                "id": "x-gap",
                "enabled": True,
                "start": 0.8,
                "end": 1.2,
                "display_mode": "split",
            }
        ],
        reference_guides=[
            {
                "id": "target-line",
                "enabled": True,
                "kind": "line",
                "axis_target": "y_primary",
                "value": 2.4,
                "label": "Target",
            },
            {
                "id": "window-region",
                "enabled": True,
                "kind": "band",
                "axis_target": "x",
                "start": 0.5,
                "end": 1.5,
                "label": "Window",
            },
        ],
        text_annotations=[
            {
                "id": "visible-note",
                "enabled": True,
                "text": "Peak",
                "coordinate_space": "data",
                "x": 2.0,
                "y": 2.8,
                "y_axis_target": "y_primary",
                "horizontal_alignment": "right",
                "vertical_alignment": "bottom",
                "connector_enabled": True,
                "target_x": 1.5,
                "target_y": 2.4,
                "target_y_axis_target": "y_primary",
            },
            {
                "id": "hidden-note",
                "enabled": True,
                "text": "Hidden",
                "coordinate_space": "data",
                "x": 1.0,
                "y": 2.0,
                "y_axis_target": "y_primary",
                "horizontal_alignment": "center",
                "vertical_alignment": "top",
            },
        ],
    )
    try:
        plot = rendered[0]
        assert plot.qa_report is not None
        assert "axis_break_overlay" in plot.qa_report.autofixes_applied
        assert "axis_break_split_layout" in plot.qa_report.autofixes_applied
        assert "reference_line_overlay" in plot.qa_report.autofixes_applied
        assert "reference_band_overlay" in plot.qa_report.autofixes_applied
        assert "text_annotation_overlay" in plot.qa_report.autofixes_applied

        assert len(plot.figure.axes) == 2
        visible_texts = {
            text.get_text()
            for axis in plot.figure.axes
            for text in axis.texts
            if text.get_visible()
        }
        assert "Peak" in visible_texts
        assert "Hidden" not in visible_texts
        assert "Target" in visible_texts
        assert "Window" in visible_texts
        assert sum(len(axis.patches) for axis in plot.figure.axes) >= 2
    finally:
        close_rendered_plots(rendered)


def test_shape_annotations_reuse_split_axis_panel_mapping(tmp_path: Path) -> None:
    input_path = _write_curve_table(tmp_path / "curve.csv")

    rendered = build_rendered_plots(
        "curve",
        input_path,
        x_axis_breaks=[
            {
                "id": "x-gap",
                "enabled": True,
                "start": 0.8,
                "end": 1.2,
                "display_mode": "split",
            }
        ],
        shape_annotations=[
            {
                "id": "focus-window",
                "enabled": True,
                "kind": "ellipse",
                "x_start": 0.5,
                "x_end": 1.8,
                "y_start": 2.0,
                "y_end": 3.2,
                "label": "Window",
            },
            {
                "id": "significance",
                "enabled": True,
                "kind": "bracket",
                "bracket_orientation": "horizontal",
                "x_start": 1.4,
                "x_end": 2.4,
                "y_start": 3.4,
                "y_end": 3.4,
                "label": "p < 0.05",
            },
        ],
    )
    try:
        plot = rendered[0]
        assert plot.qa_report is not None
        assert "axis_break_overlay" in plot.qa_report.autofixes_applied
        assert "shape_annotation_overlay" in plot.qa_report.autofixes_applied
        assert len(plot.figure.axes) >= 2
        assert sum(len(axis.patches) for axis in plot.figure.axes) >= 1
        visible_texts = {
            text.get_text()
            for axis in plot.figure.axes
            for text in axis.texts
            if text.get_visible()
        }
        assert "Window" in visible_texts
        assert "p < 0.05" in visible_texts
    finally:
        close_rendered_plots(rendered)


def test_area_curve_preflight_matches_render_filename(tmp_path: Path) -> None:
    input_path = _write_curve_table(tmp_path / "curve.csv")

    options = resolve_render_options(template="area_curve")
    preflight = preflight_render_request("area_curve", input_path, 0, options)
    assert preflight.errors == ()
    assert preflight.output_filenames == ("curve_area_curve.pdf",)

    rendered = build_rendered_plots("area_curve", input_path)
    try:
        assert tuple(plot.filename for plot in rendered) == preflight.output_filenames
        ax = rendered[0].figure.axes[0]
        assert any(isinstance(collection, PolyCollection) for collection in ax.collections)
    finally:
        close_rendered_plots(rendered)


def test_step_line_preflight_matches_render_filename(tmp_path: Path) -> None:
    input_path = _write_curve_table(tmp_path / "curve.csv")

    options = resolve_render_options(template="step_line")
    preflight = preflight_render_request("step_line", input_path, 0, options)
    assert preflight.errors == ()
    assert preflight.output_filenames == ("curve_step_line.pdf",)

    rendered = build_rendered_plots("step_line", input_path)
    try:
        assert tuple(plot.filename for plot in rendered) == preflight.output_filenames
        ax = rendered[0].figure.axes[0]
        assert "steps-mid" in {line.get_drawstyle() for line in ax.lines}
    finally:
        close_rendered_plots(rendered)


def test_stacked_area_preflight_matches_render_filename(tmp_path: Path) -> None:
    input_path = _write_curve_table(tmp_path / "curve.csv")

    options = resolve_render_options(template="stacked_area")
    preflight = preflight_render_request("stacked_area", input_path, 0, options)
    assert preflight.errors == ()
    assert preflight.output_filenames == ("curve_stacked_area.pdf",)

    rendered = build_rendered_plots("stacked_area", input_path)
    try:
        assert tuple(plot.filename for plot in rendered) == preflight.output_filenames
        ax = rendered[0].figure.axes[0]
        assert any(isinstance(collection, PolyCollection) for collection in ax.collections)
    finally:
        close_rendered_plots(rendered)


def test_bubble_scatter_preflight_matches_render_filename(tmp_path: Path) -> None:
    input_path = _write_curve_table(tmp_path / "curve.csv")

    options = resolve_render_options(template="bubble_scatter")
    preflight = preflight_render_request("bubble_scatter", input_path, 0, options)
    assert preflight.errors == ()
    assert preflight.output_filenames == ("curve_bubble_scatter.pdf",)

    rendered = build_rendered_plots("bubble_scatter", input_path)
    try:
        assert tuple(plot.filename for plot in rendered) == preflight.output_filenames
        assert rendered[0].qa_report is not None
        assert "bubble_size_encoding" in rendered[0].qa_report.autofixes_applied
        ax = rendered[0].figure.axes[0]
        bubble_sizes = np.concatenate(
            [
                np.asarray(collection.get_sizes(), dtype=float)
                for collection in ax.collections
                if np.asarray(collection.get_offsets()).size and np.asarray(collection.get_sizes()).size
            ]
        )
        assert bubble_sizes.max() > bubble_sizes.min()
    finally:
        close_rendered_plots(rendered)


def test_mean_band_preflight_matches_render_filename(tmp_path: Path) -> None:
    input_path = _write_multi_curve_table(tmp_path / "multi_curve.csv")

    options = resolve_render_options(template="mean_band")
    preflight = preflight_render_request("mean_band", input_path, 0, options)
    assert preflight.errors == ()
    assert preflight.output_filenames == ("multi_curve_mean_band.pdf",)

    rendered = build_rendered_plots("mean_band", input_path)
    try:
        assert tuple(plot.filename for plot in rendered) == preflight.output_filenames
        assert rendered[0].qa_report is not None
        assert "replicate_mean_band_overlay" in rendered[0].qa_report.autofixes_applied
    finally:
        close_rendered_plots(rendered)


def test_annotated_heatmap_preflight_matches_render_filename(tmp_path: Path) -> None:
    input_path = _write_heatmap_table(tmp_path / "heatmap.csv")

    options = resolve_render_options(template="annotated_heatmap")
    preflight = preflight_render_request("annotated_heatmap", input_path, 0, options)
    assert preflight.errors == ()
    assert preflight.output_filenames == ("heatmap_annotated_heatmap.pdf",)

    rendered = build_rendered_plots("annotated_heatmap", input_path)
    try:
        assert tuple(plot.filename for plot in rendered) == preflight.output_filenames
        assert rendered[0].qa_report is not None
        assert "annotated_heatmap_labels" in rendered[0].qa_report.autofixes_applied
        layout_debug = getattr(rendered[0].figure, "_sciplot_layout_debug", [])
        annotation_records = [
            entry
            for entry in layout_debug
            if entry.get("object_kind") == "annotation_textbox"
            and entry.get("context", {}).get("annotation_kind") == "heatmap_cell_labels"
        ]
        assert annotation_records
        assert annotation_records[0]["chosen_candidate_id"] is not None
        assert annotation_records[0]["candidates"]
    finally:
        close_rendered_plots(rendered)


def test_annotated_heatmap_preflight_warns_for_single_row_or_column_matrices(tmp_path: Path) -> None:
    input_path = tmp_path / "single_row_heatmap.csv"
    rows = [
        ["X", "Y", "Z"],
        ["Temperature", "Time", "Intensity"],
        ["degC", "min", "a.u."],
        [25.0, 0.0, 0.18],
        [40.0, 0.0, 0.46],
        [55.0, 0.0, 0.77],
    ]
    pd.DataFrame(rows).to_csv(input_path, header=False, index=False)

    options = resolve_render_options(template="annotated_heatmap")
    preflight = preflight_render_request("annotated_heatmap", input_path, 0, options)

    assert preflight.errors == ()
    assert any("single-row/column matrices" in warning for warning in preflight.warnings)


def test_function_curve_preflight_and_render_with_analytical_layer(tmp_path: Path) -> None:
    input_path = _write_curve_table(tmp_path / "function.csv")
    layer = {
        "id": "sin-layer",
        "enabled": True,
        "kind": "function",
        "expression": "sin(x) + 1",
        "x_start": 0.0,
        "x_end": 2.0,
        "sample_count": 80,
        "label": "sin layer",
    }
    options = resolve_render_options(template="function_curve", analytical_layers=[layer])

    preflight = preflight_render_request("function_curve", input_path, 0, options)
    assert preflight.errors == ()
    assert preflight.output_filenames == ("function_function_curve.pdf",)

    rendered = build_rendered_plots("function_curve", input_path, analytical_layers=[layer])
    try:
        labels = [line.get_label() for line in rendered[0].figure.axes[0].lines]
        assert "sin layer" in labels
        assert rendered[0].qa_report is not None
        assert "analytical_function_layer" in rendered[0].qa_report.autofixes_applied
    finally:
        close_rendered_plots(rendered)


def test_new_datagraph_templates_preflight_and_render(tmp_path: Path) -> None:
    cases = [
        ("contour_field", _write_contour_field_table(tmp_path / "field.csv"), "field_contour_field.pdf"),
        ("polar_curve", _write_polar_curve_table(tmp_path / "polar.csv"), "polar_polar_curve.pdf"),
        ("table_figure", _write_small_table(tmp_path / "summary.csv"), "summary_table_figure.pdf"),
    ]
    for template, input_path, filename in cases:
        options = resolve_render_options(template=template)
        preflight = preflight_render_request(template, input_path, 0, options)
        assert preflight.errors == ()
        assert preflight.output_filenames == (filename,)
        rendered = build_rendered_plots(template, input_path)
        try:
            assert rendered[0].filename == filename
            assert rendered[0].figure.axes
        finally:
            close_rendered_plots(rendered)


def test_contour_field_preflight_and_render_with_pivot_transform(tmp_path: Path) -> None:
    input_path = tmp_path / "long-field.csv"
    pd.DataFrame(
        [
            ["angle", "radius", "signal"],
            [0.0, 1.0, 10.0],
            [90.0, 1.0, 20.0],
            [0.0, 2.0, 30.0],
            [90.0, 2.0, 40.0],
        ]
    ).to_csv(input_path, header=False, index=False)
    transform = {
        "id": "field-pivot",
        "kind": "pivot_matrix",
        "x_column": "angle",
        "y_column": "radius",
        "z_column": "signal",
        "output_mode": "xyz_long",
    }

    options = resolve_render_options(template="contour_field", data_transforms=[transform])
    preflight = preflight_render_request("contour_field", input_path, 0, options)
    assert preflight.errors == ()
    assert preflight.output_filenames == ("long-field_contour_field.pdf",)

    rendered = build_rendered_plots("contour_field", input_path, data_transforms=[transform])
    try:
        assert rendered[0].filename == "long-field_contour_field.pdf"
        assert rendered[0].figure.axes
    finally:
        close_rendered_plots(rendered)


def test_datagraph_template_preflight_reports_shape_specific_errors(tmp_path: Path) -> None:
    missing_z = tmp_path / "missing_z.csv"
    pd.DataFrame(
        [
            ["X", "Y", "Signal"],
            ["mm", "mm", "a.u."],
            ["field", "field", "field"],
            [0.0, 0.0, 1.0],
            [1.0, 0.0, 2.0],
        ]
    ).to_csv(missing_z, header=False, index=False)
    non_polar = _write_curve_table(tmp_path / "curve.csv")
    large_table = tmp_path / "large_table.csv"
    pd.DataFrame([[f"C{index}" for index in range(10)], *[[row] * 10 for row in range(20)]]).to_csv(
        large_table,
        header=False,
        index=False,
    )

    contour = preflight_render_request("contour_field", missing_z, 0, resolve_render_options(template="contour_field"))
    polar = preflight_render_request("polar_curve", non_polar, 0, resolve_render_options(template="polar_curve"))
    table = preflight_render_request("table_figure", large_table, 0, resolve_render_options(template="table_figure"))

    assert contour.errors
    assert "X, Y, and Z" in contour.errors[0]
    assert polar.errors
    assert "theta/radius" in polar.errors[0].lower()
    assert table.errors
    assert "small table" in table.errors[0].lower()


def test_annotated_heatmap_dense_matrix_can_fallback_to_non_default_label_strategy(tmp_path: Path) -> None:
    input_path = tmp_path / "dense_annotated_heatmap.csv"
    rows = [["X", "Y", "Z"], ["Temperature", "Time", "Intensity"], ["degC", "min", "a.u."]]
    for x_idx in range(20):
        for y_idx in range(20):
            rows.append([float(x_idx), float(y_idx), float(np.sin(x_idx * 0.3) + np.cos(y_idx * 0.4))])
    pd.DataFrame(rows).to_csv(input_path, header=False, index=False)

    rendered = build_rendered_plots("annotated_heatmap", input_path)
    try:
        assert len(rendered) == 1
        plot = rendered[0]
        assert plot.qa_report is not None
        layout_debug = getattr(plot.figure, "_sciplot_layout_debug", [])
        annotation_records = [
            entry
            for entry in layout_debug
            if entry.get("object_kind") == "annotation_textbox"
            and entry.get("context", {}).get("annotation_kind") == "heatmap_cell_labels"
        ]
        assert annotation_records
        chosen_id = str(annotation_records[0].get("chosen_candidate_id"))
        assert chosen_id.startswith("labels_")
        assert (annotation_records[0].get("fallback_action") is not None) or (chosen_id == "labels_full")
    finally:
        close_rendered_plots(rendered)


def test_replicate_curves_with_band_preflight_matches_render_filename(tmp_path: Path) -> None:
    input_path = _write_multi_curve_table(tmp_path / "multi_curve.csv")

    options = resolve_render_options(template="replicate_curves_with_band")
    preflight = preflight_render_request("replicate_curves_with_band", input_path, 0, options)
    assert preflight.errors == ()
    assert preflight.canonical_id == "mean_band"
    assert preflight.output_filenames == ("multi_curve_mean_band.pdf",)

    rendered = build_rendered_plots("replicate_curves_with_band", input_path)
    try:
        assert tuple(plot.filename for plot in rendered) == preflight.output_filenames
        assert rendered[0].qa_report is not None
        assert "replicate_mean_band_overlay" in rendered[0].qa_report.autofixes_applied
    finally:
        close_rendered_plots(rendered)


def test_replicate_curves_with_band_rejects_rheology_bundle(tmp_path: Path) -> None:
    input_path = _write_frequency_sweep_table(tmp_path / "frequency.xlsx")

    options = resolve_render_options(template="replicate_curves_with_band")
    preflight = preflight_render_request("replicate_curves_with_band", input_path, 0, options)
    assert preflight.errors == ("mean_band is not supported for rheology export bundles.",)

    with pytest.raises(ValueError, match="not supported for rheology export bundles"):
        build_rendered_plots("replicate_curves_with_band", input_path)


def test_mean_band_rejects_rheology_bundle(tmp_path: Path) -> None:
    input_path = _write_frequency_sweep_table(tmp_path / "frequency.xlsx")

    options = resolve_render_options(template="mean_band")
    preflight = preflight_render_request("mean_band", input_path, 0, options)
    assert preflight.errors == ("mean_band is not supported for rheology export bundles.",)

    with pytest.raises(ValueError, match="not supported for rheology export bundles"):
        build_rendered_plots("mean_band", input_path)


def test_replicate_curves_with_band_preflight_rejects_poor_x_alignment(tmp_path: Path) -> None:
    input_path = _write_poorly_aligned_curve_table(tmp_path / "poorly_aligned_curve.csv")

    options = resolve_render_options(template="replicate_curves_with_band")
    preflight = preflight_render_request("replicate_curves_with_band", input_path, 0, options)

    assert preflight.errors == (
        "mean_band requires at least two shared x positions across replicates. "
        "Align the x values (or sampling grid) before rendering.",
    )


def test_small_curve_render_prefers_direct_labels_when_they_fit(tmp_path: Path) -> None:
    input_path = _write_dense_curve_table(tmp_path / "dense_curve.csv")

    rendered = build_rendered_plots("curve", input_path)
    try:
        assert len(rendered) == 1
        plot = rendered[0]
        assert plot.qa_report is not None
        assert "direct_series_labels" in plot.qa_report.autofixes_applied
        ax = plot.figure.axes[0]
        assert ax.get_legend() is None
        assert {text.get_text() for text in ax.texts} == {"Sample A", "Sample B"}
    finally:
        close_rendered_plots(rendered)


def test_large_curve_render_keeps_legend_when_direct_labels_are_not_preferred(tmp_path: Path) -> None:
    input_path = _write_dense_curve_table(tmp_path / "dense_curve.csv")

    rendered = build_rendered_plots("curve", input_path, size="120x55")
    try:
        assert len(rendered) == 1
        plot = rendered[0]
        assert plot.qa_report is not None
        ax = plot.figure.axes[0]
        assert ax.get_legend() is not None
        assert {text.get_text() for text in ax.texts} == set()
    finally:
        close_rendered_plots(rendered)


def test_small_tensile_curve_with_four_series_keeps_legend(tmp_path: Path) -> None:
    input_path = _write_multi_tensile_curve_table(tmp_path / "multi_tensile_curve.csv")

    rendered = build_rendered_plots("curve", input_path)
    try:
        assert len(rendered) == 1
        plot = rendered[0]
        assert plot.qa_report is not None
        assert "direct_series_labels" not in plot.qa_report.autofixes_applied
        ax = plot.figure.axes[0]
        assert ax.get_legend() is not None
    finally:
        close_rendered_plots(rendered)


def test_small_monotonic_curve_uses_direct_label_fallback_when_edge_labels_fail(tmp_path: Path) -> None:
    input_path = _write_monotonic_curve_table(tmp_path / "dma_like_curve.csv")

    rendered = build_rendered_plots("curve", input_path)
    try:
        assert len(rendered) == 1
        plot = rendered[0]
        assert plot.qa_report is not None
        issue_ids = {issue.id for issue in plot.qa_report.issues}
        assert plot.qa_report.grade in {"solid", "excellent"}
        assert "direct_series_labels" in plot.qa_report.autofixes_applied
        assert "legend_footprint" not in issue_ids
        assert "series_identification" not in issue_ids
        assert "stroke_hierarchy" not in issue_ids
        ax = plot.figure.axes[0]
        assert ax.get_legend() is None
        assert {text.get_text() for text in ax.texts} == {"Sample A", "Sample B"}
        layout_debug = getattr(plot.figure, "_sciplot_layout_debug", [])
        endpoint_records = [entry for entry in layout_debug if entry.get("object_kind") == "endpoint_direct_labels"]
        assert endpoint_records
    finally:
        close_rendered_plots(rendered)


def test_compact_legend_policy_records_debug_decision() -> None:
    fig, ax = plot_style.create_panel_figure()
    try:
        x = np.linspace(0.0, 5.0, 60)
        ax.plot(x, np.sin(x) + 1.5, label="Sample A")
        ax.plot(x, np.cos(x) + 2.5, label="Sample B")
        ax.plot(x, np.sin(x * 0.8) + 3.2, label="Sample C")

        applied = _apply_compact_inside_legend(ax, series_count=3)
        assert applied
        layout_debug = getattr(fig, "_sciplot_layout_debug", [])
        compact_records = [entry for entry in layout_debug if entry.get("object_kind") == "compact_legend"]
        assert compact_records
        assert compact_records[0]["chosen_candidate_id"] is not None
    finally:
        plt.close(fig)


def test_small_point_line_quality_clears_compact_editorial_checks(tmp_path: Path) -> None:
    input_path = _write_temperature_sweep_table(tmp_path / "temperature.xlsx")

    rendered = build_rendered_plots("point_line", input_path, yscale="log")
    try:
        assert rendered
        for plot in rendered:
            assert plot.qa_report is not None
            issue_ids = {issue.id for issue in plot.qa_report.issues}
            assert plot.qa_report.grade in {"solid", "excellent"}
            assert "legend_footprint" not in issue_ids
            assert "stroke_hierarchy" not in issue_ids
            assert "series_identification" not in issue_ids
    finally:
        close_rendered_plots(rendered)


def test_bar_render_keeps_editorial_spacing_without_raw_point_overlay(tmp_path: Path) -> None:
    input_path = _write_replicate_table(tmp_path / "replicates.csv")

    rendered = build_rendered_plots("bar", input_path)
    try:
        assert len(rendered) == 1
        plot = rendered[0]
        assert plot.qa_report is not None
        assert "stats_spacing_profile" in plot.qa_report.autofixes_applied
        ax = plot.figure.axes[0]
        assert "bar_raw_points_overlay" not in plot.qa_report.autofixes_applied
        assert not _path_collections(ax)
    finally:
        close_rendered_plots(rendered)
