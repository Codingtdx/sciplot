from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol

from src.rendering.themes import (
    publication_profile_hard_constraints,
    publication_profile_protected_keys,
    visual_theme_soft_overrides,
)


@dataclass(frozen=True)
class StyleBundle:
    publication_profile_id: str
    visual_theme_id: str | None
    resolved_hard: dict[str, object]
    resolved_soft: dict[str, object]
    protected_keys: tuple[str, ...]


class StyleComposer(Protocol):
    def compose(self, publication_profile_id: str, visual_theme_id: str | None) -> StyleBundle: ...


class ContractStyleComposer:
    def compose(self, publication_profile_id: str, visual_theme_id: str | None) -> StyleBundle:
        return StyleBundle(
            publication_profile_id=publication_profile_id,
            visual_theme_id=visual_theme_id,
            resolved_hard=publication_profile_hard_constraints(publication_profile_id),
            resolved_soft=visual_theme_soft_overrides(visual_theme_id),
            protected_keys=publication_profile_protected_keys(publication_profile_id),
        )


DEFAULT_STYLE_COMPOSER = ContractStyleComposer()


__all__ = ["ContractStyleComposer", "DEFAULT_STYLE_COMPOSER", "StyleBundle", "StyleComposer"]
