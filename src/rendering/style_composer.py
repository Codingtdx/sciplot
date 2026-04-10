from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol

from src import plot_style
from src.rendering.themes import (
    publication_profile_hard_constraints,
    publication_profile_protected_keys,
    sanitized_visual_theme_soft_overrides,
)


@dataclass(frozen=True)
class StyleBundle:
    publication_profile_id: str
    visual_theme_id: str | None
    resolved_hard: dict[str, object]
    resolved_soft: dict[str, object]
    protected_keys: tuple[str, ...]
    blocked_soft_keys: tuple[str, ...] = ()


class StyleComposer(Protocol):
    def compose(self, publication_profile_id: str, visual_theme_id: str | None) -> StyleBundle: ...


class ContractStyleComposer:
    def compose(self, publication_profile_id: str, visual_theme_id: str | None) -> StyleBundle:
        normalized_profile_id = plot_style.normalize_style_preset(publication_profile_id)
        resolved_soft, blocked_soft_keys = sanitized_visual_theme_soft_overrides(
            normalized_profile_id,
            visual_theme_id,
        )
        return StyleBundle(
            publication_profile_id=normalized_profile_id,
            visual_theme_id=visual_theme_id,
            resolved_hard=publication_profile_hard_constraints(normalized_profile_id),
            resolved_soft=resolved_soft,
            protected_keys=publication_profile_protected_keys(normalized_profile_id),
            blocked_soft_keys=blocked_soft_keys,
        )


DEFAULT_STYLE_COMPOSER = ContractStyleComposer()


__all__ = ["ContractStyleComposer", "DEFAULT_STYLE_COMPOSER", "StyleBundle", "StyleComposer"]
