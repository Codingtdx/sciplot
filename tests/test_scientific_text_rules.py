from __future__ import annotations

from fastapi.testclient import TestClient

from app.sidecar.server import app
from src import scientific_text_rules
from src.text_normalization import normalize_label, normalize_unit

client = TestClient(app)


def test_scientific_text_rules_override_builtins_and_disabled_rules_fall_back(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr(scientific_text_rules, "USER_RULES_PATH", tmp_path / "scientific_text_rules.json")

    saved = scientific_text_rules.save_scientific_text_rule(
        {"kind": "unit", "input": "a.u.", "output": "arb. u.", "enabled": True}
    )
    assert saved.id == "unit/a_u"
    assert normalize_unit("a.u.") == "arb. u."

    scientific_text_rules.save_scientific_text_rule(
        {"kind": "unit", "input": "a.u.", "output": "arb. u.", "enabled": False},
        replacing_id=saved.id,
    )
    assert normalize_unit("a.u.") == "a.u."

    scientific_text_rules.save_scientific_text_rule(
        {"kind": "label", "input": "photoluminescence", "output": "PL", "enabled": True}
    )
    assert normalize_label("Photoluminescence") == "PL"


def test_scientific_text_rules_routes_preview_crud_and_normalization(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr(scientific_text_rules, "USER_RULES_PATH", tmp_path / "scientific_text_rules.json")

    preview = client.post(
        "/scientific-text/rules/preview",
        json={"kind": "unit", "input": "counts/s", "output": "cps", "enabled": True},
    )
    assert preview.status_code == 200, preview.text
    preview_payload = preview.json()
    assert preview_payload["rule"]["id"] == "unit/counts_s"
    assert preview_payload["effective_output"] == "cps"
    assert preview_payload["automatic_output"] == r"counts$\cdot$s$^{-1}$"
    assert preview_payload["errors"] == []

    created = client.post(
        "/scientific-text/rules",
        json={"kind": "unit", "input": "counts/s", "output": "cps", "enabled": True},
    )
    assert created.status_code == 200, created.text
    assert normalize_unit("counts/s") == "cps"

    listed = client.get("/scientific-text/rules")
    assert listed.status_code == 200, listed.text
    assert [item["id"] for item in listed.json()["rules"]] == ["unit/counts_s"]

    updated = client.put(
        "/scientific-text/rules/unit/counts_s",
        json={"kind": "unit", "input": "counts/s", "output": "count s^-1", "enabled": True},
    )
    assert updated.status_code == 200, updated.text
    assert normalize_unit("counts/s") == "count s^-1"

    invalid = client.post(
        "/scientific-text/rules/preview",
        json={"kind": "unit", "input": "counts/s", "output": "", "enabled": True},
    )
    assert invalid.status_code == 200, invalid.text
    assert invalid.json()["errors"] == ["Output cannot be empty."]

    deleted = client.delete("/scientific-text/rules/unit/counts_s")
    assert deleted.status_code == 200, deleted.text
    assert client.get("/scientific-text/rules").json()["rules"] == []
