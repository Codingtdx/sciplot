from __future__ import annotations

from pathlib import Path

import pandas as pd
from fastapi.testclient import TestClient

from app.sidecar.server import app
from src.data_loader import load_curve_table
from src.data_studio.builtin import tensile as tensile_builtin

client = TestClient(app)

ROOT = Path(__file__).resolve().parents[1]
FIXTURE_DIR = ROOT / "tests" / "fixtures" / "tensile_raw"


def _build_workbook(tmp_path: Path, name: str) -> Path:
    output_path = tmp_path / f"{name}.xlsx"
    response = client.post(
        "/data-studio/build-workbook",
        json={
            "file_paths": [
                str(FIXTURE_DIR / "BlendSet_A.csv"),
                str(FIXTURE_DIR / "BlendSet_B.csv"),
                str(FIXTURE_DIR / "BlendSet_bad.csv"),
            ],
            "output_path": str(output_path),
            "template_id": "builtin/tensile",
            "group_name": name,
        },
    )
    assert response.status_code == 200, response.text
    assert output_path.exists()
    return output_path


def _rewrite_metadata_sheet(workbook_path: Path, rows: list[list[object]]) -> None:
    with pd.ExcelFile(workbook_path) as workbook:
        sheets = {
            sheet_name: pd.read_excel(workbook_path, sheet_name=sheet_name, header=None)
            for sheet_name in workbook.sheet_names
        }
    sheets["DataStudio_Metadata"] = pd.DataFrame(rows)
    with pd.ExcelWriter(workbook_path) as writer:
        for sheet_name, dataframe in sheets.items():
            dataframe.to_excel(writer, sheet_name=sheet_name, header=False, index=False)


def _curve_dataframe(*, scale: int) -> pd.DataFrame:
    return pd.DataFrame(
        {
            "x": [0.0, 5.0, 10.0, 15.0],
            "y": [0.0, 1.0 * scale, 2.0 * scale, 2.6 * scale],
        }
    )


def _write_specimen_filter_workbook(path: Path, *, label: str = "Sidecar Filter") -> Path:
    specimen_rows = [
        ("sample_1.csv", 80.0, 30.0, 5.0),
        ("sample_2.csv", 98.0, 48.0, 9.8),
        ("sample_3.csv", 99.0, 49.0, 9.9),
        ("sample_4.csv", 100.0, 50.0, 10.0),
        ("sample_5.csv", 101.0, 51.0, 10.1),
        ("sample_6.csv", 102.0, 52.0, 10.2),
        ("sample_7.csv", 120.0, 70.0, 15.0),
    ]
    summary_df = pd.DataFrame(
        [
            {
                "Filename": filename,
                "Strength (MPa)": strength,
                "Modulus (MPa)": modulus,
                "Elongation (%)": elongation,
            }
            for filename, strength, modulus, elongation in specimen_rows
        ]
    )
    representative_index = tensile_builtin._representative_index(summary_df)
    representative_filename = specimen_rows[representative_index][0]
    representative_curve = next(
        _curve_dataframe(scale=index + 1)
        for index, (filename, *_rest) in enumerate(specimen_rows)
        if filename == representative_filename
    )
    metrics = tensile_builtin._metric_summaries(summary_df)

    with pd.ExcelWriter(path) as writer:
        tensile_builtin._curve_table_dataframe(
            ((f"{label} representative", representative_curve),)
        ).to_excel(writer, sheet_name=tensile_builtin.REPRESENTATIVE_CURVE_SHEET, header=False, index=False)
        tensile_builtin._curve_table_dataframe(
            (Path(filename).stem, _curve_dataframe(scale=index + 1))
            for index, (filename, *_rest) in enumerate(specimen_rows)
        ).to_excel(writer, sheet_name=tensile_builtin.ALL_CURVES_SHEET, header=False, index=False)
        tensile_builtin._summary_sheet_dataframe(
            summary_df,
            representative_filename,
            metrics,
        ).to_excel(writer, sheet_name=tensile_builtin.SUMMARY_SHEET, header=False, index=False)
        tensile_builtin._plain_table_dataframe(summary_df).to_excel(
            writer,
            sheet_name=tensile_builtin.ALL_SPECIMENS_SHEET,
            header=False,
            index=False,
        )
        for metric in metrics:
            tensile_builtin._replicate_table_dataframe(
                group_name=label,
                value_label=metric.label,
                value_unit=metric.unit,
                values=summary_df[f"{metric.label} ({metric.unit})"].dropna().tolist(),
            ).to_excel(writer, sheet_name=f"{metric.label}_Replicates", header=False, index=False)
        tensile_builtin._metadata_sheet_dataframe(
            label=label,
            source_files=[path.with_name(filename) for filename, *_rest in specimen_rows],
            warnings=[],
            template_id=tensile_builtin.TENSILE_TEMPLATE_ID,
        ).to_excel(writer, sheet_name=tensile_builtin.METADATA_SHEET, header=False, index=False)
    return path


def test_data_studio_template_routes_and_template_preview_stay_live(tmp_path: Path) -> None:
    templates = client.get("/data-studio/templates")
    assert templates.status_code == 200
    template_payload = templates.json()
    assert any(item["id"] == "builtin/tensile" for item in template_payload["templates"])

    source_preview = client.post(
        "/source-table-preview",
        json={
            "input_path": str(FIXTURE_DIR / "BlendSet_A.csv"),
            "sheet": 0,
            "offset": 0,
            "limit": 8,
            "header_row": 6,
            "unit_row": 7,
            "data_start_row": 8,
        },
    )
    assert source_preview.status_code == 200, source_preview.text
    payload = source_preview.json()
    assert payload["encoding"] is not None
    assert payload["candidate_roles"]["x"]
    assert payload["candidate_roles"]["y"]

    template_preview = client.post(
        "/data-studio/template-preview",
        json={
            "source_path": str(FIXTURE_DIR / "BlendSet_A.csv"),
            "template": {
                "label": "Draft Tensile Curve",
                "template_id": "user/draft_tensile_curve",
                "description": "",
                "output_kind": "curve_metrics",
                "source_format": {"encoding": "utf-8", "delimiter": ","},
                "segment_policy": "single_table",
                "segment_selectors": [
                    {
                        "id": "Sheet1::table",
                        "label": "Result Table 2",
                        "start_row": 5,
                        "header_row": 6,
                        "unit_row": 7,
                        "data_start_row": 8,
                    }
                ],
                "field_bindings": [
                    {
                        "id": "strain",
                        "role": "curve_x",
                        "label": "Strain",
                        "column_name": "Tensile Strain",
                    },
                    {
                        "id": "stress",
                        "role": "curve_y",
                        "label": "Stress",
                        "column_name": "Tensile Stress",
                    },
                ],
            },
        },
    )
    assert template_preview.status_code == 200, template_preview.text
    assert template_preview.json()["series_count"] >= 1

    normalize = client.post(
        "/data-studio/session/normalize",
        json={
            "payload": {
                "selected_template_id": "builtin/tensile",
                "workbook_paths": [str(tmp_path / "a.xlsx")],
                "selected_recipe_id": "strength_grouped_bar_error",
                "comparison_recipe_ids": ["representative_curve", "strength_grouped_bar_compare"],
                "selected_figure_template_id": "grouped_bar_error",
                "imported_paths": [str(FIXTURE_DIR / "BlendSet_A.csv")],
            }
        },
    )
    assert normalize.status_code == 200, normalize.text
    assert normalize.json()["selected_template_id"] == "builtin/tensile"
    assert normalize.json()["selected_recipe_id"] == "strength_bar"
    assert normalize.json()["comparison_recipe_ids"] == ["representative_curve", "strength_bar"]
    assert normalize.json()["selected_figure_template_id"] == "bar"


def test_data_studio_workbook_import_preview_and_export_routes_work_end_to_end(tmp_path: Path) -> None:
    left = _build_workbook(tmp_path, "Left Group")
    right = _build_workbook(tmp_path, "Right Group")

    imported = client.post("/data-studio/import-workbook", json={"workbook_path": str(left)})
    assert imported.status_code == 200, imported.text
    imported_payload = imported.json()
    assert len(imported_payload["workbooks"]) == 1
    assert imported_payload["workbooks"][0]["label"] == "Left Group"

    preview = client.post(
        "/data-studio/comparison-preview",
        json={
            "workbook_paths": [str(left), str(right)],
            "recipe_id": "representative_curve",
            "group_states": [
                {
                    "workbook_path": str(right),
                    "display_name": "Right",
                    "include_in_compare": True,
                    "sort_order": 0,
                },
                {
                    "workbook_path": str(left),
                    "display_name": "Left",
                    "include_in_compare": True,
                    "sort_order": 1,
                },
            ],
        },
    )
    assert preview.status_code == 200, preview.text
    preview_payload = preview.json()
    assert preview_payload["recipe"]["id"] == "representative_curve"
    assert preview_payload["preview"]["pdf_base64"]

    export_dir = tmp_path / "exports"
    exported = client.post(
        "/data-studio/comparison-export",
        json={
            "workbook_paths": [str(left), str(right)],
            "output_dir": str(export_dir),
            "group_states": [
                {
                    "workbook_path": str(right),
                    "display_name": "Right",
                    "include_in_compare": True,
                    "sort_order": 0,
                },
                {
                    "workbook_path": str(left),
                    "display_name": "Left",
                    "include_in_compare": True,
                    "sort_order": 1,
                },
            ],
            "selected_recipe_ids": ["representative_curve", "strength_box"],
            "figure_options_by_recipe_id": {
                "representative_curve": {
                    "style_preset": "default",
                    "palette_preset": "colorblind_safe",
                    "size": "single_panel",
                }
            },
        },
    )
    assert exported.status_code == 200, exported.text
    exported_payload = exported.json()
    assert exported_payload["comparison_set"]["comparison_workbook_path"]
    assert exported_payload["comparison_set"]["workbook_labels"] == ["Right", "Left"]
    assert {item["recipe_id"] for item in exported_payload["figure_outputs"]} == {
        "representative_curve",
        "strength_box",
    }
    assert [item["label"] for item in exported_payload["filtered_workbooks"]] == ["Right", "Left"]
    assert all(Path(item["path"]).exists() for item in exported_payload["filtered_workbooks"])

    reimported = client.post(
        "/data-studio/import-workbook",
        json={"workbook_path": exported_payload["comparison_set"]["comparison_workbook_path"]},
    )
    assert reimported.status_code == 200, reimported.text
    reimported_payload = reimported.json()
    assert [item["label"] for item in reimported_payload["workbooks"]] == ["Right Group", "Left Group"]


def test_data_studio_comparison_export_route_returns_filtered_workbooks_with_four_decimal_curves(
    tmp_path: Path,
) -> None:
    workbook_path = _write_specimen_filter_workbook(tmp_path / "sidecar_filtered_export.xlsx")
    preview = client.post(
        "/data-studio/workbook-preview",
        json={"workbook_path": str(workbook_path)},
    )
    assert preview.status_code == 200, preview.text
    preview_payload = preview.json()
    specimen_ids_by_filename = {
        specimen["filename"]: specimen["specimen_id"]
        for specimen in preview_payload["specimens"]
    }
    specimen_states = [
        {
            "workbook_path": str(workbook_path),
            "specimen_id": specimen_id,
            "included": False,
        }
        for specimen_id in preview_payload["suggested_exclusion_ids"]
    ]
    specimen_states.append(
        {
            "workbook_path": str(workbook_path),
            "specimen_id": specimen_ids_by_filename["sample_2.csv"],
            "included": True,
            "selected_as_representative": True,
        }
    )

    exported = client.post(
        "/data-studio/comparison-export",
        json={
            "workbook_paths": [str(workbook_path)],
            "output_dir": str(tmp_path / "filtered_route_exports"),
            "specimen_states": specimen_states,
            "selected_recipe_ids": ["representative_curve"],
        },
    )
    assert exported.status_code == 200, exported.text
    exported_payload = exported.json()
    assert len(exported_payload["filtered_workbooks"]) == 1

    filtered_workbook_path = Path(exported_payload["filtered_workbooks"][0]["path"])
    assert filtered_workbook_path.exists()
    specimen_sheet = pd.read_excel(
        filtered_workbook_path,
        sheet_name=tensile_builtin.ALL_SPECIMENS_SHEET,
        header=None,
        dtype=str,
    ).fillna("")
    assert specimen_sheet.iloc[1:, 0].tolist() == [
        "sample_2.csv",
        "sample_3.csv",
        "sample_4.csv",
        "sample_5.csv",
        "sample_6.csv",
    ]
    assert specimen_sheet.iloc[1, 1] == "98.00"

    summary_sheet = pd.read_excel(
        filtered_workbook_path,
        sheet_name=tensile_builtin.SUMMARY_SHEET,
        header=None,
        dtype=str,
    ).fillna("")
    assert summary_sheet.iloc[1, 2] == "100.00"
    assert summary_sheet.iloc[1, 3] == "1.58"
    assert summary_sheet.iloc[1, 4] == "sample_2.csv"

    representative_curve_sheet = pd.read_excel(
        filtered_workbook_path,
        sheet_name=tensile_builtin.REPRESENTATIVE_CURVE_SHEET,
        header=None,
        dtype=str,
    ).fillna("")
    assert representative_curve_sheet.iloc[3, 0] == "0.0000"
    assert representative_curve_sheet.iloc[4, 1] == "2.0000"


def test_data_studio_import_workbook_route_recovers_groups_when_comparison_metadata_is_missing(tmp_path: Path) -> None:
    left = _build_workbook(tmp_path, "Route Left")
    right = _build_workbook(tmp_path, "Route Right")

    preview = client.post(
        "/data-studio/comparison-preview",
        json={
            "workbook_paths": [str(left), str(right)],
            "recipe_id": "representative_curve",
        },
    )
    assert preview.status_code == 200, preview.text
    comparison_workbook_path = Path(preview.json()["comparison_set"]["comparison_workbook_path"])
    _rewrite_metadata_sheet(comparison_workbook_path, [["label", "Route Compare"]])

    reimported = client.post(
        "/data-studio/import-workbook",
        json={"workbook_path": str(comparison_workbook_path)},
    )

    assert reimported.status_code == 200, reimported.text
    payload = reimported.json()
    assert [item["label"] for item in payload["workbooks"]] == ["Route Left", "Route Right"]


def test_data_studio_workbook_preview_and_comparison_routes_apply_specimen_filters(tmp_path: Path) -> None:
    workbook_path = _write_specimen_filter_workbook(tmp_path / "route_specimen_filter.xlsx")

    preview = client.post(
        "/data-studio/workbook-preview",
        json={"workbook_path": str(workbook_path)},
    )
    assert preview.status_code == 200, preview.text
    preview_payload = preview.json()
    assert preview_payload["supported"] is True
    assert preview_payload["included_specimen_count"] == 7
    assert sorted(preview_payload["suggested_exclusion_ids"]) == sorted(
        [
            specimen["specimen_id"]
            for specimen in preview_payload["specimens"]
            if specimen["filename"] in {"sample_1.csv", "sample_7.csv"}
        ]
    )
    auto_roles = {specimen["filename"]: specimen["auto_rule_role"] for specimen in preview_payload["specimens"]}
    assert auto_roles["sample_1.csv"] == "exclude"
    assert auto_roles["sample_7.csv"] == "exclude"
    assert auto_roles["sample_4.csv"] == "keep"
    assert preview_payload["specimens"][0]["score_side"] in {"low", "high", "neutral", "ineligible"}
    assert "distance_from_mean_score" in preview_payload["specimens"][0]

    specimen_states = [
        {
            "workbook_path": str(workbook_path),
            "specimen_id": specimen_id,
            "included": False,
        }
        for specimen_id in preview_payload["suggested_exclusion_ids"]
    ]
    filtered_preview = client.post(
        "/data-studio/workbook-preview",
        json={
            "workbook_path": str(workbook_path),
            "specimen_states": specimen_states,
        },
    )
    assert filtered_preview.status_code == 200, filtered_preview.text
    filtered_payload = filtered_preview.json()
    assert filtered_payload["included_specimen_count"] == 5
    assert filtered_payload["representative_filename"] == "sample_4.csv"

    comparison_context = client.post(
        "/data-studio/comparison-context",
        json={
            "workbook_paths": [str(workbook_path)],
            "specimen_states": specimen_states,
        },
    )
    assert comparison_context.status_code == 200, comparison_context.text
    comparison_context_payload = comparison_context.json()
    assert comparison_context_payload["cache_key"]
    assert comparison_context_payload["materialized_at"]
    comparison_workbook_path = Path(comparison_context_payload["comparison_set"]["comparison_workbook_path"])
    assert comparison_workbook_path.exists()

    repeated_context = client.post(
        "/data-studio/comparison-context",
        json={
            "workbook_paths": [str(workbook_path)],
            "specimen_states": specimen_states,
        },
    )
    assert repeated_context.status_code == 200, repeated_context.text
    repeated_payload = repeated_context.json()
    assert repeated_payload["cache_key"] == comparison_context_payload["cache_key"]
    assert repeated_payload["comparison_set"]["comparison_workbook_path"] == str(comparison_workbook_path)

    comparison = client.post(
        "/data-studio/comparison-preview",
        json={
            "workbook_paths": [str(workbook_path)],
            "recipe_id": "strength_box",
            "specimen_states": specimen_states,
        },
    )
    assert comparison.status_code == 200, comparison.text
    comparison_payload = comparison.json()
    preview_workbook_path = Path(comparison_payload["comparison_set"]["comparison_workbook_path"])
    with pd.ExcelFile(preview_workbook_path) as workbook:
        strength = pd.read_excel(preview_workbook_path, sheet_name="Strength_Replicates", header=None)
    assert workbook.sheet_names
    numeric_values = pd.to_numeric(strength.iloc[3:, 0], errors="coerce").dropna().tolist()
    assert numeric_values == [98.0, 99.0, 100.0, 101.0, 102.0]


def test_data_studio_routes_apply_manual_representative_selection(tmp_path: Path) -> None:
    workbook_path = _write_specimen_filter_workbook(tmp_path / "route_manual_rep.xlsx")

    preview = client.post(
        "/data-studio/workbook-preview",
        json={"workbook_path": str(workbook_path)},
    )
    assert preview.status_code == 200, preview.text
    preview_payload = preview.json()
    specimen_id_by_filename = {
        specimen["filename"]: specimen["specimen_id"]
        for specimen in preview_payload["specimens"]
    }

    specimen_states = [
        {
            "workbook_path": str(workbook_path),
            "specimen_id": specimen_id,
            "included": False,
        }
        for specimen_id in preview_payload["suggested_exclusion_ids"]
    ]
    specimen_states.append(
        {
            "workbook_path": str(workbook_path),
            "specimen_id": specimen_id_by_filename["sample_2.csv"],
            "included": True,
            "selected_as_representative": True,
        }
    )

    filtered_preview = client.post(
        "/data-studio/workbook-preview",
        json={
            "workbook_path": str(workbook_path),
            "specimen_states": specimen_states,
        },
    )
    assert filtered_preview.status_code == 200, filtered_preview.text
    filtered_payload = filtered_preview.json()
    assert filtered_payload["representative_specimen_id"] == specimen_id_by_filename["sample_2.csv"]
    assert filtered_payload["representative_filename"] == "sample_2.csv"

    comparison_context = client.post(
        "/data-studio/comparison-context",
        json={
            "workbook_paths": [str(workbook_path)],
            "specimen_states": specimen_states,
        },
    )
    assert comparison_context.status_code == 200, comparison_context.text
    comparison_workbook_path = Path(comparison_context.json()["comparison_set"]["comparison_workbook_path"])
    representative_curves = load_curve_table(
        comparison_workbook_path,
        sheet_name=tensile_builtin.REPRESENTATIVE_CURVE_SHEET,
    )
    assert len(representative_curves) == 1
    assert representative_curves[0].data["y"].tolist() == [0.0, 2.0, 4.0, 5.2]
