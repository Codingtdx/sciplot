from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Final

from src.plot_contract import default_options_for_template, default_size_for_template
from src.rendering.dataset_models import NormalizedDataset
from src.rendering.recommender_models import TemplateRecommendation, TemplateRecommender
from src.text_normalization import canonicalize_token
from src.wide_nmr import wide_nmr_sidecar_path

_LEGACY_SCORE: Final[float] = 100.0
_CURVE_MODELS: Final[set[str]] = {
    "curve_table",
    "tensile_curve",
    "frequency_sweep",
    "temperature_sweep",
    "stress_relaxation",
}
_BUNDLE_MODELS: Final[set[str]] = {
    "frequency_sweep",
    "temperature_sweep",
    "stress_relaxation",
}
_CURVE_TEMPLATE_IDS: Final[tuple[str, ...]] = (
    "curve",
    "point_line",
    "replicate_curves_with_band",
    "stacked_curve",
    "segmented_stacked_curve",
    "scatter",
    "scatter_with_fit",
)
_REP_TEMPLATE_IDS: Final[tuple[str, ...]] = (
    "distribution_compare",
    "grouped_bar_compare",
    "histogram_density",
    "box",
    "violin",
    "bar",
)


@dataclass(frozen=True)
class _ScoredCandidate:
    template_id: str
    score: float
    why_hard_match: tuple[str, ...]
    why_soft_prior: tuple[str, ...]
    inferred_mapping: dict[str, str]
    optional_enhancements: tuple[str, ...]
    preview_config_summary: dict[str, Any]


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


def _clean_token(value: str | None) -> str:
    return canonicalize_token(value) if value else ""


def _label_tokens(dataset: NormalizedDataset) -> set[str]:
    return {_clean_token(value) for value in dataset.candidate_roles.label if value}


def _series_count(dataset: NormalizedDataset) -> int:
    return len({value for value in dataset.candidate_roles.series if value})


def _group_count(dataset: NormalizedDataset) -> int:
    return len({value for value in dataset.candidate_roles.group if value})


def _default_preview_summary(template_id: str, dataset: NormalizedDataset, **overrides: object) -> dict[str, Any]:
    defaults = default_options_for_template(template_id)
    summary: dict[str, Any] = {
        "template": template_id,
        "size": defaults.get("size", default_size_for_template(template_id)),
        "xscale": defaults.get("xscale"),
        "yscale": defaults.get("yscale"),
        "reverse_x": defaults.get("reverse_x"),
        "baseline": defaults.get("baseline"),
        "show_colorbar": defaults.get("show_colorbar"),
        "style_preset": defaults.get("style_preset"),
        "palette_preset": defaults.get("palette_preset"),
        "use_sidecar": defaults.get("use_sidecar"),
        "model": dataset.model,
        "shape": dataset.data_shapes[0] if dataset.data_shapes else None,
    }
    summary.update(overrides)
    return {key: value for key, value in summary.items() if value is not None}


def _build_candidate(
    *,
    template_id: str,
    score: float,
    why_hard_match: tuple[str, ...],
    why_soft_prior: list[str],
    inferred_mapping: dict[str, str],
    optional_enhancements: list[str],
    dataset: NormalizedDataset,
    **preview_overrides: object,
) -> _ScoredCandidate:
    bounded_score = round(max(0.0, min(100.0, score)), 1)
    return _ScoredCandidate(
        template_id=template_id,
        score=bounded_score,
        why_hard_match=why_hard_match,
        why_soft_prior=tuple(why_soft_prior),
        inferred_mapping=inferred_mapping,
        optional_enhancements=tuple(optional_enhancements),
        preview_config_summary=_default_preview_summary(template_id, dataset, **preview_overrides),
    )


def _bundle_candidates(dataset: NormalizedDataset) -> tuple[_ScoredCandidate, ...]:
    series_count = _series_count(dataset)
    hard = (
        f"Normalized dataset model is {dataset.model} with curve_like shape.",
        f"Detected {series_count} paired rheology series in the bundle.",
    )
    point_line_soft = [
        "Markers keep bundle exports readable when multiple traces share the same axis.",
    ]
    curve_soft = [
        "Curve remains available when the bundle needs a lighter look.",
    ]

    point_line_score = 84.0
    curve_score = 80.0
    if series_count >= 4:
        point_line_score += 2.0
        curve_score += 1.0
        point_line_soft.append("Several bundle series benefit from visible sample markers.")
        curve_soft.append("Several bundle series still fit on a simple paired curve.")
    if dataset.model == "stress_relaxation":
        point_line_score += 2.0
        curve_score += 1.0
        point_line_soft.append("Stress relaxation bundles already default to point-line inspection.")

    return (
        _build_candidate(
            template_id="point_line",
            score=point_line_score,
            why_hard_match=hard,
            why_soft_prior=point_line_soft,
            inferred_mapping={
                "x": dataset.candidate_roles.x[0] if dataset.candidate_roles.x else "",
                "y": dataset.candidate_roles.y[0] if dataset.candidate_roles.y else "",
            },
            optional_enhancements=["Keep markers visible for bundle inspection."],
            dataset=dataset,
        ),
        _build_candidate(
            template_id="curve",
            score=curve_score,
            why_hard_match=hard,
            why_soft_prior=curve_soft,
            inferred_mapping={
                "x": dataset.candidate_roles.x[0] if dataset.candidate_roles.x else "",
                "y": dataset.candidate_roles.y[0] if dataset.candidate_roles.y else "",
            },
            optional_enhancements=["Use curve when you want a lighter bundle preview."],
            dataset=dataset,
        ),
    )


def _curve_candidates(dataset: NormalizedDataset) -> tuple[_ScoredCandidate, ...]:
    labels = _label_tokens(dataset)
    series_count = max(1, _series_count(dataset))
    has_sidecar = dataset.source_path is not None and wide_nmr_sidecar_path(dataset.source_path).exists()
    is_tensile = dataset.model == "tensile_curve"
    is_nmr_like = "chemical shift" in labels or "ppm" in labels
    is_ftir_like = "wavenumber" in labels or "cm-1" in labels or "cm" in labels
    is_dsc_like = "heat flow" in labels
    is_xrd_like = "2theta" in labels or "2 theta" in labels or "count" in labels or "intensity" in labels

    hard = (
        f"Normalized dataset model is {dataset.model} with curve_like shape.",
        f"Detected {series_count} paired curve series.",
    )

    curve_score = 78.0
    point_line_score = 75.0
    stacked_score = 71.0
    segmented_score = 63.0
    scatter_score = 67.0
    scatter_fit_score = 69.0
    replicate_band_score = 66.0
    curve_soft = ["Compact paired curves are the safest default."]
    point_line_soft = ["Markers make paired observations easier to scan."]
    scatter_fit_soft = ["A deterministic linear fit can summarize trend direction without changing raw points."]
    replicate_band_soft = ["A mean-with-band overlay can summarize replicate spread across aligned curves."]
    stacked_soft = ["Offsets help compare several aligned samples without overplotting."]
    segmented_soft = ["Segmented stacks keep grouped traces separated."]
    scatter_soft = ["Scatter stays available when point continuity matters less than point density."]

    if is_tensile:
        curve_score += 10.0
        point_line_score += 8.0
        scatter_score += 4.0
        stacked_score -= 10.0
        segmented_score -= 8.0
        replicate_band_score += 10.0
        scatter_fit_score += 8.0
        curve_soft.append("Tensile curves stay linear and compact by default.")
        point_line_soft.append("Markers still help when tensile samples are sparse.")
        scatter_soft.append("Scatter can help when the tensile points need to stay separate.")
        scatter_fit_soft.append("Tensile stress-strain trends often benefit from a simple fit overlay.")
        replicate_band_soft.append("Aligned tensile replicates often benefit from a mean band summary.")
        stacked_soft.append("Stacked traces are less natural for tensile stress-strain data.")
        segmented_soft.append("Segmented stacks are overkill for tensile stress-strain data.")
    elif has_sidecar:
        segmented_score += 20.0
        stacked_score += 10.0
        curve_score -= 4.0
        point_line_score -= 2.0
        scatter_score -= 2.0
        scatter_fit_score -= 2.0
        replicate_band_score -= 4.0
        segmented_soft.append("The .wide_nmr sidecar marks this as a segmented stacked curve workflow.")
        stacked_soft.append("The sidecar keeps grouped traces readable as stacked spectra.")
        scatter_fit_soft.append("Segmented spectra workflows usually favor stacked views over fitted scatter.")
        replicate_band_soft.append("Segmented spectra workflows usually favor stacked views over mean bands.")
    elif is_nmr_like:
        stacked_score += 18.0
        segmented_score += 14.0
        curve_score -= 4.0
        point_line_score -= 2.0
        scatter_score -= 4.0
        scatter_fit_score -= 5.0
        replicate_band_score -= 6.0
        stacked_soft.append("Chemical shift / ppm data reads best as stacked spectra.")
        segmented_soft.append("The same spectral family can be separated with a segmented stack.")
        scatter_fit_soft.append("NMR-like spectra generally do not benefit from linear trend overlays.")
        replicate_band_soft.append("NMR-like spectra are usually better compared through stacked layouts.")
    elif is_ftir_like:
        stacked_score += 16.0
        curve_score += 2.0
        point_line_score += 1.0
        scatter_score -= 2.0
        scatter_fit_score -= 3.0
        replicate_band_score -= 2.0
        stacked_soft.append("Wavenumber / cm^-1 data is easier to compare as stacked spectra.")
        scatter_fit_soft.append("FTIR-like spectra usually prioritize trace shape over fitted trends.")
        replicate_band_soft.append("FTIR-like spectra usually prioritize stacked readability over mean bands.")
    elif is_dsc_like:
        stacked_score += 14.0
        curve_score += 2.0
        point_line_score += 1.0
        scatter_fit_score -= 1.0
        replicate_band_score += 1.0
        stacked_soft.append("Heat flow traces are usually read as stacked thermal curves.")
        scatter_fit_soft.append("Thermal traces are usually interpreted as curves before fit overlays.")
        replicate_band_soft.append("Thermal replicate sweeps can benefit from a mean band summary.")
    elif is_xrd_like:
        stacked_score += 14.0
        curve_score += 2.0
        point_line_score += 1.0
        scatter_fit_score -= 2.0
        replicate_band_score -= 1.0
        stacked_soft.append("2theta / intensity traces are easier to compare as stacked spectra.")
        scatter_fit_soft.append("XRD-like traces usually prioritize spectral shape over fitted trends.")
        replicate_band_soft.append("XRD-like traces usually prioritize stacked readability over mean bands.")
    else:
        if series_count <= 2:
            curve_score += 4.0
            point_line_score += 3.0
            scatter_score += 1.0
            scatter_fit_score += 5.0
            replicate_band_score -= 1.0
            curve_soft.append("A small number of series keeps the compact curve easy to read.")
            point_line_soft.append("A small number of series also benefits from visible markers.")
            scatter_fit_soft.append("Fewer series make a fit overlay easier to read and explain.")
            replicate_band_soft.append("A mean band is available but often unnecessary with very few series.")
        if series_count >= 4:
            stacked_score += 4.0
            point_line_score += 1.0
            curve_score += 1.0
            replicate_band_score += 8.0
            scatter_fit_score -= 1.0
            stacked_soft.append("Several series make overplotting more likely, so offsets help.")
            replicate_band_soft.append("More replicate series make a mean band overlay more informative.")
            scatter_fit_soft.append("Many traces can make fitted overlays visually crowded.")

    candidates = (
        _build_candidate(
            template_id="curve",
            score=curve_score,
            why_hard_match=hard,
            why_soft_prior=curve_soft,
            inferred_mapping={
                "x": dataset.candidate_roles.x[0] if dataset.candidate_roles.x else "",
                "y": dataset.candidate_roles.y[0] if dataset.candidate_roles.y else "",
            },
            optional_enhancements=["Use point_line if markers become useful."],
            dataset=dataset,
        ),
        _build_candidate(
            template_id="point_line",
            score=point_line_score,
            why_hard_match=hard,
            why_soft_prior=point_line_soft,
            inferred_mapping={
                "x": dataset.candidate_roles.x[0] if dataset.candidate_roles.x else "",
                "y": dataset.candidate_roles.y[0] if dataset.candidate_roles.y else "",
            },
            optional_enhancements=["Keep markers small when the series density is high."],
            dataset=dataset,
        ),
        _build_candidate(
            template_id="replicate_curves_with_band",
            score=replicate_band_score,
            why_hard_match=hard,
            why_soft_prior=replicate_band_soft,
            inferred_mapping={
                "x": dataset.candidate_roles.x[0] if dataset.candidate_roles.x else "",
                "y": dataset.candidate_roles.y[0] if dataset.candidate_roles.y else "",
                "sample": dataset.candidate_roles.sample[0] if dataset.candidate_roles.sample else "",
            },
            optional_enhancements=["Use curve when you need the raw traces without the summary band."],
            dataset=dataset,
        ),
        _build_candidate(
            template_id="stacked_curve",
            score=stacked_score,
            why_hard_match=hard,
            why_soft_prior=stacked_soft,
            inferred_mapping={
                "x": dataset.candidate_roles.x[0] if dataset.candidate_roles.x else "",
                "y": dataset.candidate_roles.y[0] if dataset.candidate_roles.y else "",
            },
            optional_enhancements=["Baseline correction can help stacked traces breathe."],
            dataset=dataset,
        ),
        _build_candidate(
            template_id="segmented_stacked_curve",
            score=segmented_score,
            why_hard_match=hard,
            why_soft_prior=segmented_soft,
            inferred_mapping={
                "x": dataset.candidate_roles.x[0] if dataset.candidate_roles.x else "",
                "y": dataset.candidate_roles.y[0] if dataset.candidate_roles.y else "",
            },
            optional_enhancements=["Use the segmented template when trace groups need more separation."],
            dataset=dataset,
        ),
        _build_candidate(
            template_id="scatter",
            score=scatter_score,
            why_hard_match=hard,
            why_soft_prior=scatter_soft,
            inferred_mapping={
                "x": dataset.candidate_roles.x[0] if dataset.candidate_roles.x else "",
                "y": dataset.candidate_roles.y[0] if dataset.candidate_roles.y else "",
            },
            optional_enhancements=["Scatter can downplay line continuity when needed."],
            dataset=dataset,
        ),
        _build_candidate(
            template_id="scatter_with_fit",
            score=scatter_fit_score,
            why_hard_match=hard,
            why_soft_prior=scatter_fit_soft,
            inferred_mapping={
                "x": dataset.candidate_roles.x[0] if dataset.candidate_roles.x else "",
                "y": dataset.candidate_roles.y[0] if dataset.candidate_roles.y else "",
            },
            optional_enhancements=["Use scatter when you want points without the fit overlay."],
            dataset=dataset,
        ),
    )
    return tuple(sorted(candidates, key=lambda candidate: (-candidate.score, candidate.template_id)))


def _replicate_candidates(dataset: NormalizedDataset) -> tuple[_ScoredCandidate, ...]:
    group_count = _group_count(dataset)
    replicate_rows = max(dataset.raw_rows - 3, 0)
    estimated_points = replicate_rows * max(group_count, 1)
    quality_flags = set(dataset.quality_flags)
    hard = (
        "Normalized dataset shape includes replicate_table and distribution.",
        f"Detected {group_count} replicate groups with a shared value label.",
    )

    distribution_score = 82.0
    grouped_bar_compare_score = 72.0
    histogram_density_score = 68.0
    box_score = 78.0
    violin_score = 74.0
    bar_score = 70.0
    distribution_soft = [
        "distribution_compare stays as one structural family in v1 with deterministic internal variants."
    ]
    grouped_bar_compare_soft = ["Grouped bars keep cross-group mean differences explicit."]
    histogram_density_soft = ["Histogram with density overlays highlights overlap between groups."]
    box_soft = ["Box plots keep medians and spread readable with minimal visual noise."]
    violin_soft = ["Violin plots reveal distribution shape when replicate density is sufficient."]
    bar_soft = ["Bar charts keep simple group means easy to compare."]

    if group_count <= 3:
        grouped_bar_compare_score += 4.0
        histogram_density_score += 2.0
        distribution_score -= 2.0
        bar_score += 2.0
        box_score += 2.0
        violin_score -= 1.0
        grouped_bar_compare_soft.append("A small number of groups keeps grouped bars compact and readable.")
        histogram_density_soft.append("Fewer groups keep overlap in histogram densities legible.")
        distribution_soft.append("With few groups, distribution compare can still default to a compact variant.")
        bar_soft.append("Few groups keep bar labels compact and readable.")
    if group_count >= 5:
        distribution_score += 4.0
        grouped_bar_compare_score -= 2.0
        histogram_density_score -= 2.0
        box_score += 4.0
        violin_score += 6.0
        bar_score -= 4.0
        distribution_soft.append("Many groups benefit from a deterministic distribution-first comparison view.")
        grouped_bar_compare_soft.append("Many groups can make grouped bars visually dense.")
        histogram_density_soft.append("Many groups can make density overlays visually crowded.")
        box_soft.append("Many groups make box summaries more legible than bars.")
        violin_soft.append("More groups make the density shape more informative.")

    if "replicate_sparse_replicates" in quality_flags:
        distribution_score -= 5.0
        grouped_bar_compare_score += 3.0
        histogram_density_score -= 10.0
        box_score += 3.0
        violin_score -= 2.0
        bar_score += 2.0
        distribution_soft.append("Sparse replicate counts favor simpler spread summaries over density-heavy variants.")
        grouped_bar_compare_soft.append(
            "Sparse replicates keep grouped means easier to read than detailed distributions."
        )
        histogram_density_soft.append("Sparse replicate counts make histogram-density overlays unstable.")
        box_soft.append("Box summaries stay robust when replicate counts are low.")
        bar_soft.append("Simple mean comparisons remain readable with sparse replicates.")

    if "replicate_singleton_groups" in quality_flags:
        distribution_score -= 4.0
        grouped_bar_compare_score += 2.0
        histogram_density_score -= 8.0
        violin_score -= 6.0
        box_score += 2.0
        distribution_soft.append("At least one group has very few replicates, so robust summaries are preferred.")
        histogram_density_soft.append("Singleton-like groups reduce the reliability of smoothed density overlays.")
        violin_soft.append("Very low group replicate counts reduce violin-shape reliability.")

    if "replicate_highly_discrete" in quality_flags:
        histogram_density_score -= 8.0
        distribution_score += 1.0
        grouped_bar_compare_score += 2.0
        box_score += 2.0
        histogram_density_soft.append("Highly discrete values can make histogram-density overlays blocky.")
        distribution_soft.append(
            "Discrete-valued groups still compare well through deterministic distribution summaries."
        )
        box_soft.append("Discrete-valued replicates remain clear in box summaries.")
    if estimated_points >= 24:
        histogram_density_score += 8.0
        distribution_score += 2.0
        histogram_density_soft.append("Higher replicate counts make histogram density overlays more informative.")
        distribution_soft.append("Higher replicate counts make robust distribution comparison more reliable.")
    elif estimated_points < 10:
        histogram_density_score -= 6.0
        histogram_density_soft.append("Very sparse replicate counts reduce histogram-density reliability.")
    if estimated_points >= 12:
        violin_score += 4.0
        violin_soft.append("More replicate points make the distribution shape clearer.")

    return tuple(
        sorted(
            (
                _build_candidate(
                    template_id="distribution_compare",
                    score=distribution_score,
                    why_hard_match=hard,
                    why_soft_prior=distribution_soft,
                    inferred_mapping={
                        "group": dataset.candidate_roles.group[0] if dataset.candidate_roles.group else "",
                        "value": dataset.candidate_roles.value[0] if dataset.candidate_roles.value else "",
                    },
                    optional_enhancements=[
                        "The renderer chooses a deterministic internal variant (box / violin / strip+box)."
                    ],
                    dataset=dataset,
                ),
                _build_candidate(
                    template_id="grouped_bar_compare",
                    score=grouped_bar_compare_score,
                    why_hard_match=hard,
                    why_soft_prior=grouped_bar_compare_soft,
                    inferred_mapping={
                        "group": dataset.candidate_roles.group[0] if dataset.candidate_roles.group else "",
                        "value": dataset.candidate_roles.value[0] if dataset.candidate_roles.value else "",
                    },
                    optional_enhancements=["Use distribution_compare when spread shape matters more than means."],
                    dataset=dataset,
                ),
                _build_candidate(
                    template_id="histogram_density",
                    score=histogram_density_score,
                    why_hard_match=hard,
                    why_soft_prior=histogram_density_soft,
                    inferred_mapping={
                        "group": dataset.candidate_roles.group[0] if dataset.candidate_roles.group else "",
                        "value": dataset.candidate_roles.value[0] if dataset.candidate_roles.value else "",
                    },
                    optional_enhancements=["Use grouped_bar_compare when category means are the primary focus."],
                    dataset=dataset,
                ),
                _build_candidate(
                    template_id="box",
                    score=box_score,
                    why_hard_match=hard,
                    why_soft_prior=box_soft,
                    inferred_mapping={
                        "group": dataset.candidate_roles.group[0] if dataset.candidate_roles.group else "",
                        "value": dataset.candidate_roles.value[0] if dataset.candidate_roles.value else "",
                    },
                    optional_enhancements=["Keep box summaries when you want the simplest spread view."],
                    dataset=dataset,
                ),
                _build_candidate(
                    template_id="violin",
                    score=violin_score,
                    why_hard_match=hard,
                    why_soft_prior=violin_soft,
                    inferred_mapping={
                        "group": dataset.candidate_roles.group[0] if dataset.candidate_roles.group else "",
                        "value": dataset.candidate_roles.value[0] if dataset.candidate_roles.value else "",
                    },
                    optional_enhancements=["Use violin when the distribution shape matters."],
                    dataset=dataset,
                ),
                _build_candidate(
                    template_id="bar",
                    score=bar_score,
                    why_hard_match=hard,
                    why_soft_prior=bar_soft,
                    inferred_mapping={
                        "group": dataset.candidate_roles.group[0] if dataset.candidate_roles.group else "",
                        "value": dataset.candidate_roles.value[0] if dataset.candidate_roles.value else "",
                    },
                    optional_enhancements=["Keep bar charts for simple mean comparisons."],
                    dataset=dataset,
                ),
            ),
            key=lambda candidate: (-candidate.score, candidate.template_id),
        )
    )


def _heatmap_candidates(dataset: NormalizedDataset) -> tuple[_ScoredCandidate, ...]:
    hard = (
        "Normalized dataset shape includes matrix.",
        "Detected explicit x / y / z roles in the long table.",
    )
    return tuple(
        sorted(
            (
        _build_candidate(
            template_id="heatmap",
            score=90.0,
            why_hard_match=hard,
            why_soft_prior=["Heatmap is the direct matrix view for x, y, and z input roles."],
            inferred_mapping={
                "x": dataset.candidate_roles.x[0] if dataset.candidate_roles.x else "",
                "y": dataset.candidate_roles.y[0] if dataset.candidate_roles.y else "",
                "z": dataset.candidate_roles.z[0] if dataset.candidate_roles.z else "",
            },
            optional_enhancements=["Show the colorbar when the z scale is part of the story."],
            dataset=dataset,
            show_colorbar=True,
        ),
                _build_candidate(
                    template_id="annotated_heatmap",
                    score=86.0,
                    why_hard_match=hard,
                    why_soft_prior=[
                        "Annotated heatmap keeps the same matrix layout and adds deterministic cell labels."
                    ],
                    inferred_mapping={
                        "x": dataset.candidate_roles.x[0] if dataset.candidate_roles.x else "",
                        "y": dataset.candidate_roles.y[0] if dataset.candidate_roles.y else "",
                        "z": dataset.candidate_roles.z[0] if dataset.candidate_roles.z else "",
                    },
                    optional_enhancements=["Use plain heatmap when annotations become too dense."],
                    dataset=dataset,
                    show_colorbar=True,
                ),
            ),
            key=lambda candidate: (-candidate.score, candidate.template_id),
        )
    )


def _recommendations_for_dataset(dataset: NormalizedDataset) -> tuple[TemplateRecommendation, ...]:
    if dataset.model in _BUNDLE_MODELS:
        candidates = _bundle_candidates(dataset)
    elif dataset.model == "replicate_table":
        candidates = _replicate_candidates(dataset)
    elif dataset.model == "heatmap_table":
        candidates = _heatmap_candidates(dataset)
    else:
        candidates = _curve_candidates(dataset)
    return tuple(
        TemplateRecommendation(
            template_id=candidate.template_id,
            score=candidate.score,
            why_hard_match=candidate.why_hard_match,
            why_soft_prior=candidate.why_soft_prior,
            inferred_mapping=candidate.inferred_mapping,
            optional_enhancements=candidate.optional_enhancements,
            preview_config_summary=candidate.preview_config_summary,
        )
        for candidate in candidates
    )


class RuleBasedDatasetRecommender:
    def recommend(self, dataset: NormalizedDataset, limit: int = 5) -> tuple[TemplateRecommendation, ...]:
        if limit <= 0:
            return ()
        return _recommendations_for_dataset(dataset)[:limit]


class LegacyDatasetRecommender(RuleBasedDatasetRecommender):
    pass


DEFAULT_RECOMMENDER: TemplateRecommender = RuleBasedDatasetRecommender()


__all__ = [
    "DEFAULT_RECOMMENDER",
    "LegacyDatasetRecommender",
    "RuleBasedDatasetRecommender",
    "legacy_recommendation_to_template_recommendation",
    "legacy_recommendations",
]
