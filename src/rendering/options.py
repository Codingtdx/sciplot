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
        raise ValueError(f"旧模板名 `{template}` 已停用。{LEGACY_TEMPLATE_HINTS[template]}")
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
    reverse_x: bool = False,
    baseline: str | None = None,
    show_colorbar: bool | None = None,
    style_preset: str = plot_style.DEFAULT_STYLE_PRESET,
    palette_preset: str = plot_style.DEFAULT_PALETTE_PRESET,
    use_sidecar: bool | None = None,
) -> RenderOptions:
    width_mm, height_mm = resolve_size(size, template)
    defaults = default_options_for_template(template)
    return RenderOptions(
        width_mm=width_mm,
        height_mm=height_mm,
        xscale=xscale or defaults.get("xscale", "linear"),
        yscale=yscale or defaults.get("yscale", "linear"),
        reverse_x=reverse_x,
        baseline=baseline or defaults.get("baseline", "none"),
        show_colorbar=defaults.get("show_colorbar", True) if show_colorbar is None else show_colorbar,
        style_preset=plot_style.normalize_style_preset(style_preset),
        palette_preset=palette_preset,
        use_sidecar=use_sidecar,
    )


__all__ = [
    "resolve_render_options",
    "resolve_size",
    "validate_template_name",
]
