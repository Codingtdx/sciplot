from __future__ import annotations

import json
import re
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

USER_RULES_PATH = Path.home() / "Library" / "Application Support" / "SciPlot" / "scientific_text_rules.json"

_RULE_KINDS = frozenset({"unit", "label"})


@dataclass(frozen=True)
class ScientificTextRule:
    id: str
    kind: str
    input: str
    output: str
    enabled: bool
    canonical_input: str


@dataclass(frozen=True)
class ScientificTextRulePreview:
    rule: ScientificTextRule
    automatic_output: str
    effective_output: str
    errors: tuple[str, ...] = ()
    warnings: tuple[str, ...] = ()


def _canonicalize(value: str) -> str:
    from src.text_normalization import canonicalize_token

    return canonicalize_token(value)


def _automatic_output(kind: str, input_text: str) -> str:
    from src.text_normalization import normalize_label_without_user_rules, normalize_unit_without_user_rules

    if kind == "label":
        return normalize_label_without_user_rules(input_text)
    return normalize_unit_without_user_rules(input_text)


def _rule_id(kind: str, canonical_input: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "_", canonical_input.lower()).strip("_")
    return f"{kind}/{slug or 'rule'}"


def _rule_from_payload(value: object) -> ScientificTextRule:
    if not isinstance(value, dict):
        raise ValueError("Scientific text rule payload must be an object.")
    kind = str(value.get("kind", "")).strip().lower()
    if kind not in _RULE_KINDS:
        raise ValueError("Scientific text rule kind must be 'unit' or 'label'.")
    input_text = str(value.get("input", "")).strip()
    if not input_text:
        raise ValueError("Input cannot be empty.")
    output = str(value.get("output", "")).strip()
    enabled = bool(value.get("enabled", True))
    canonical = _canonicalize(input_text)
    return ScientificTextRule(
        id=_rule_id(kind, canonical),
        kind=kind,
        input=input_text,
        output=output,
        enabled=enabled,
        canonical_input=canonical,
    )


def _rule_errors(rule: ScientificTextRule) -> tuple[str, ...]:
    errors: list[str] = []
    if not rule.output:
        errors.append("Output cannot be empty.")
    return tuple(errors)


def preview_scientific_text_rule(value: object) -> ScientificTextRulePreview:
    rule = _rule_from_payload(value)
    errors = _rule_errors(rule)
    automatic = _automatic_output(rule.kind, rule.input)
    return ScientificTextRulePreview(
        rule=rule,
        automatic_output=automatic,
        effective_output=rule.output if rule.enabled and not errors else automatic,
        errors=errors,
    )


def ensure_user_rules_dir() -> None:
    USER_RULES_PATH.parent.mkdir(parents=True, exist_ok=True)


def list_scientific_text_rules() -> list[ScientificTextRule]:
    if not USER_RULES_PATH.exists():
        return []
    payload = json.loads(USER_RULES_PATH.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        return []
    rules: list[ScientificTextRule] = []
    for item in payload.get("rules", []):
        try:
            rules.append(_rule_from_payload(item))
        except ValueError:
            continue
    return sorted(rules, key=lambda item: (item.kind, item.input.lower(), item.id))


def _write_rules(rules: list[ScientificTextRule]) -> None:
    ensure_user_rules_dir()
    payload: dict[str, Any] = {
        "version": 1,
        "rules": [asdict(rule) for rule in sorted(rules, key=lambda item: (item.kind, item.input.lower(), item.id))],
    }
    USER_RULES_PATH.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def save_scientific_text_rule(value: object, *, replacing_id: str | None = None) -> ScientificTextRule:
    preview = preview_scientific_text_rule(value)
    if preview.errors:
        raise ValueError(" ".join(preview.errors))
    rule = preview.rule
    rules = [item for item in list_scientific_text_rules() if item.id != replacing_id]
    if any(item.id == rule.id for item in rules):
        raise FileExistsError(f"Scientific text rule already exists: {rule.id}")
    rules.append(rule)
    _write_rules(rules)
    return rule


def delete_scientific_text_rule(rule_id: str) -> None:
    rules = list_scientific_text_rules()
    remaining = [item for item in rules if item.id != rule_id]
    if len(remaining) == len(rules):
        raise FileNotFoundError(f"Scientific text rule not found: {rule_id}")
    _write_rules(remaining)


def lookup_scientific_text_rule(kind: str, canonical_input: str) -> str | None:
    for rule in list_scientific_text_rules():
        if rule.enabled and rule.kind == kind and rule.canonical_input == canonical_input:
            return rule.output
    return None


__all__ = [
    "ScientificTextRule",
    "ScientificTextRulePreview",
    "USER_RULES_PATH",
    "delete_scientific_text_rule",
    "list_scientific_text_rules",
    "lookup_scientific_text_rule",
    "preview_scientific_text_rule",
    "save_scientific_text_rule",
]
