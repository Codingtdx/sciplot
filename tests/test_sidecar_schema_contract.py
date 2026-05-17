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
    catalog_groups = {group.id: group for group in meta.capability_catalogs}
    assert {
        "data_containers",
        "plot_objects",
        "analysis_operations",
        "import_filters",
        "export_targets",
        "project_bundle_features",
        "native_preview_features",
    }.issubset(catalog_groups)
    assert any(
        item.id == "plot.axis" and item.status == "enabled"
        for item in catalog_groups["plot_objects"].capabilities
    )
    assert any(
        item.id == "analysis.smoothing" and item.status == "coming_soon"
        for item in catalog_groups["analysis_operations"].capabilities
    )
    assert all(item.help for group in catalog_groups.values() for item in group.capabilities)

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


def test_labplot_scale_catalogs_cover_one_run_capabilities() -> None:
    response = client.get("/meta")

    assert response.status_code == 200, response.text
    meta = MetaResponse.model_validate(response.json())
    groups = {group.id: {item.id: item for item in group.capabilities} for group in meta.capability_catalogs}

    assert {
        "data.table",
        "data.matrix",
        "data.transformed_view",
        "data.statistics_summary",
        "data.fit_result",
        "data.notebook_output",
    }.issubset(groups["data_containers"])
    assert {
        "plot.series",
        "plot.axis",
        "plot.legend",
        "plot.guide",
        "plot.annotation.text",
        "plot.annotation.shape",
        "plot.layer.function",
        "plot.axis.extra",
        "plot.axis.break",
        "plot.fit_overlay",
        "plot.page",
        "plot.plot_area",
    }.issubset(groups["plot_objects"])
    assert {
        "analysis.fit",
        "analysis.smoothing",
        "analysis.interpolation",
        "analysis.differentiation",
        "analysis.integration",
        "analysis.fft",
        "analysis.fourier_filter",
        "analysis.correlation",
        "analysis.convolution",
        "analysis.baseline",
        "analysis.peak_detection",
        "analysis.kde",
        "analysis.statistical_tests",
        "analysis.distribution_fitting",
        "analysis.peak_fitting",
        "analysis.growth_models",
    }.issubset(groups["analysis_operations"])
    assert {
        "import.csv",
        "import.excel",
        "import.json",
        "import.sql",
        "import.hdf5",
        "import.netcdf",
        "import.fits",
        "import.ods",
        "import.readstat",
        "import.binary_raw",
        "import.origin_scidavis_eval",
        "import.image_digitizer",
    }.issubset(groups["import_filters"])
    assert {
        "export.figure.pdf",
        "export.figure.tiff",
        "export.data_workbook",
        "export.project_bundle",
        "export.comparison_bundle",
        "export.artifact_manifest",
        "export.code_console_figure_set",
    }.issubset(groups["export_targets"])
    assert groups["analysis_operations"]["analysis.fft"].status in {"experimental", "coming_soon"}
    assert groups["import_filters"]["import.image_digitizer"].status == "coming_soon"


def test_labplot_scale_payload_models_validate_code_landings() -> None:
    from app.sidecar.schemas import (
        AnalysisOperationResultPayload,
        DataContainerPayload,
        ExportTargetPayload,
        ImportFilterPayload,
        NotebookOutputPayload,
        PlotEditCommandPayload,
        PlotObjectPayload,
    )

    matrix = DataContainerPayload.model_validate(
        {
            "id": "matrix-1",
            "kind": "matrix",
            "label": "Scalar Field",
            "status": "experimental",
            "readonly": True,
            "row_count": 4,
            "column_count": 3,
            "source": {"input_path": "/tmp/field.csv", "sheet": "Sheet1", "offset": 0, "limit": 50},
            "dimensions": {"rows": 2, "columns": 2},
            "coordinate_vectors": {"x": [25.0, 40.0], "y": [0.0, 5.0]},
            "missing_value_policy": "preserve",
            "help": "Matrix container landing.",
        }
    )
    assert matrix.kind == "matrix"

    plot_object = PlotObjectPayload.model_validate(
        {
            "id": "plot:guide:target-line",
            "kind": "plot.guide",
            "module": "plot",
            "label": "Target",
            "graph_node_id": "plot:guide:target-line",
            "payload": {"axis_target": "y_primary"},
        }
    )
    assert plot_object.visible is True

    command = PlotEditCommandPayload.model_validate(
        {
            "command_id": "cmd-1",
            "kind": "edit",
            "target_object_id": plot_object.id,
            "after": {"visible": False},
        }
    )
    assert command.reversible is True

    result = AnalysisOperationResultPayload.model_validate(
        {
            "operation_id": "analysis.fit",
            "available": True,
            "valid": True,
            "status_code": "ok",
            "message": "Fit complete.",
            "metrics": {"r_squared": 0.99},
        }
    )
    assert result.metrics["r_squared"] == 0.99

    import_filter = ImportFilterPayload.model_validate(
        {
            "id": "import.hdf5",
            "label": "HDF5",
            "status": "coming_soon",
            "output_container_kinds": ["matrix"],
            "help": "Explicit import filter landing.",
        }
    )
    export_target = ExportTargetPayload.model_validate(
        {
            "id": "export.artifact_manifest",
            "label": "Artifact Manifest",
            "status": "coming_soon",
            "allowed_modules": ["plot", "data_studio", "composer", "code_console"],
            "artifact_kind": "manifest",
            "filename_policy": "base_name_with_suffixes",
            "help": "Explicit export target landing.",
        }
    )
    notebook_output = NotebookOutputPayload.model_validate(
        {
            "id": "notebook-output-1",
            "kind": "figure",
            "label": "Generated Figure",
            "status": "experimental",
            "source_run_id": "run-1",
            "container_ids": ["data.notebook_output:run-1"],
        }
    )
    assert import_filter.status == export_target.status == "coming_soon"
    assert notebook_output.kind == "figure"


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
