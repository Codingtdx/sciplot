from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Protocol

from src.rendering.dataset_models import NormalizedDataset


@dataclass(frozen=True)
class TemplateRecommendation:
    template_id: str
    score: float
    why_hard_match: tuple[str, ...]
    why_soft_prior: tuple[str, ...]
    inferred_mapping: dict[str, str]
    optional_enhancements: tuple[str, ...]
    preview_config_summary: dict[str, Any]
    rank: int | None = None
    reason: str = ""
    suitability_hint: str = ""
    score_gap_to_top: float = 0.0


class TemplateRecommender(Protocol):
    def recommend(self, dataset: NormalizedDataset, limit: int = 5) -> tuple[TemplateRecommendation, ...]: ...


__all__ = ["TemplateRecommendation", "TemplateRecommender"]
