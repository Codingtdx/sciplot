from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol

from src.plot_contract import template_contract, template_names
from src.rendering.dataset_models import DataShape, RoleKey


@dataclass(frozen=True)
class TemplateSpec:
    id: str
    label: str
    supported_shapes: tuple[DataShape, ...]
    required_roles: tuple[RoleKey, ...]
    optional_roles: tuple[RoleKey, ...]
    preview_priority: int
    scientific_tags: tuple[str, ...]
    family: str
    implementation_id: str


class TemplateCatalog(Protocol):
    def list_templates(self) -> tuple[TemplateSpec, ...]: ...

    def get(self, template_id: str) -> TemplateSpec: ...


def _supported_shapes(template_id: str) -> tuple[DataShape, ...]:
    if template_id in {"curve", "point_line", "stacked_curve", "segmented_stacked_curve", "scatter"}:
        return ("curve_like",)
    if template_id in {"bar", "box", "violin"}:
        return ("replicate_table", "distribution")
    if template_id == "heatmap":
        return ("matrix",)
    return ()


def _scientific_tags(template_id: str) -> tuple[str, ...]:
    if template_id in {"curve", "point_line", "scatter", "stacked_curve", "segmented_stacked_curve"}:
        return ("curve", "spectra")
    if template_id in {"bar", "box", "violin"}:
        return ("distribution", "statistics")
    if template_id == "heatmap":
        return ("matrix", "heatmap")
    return ()


def _family(template_id: str) -> str:
    if template_id in {"curve", "point_line", "scatter", "stacked_curve", "segmented_stacked_curve"}:
        return "curve"
    if template_id in {"bar", "box", "violin"}:
        return "statistics"
    if template_id == "heatmap":
        return "heatmap"
    return "other"


def _preview_priority(template_id: str) -> int:
    if template_id == "curve":
        return 100
    if template_id == "point_line":
        return 95
    if template_id == "scatter":
        return 80
    if template_id == "heatmap":
        return 90
    if template_id in {"bar", "box", "violin"}:
        return 70
    return 60


class ContractTemplateCatalog:
    def list_templates(self) -> tuple[TemplateSpec, ...]:
        specs: list[TemplateSpec] = []
        for template_id in template_names():
            contract = template_contract(template_id)
            specs.append(
                TemplateSpec(
                    id=template_id,
                    label=contract.label,
                    supported_shapes=_supported_shapes(template_id),
                    required_roles=(),
                    optional_roles=tuple(contract.editable_options),
                    preview_priority=_preview_priority(template_id),
                    scientific_tags=_scientific_tags(template_id),
                    family=_family(template_id),
                    implementation_id=template_id,
                )
            )
        return tuple(specs)

    def get(self, template_id: str) -> TemplateSpec:
        for spec in self.list_templates():
            if spec.id == template_id:
                return spec
        raise ValueError(f"Unknown template: {template_id}")


DEFAULT_TEMPLATE_CATALOG = ContractTemplateCatalog()


__all__ = [
    "ContractTemplateCatalog",
    "DEFAULT_TEMPLATE_CATALOG",
    "TemplateCatalog",
    "TemplateSpec",
]
