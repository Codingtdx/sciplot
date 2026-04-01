from __future__ import annotations

import json
from pathlib import Path

from src.data_studio.models import (
    TemplateDefinition,
    TemplateFieldBinding,
    TemplateMatchCondition,
)

ROOT = Path(__file__).resolve().parents[2]
TEMPLATE_ROOT = ROOT / "data_studio_templates"
BUILTIN_TEMPLATE_DIR = TEMPLATE_ROOT / "builtin"
USER_TEMPLATE_DIR = TEMPLATE_ROOT / "user"


def ensure_template_dirs() -> None:
    BUILTIN_TEMPLATE_DIR.mkdir(parents=True, exist_ok=True)
    USER_TEMPLATE_DIR.mkdir(parents=True, exist_ok=True)


def template_path(template_id: str, *, builtin: bool | None = None) -> Path:
    ensure_template_dirs()
    normalized = template_id.replace("/", "__")
    if builtin is True:
        return BUILTIN_TEMPLATE_DIR / f"{normalized}.json"
    if builtin is False:
        return USER_TEMPLATE_DIR / f"{normalized}.json"
    builtin_path = BUILTIN_TEMPLATE_DIR / f"{normalized}.json"
    if builtin_path.exists():
        return builtin_path
    return USER_TEMPLATE_DIR / f"{normalized}.json"


def _condition_from_payload(payload: dict[str, object]) -> TemplateMatchCondition:
    return TemplateMatchCondition(
        sheet_name_contains=tuple(str(item) for item in payload.get("sheet_name_contains", ()) or ()),
        text_contains=tuple(str(item) for item in payload.get("text_contains", ()) or ()),
        field_kinds=tuple(str(item) for item in payload.get("field_kinds", ()) or ()),
        minimum_score=float(payload.get("minimum_score", 0.0) or 0.0),
    )


def _binding_from_payload(payload: dict[str, object]) -> TemplateFieldBinding:
    return TemplateFieldBinding(
        id=str(payload["id"]),
        role=str(payload["role"]),
        label=str(payload["label"]),
        sheet_name=str(payload["sheet_name"]) if payload.get("sheet_name") is not None else None,
        block_id=str(payload["block_id"]) if payload.get("block_id") is not None else None,
        column_name=str(payload["column_name"]) if payload.get("column_name") is not None else None,
        column_index=int(payload["column_index"]) if payload.get("column_index") is not None else None,
        row_label_contains=(
            str(payload["row_label_contains"]) if payload.get("row_label_contains") is not None else None
        ),
        cell_value_contains=tuple(str(item) for item in payload.get("cell_value_contains", ()) or ()),
        unit_hint=str(payload["unit_hint"]) if payload.get("unit_hint") is not None else None,
        optional=bool(payload.get("optional", False)),
    )


def template_from_payload(payload: dict[str, object]) -> TemplateDefinition:
    return TemplateDefinition(
        version=int(payload.get("version", 1)),
        id=str(payload["id"]),
        label=str(payload["label"]),
        family=str(payload["family"]),
        builtin=bool(payload.get("builtin", False)),
        description=str(payload.get("description", "")),
        file_types=tuple(str(item) for item in payload.get("file_types", ()) or ()),
        parse_strategy=str(payload["parse_strategy"]),
        match_conditions=tuple(
            _condition_from_payload(item) for item in payload.get("match_conditions", ()) or ()
        ),
        field_bindings=tuple(_binding_from_payload(item) for item in payload.get("field_bindings", ()) or ()),
        workbook_metric_ids=tuple(str(item) for item in payload.get("workbook_metric_ids", ()) or ()),
        default_group_name_strategy=str(payload.get("default_group_name_strategy", "common_prefix")),
        preferred_sheet_name=str(payload.get("preferred_sheet_name", "Representative_Curve")),
        metadata=dict(payload.get("metadata", {}) or {}),
    )


def template_to_payload(template: TemplateDefinition) -> dict[str, object]:
    return {
        "version": template.version,
        "id": template.id,
        "label": template.label,
        "family": template.family,
        "builtin": template.builtin,
        "description": template.description,
        "file_types": list(template.file_types),
        "parse_strategy": template.parse_strategy,
        "match_conditions": [
            {
                "sheet_name_contains": list(condition.sheet_name_contains),
                "text_contains": list(condition.text_contains),
                "field_kinds": list(condition.field_kinds),
                "minimum_score": condition.minimum_score,
            }
            for condition in template.match_conditions
        ],
        "field_bindings": [
            {
                "id": binding.id,
                "role": binding.role,
                "label": binding.label,
                "sheet_name": binding.sheet_name,
                "block_id": binding.block_id,
                "column_name": binding.column_name,
                "column_index": binding.column_index,
                "row_label_contains": binding.row_label_contains,
                "cell_value_contains": list(binding.cell_value_contains),
                "unit_hint": binding.unit_hint,
                "optional": binding.optional,
            }
            for binding in template.field_bindings
        ],
        "workbook_metric_ids": list(template.workbook_metric_ids),
        "default_group_name_strategy": template.default_group_name_strategy,
        "preferred_sheet_name": template.preferred_sheet_name,
        "metadata": template.metadata,
    }


def load_template(template_id: str) -> TemplateDefinition:
    path = template_path(template_id)
    if not path.exists():
        raise FileNotFoundError(f"Unknown Data Studio template: {template_id}")
    payload = json.loads(path.read_text(encoding="utf-8"))
    return template_from_payload(payload)


def list_templates() -> list[TemplateDefinition]:
    ensure_template_dirs()
    templates: list[TemplateDefinition] = []
    for directory in (BUILTIN_TEMPLATE_DIR, USER_TEMPLATE_DIR):
        for path in sorted(directory.glob("*.json")):
            payload = json.loads(path.read_text(encoding="utf-8"))
            templates.append(template_from_payload(payload))
    return sorted(templates, key=lambda item: (not item.builtin, item.label.lower(), item.id))


def save_template(template: TemplateDefinition, *, overwrite: bool = False) -> Path:
    path = template_path(template.id, builtin=template.builtin)
    if path.exists() and not overwrite:
        raise FileExistsError(f"Template already exists: {template.id}")
    path.write_text(json.dumps(template_to_payload(template), indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return path


def delete_template(template_id: str) -> None:
    path = template_path(template_id, builtin=False)
    if not path.exists():
        raise FileNotFoundError(f"User template not found: {template_id}")
    path.unlink()


def rename_template(template_id: str, *, new_id: str | None = None, new_label: str | None = None) -> TemplateDefinition:
    template = load_template(template_id)
    if template.builtin:
        raise ValueError("Built-in templates cannot be renamed.")
    updated = TemplateDefinition(
        version=template.version,
        id=new_id or template.id,
        label=new_label or template.label,
        family=template.family,
        builtin=False,
        description=template.description,
        file_types=template.file_types,
        parse_strategy=template.parse_strategy,
        match_conditions=template.match_conditions,
        field_bindings=template.field_bindings,
        workbook_metric_ids=template.workbook_metric_ids,
        default_group_name_strategy=template.default_group_name_strategy,
        preferred_sheet_name=template.preferred_sheet_name,
        metadata=template.metadata,
    )
    delete_template(template_id)
    save_template(updated)
    return updated


__all__ = [
    "BUILTIN_TEMPLATE_DIR",
    "TEMPLATE_ROOT",
    "USER_TEMPLATE_DIR",
    "delete_template",
    "ensure_template_dirs",
    "list_templates",
    "load_template",
    "rename_template",
    "save_template",
    "template_from_payload",
    "template_path",
    "template_to_payload",
]
