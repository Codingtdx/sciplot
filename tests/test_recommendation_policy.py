from __future__ import annotations

from pathlib import Path

from src.rendering import build_normalized_dataset
from src.rendering.recommendation_policy import build_recommendation_presentation
from src.rendering.recommender import DEFAULT_RECOMMENDER
from src.tensile_replicates import export_tensile_replicate_workbook

ROOT = Path(__file__).resolve().parents[1]
FIXTURE_DIR = ROOT / "tests" / "fixtures" / "tensile_raw"


def _tensile_workbook(tmp_path: Path) -> Path:
    return export_tensile_replicate_workbook(
        [
            FIXTURE_DIR / "BlendSet_A.csv",
            FIXTURE_DIR / "BlendSet_B.csv",
        ],
        tmp_path / "blendset.xlsx",
        group_name="BlendSet",
    ).output_path


def _recommendation_ids(items) -> list[str]:
    return [item.template_id for item in items]


def test_curve_policy_keeps_primary_and_nearby_alternatives_visible(tmp_path: Path) -> None:
    dataset = build_normalized_dataset(ROOT / "examples" / "curve_table.csv")
    ranked = DEFAULT_RECOMMENDER.recommend(dataset, limit=10)

    policy = build_recommendation_presentation(ranked)

    assert _recommendation_ids(policy.primary_recommendation) == ["curve"]
    assert _recommendation_ids(policy.alternative_recommendations) == [
        "point_line",
        "area_curve",
        "scatter_fit",
    ]
    assert policy.score_gap_to_second_primary == 4.0
    assert _recommendation_ids(policy.visible_recommendations) == [
        "curve",
        "point_line",
        "area_curve",
        "scatter_fit",
    ]
    assert "stacked_curve" in _recommendation_ids(policy.advanced_templates)
    assert "bubble_scatter" in _recommendation_ids(policy.advanced_templates)
    assert "scatter_with_fit" not in _recommendation_ids(policy.visible_recommendations)


def test_replicate_policy_allows_co_primary_and_limits_visible_budget(tmp_path: Path) -> None:
    dataset = build_normalized_dataset(ROOT / "examples" / "replicate_table.csv")
    ranked = DEFAULT_RECOMMENDER.recommend(dataset, limit=10)

    policy = build_recommendation_presentation(ranked)

    assert _recommendation_ids(policy.primary_recommendation) == ["box_strip"]
    assert policy.score_gap_to_second_primary == 2.0
    assert _recommendation_ids(policy.alternative_recommendations) == [
        "box",
        "point_error",
        "violin",
    ]
    assert _recommendation_ids(policy.visible_recommendations) == [
        "box_strip",
        "box",
        "point_error",
        "violin",
    ]
    assert "lollipop_error" in _recommendation_ids(policy.advanced_templates)
    assert "bar" in _recommendation_ids(policy.advanced_templates)
    assert "grouped_bar_error" not in _recommendation_ids(policy.advanced_templates)
    assert "grouped_bar_compare" not in _recommendation_ids(policy.visible_recommendations)


def test_tensile_policy_keeps_aliases_out_of_visible_recommendations(tmp_path: Path) -> None:
    workbook_path = _tensile_workbook(tmp_path)
    dataset = build_normalized_dataset(workbook_path, "Representative_Curve")
    ranked = DEFAULT_RECOMMENDER.recommend(dataset, limit=10)

    policy = build_recommendation_presentation(ranked)

    assert _recommendation_ids(policy.primary_recommendation) == ["curve"]
    assert _recommendation_ids(policy.alternative_recommendations) == [
        "point_line",
        "mean_band",
        "scatter_fit",
    ]
    assert "replicate_curves_with_band" not in _recommendation_ids(policy.visible_recommendations)
    assert "scatter_with_fit" not in _recommendation_ids(policy.visible_recommendations)
    assert "bubble_scatter" in _recommendation_ids(policy.advanced_templates)
