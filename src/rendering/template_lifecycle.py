from __future__ import annotations

from dataclasses import dataclass
from typing import Final

_CANONICAL_TO_ALIASES: Final[dict[str, tuple[str, ...]]] = {
    "scatter_fit": ("scatter_with_fit",),
    "mean_band": ("replicate_curves_with_band",),
    "grouped_bar_error": ("grouped_bar_compare",),
}

_ALIAS_STATUS: Final[dict[str, str]] = {
    "scatter_with_fit": "deprecated_in_practice",
    "replicate_curves_with_band": "deprecated_in_practice",
    "grouped_bar_compare": "indefinite_compat",
}

_ALIAS_RECOMMENDATION_PENALTY: Final[dict[str, float]] = {
    "scatter_with_fit": 5.0,
    "replicate_curves_with_band": 4.0,
    "grouped_bar_compare": 4.0,
}

_ALIAS_TO_CANONICAL: Final[dict[str, str]] = {
    alias: canonical
    for canonical, aliases in _CANONICAL_TO_ALIASES.items()
    for alias in aliases
}


@dataclass(frozen=True)
class TemplateLifecycleEntry:
    template_id: str
    canonical_id: str
    role: str
    lifecycle_policy: str


@dataclass(frozen=True)
class TemplateIdentity:
    requested_template_id: str
    canonical_id: str
    role: str
    lifecycle_policy: str
    implementation_id: str


def canonical_template_id(template_id: str) -> str:
    return _ALIAS_TO_CANONICAL.get(template_id, template_id)


def alias_templates_for(canonical_id: str) -> tuple[str, ...]:
    return _CANONICAL_TO_ALIASES.get(canonical_id, ())


def template_family_ids(canonical_id: str) -> tuple[str, ...]:
    return (canonical_id, *alias_templates_for(canonical_id))


def alias_lifecycle_policy(template_id: str) -> str:
    return _ALIAS_STATUS.get(template_id, "canonical")


def template_role(template_id: str) -> str:
    return "alias" if canonical_template_id(template_id) != template_id else "canonical"


def alias_recommendation_penalty(template_id: str) -> float:
    return float(_ALIAS_RECOMMENDATION_PENALTY.get(template_id, 0.0))


def template_identity(template_id: str) -> TemplateIdentity:
    canonical_id = canonical_template_id(template_id)
    return TemplateIdentity(
        requested_template_id=template_id,
        canonical_id=canonical_id,
        role=template_role(template_id),
        lifecycle_policy=alias_lifecycle_policy(template_id),
        implementation_id=canonical_id,
    )


def template_lifecycle_inventory() -> tuple[TemplateLifecycleEntry, ...]:
    rows: list[TemplateLifecycleEntry] = []
    for canonical_id, aliases in _CANONICAL_TO_ALIASES.items():
        rows.append(
            TemplateLifecycleEntry(
                template_id=canonical_id,
                canonical_id=canonical_id,
                role="canonical",
                lifecycle_policy="canonical",
            )
        )
        for alias_id in aliases:
            rows.append(
                TemplateLifecycleEntry(
                    template_id=alias_id,
                    canonical_id=canonical_id,
                    role="alias",
                    lifecycle_policy=alias_lifecycle_policy(alias_id),
                )
            )
    return tuple(rows)


__all__ = [
    "TemplateIdentity",
    "TemplateLifecycleEntry",
    "alias_lifecycle_policy",
    "alias_recommendation_penalty",
    "alias_templates_for",
    "canonical_template_id",
    "template_identity",
    "template_role",
    "template_family_ids",
    "template_lifecycle_inventory",
]
