from __future__ import annotations

from src import plot_style
from src.plot_contract import (
    default_options_for_template,
    size_preset_contract,
    template_contract,
)
from src.rendering.constants import DEFAULT_SIZE_BY_TEMPLATE, LEGACY_TEMPLATE_HINTS, TEMPLATE_CHOICES
from src.rendering.models import RenderOptions


def validate_template_name(template: str) -> str:
    if template in LEGACY_TEMPLATE_HINTS:
        raise ValueError(f"Legacy template name `{template}` is no longer supported. {LEGACY_TEMPLATE_HINTS[template]}")
    if template not in TEMPLATE_CHOICES:
        raise ValueError(f"Unknown template: {template}. Supported templates: {', '.join(TEMPLATE_CHOICES)}")
    return template


def resolve_size(size_text: str | None, template: str) -> tuple[float, float]:
    spec = template_contract(template)
    chosen = size_text or DEFAULT_SIZE_BY_TEMPLATE[template]
    if chosen not in spec.allowed_sizes:
        raise ValueError(
            f"Template `{template}` does not support size `{chosen}`. Supported sizes: {', '.join(spec.allowed_sizes)}"
        )
    size_spec = size_preset_contract(chosen)
    return size_spec.width_mm, size_spec.height_mm


def resolve_render_options(
    *,
    template: str,
    size: str | None = None,
    xscale: str | None = None,
    yscale: str | None = None,
    reverse_x: bool | None = None,
    baseline: str | None = None,
    show_colorbar: bool | None = None,
    style_preset: str = plot_style.DEFAULT_STYLE_PRESET,
    palette_preset: str = plot_style.DEFAULT_PALETTE_PRESET,
    use_sidecar: bool | None = None,
) -> RenderOptions:
    width_mm, height_mm = resolve_size(size, template)
    spec = template_contract(template)
    defaults = default_options_for_template(template)
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
        use_sidecar=use_sidecar,
    )


__all__ = [
    "resolve_render_options",
    "resolve_size",
    "validate_template_name",
]
