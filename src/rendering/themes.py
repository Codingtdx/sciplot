from __future__ import annotations

from collections.abc import Mapping
from dataclasses import asdict, dataclass, fields, is_dataclass
from typing import Any

from src import plot_style


@dataclass(frozen=True)
class VisualThemeSpec:
    label: str
    description: str
    soft_overrides: dict[str, Any]


# Publication-critical sizing/stroke/export knobs must remain contract-owned.
_PROTECTED_RCPARAM_KEYS: frozenset[str] = frozenset(
    {
        "figure.dpi",
        "savefig.dpi",
        "savefig.format",
        "pdf.fonttype",
        "ps.fonttype",
        "font.family",
        "font.sans-serif",
        "font.size",
        "axes.labelsize",
        "axes.titlesize",
        "xtick.labelsize",
        "ytick.labelsize",
        "legend.fontsize",
        "axes.labelpad",
        "xtick.major.pad",
        "ytick.major.pad",
        "axes.linewidth",
        "xtick.major.width",
        "ytick.major.width",
        "xtick.major.size",
        "ytick.major.size",
        "xtick.minor.width",
        "ytick.minor.width",
        "xtick.minor.size",
        "ytick.minor.size",
        "lines.linewidth",
        "lines.markersize",
    }
)


def _flatten_keys(value: Any, *, prefix: str = "") -> tuple[str, ...]:
    keys: list[str] = []
    if is_dataclass(value) and not isinstance(value, type):
        for field in fields(value):
            child = getattr(value, field.name)
            path = f"{prefix}.{field.name}" if prefix else field.name
            if is_dataclass(child) and not isinstance(child, type):
                keys.extend(_flatten_keys(child, prefix=path))
            elif isinstance(child, Mapping):
                for child_key, child_value in child.items():
                    nested = f"{path}.{child_key}"
                    if is_dataclass(child_value) and not isinstance(child_value, type):
                        keys.extend(_flatten_keys(child_value, prefix=nested))
                    else:
                        keys.append(nested)
            else:
                keys.append(path)
    return tuple(keys)


def publication_profile_hard_constraints(publication_profile_id: str) -> dict[str, Any]:
    spec = plot_style.get_style_spec(publication_profile_id)
    return asdict(spec)


def publication_profile_protected_keys(publication_profile_id: str) -> tuple[str, ...]:
    spec = plot_style.get_style_spec(publication_profile_id)
    return _flatten_keys(spec)


def publication_profile_protected_rcparams(publication_profile_id: str) -> tuple[str, ...]:
    # The set is currently style-agnostic, but the profile id keeps the callsite
    # contract explicit: protected keys are tied to publication profiles.
    _ = publication_profile_id
    return tuple(sorted(_PROTECTED_RCPARAM_KEYS))


_VISUAL_THEMES: dict[str, VisualThemeSpec] = {
    "clean_light": VisualThemeSpec(
        label="Clean Light",
        description="A minimal soft theme with plain surfaces and no visible grid.",
        soft_overrides={
            "axes.facecolor": "#ffffff",
            "figure.facecolor": "#ffffff",
            "axes.grid": False,
            "grid.alpha": 0.0,
            "legend.frameon": False,
        },
    ),
    "soft_grid": VisualThemeSpec(
        label="Soft Grid",
        description="A quiet grid-forward theme for technical figures that need light structure.",
        soft_overrides={
            "axes.facecolor": "#fbfcfd",
            "figure.facecolor": "#fbfcfd",
            "axes.grid": True,
            "grid.alpha": 0.16,
            "grid.linestyle": "-",
            "legend.frameon": True,
        },
    ),
    "presentation_like": VisualThemeSpec(
        label="Presentation Like",
        description="A slightly warmer theme tuned for slides and talk-friendly contrast.",
        soft_overrides={
            "axes.facecolor": "#f8faf7",
            "figure.facecolor": "#f8faf7",
            "axes.grid": True,
            "grid.alpha": 0.1,
            "grid.linestyle": "-",
            "legend.frameon": True,
            "legend.fancybox": True,
        },
    ),
}


def visual_theme_ids() -> tuple[str, ...]:
    return tuple(_VISUAL_THEMES.keys())


def visual_theme_spec(visual_theme_id: str) -> VisualThemeSpec:
    try:
        return _VISUAL_THEMES[visual_theme_id]
    except KeyError as exc:
        raise ValueError(f"Unknown visual theme: {visual_theme_id}.") from exc


def visual_theme_soft_overrides(visual_theme_id: str | None) -> dict[str, Any]:
    if visual_theme_id is None:
        return {}
    return dict(visual_theme_spec(visual_theme_id).soft_overrides)


def sanitized_visual_theme_soft_overrides(
    publication_profile_id: str,
    visual_theme_id: str | None,
) -> tuple[dict[str, Any], tuple[str, ...]]:
    raw_overrides = visual_theme_soft_overrides(visual_theme_id)
    if not raw_overrides:
        return {}, ()
    blocked = set(publication_profile_protected_rcparams(publication_profile_id))
    resolved = {key: value for key, value in raw_overrides.items() if key not in blocked}
    blocked_keys = tuple(sorted(key for key in raw_overrides if key in blocked))
    return resolved, blocked_keys


def visual_theme_catalog_payload() -> list[dict[str, Any]]:
    return [
        {
            "id": theme_id,
            "label": spec.label,
            "description": spec.description,
        }
        for theme_id, spec in _VISUAL_THEMES.items()
    ]


__all__ = [
    "publication_profile_hard_constraints",
    "publication_profile_protected_keys",
    "publication_profile_protected_rcparams",
    "sanitized_visual_theme_soft_overrides",
    "visual_theme_catalog_payload",
    "visual_theme_ids",
    "visual_theme_soft_overrides",
    "visual_theme_spec",
]
