from __future__ import annotations

from pathlib import Path

from fastapi.testclient import TestClient

from app.sidecar.schemas import MetaResponse
from app.sidecar.server import app

ROOT = Path(__file__).resolve().parents[1]
ENGINEERING_HANDOFF = ROOT / "docs" / "engineering-handoff.md"
TECHNICAL_BORROWING = ROOT / "docs" / "labplot-technical-borrowing.md"
ROADMAP_FILES = (
    ROOT / "docs" / "labplot-informed-roadmap.md",
    ROOT / "docs" / "labplot-roadmap-progress.md",
)

client = TestClient(app)


def test_labplot_scale_catalogs_are_runtime_or_explicitly_disabled() -> None:
    response = client.get("/meta")

    assert response.status_code == 200, response.text
    meta = MetaResponse.model_validate(response.json())
    unsupported_statuses = {
        item.id: item.status
        for group in meta.capability_catalogs
        for item in group.capabilities
        if item.status not in {"enabled", "disabled"}
    }
    assert unsupported_statuses == {}
    assert all(item.help for group in meta.capability_catalogs for item in group.capabilities)
    assert all(item.test_requirements for group in meta.capability_catalogs for item in group.capabilities)


def test_labplot_scale_roadmap_is_retired_into_development_docs() -> None:
    handoff = ENGINEERING_HANDOFF.read_text(encoding="utf-8")
    borrowing = TECHNICAL_BORROWING.read_text(encoding="utf-8")

    for roadmap_file in ROADMAP_FILES:
        assert not roadmap_file.exists(), f"{roadmap_file.name} should be retired after implementation."

    required_handoff_phrases = (
        "LabPlot-scale runtime is product surface, not roadmap",
        "Clean-room policy",
        "Capability status policy",
        "Runtime surfaces",
        "SciPlotDocumentGraph",
        "Data containers",
        "Analysis operations",
        "Import and export runtime",
        "Plot object commands and UndoManager",
        "Code Console notebook bridge",
        "Testing policy",
    )
    for phrase in required_handoff_phrases:
        assert phrase in handoff

    assert "No LabPlot C++ implementation is vendored" in borrowing
    assert "operation result envelope" in borrowing
