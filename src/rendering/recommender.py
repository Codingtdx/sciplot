from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Final

from src.plot_contract import default_options_for_template, default_size_for_template
from src.rendering.dataset_models import NormalizedDataset
from src.rendering.recommender_models import TemplateRecommendation, TemplateRecommender
from src.rendering.template_lifecycle import template_identity
from src.text_normalization import canonicalize_token
from src.wide_nmr import wide_nmr_sidecar_path

_OVERRIDE_SCORE: Final[float] = 100.0
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


@dataclass(frozen=True)
class _ScoredCandidate:
    template_id: str
    score: float
    why_hard_match: tuple[str, ...]
    why_soft_prior: tuple[str, ...]
    reason: str
    suitability_hint: str
    inferred_mapping: dict[str, str]
    optional_enhancements: tuple[str, ...]
    preview_config_summary: dict[str, Any]


def template_recommendation_from_override(
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
    visual_theme_id: str | None,
) -> TemplateRecommendation:
    identity = template_identity(template_id)
    return TemplateRecommendation(
        template_id=template_id,
        score=_OVERRIDE_SCORE,
        rank=1,
        score_gap_to_top=0.0,
        reason=reason,
        suitability_hint="Primary recommendation from compatibility inspection.",
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
            "visual_theme_id": visual_theme_id,
        },
        canonical_id=identity.canonical_id,
        role=identity.role,
        lifecycle_policy=identity.lifecycle_policy,
        implementation_id=identity.implementation_id,
    )


def _clean_token(value: str | None) -> str:
    return canonicalize_token(value) if value else ""


def _label_tokens(dataset: NormalizedDataset) -> set[str]:
    return {_clean_token(value) for value in dataset.candidate_roles.label if value}


def _series_count(dataset: NormalizedDataset) -> int:
    return len({value for value in dataset.candidate_roles.series if value})


def _group_count(dataset: NormalizedDataset) -> int:
    return len({value for value in dataset.candidate_roles.group if value})


def _distribution_variant_template_id(group_count: int, min_group_points: int) -> str:
    if group_count >= 6:
        return "box"
    if group_count <= 4 and min_group_points >= 6:
        return "violin"
    return "box_strip"


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
        "visual_theme_id": defaults.get("visual_theme_id"),
        "model": dataset.model,
        "shape": dataset.data_shapes[0] if dataset.data_shapes else None,
    }
    summary.update(overrides)
    return {key: value for key, value in summary.items() if value is not None}


def _candidate_reason(why_hard_match: tuple[str, ...], why_soft_prior: list[str]) -> str:
    if why_hard_match:
        return why_hard_match[0]
    if why_soft_prior:
        return why_soft_prior[0]
    return "Compatible template for the detected input model."


def _candidate_suitability_hint(score: float) -> str:
    if score >= 88.0:
        return "Strong structural and semantic match for the detected model."
    if score >= 76.0:
        return "Good fit with minor trade-offs compared with the primary choice."
    return "Compatible fallback when you need a different visual emphasis."


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
    suitability_hint = _candidate_suitability_hint(bounded_score)
    return _ScoredCandidate(
        template_id=template_id,
        score=bounded_score,
        why_hard_match=why_hard_match,
        why_soft_prior=tuple(why_soft_prior),
        reason=_candidate_reason(why_hard_match, why_soft_prior),
        suitability_hint=suitability_hint,
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
    bubble_scatter_score = 63.0
    scatter_fit_score = 69.0
    mean_band_score = 67.0
    curve_soft = ["Compact paired curves are the safest default."]
    point_line_soft = ["Markers make paired observations easier to scan."]
    scatter_fit_soft = ["A deterministic linear fit can summarize trend direction without changing raw points."]
    mean_band_soft = ["A mean-with-band overlay can summarize replicate spread across aligned curves."]
    stacked_soft = ["Offsets help compare several aligned samples without overplotting."]
    segmented_soft = ["Segmented stacks keep grouped traces separated."]
    scatter_soft = ["Scatter stays available when point continuity matters less than point density."]
    bubble_scatter_soft = [
        "Bubble scatter adds deterministic point-size encoding to emphasize relative response magnitude."
    ]

    if is_tensile:
        curve_score += 10.0
        point_line_score += 8.0
        scatter_score += 4.0
        bubble_scatter_score += 3.0
        stacked_score -= 10.0
        segmented_score -= 8.0
        mean_band_score += 10.0
        scatter_fit_score += 8.0
        curve_soft.append("Tensile curves stay linear and compact by default.")
        point_line_soft.append("Markers still help when tensile samples are sparse.")
        scatter_soft.append("Scatter can help when the tensile points need to stay separate.")
        bubble_scatter_soft.append("Bubble sizing can highlight stress magnitude changes along tensile traces.")
        scatter_fit_soft.append("Tensile stress-strain trends often benefit from a simple fit overlay.")
        mean_band_soft.append("Aligned tensile replicates often benefit from a mean band summary.")
        stacked_soft.append("Stacked traces are less natural for tensile stress-strain data.")
        segmented_soft.append("Segmented stacks are overkill for tensile stress-strain data.")
    elif has_sidecar:
        segmented_score += 20.0
        stacked_score += 10.0
        curve_score -= 4.0
        point_line_score -= 2.0
        scatter_score -= 2.0
        bubble_scatter_score -= 3.0
        scatter_fit_score -= 2.0
        mean_band_score -= 4.0
        segmented_soft.append("The .wide_nmr sidecar marks this as a segmented stacked curve workflow.")
        stacked_soft.append("The sidecar keeps grouped traces readable as stacked spectra.")
        bubble_scatter_soft.append("Segmented spectra workflows usually prioritize trace shape over bubble encoding.")
        scatter_fit_soft.append("Segmented spectra workflows usually favor stacked views over fitted scatter.")
        mean_band_soft.append("Segmented spectra workflows usually favor stacked views over mean bands.")
    elif is_nmr_like:
        stacked_score += 18.0
        segmented_score += 14.0
        curve_score -= 4.0
        point_line_score -= 2.0
        scatter_score -= 4.0
        bubble_scatter_score -= 4.0
        scatter_fit_score -= 5.0
        mean_band_score -= 6.0
        stacked_soft.append("Chemical shift / ppm data reads best as stacked spectra.")
        bubble_scatter_soft.append("NMR-like spectra usually prioritize trace shape over bubble-size encoding.")
        segmented_soft.append("The same spectral family can be separated with a segmented stack.")
        scatter_fit_soft.append("NMR-like spectra generally do not benefit from linear trend overlays.")
        mean_band_soft.append("NMR-like spectra are usually better compared through stacked layouts.")
    elif is_ftir_like:
        stacked_score += 16.0
        curve_score += 2.0
        point_line_score += 1.0
        scatter_score -= 2.0
        bubble_scatter_score -= 2.0
        scatter_fit_score -= 3.0
        mean_band_score -= 2.0
        stacked_soft.append("Wavenumber / cm^-1 data is easier to compare as stacked spectra.")
        bubble_scatter_soft.append("FTIR-like spectra typically prioritize trace shape over bubble-size emphasis.")
        scatter_fit_soft.append("FTIR-like spectra usually prioritize trace shape over fitted trends.")
        mean_band_soft.append("FTIR-like spectra usually prioritize stacked readability over mean bands.")
    elif is_dsc_like:
        stacked_score += 14.0
        curve_score += 2.0
        point_line_score += 1.0
        bubble_scatter_score -= 1.0
        scatter_fit_score -= 1.0
        mean_band_score += 1.0
        stacked_soft.append("Heat flow traces are usually read as stacked thermal curves.")
        bubble_scatter_soft.append("Thermal traces usually read better as lines than size-weighted bubbles.")
        scatter_fit_soft.append("Thermal traces are usually interpreted as curves before fit overlays.")
        mean_band_soft.append("Thermal replicate sweeps can benefit from a mean band summary.")
    elif is_xrd_like:
        stacked_score += 14.0
        curve_score += 2.0
        point_line_score += 1.0
        bubble_scatter_score -= 2.0
        scatter_fit_score -= 2.0
        mean_band_score -= 1.0
        stacked_soft.append("2theta / intensity traces are easier to compare as stacked spectra.")
        bubble_scatter_soft.append("XRD-like traces usually prioritize line-shape comparison over bubble sizing.")
        scatter_fit_soft.append("XRD-like traces usually prioritize spectral shape over fitted trends.")
        mean_band_soft.append("XRD-like traces usually prioritize stacked readability over mean bands.")
    else:
        if series_count <= 2:
            curve_score += 4.0
            point_line_score += 3.0
            scatter_score += 1.0
            bubble_scatter_score += 3.0
            scatter_fit_score += 5.0
            mean_band_score -= 1.0
            curve_soft.append("A small number of series keeps the compact curve easy to read.")
            point_line_soft.append("A small number of series also benefits from visible markers.")
            scatter_fit_soft.append("Fewer series make a fit overlay easier to read and explain.")
            bubble_scatter_soft.append("With fewer series, bubble-size encoding remains easy to parse.")
            mean_band_soft.append("A mean band is available but often unnecessary with very few series.")
        if series_count >= 4:
            stacked_score += 4.0
            point_line_score += 1.0
            curve_score += 1.0
            mean_band_score += 8.0
            bubble_scatter_score -= 2.0
            scatter_fit_score -= 1.0
            stacked_soft.append("Several series make overplotting more likely, so offsets help.")
            mean_band_soft.append("More replicate series make a mean band overlay more informative.")
            bubble_scatter_soft.append("Many traces can make bubble-size layers visually crowded.")
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
            template_id="mean_band",
            score=mean_band_score,
            why_hard_match=hard,
            why_soft_prior=mean_band_soft,
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
            template_id="bubble_scatter",
            score=bubble_scatter_score,
            why_hard_match=hard,
            why_soft_prior=bubble_scatter_soft,
            inferred_mapping={
                "x": dataset.candidate_roles.x[0] if dataset.candidate_roles.x else "",
                "y": dataset.candidate_roles.y[0] if dataset.candidate_roles.y else "",
            },
            optional_enhancements=["Use scatter when uniform marker size is preferred."],
            dataset=dataset,
        ),
        _build_candidate(
            template_id="scatter_fit",
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
    distribution_template_id = _distribution_variant_template_id(group_count, replicate_rows)
    quality_flags = set(dataset.quality_flags)
    hard = (
        "Normalized dataset shape includes replicate_table and distribution.",
        f"Detected {group_count} replicate groups with a shared value label.",
    )

    point_error_score = 73.0
    lollipop_error_score = 64.0
    histogram_density_score = 68.0
    box_score = 78.0
    box_strip_score = 77.0
    violin_box_score = 73.0
    violin_score = 74.0
    bar_score = 72.0
    bar_soft = ["Bar charts keep group means and error bars explicit with filled summaries."]
    point_error_soft = ["Point + error keeps group means and uncertainty visible without bar area fill."]
    lollipop_error_soft = ["Lollipop stems keep group means explicit while preserving vertical uncertainty cues."]
    histogram_density_soft = ["Histogram with density overlays highlights overlap between groups."]
    box_soft = ["Box plots keep medians and spread readable with minimal visual noise."]
    box_strip_soft = ["Box + strip keeps spread summaries while exposing individual replicate points."]
    violin_box_soft = ["Violin + box combines density shape with a compact box-summary overlay."]
    violin_soft = ["Violin plots reveal distribution shape when replicate density is sufficient."]

    if group_count <= 3:
        bar_score += 4.0
        point_error_score += 5.0
        lollipop_error_score += 2.0
        histogram_density_score += 2.0
        box_score += 2.0
        box_strip_score += 2.0
        violin_box_score += 1.0
        violin_score -= 1.0
        bar_soft.append("A small number of groups keeps filled bars compact and readable.")
        point_error_soft.append("A small number of groups keeps point+error markers compact and readable.")
        lollipop_error_soft.append("A small number of groups keeps lollipop stems compact and readable.")
        histogram_density_soft.append("Fewer groups keep overlap in histogram densities legible.")
        box_strip_soft.append("Few groups keep strip overlays clean without clutter.")
        violin_box_soft.append("Few groups keep violin+box overlays compact and readable.")
    if group_count >= 5:
        bar_score -= 2.0
        point_error_score -= 1.0
        lollipop_error_score -= 1.0
        histogram_density_score -= 2.0
        box_score += 4.0
        box_strip_score += 1.0
        violin_box_score += 2.0
        violin_score += 6.0
        bar_soft.append("Many groups can make filled bars visually dense.")
        point_error_soft.append("Many groups can still remain readable with compact point+error markers.")
        lollipop_error_soft.append("Many groups can make lollipop stems dense, so spacing discipline is important.")
        histogram_density_soft.append("Many groups can make density overlays visually crowded.")
        box_soft.append("Many groups make box summaries more legible than bars.")
        box_strip_soft.append("Many groups still remain traceable when replicate points are visible.")
        violin_box_soft.append("Many groups still retain shape cues with compact box overlays.")
        violin_soft.append("More groups make the density shape more informative.")

    if "replicate_sparse_replicates" in quality_flags:
        bar_score += 3.0
        point_error_score += 4.0
        lollipop_error_score += 2.0
        histogram_density_score -= 10.0
        box_score += 3.0
        box_strip_score += 3.0
        violin_box_score += 1.0
        violin_score -= 2.0
        bar_soft.append("Sparse replicates keep mean+error bar summaries easy to read.")
        point_error_soft.append("Sparse replicates still read well with explicit mean points and error bars.")
        lollipop_error_soft.append("Sparse replicates keep lollipop mean+error summaries readable.")
        histogram_density_soft.append("Sparse replicate counts make histogram-density overlays unstable.")
        box_soft.append("Box summaries stay robust when replicate counts are low.")
        box_strip_soft.append("Sparse replicates benefit from explicit point overlays on top of box summaries.")
        violin_box_soft.append("Sparse replicates can still use violin+box as a balanced spread summary.")

    if "replicate_singleton_groups" in quality_flags:
        bar_score += 2.0
        point_error_score += 2.0
        lollipop_error_score += 1.0
        histogram_density_score -= 8.0
        violin_score -= 6.0
        box_score += 2.0
        box_strip_score += 2.0
        violin_box_score -= 1.0
        histogram_density_soft.append("Singleton-like groups reduce the reliability of smoothed density overlays.")
        violin_soft.append("Very low group replicate counts reduce violin-shape reliability.")
        box_strip_soft.append("Visible strip points make singleton-like groups explicit.")
        violin_box_soft.append("Very low replicate counts reduce violin-shape confidence even with box overlays.")
        bar_soft.append("Singleton-like groups remain explicit in filled mean+error bar summaries.")
        point_error_soft.append("Point+error keeps singleton-like groups explicit while preserving uncertainty cues.")
        lollipop_error_soft.append(
            "Lollipop stems keep singleton-like groups explicit while preserving uncertainty cues."
        )

    if "replicate_highly_discrete" in quality_flags:
        histogram_density_score -= 8.0
        bar_score += 2.0
        point_error_score += 2.0
        lollipop_error_score += 1.0
        box_score += 2.0
        box_strip_score += 2.0
        violin_box_score += 1.0
        histogram_density_soft.append("Highly discrete values can make histogram-density overlays blocky.")
        box_soft.append("Discrete-valued replicates remain clear in box summaries.")
        box_strip_soft.append("Discrete replicates stay interpretable when each point remains visible.")
        violin_box_soft.append("Discrete groups keep both shape and quartile cues in violin+box overlays.")
        bar_soft.append("Discrete-valued replicates remain clear in filled mean+error bar summaries.")
        point_error_soft.append("Discrete replicates stay readable with uncluttered mean/error markers.")
        lollipop_error_soft.append("Discrete replicates remain readable with lollipop stems and explicit error bars.")
    if estimated_points >= 24:
        histogram_density_score += 8.0
        box_strip_score += 1.0
        violin_box_score += 2.0
        point_error_score += 1.0
        lollipop_error_score += 1.0
        histogram_density_soft.append("Higher replicate counts make histogram density overlays more informative.")
    elif estimated_points < 10:
        histogram_density_score -= 6.0
        histogram_density_soft.append("Very sparse replicate counts reduce histogram-density reliability.")
        box_strip_score -= 1.0
        violin_box_score -= 1.0
        point_error_score -= 1.0
        lollipop_error_score -= 1.0
        box_strip_soft.append("Very sparse replicates reduce the benefit of strip overlays.")
        point_error_soft.append(
            "Very sparse replicates reduce uncertainty precision, but point+error remains interpretable."
        )
    if estimated_points >= 12:
        violin_score += 4.0
        violin_soft.append("More replicate points make the distribution shape clearer.")

    distribution_variant_soft = {
        "box": "Many groups default to box for cleaner side-by-side spread comparison.",
        "violin": "Higher replicate density with fewer groups defaults to violin for shape visibility.",
        "box_strip": (
            "Moderate group and replicate density defaults to box + strip for balanced "
            "spread and readability."
        ),
    }[distribution_template_id]
    if distribution_template_id == "box":
        box_score = max(box_score, 82.0)
        box_soft.append(distribution_variant_soft)
    elif distribution_template_id == "violin":
        violin_score = max(violin_score, 82.0)
        violin_soft.append(distribution_variant_soft)
    else:
        box_strip_score = max(box_strip_score, 82.0)
        box_strip_soft.append(distribution_variant_soft)

    return tuple(
        sorted(
            (
                _build_candidate(
                    template_id="box_strip",
                    score=box_strip_score,
                    why_hard_match=hard,
                    why_soft_prior=box_strip_soft,
                    inferred_mapping={
                        "group": dataset.candidate_roles.group[0] if dataset.candidate_roles.group else "",
                        "value": dataset.candidate_roles.value[0] if dataset.candidate_roles.value else "",
                    },
                    optional_enhancements=["Use box when you need the cleanest non-point spread summary."],
                    dataset=dataset,
                ),
                _build_candidate(
                    template_id="violin_box",
                    score=violin_box_score,
                    why_hard_match=hard,
                    why_soft_prior=violin_box_soft,
                    inferred_mapping={
                        "group": dataset.candidate_roles.group[0] if dataset.candidate_roles.group else "",
                        "value": dataset.candidate_roles.value[0] if dataset.candidate_roles.value else "",
                    },
                    optional_enhancements=["Use violin when you need shape emphasis without box overlays."],
                    dataset=dataset,
                ),
                _build_candidate(
                    template_id="point_error",
                    score=point_error_score,
                    why_hard_match=hard,
                    why_soft_prior=point_error_soft,
                    inferred_mapping={
                        "group": dataset.candidate_roles.group[0] if dataset.candidate_roles.group else "",
                        "value": dataset.candidate_roles.value[0] if dataset.candidate_roles.value else "",
                    },
                    optional_enhancements=["Use bar when filled group bars are required."],
                    dataset=dataset,
                ),
                _build_candidate(
                    template_id="lollipop_error",
                    score=lollipop_error_score,
                    why_hard_match=hard,
                    why_soft_prior=lollipop_error_soft,
                    inferred_mapping={
                        "group": dataset.candidate_roles.group[0] if dataset.candidate_roles.group else "",
                        "value": dataset.candidate_roles.value[0] if dataset.candidate_roles.value else "",
                    },
                    optional_enhancements=["Use point_error when stem baselines are not needed."],
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
                    optional_enhancements=["Use bar when category means are the primary focus."],
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
    top_score = candidates[0].score if candidates else 0.0
    ranked: list[TemplateRecommendation] = []
    for index, candidate in enumerate(candidates):
        identity = template_identity(candidate.template_id)
        ranked.append(
            TemplateRecommendation(
                template_id=candidate.template_id,
                score=candidate.score,
                rank=index + 1,
                score_gap_to_top=round(max(0.0, top_score - candidate.score), 1),
                reason=candidate.reason,
                suitability_hint=candidate.suitability_hint,
                why_hard_match=candidate.why_hard_match,
                why_soft_prior=candidate.why_soft_prior,
                inferred_mapping=candidate.inferred_mapping,
                optional_enhancements=candidate.optional_enhancements,
                preview_config_summary=candidate.preview_config_summary,
                canonical_id=identity.canonical_id,
                role=identity.role,
                lifecycle_policy=identity.lifecycle_policy,
                implementation_id=identity.implementation_id,
            )
        )
    return tuple(ranked)


class RuleBasedDatasetRecommender:
    def recommend(self, dataset: NormalizedDataset, limit: int = 5) -> tuple[TemplateRecommendation, ...]:
        if limit <= 0:
            return ()
        return _recommendations_for_dataset(dataset)[:limit]


DEFAULT_RECOMMENDER: TemplateRecommender = RuleBasedDatasetRecommender()


__all__ = [
    "DEFAULT_RECOMMENDER",
    "RuleBasedDatasetRecommender",
    "template_recommendation_from_override",
]
