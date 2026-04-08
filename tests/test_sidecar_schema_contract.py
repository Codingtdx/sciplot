from __future__ import annotations

from pathlib import Path
from uuid import uuid4

from fastapi.testclient import TestClient

from app.sidecar.schemas import MetaResponse, PlotContractResponse, StatusResponse
from app.sidecar.server import app

client = TestClient(app)
ROOT = Path(__file__).resolve().parents[1]
FIXTURE_DIR = ROOT / "tests" / "fixtures" / "tensile_raw"


def test_meta_and_plot_contract_responses_match_explicit_models() -> None:
    meta_response = client.get("/meta")
    assert meta_response.status_code == 200, meta_response.text
    meta = MetaResponse.model_validate(meta_response.json())
    assert meta.template_ids
    assert meta.visual_themes

    contract_response = client.get("/plot-contract")
    assert contract_response.status_code == 200, contract_response.text
    contract = PlotContractResponse.model_validate(contract_response.json())
    assert contract.templates
    assert contract.size_presets


def test_delete_data_studio_template_returns_status_response() -> None:
    template_id = f"user/schema-delete-{uuid4().hex[:8]}"
    create_response = client.post(
        "/data-studio/templates",
        json={
            "source_path": str(FIXTURE_DIR / "BlendSet_A.csv"),
            "label": "Schema Delete Test",
            "template_id": template_id,
        },
    )
    assert create_response.status_code == 200, create_response.text

    delete_response = client.delete(f"/data-studio/templates/{template_id}")
    assert delete_response.status_code == 200, delete_response.text
    payload = StatusResponse.model_validate(delete_response.json())
    assert payload.status == "ok"
