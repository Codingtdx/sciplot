from __future__ import annotations

from dataclasses import replace
from typing import Final

from src.rendering.dataset_models import NormalizedDataset
from src.rendering.recommender_models import TemplateRecommendation, TemplateRecommender

_LEGACY_SCORE: Final[float] = 100.0


def legacy_recommendation_to_template_recommendation(
    *,
    template_id: str,
    reason: str,
    size: str | None,
    xscale: str | None,
    yscale: str | None,
    reverse_x: bool | None,
    baseline: str | None,
    show_colorbar: bool | None,
    style_preset: str | None,
    palette_preset: str | None,
    use_sidecar: bool | None,
) -> TemplateRecommendation:
    return TemplateRecommendation(
        template_id=template_id,
        score=_LEGACY_SCORE,
        why_hard_match=(reason,),
        why_soft_prior=(),
        inferred_mapping={},
        optional_enhancements=(),
        preview_config_summary={
            "size": size,
            "xscale": xscale,
            "yscale": yscale,
            "reverse_x": reverse_x,
            "baseline": baseline,
            "show_colorbar": show_colorbar,
            "style_preset": style_preset,
            "palette_preset": palette_preset,
            "use_sidecar": use_sidecar,
        },
    )


def legacy_recommendations(template_recommendation: TemplateRecommendation) -> tuple[TemplateRecommendation, ...]:
    return (template_recommendation,)


class LegacyDatasetRecommender:
    def recommend(self, dataset: NormalizedDataset, limit: int = 5) -> tuple[TemplateRecommendation, ...]:
        if limit <= 0:
            return ()
        if dataset.model in {"frequency_sweep", "temperature_sweep", "stress_relaxation"}:
            recommendation = TemplateRecommendation(
                template_id="point_line",
                score=_LEGACY_SCORE,
                why_hard_match=tuple(dataset.semantic_signals[:2]),
                why_soft_prior=(),
                inferred_mapping={},
                optional_enhancements=(),
                preview_config_summary={"model": dataset.model},
            )
            return (recommendation,)
        if dataset.model == "replicate_table":
            return (
                TemplateRecommendation(
                    template_id="box",
                    score=_LEGACY_SCORE,
                    why_hard_match=tuple(dataset.semantic_signals[:2]),
                    why_soft_prior=(),
                    inferred_mapping={},
                    optional_enhancements=(),
                    preview_config_summary={"model": dataset.model},
                ),
            )
        if dataset.model == "heatmap_table":
            return (
                TemplateRecommendation(
                    template_id="heatmap",
                    score=_LEGACY_SCORE,
                    why_hard_match=tuple(dataset.semantic_signals[:2]),
                    why_soft_prior=(),
                    inferred_mapping={},
                    optional_enhancements=(),
                    preview_config_summary={"model": dataset.model},
                ),
            )
        if dataset.model == "tensile_curve":
            return (
                TemplateRecommendation(
                    template_id="curve",
                    score=_LEGACY_SCORE,
                    why_hard_match=tuple(dataset.semantic_signals[:2]),
                    why_soft_prior=(),
                    inferred_mapping={},
                    optional_enhancements=(),
                    preview_config_summary={"model": dataset.model},
                ),
            )
        return (
            TemplateRecommendation(
                template_id="curve",
                score=_LEGACY_SCORE,
                why_hard_match=tuple(dataset.semantic_signals[:2]),
                why_soft_prior=(),
                inferred_mapping={},
                optional_enhancements=(),
                preview_config_summary={"model": dataset.model},
            ),
        )


DEFAULT_RECOMMENDER: TemplateRecommender = LegacyDatasetRecommender()


__all__ = [
    "DEFAULT_RECOMMENDER",
    "LegacyDatasetRecommender",
    "legacy_recommendation_to_template_recommendation",
    "legacy_recommendations",
]
