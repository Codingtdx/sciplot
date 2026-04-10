from __future__ import annotations

from pathlib import Path

import pandas as pd

from src.rendering import build_normalized_dataset
from src.rendering.recommender import DEFAULT_RECOMMENDER
from src.rendering.template_catalog import DEFAULT_TEMPLATE_CATALOG
from src.rendering.template_lifecycle import (
    alias_lifecycle_policy,
    alias_templates_for,
    canonical_template_id,
    template_identity,
    template_lifecycle_inventory,
)


def _write_curve_table(path: Path) -> Path:
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


def test_template_lifecycle_inventory_marks_aliases_and_policies() -> None:
    entries = {entry.template_id: entry for entry in template_lifecycle_inventory()}

    assert canonical_template_id("scatter_with_fit") == "scatter_fit"
    assert canonical_template_id("replicate_curves_with_band") == "mean_band"
    assert canonical_template_id("grouped_bar_compare") == "grouped_bar_error"
    assert alias_templates_for("scatter_fit") == ("scatter_with_fit",)
    assert alias_templates_for("mean_band") == ("replicate_curves_with_band",)
    assert alias_lifecycle_policy("scatter_with_fit") == "deprecated_in_practice"
    assert alias_lifecycle_policy("replicate_curves_with_band") == "deprecated_in_practice"
    assert alias_lifecycle_policy("grouped_bar_compare") == "indefinite_compat"
    assert entries["scatter_fit"].role == "canonical"
    assert entries["scatter_with_fit"].role == "alias"
    scatter_alias_identity = template_identity("scatter_with_fit")
    assert scatter_alias_identity.requested_template_id == "scatter_with_fit"
    assert scatter_alias_identity.canonical_id == "scatter_fit"
    assert scatter_alias_identity.role == "alias"
    assert scatter_alias_identity.lifecycle_policy == "deprecated_in_practice"
    assert scatter_alias_identity.implementation_id == "scatter_fit"
    distribution_identity = template_identity("distribution_compare")
    assert distribution_identity.requested_template_id == "distribution_compare"
    assert distribution_identity.role == "family_alias"
    assert distribution_identity.canonical_id == "box"
    assert distribution_identity.implementation_id == "box"


def test_template_catalog_only_exposes_public_canonical_templates() -> None:
    assert DEFAULT_TEMPLATE_CATALOG.get("scatter_fit").implementation_id == "scatter_fit"
    assert DEFAULT_TEMPLATE_CATALOG.get("mean_band").implementation_id == "mean_band"
    assert DEFAULT_TEMPLATE_CATALOG.get("bubble_scatter").canonical_id == "bubble_scatter"
    assert DEFAULT_TEMPLATE_CATALOG.get("bubble_scatter").role == "canonical"
    assert DEFAULT_TEMPLATE_CATALOG.get("lollipop_error").canonical_id == "lollipop_error"
    assert DEFAULT_TEMPLATE_CATALOG.get("lollipop_error").role == "canonical"
    for legacy_id in (
        "scatter_with_fit",
        "replicate_curves_with_band",
        "grouped_bar_compare",
        "distribution_compare",
    ):
        try:
            DEFAULT_TEMPLATE_CATALOG.get(legacy_id)
        except ValueError:
            pass
        else:
            raise AssertionError(f"{legacy_id} should not remain in the public template catalog.")


def test_recommender_prefers_canonical_templates_over_aliases_for_curve_data(tmp_path: Path) -> None:
    dataset = build_normalized_dataset(_write_curve_table(tmp_path / "curve.csv"))
    recommendations = DEFAULT_RECOMMENDER.recommend(dataset, limit=10)
    template_ids = [item.template_id for item in recommendations]

    assert "scatter_with_fit" not in template_ids
    assert "replicate_curves_with_band" not in template_ids
    assert "scatter_fit" in template_ids
    assert "mean_band" in template_ids


def test_recommender_keeps_grouped_bar_compare_as_compatibility_only(tmp_path: Path) -> None:
    dataset = build_normalized_dataset(_write_replicate_table(tmp_path / "replicates.csv"))
    recommendations = DEFAULT_RECOMMENDER.recommend(dataset, limit=10)
    template_ids = [item.template_id for item in recommendations]

    assert "grouped_bar_error" in template_ids
    assert "grouped_bar_compare" not in template_ids
