from __future__ import annotations

from pathlib import Path

import pandas as pd

from src.rendering import build_normalized_dataset
from src.rendering.recommender import DEFAULT_RECOMMENDER
from src.wide_nmr import wide_nmr_sidecar_path


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


def _write_heatmap_table(path: Path) -> Path:
    rows = [
        ["X", "Y", "Z"],
        ["Temperature", "Time", "Intensity"],
        ["degC", "min", "a.u."],
        [25.0, 0.0, 0.18],
        [25.0, 5.0, 0.31],
        [40.0, 0.0, 0.46],
        [40.0, 5.0, 0.63],
    ]
    pd.DataFrame(rows).to_csv(path, header=False, index=False)
    return path


def test_curve_table_recommender_returns_five_ranked_choices(tmp_path: Path) -> None:
    dataset = build_normalized_dataset(_write_curve_table(tmp_path / "curve.csv"))

    recommendations = DEFAULT_RECOMMENDER.recommend(dataset, limit=5)

    assert [item.template_id for item in recommendations] == [
        "curve",
        "point_line",
        "scatter_fit",
        "stacked_curve",
        "scatter",
    ]
    assert recommendations[0].score > recommendations[1].score > recommendations[2].score
    assert recommendations[0].rank == 1
    assert recommendations[1].rank == 2
    assert recommendations[0].reason
    assert recommendations[0].suitability_hint
    assert recommendations[0].score_gap_to_top == 0.0
    assert recommendations[1].score_gap_to_top > 0.0
    assert recommendations[0].why_hard_match
    assert recommendations[0].why_soft_prior


def test_curve_table_recommender_exposes_bubble_scatter_at_higher_limit(tmp_path: Path) -> None:
    dataset = build_normalized_dataset(_write_curve_table(tmp_path / "curve.csv"))

    recommendations = DEFAULT_RECOMMENDER.recommend(dataset, limit=10)
    template_ids = [item.template_id for item in recommendations]

    assert "bubble_scatter" in template_ids
    bubble_candidate = next(item for item in recommendations if item.template_id == "bubble_scatter")
    assert any("bubble scatter" in reason.lower() for reason in bubble_candidate.why_soft_prior)


def test_multi_curve_table_recommender_surfaces_mean_band_without_legacy_aliases(tmp_path: Path) -> None:
    dataset = build_normalized_dataset(_write_multi_curve_table(tmp_path / "multi_curve.csv"))

    recommendations = DEFAULT_RECOMMENDER.recommend(dataset, limit=5)

    assert [item.template_id for item in recommendations] == [
        "curve",
        "point_line",
        "mean_band",
        "stacked_curve",
        "scatter_fit",
    ]
    mean_band = next(item for item in recommendations if item.template_id == "mean_band")
    assert any("mean band" in reason.lower() for reason in mean_band.why_soft_prior)
    assert "replicate_curves_with_band" not in [item.template_id for item in recommendations]


def test_replicate_table_recommender_includes_e2_templates_with_deterministic_order(tmp_path: Path) -> None:
    dataset = build_normalized_dataset(_write_replicate_table(tmp_path / "replicates.csv"))

    recommendations = DEFAULT_RECOMMENDER.recommend(dataset, limit=5)

    template_ids = [item.template_id for item in recommendations]
    assert template_ids[0] == "box"
    assert "box_strip" in template_ids
    assert "point_error" in template_ids
    assert "bar" in template_ids
    assert "grouped_bar_error" not in template_ids
    assert "distribution_compare" not in template_ids
    assert recommendations[0].why_hard_match[0].startswith("Normalized dataset shape includes")
    box_candidate = next(item for item in recommendations if item.template_id == "box")
    assert any("box summaries" in reason.lower() for reason in box_candidate.why_soft_prior)


def test_replicate_table_recommender_keeps_violin_box_available_with_higher_limit(tmp_path: Path) -> None:
    dataset = build_normalized_dataset(_write_replicate_table(tmp_path / "replicates.csv"))

    recommendations = DEFAULT_RECOMMENDER.recommend(dataset, limit=9)
    template_ids = [item.template_id for item in recommendations]

    assert "violin_box" in template_ids


def test_replicate_table_recommender_exposes_lollipop_error_at_higher_limit(tmp_path: Path) -> None:
    dataset = build_normalized_dataset(_write_replicate_table(tmp_path / "replicates.csv"))

    recommendations = DEFAULT_RECOMMENDER.recommend(dataset, limit=10)
    template_ids = [item.template_id for item in recommendations]

    assert "lollipop_error" in template_ids
    lollipop_candidate = next(item for item in recommendations if item.template_id == "lollipop_error")
    assert any("lollipop" in reason.lower() for reason in lollipop_candidate.why_soft_prior)


def test_replicate_table_recommender_promotes_histogram_density_when_replicates_are_dense(tmp_path: Path) -> None:
    dataset = build_normalized_dataset(_write_dense_replicate_table(tmp_path / "dense_replicates.csv"))

    recommendations = DEFAULT_RECOMMENDER.recommend(dataset, limit=7)

    template_ids = [item.template_id for item in recommendations]
    assert template_ids[0] == "violin"
    assert "box_strip" in template_ids[:3]
    assert template_ids.index("histogram_density") < template_ids.index("bar")
    histogram_candidate = next(item for item in recommendations if item.template_id == "histogram_density")
    assert any(
        "Higher replicate counts make histogram density overlays more informative." in reason
        for reason in histogram_candidate.why_soft_prior
    )


def test_replicate_table_recommender_downranks_histogram_for_highly_discrete_values(tmp_path: Path) -> None:
    dataset = build_normalized_dataset(_write_discrete_replicate_table(tmp_path / "discrete_replicates.csv"))

    recommendations = DEFAULT_RECOMMENDER.recommend(dataset, limit=7)

    template_ids = [item.template_id for item in recommendations]
    assert template_ids[0] == "box"
    assert "box_strip" in template_ids
    assert "point_error" in template_ids
    assert "bar" in template_ids
    assert "grouped_bar_error" not in template_ids
    if "histogram_density" in template_ids:
        histogram_candidate = next(item for item in recommendations if item.template_id == "histogram_density")
        assert template_ids.index("histogram_density") > template_ids.index("bar")
        assert any("highly discrete values" in reason.lower() for reason in histogram_candidate.why_soft_prior)


def test_heatmap_recommender_returns_annotated_heatmap_as_secondary_choice(tmp_path: Path) -> None:
    dataset = build_normalized_dataset(_write_heatmap_table(tmp_path / "heatmap.csv"))

    recommendations = DEFAULT_RECOMMENDER.recommend(dataset, limit=5)

    assert [item.template_id for item in recommendations] == ["heatmap", "annotated_heatmap"]
    assert recommendations[0].score > recommendations[1].score
    assert recommendations[1].why_hard_match
    assert recommendations[1].why_soft_prior


def test_wide_nmr_sidecar_promotes_segmented_stacked_curve(tmp_path: Path) -> None:
    input_path = _write_curve_table(tmp_path / "wide_nmr.csv")
    wide_nmr_sidecar_path(input_path).write_text("[layout]\npanel_label = 'Wide NMR'\n", encoding="utf-8")

    dataset = build_normalized_dataset(input_path)
    recommendations = DEFAULT_RECOMMENDER.recommend(dataset, limit=7)

    assert recommendations[0].template_id == "segmented_stacked_curve"
    assert recommendations[1].template_id == "stacked_curve"
    assert {item.template_id for item in recommendations} == {
        "curve",
        "point_line",
        "mean_band",
        "stacked_curve",
        "scatter",
        "scatter_fit",
        "segmented_stacked_curve",
    }
