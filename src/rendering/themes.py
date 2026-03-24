from __future__ import annotations

from collections.abc import Mapping
from dataclasses import asdict, fields, is_dataclass
from typing import Any

from src import plot_style


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


__all__ = [
    "publication_profile_hard_constraints",
    "publication_profile_protected_keys",
]
