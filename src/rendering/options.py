from __future__ import annotations

import math

from src import plot_style
from src.plot_contract import (
    default_options_for_template,
    size_preset_contract,
    template_contract,
)
from src.rendering.constants import DEFAULT_SIZE_BY_TEMPLATE, LEGACY_TEMPLATE_HINTS, TEMPLATE_CHOICES
from src.rendering.models import RenderOptions
from src.rendering.template_lifecycle import is_supported_template_id, resolve_template_id
from src.rendering.themes import visual_theme_ids

_VALID_TICK_DENSITIES = frozenset({"auto", "sparse", "dense"})
_VALID_TICK_EDGE_LABELS = frozenset({"auto", "hide_min", "hide_max", "hide_both"})


def validate_template_name(template: str) -> str:
    if template in LEGACY_TEMPLATE_HINTS:
        raise ValueError(f"Legacy template name `{template}` is no longer supported. {LEGACY_TEMPLATE_HINTS[template]}")
    if not is_supported_template_id(template):
        raise ValueError(f"Unknown template: {template}. Supported templates: {', '.join(TEMPLATE_CHOICES)}")
    return template


def resolve_size(
    size_text: str | None,
    template: str,
    *,
    resolved_template_id: str | None = None,
) -> tuple[float, float]:
    effective_template = resolved_template_id or resolve_template_id(template)
    spec = template_contract(effective_template)
    chosen = size_text or DEFAULT_SIZE_BY_TEMPLATE[effective_template]
    if chosen not in spec.allowed_sizes:
        raise ValueError(
            f"Template `{template}` does not support size `{chosen}`. Supported sizes: {', '.join(spec.allowed_sizes)}"
        )
    size_spec = size_preset_contract(chosen)
    return size_spec.width_mm, size_spec.height_mm


def _ensure_template_option_supported(
    template: str,
    option_id: str,
    *,
    resolved_template_id: str | None = None,
) -> None:
    spec = template_contract(resolved_template_id or resolve_template_id(template))
    if option_id not in spec.editable_options:
        raise ValueError(
            f"Template `{template}` does not support option `{option_id}`. "
            f"Supported editable options: {', '.join(spec.editable_options)}"
        )


def _normalize_manual_bound(
    template: str,
    option_id: str,
    value: float | None,
    *,
    resolved_template_id: str | None = None,
) -> float | None:
    if value is None:
        return None
    _ensure_template_option_supported(template, option_id, resolved_template_id=resolved_template_id)
    numeric = float(value)
    if not math.isfinite(numeric):
        raise ValueError(f"`{option_id}` must be a finite number.")
    return numeric


def _normalize_series_order(
    template: str,
    series_order: list[str] | tuple[str, ...] | None,
    *,
    resolved_template_id: str | None = None,
) -> tuple[str, ...] | None:
    if series_order is None:
        return None
    _ensure_template_option_supported(template, "series_order", resolved_template_id=resolved_template_id)
    cleaned: list[str] = []
    seen: set[str] = set()
    for item in series_order:
        label = str(item).strip()
        if not label:
            continue
        key = label.lower()
        if key in seen:
            continue
        seen.add(key)
        cleaned.append(label)
    return tuple(cleaned) if cleaned else None


def _normalize_label_override(value: str | None) -> str | None:
    if value is None:
        return None
    cleaned = str(value).strip()
    return cleaned or None


def _normalize_enumerated_option(
    template: str,
    option_id: str,
    value: str | None,
    *,
    allowed: frozenset[str],
    resolved_template_id: str | None = None,
) -> str | None:
    if value is None:
        return None
    _ensure_template_option_supported(template, option_id, resolved_template_id=resolved_template_id)
    cleaned = str(value).strip().lower()
    if not cleaned or cleaned == "auto":
        return None
    if cleaned not in allowed:
        raise ValueError(
            f"`{option_id}` must be one of {', '.join(sorted(allowed))}."
        )
    return cleaned


def resolve_render_options(
    *,
    template: str,
    size: str | None = None,
    xscale: str | None = None,
    yscale: str | None = None,
    reverse_x: bool | None = None,
    x_min: float | None = None,
    x_max: float | None = None,
    y_min: float | None = None,
    y_max: float | None = None,
    x_tick_density: str | None = None,
    y_tick_density: str | None = None,
    x_tick_edge_labels: str | None = None,
    y_tick_edge_labels: str | None = None,
    series_order: list[str] | tuple[str, ...] | None = None,
    x_label_override: str | None = None,
    y_label_override: str | None = None,
    baseline: str | None = None,
    show_colorbar: bool | None = None,
    style_preset: str = plot_style.DEFAULT_STYLE_PRESET,
    palette_preset: str = plot_style.DEFAULT_PALETTE_PRESET,
    use_sidecar: bool | None = None,
    visual_theme_id: str | None = None,
    resolved_template_id: str | None = None,
) -> RenderOptions:
    contract_template = resolved_template_id or resolve_template_id(template)
    width_mm, height_mm = resolve_size(size, template, resolved_template_id=contract_template)
    spec = template_contract(contract_template)
    defaults = default_options_for_template(contract_template)
    normalized_style = plot_style.normalize_style_preset(style_preset or defaults.get("style_preset"))
    if normalized_style not in spec.available_styles:
        raise ValueError(
            f"Template `{template}` does not support style `{normalized_style}`. "
            f"Supported styles: {', '.join(spec.available_styles)}"
        )
    resolved_palette = palette_preset or defaults.get("palette_preset", plot_style.DEFAULT_PALETTE_PRESET)
    if resolved_palette not in spec.available_palettes:
        raise ValueError(
            f"Template `{template}` does not support palette `{resolved_palette}`. "
            f"Supported palettes: {', '.join(spec.available_palettes)}"
        )
    resolved_theme = visual_theme_id.strip() if isinstance(visual_theme_id, str) else None
    if resolved_theme and resolved_theme not in visual_theme_ids():
        raise ValueError(
            f"Unknown visual theme: {resolved_theme}. Supported themes: {', '.join(visual_theme_ids())}"
        )
    return RenderOptions(
        width_mm=width_mm,
        height_mm=height_mm,
        xscale=xscale or defaults.get("xscale", "linear"),
        yscale=yscale or defaults.get("yscale", "linear"),
        reverse_x=bool(defaults.get("reverse_x", False)) if reverse_x is None else reverse_x,
        baseline=baseline or defaults.get("baseline", "none"),
        show_colorbar=defaults.get("show_colorbar", True) if show_colorbar is None else show_colorbar,
        style_preset=normalized_style,
        palette_preset=resolved_palette,
        x_min=_normalize_manual_bound(template, "x_min", x_min, resolved_template_id=contract_template),
        x_max=_normalize_manual_bound(template, "x_max", x_max, resolved_template_id=contract_template),
        y_min=_normalize_manual_bound(template, "y_min", y_min, resolved_template_id=contract_template),
        y_max=_normalize_manual_bound(template, "y_max", y_max, resolved_template_id=contract_template),
        x_tick_density=_normalize_enumerated_option(
            template,
            "x_tick_density",
            x_tick_density,
            allowed=_VALID_TICK_DENSITIES,
            resolved_template_id=contract_template,
        ),
        y_tick_density=_normalize_enumerated_option(
            template,
            "y_tick_density",
            y_tick_density,
            allowed=_VALID_TICK_DENSITIES,
            resolved_template_id=contract_template,
        ),
        x_tick_edge_labels=_normalize_enumerated_option(
            template,
            "x_tick_edge_labels",
            x_tick_edge_labels,
            allowed=_VALID_TICK_EDGE_LABELS,
            resolved_template_id=contract_template,
        ),
        y_tick_edge_labels=_normalize_enumerated_option(
            template,
            "y_tick_edge_labels",
            y_tick_edge_labels,
            allowed=_VALID_TICK_EDGE_LABELS,
            resolved_template_id=contract_template,
        ),
        series_order=_normalize_series_order(
            template,
            series_order,
            resolved_template_id=contract_template,
        ),
        x_label_override=_normalize_label_override(x_label_override),
        y_label_override=_normalize_label_override(y_label_override),
        use_sidecar=use_sidecar,
        visual_theme_id=resolved_theme or None,
    )


__all__ = [
    "resolve_render_options",
    "resolve_size",
    "validate_template_name",
]
