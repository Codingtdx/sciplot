from __future__ import annotations

from pathlib import Path
from uuid import uuid4

from fastapi.testclient import TestClient

from app.sidecar.schemas import MetaResponse, PlotContractResponse, StatusResponse
from app.sidecar.server import app

client = TestClient(app)
ROOT = Path(__file__).resolve().parents[1]
FIXTURE_DIR = ROOT / "tests" / "fixtures" / "tensile_raw"
EXPECTED_STYLE_IDS = {
    "nature",
    "acs",
    "science",
    "wiley",
    "elsevier",
}
EXPECTED_FIGURE_SIZE_IDS = {
    "60x55",
    "120x55",
    "180x55",
    "60x110",
    "120x110",
    "180x110",
}


def test_meta_and_plot_contract_responses_match_explicit_models() -> None:
    meta_response = client.get("/meta")
    assert meta_response.status_code == 200, meta_response.text
    meta = MetaResponse.model_validate(meta_response.json())
    removed_template_ids = {
        "grouped_bar_error",
        "scatter_with_fit",
        "replicate_curves_with_band",
        "grouped_bar_compare",
        "distribution_compare",
    }
    assert meta.template_ids
    assert meta.visual_themes
    assert {item.id for item in meta.sizes} == EXPECTED_FIGURE_SIZE_IDS
    assert {item.id for item in meta.styles} == EXPECTED_STYLE_IDS
    assert {item.id for item in meta.styles if item.display_group == "publication"} == {
        "nature",
        "acs",
        "science",
        "wiley",
        "elsevier",
    }
    assert {item.id for item in meta.styles if item.display_group == "legacy_display"} == set()
    assert meta.styles[0].recommended_palette_preset
    assert any(item.recommended_visual_theme_id == "clean_light" for item in meta.styles if item.id == "nature")
    assert {
        "infographic",
        "roma",
        "macarons",
        "shine",
        "vintage",
        "tableau_10",
        "seaborn_pastel",
        "seaborn_dark",
        "primer_accessible",
        "viridis_discrete",
    }.issubset({item.id for item in meta.palettes})
    assert {"infographic", "roma", "macarons", "shine", "vintage"}.issubset({item.id for item in meta.visual_themes})
    assert removed_template_ids.isdisjoint(meta.template_ids)
    assert removed_template_ids.isdisjoint({item.id for item in meta.templates})
    assert "nature" in {item.default_options.get("style_preset") for item in meta.templates}
    assert {"area_curve", "step_line", "stacked_area", "density_area"}.issubset({item.id for item in meta.templates})
    assert all(item.default_options.get("palette_preset") for item in meta.templates)
    assert all(item.default_options.get("visual_theme_id") for item in meta.templates)
    assert all(item.presentation_kind for item in meta.templates)

    contract_response = client.get("/plot-contract")
    assert contract_response.status_code == 200, contract_response.text
    contract = PlotContractResponse.model_validate(contract_response.json())
    assert contract.templates
    assert set(contract.size_presets.keys()) == EXPECTED_FIGURE_SIZE_IDS
    assert set(contract.styles.keys()) == EXPECTED_STYLE_IDS
    assert removed_template_ids.isdisjoint(contract.templates)
    assert {"area_curve", "step_line", "stacked_area", "density_area"}.issubset(contract.templates)
    assert contract.aliases["style_presets"]["default"] == "nature"
    assert contract.aliases["style_presets"]["jacs"] == "acs"
    assert contract.aliases["style_presets"]["aaas"] == "science"
    assert contract.aliases["style_presets"]["advanced_materials"] == "wiley"
    assert contract.aliases["style_presets"]["editorial"] == "nature"
    assert contract.aliases["style_presets"]["presentation"] == "nature"
    assert contract.aliases["style_presets"]["poster"] == "nature"
    assert all(template["presentation_kind"] for template in contract.templates.values())


def test_delete_data_studio_template_returns_status_response() -> None:
    template_id = f"user/schema-delete-{uuid4().hex[:8]}"
    create_response = client.post(
        "/data-studio/templates",
        json={
            "label": "Schema Delete Test",
            "template_id": template_id,
            "output_kind": "curve_metrics",
            "comparison_enabled": False,
            "source_format": {"encoding": "utf-8", "delimiter": ","},
            "segment_policy": "single_table",
            "segment_selectors": [
                {
                    "id": "result-table-2",
                    "label": "Result Table 2",
                    "header_row_index": 6,
                    "unit_row_index": 7,
                    "data_start_row_index": 8,
                },
            ],
            "field_bindings": [
                {
                    "id": "strain",
                    "role": "curve_x",
                    "label": "Tensile Strain",
                    "column_name": "Tensile Strain (Displacement)",
                    "unit_hint": "%",
                },
                {
                    "id": "stress",
                    "role": "curve_y",
                    "label": "Tensile Stress",
                    "column_name": "Tensile Stress",
                    "unit_hint": "MPa",
                },
            ],
        },
    )
    assert create_response.status_code == 200, create_response.text

    delete_response = client.delete(f"/data-studio/templates/{template_id}")
    assert delete_response.status_code == 200, delete_response.text
    payload = StatusResponse.model_validate(delete_response.json())
    assert payload.status == "ok"
