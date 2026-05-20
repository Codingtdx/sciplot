from __future__ import annotations

import re
from base64 import b64decode
from io import BytesIO
from pathlib import Path

import fitz
from fastapi.testclient import TestClient
from PIL import Image

from app.sidecar.server import app

client = TestClient(app)


def _write_pdf_with_text(path: Path, width_mm: float, height_mm: float, text: str) -> Path:
    document = fitz.open()
    page = document.new_page(width=width_mm / 25.4 * 72.0, height=height_mm / 25.4 * 72.0)
    page.insert_text((24, 40), text, fontsize=12)
    document.save(path)
    document.close()
    return path


def _write_png(path: Path, color: tuple[int, int, int]) -> Path:
    Image.new("RGB", (48, 24), color).save(path)
    return path


def _image_from_png_bytes(png_bytes: bytes) -> Image.Image:
    return Image.open(BytesIO(png_bytes)).convert("RGB")


def _render_pdf_page_image(path: Path, *, dpi: int = 144) -> Image.Image:
    document = fitz.open(path)
    try:
        page = document.load_page(0)
        scale = dpi / 72.0
        pixmap = page.get_pixmap(matrix=fitz.Matrix(scale, scale), alpha=False)
        return Image.open(BytesIO(pixmap.tobytes("png"))).convert("RGB")
    finally:
        document.close()


def _sample_rgb_at_mm(image: Image.Image, x_mm: float, y_mm: float, *, dpi: int = 144) -> tuple[int, int, int]:
    x_px = int(round(x_mm / 25.4 * dpi))
    y_px = int(round(y_mm / 25.4 * dpi))
    x_px = max(0, min(image.width - 1, x_px))
    y_px = max(0, min(image.height - 1, y_px))
    return image.getpixel((x_px, y_px))


def _assert_rgb_close(actual: tuple[int, int, int], expected: tuple[int, int, int], tolerance: int = 16) -> None:
    assert all(abs(a - b) <= tolerance for a, b in zip(actual, expected, strict=True)), (
        f"Expected approximately {expected}, got {actual}"
    )


def _layer_name_by_oc_xref(document: fitz.Document) -> dict[int, str]:
    return {
        int(xref): str(payload["name"])
        for xref, payload in document.get_ocgs().items()
    }


def _object_oc_xref(document: fitz.Document, xref: int) -> int | None:
    match = re.search(r"/OC\s+(\d+)\s+0\s+R", document.xref_object(xref))
    return int(match.group(1)) if match else None


def _top_level_form_layer_names(document: fitz.Document, page: fitz.Page) -> list[str]:
    names_by_xref = _layer_name_by_oc_xref(document)
    layer_names: list[str] = []
    for xref, _name, parent_xref, _bbox in page.get_xobjects():
        if parent_xref != 0:
            continue
        oc_xref = _object_oc_xref(document, xref)
        if oc_xref is not None and oc_xref in names_by_xref:
            layer_names.append(names_by_xref[oc_xref])
    return layer_names


def _image_layer_names(document: fitz.Document, page: fitz.Page) -> list[str]:
    names_by_xref = _layer_name_by_oc_xref(document)
    layer_names: list[str] = []
    for image_xref, *_rest in page.get_images():
        oc_xref = _object_oc_xref(document, image_xref)
        if oc_xref is not None and oc_xref in names_by_xref:
            layer_names.append(names_by_xref[oc_xref])
    return layer_names


def _composer_asset_ref(
    *,
    asset_id: str,
    source_module: str = "code_console",
    source_graph_node_id: str = "code_console:notebook_output:1",
    kind: str = "figure",
    label: str = "Linked Figure",
    mime_type: str = "application/pdf",
    sha256: str = "fixture-sha",
    embedded_path: str = "artifacts/code_console/latest_run/linked.pdf",
    manifest_id: str = "artifact:linked",
) -> dict[str, object]:
    return {
        "asset_id": asset_id,
        "source_module": source_module,
        "source_graph_node_id": source_graph_node_id,
        "artifact_manifest_id": manifest_id,
        "label": label,
        "kind": kind,
        "mime_type": mime_type,
        "sha256": sha256,
        "embedded_path": embedded_path,
        "refresh_policy": "manual",
        "preflight_status": "ready",
    }


def _single_panel_project(
    panel_path: Path,
    *,
    kind: str = "asset",
    asset_ref: dict[str, object] | None = None,
) -> dict[str, object]:
    panel: dict[str, object] = {
        "id": "panel-linked",
        "file_path": str(panel_path),
        "page_index": 0,
        "x_mm": 0,
        "y_mm": 2.5,
        "w_mm": 60,
        "h_mm": 55,
        "kind": kind,
        "z_index": 0,
        "locked": False,
        "hidden": False,
        "label": None,
        "group_id": None,
        "region_id": None,
        "slot_id": None,
        "crop_rect": {"x": 0, "y": 0, "width": 1, "height": 1},
    }
    if asset_ref is not None:
        panel["asset_ref"] = asset_ref
    return {
        "version": 2,
        "mode": "composer",
        "canvas_width_mm": 180,
        "canvas_height_mm": 170,
        "grid_mm": 0.5,
        "layout_grid": {
            "columns": 3,
            "rows": 3,
            "cell_width_mm": 60,
            "cell_height_mm": 55,
            "frame_x_mm": 0,
            "frame_y_mm": 2.5,
            "frame_width_mm": 180,
            "frame_height_mm": 165,
        },
        "regions": [],
        "panels": [panel],
        "texts": [],
        "auto_labels": True,
    }


def test_composer_import_preserves_linked_asset_refs(tmp_path: Path) -> None:
    graph_path = _write_pdf_with_text(tmp_path / "linked-plot.pdf", 60.0, 55.0, "Linked Plot")
    asset_ref = _composer_asset_ref(
        asset_id="artifact:plot:latest",
        source_module="plot",
        source_graph_node_id="plot:scene:latest",
        label="Plot latest figure",
        embedded_path="artifacts/plot/latest.pdf",
        manifest_id="artifact:plot:latest",
    )

    response = client.post(
        "/composer/import-panels",
        json={
            "project": _single_panel_project(graph_path)["panels"] and {
                "version": 2,
                "mode": "composer",
                "canvas_width_mm": 180,
                "canvas_height_mm": 170,
                "grid_mm": 0.5,
                "layout_grid": {
                    "columns": 3,
                    "rows": 3,
                    "cell_width_mm": 60,
                    "cell_height_mm": 55,
                    "frame_x_mm": 0,
                    "frame_y_mm": 2.5,
                    "frame_width_mm": 180,
                    "frame_height_mm": 165,
                },
                "regions": [],
                "panels": [],
                "texts": [],
                "auto_labels": True,
            },
            "file_paths": [str(graph_path)],
            "kind": "graph",
            "asset_refs": [asset_ref],
        },
    )

    assert response.status_code == 200, response.text
    panel = response.json()["panels"][0]
    assert panel["asset_ref"]["asset_id"] == "artifact:plot:latest"
    assert panel["asset_ref"]["source_module"] == "plot"
    assert panel["asset_ref"]["source_graph_node_id"] == "plot:scene:latest"


def test_composer_preflight_reports_low_resolution_linked_asset_and_blocks_export(tmp_path: Path) -> None:
    low_res_path = tmp_path / "tiny.png"
    Image.new("RGB", (8, 8), (20, 160, 240)).save(low_res_path)
    project_payload = _single_panel_project(
        low_res_path,
        kind="asset",
        asset_ref=_composer_asset_ref(
            asset_id="artifact:code_console:tiny",
            label="Tiny notebook output",
            mime_type="image/png",
            embedded_path="artifacts/code_console/latest_run/tiny.png",
            manifest_id="artifact:code_console:tiny",
        ),
    )

    preview_response = client.post("/compose-preview", json=project_payload)

    assert preview_response.status_code == 200, preview_response.text
    preflight = preview_response.json()["export_preflight"]
    assert preflight["status"] == "blocked"
    assert "panel-linked" in preflight["blocking_panel_ids"]
    assert any(
        item["id"] == "low_resolution_raster" and item["severity"] == "critical"
        for item in preflight["diagnostics"]
    )

    export_response = client.post("/compose-export", json=project_payload)

    assert export_response.status_code == 400
    assert "low-resolution" in export_response.text.lower()


def test_compose_export_endpoint_preserves_pdf_and_raster_resources(tmp_path: Path) -> None:
    graph_path = _write_pdf_with_text(tmp_path / "graph.pdf", 60.0, 55.0, "Endpoint Graph")
    asset_pdf_path = _write_pdf_with_text(tmp_path / "asset.pdf", 60.0, 55.0, "Endpoint Asset")
    raster_path = _write_png(tmp_path / "asset.png", (14, 165, 233))

    response = client.post(
        "/compose-export",
        json={
            "version": 2,
            "mode": "composer",
            "canvas_width_mm": 180,
            "canvas_height_mm": 170,
            "grid_mm": 0.5,
            "layout_grid": {
                "columns": 3,
                "rows": 3,
                "cell_width_mm": 60,
                "cell_height_mm": 55,
                "frame_x_mm": 0,
                "frame_y_mm": 2.5,
                "frame_width_mm": 180,
                "frame_height_mm": 165,
            },
            "regions": [
                {
                    "id": "region-graph",
                    "kind": "graph",
                    "col": 0,
                    "row": 0,
                    "col_span": 1,
                    "row_span": 1,
                    "label": None,
                    "locked": False,
                    "slot_kind": None,
                }
            ],
            "panels": [
                {
                    "id": "panel-1",
                    "file_path": str(graph_path),
                    "page_index": 0,
                    "x_mm": 0,
                    "y_mm": 0,
                    "w_mm": 60,
                    "h_mm": 55,
                    "kind": "graph",
                    "z_index": 0,
                    "locked": False,
                    "hidden": False,
                    "group_id": None,
                    "region_id": "region-graph",
                    "slot_id": None,
                    "crop_rect": {"x": 0, "y": 0, "width": 1, "height": 1},
                },
                {
                    "id": "panel-2",
                    "file_path": str(asset_pdf_path),
                    "page_index": 0,
                    "x_mm": 70,
                    "y_mm": 0,
                    "w_mm": 60,
                    "h_mm": 55,
                    "kind": "asset",
                    "z_index": 1,
                    "locked": False,
                    "hidden": False,
                    "group_id": None,
                    "region_id": None,
                    "slot_id": None,
                    "crop_rect": {"x": 0, "y": 0, "width": 1, "height": 1},
                },
                {
                    "id": "panel-3",
                    "file_path": str(raster_path),
                    "page_index": 0,
                    "x_mm": 0,
                    "y_mm": 70,
                    "w_mm": 30,
                    "h_mm": 15,
                    "kind": "asset",
                    "z_index": 2,
                    "locked": False,
                    "hidden": False,
                    "group_id": None,
                    "region_id": None,
                    "slot_id": None,
                    "crop_rect": {"x": 0, "y": 0, "width": 1, "height": 1},
                },
            ],
            "texts": [
                {
                    "id": "text-1",
                    "text": "Endpoint Overlay",
                    "x_mm": 10,
                    "y_mm": 110,
                    "font_size_pt": 9,
                    "align": "left",
                    "z_index": 3,
                    "locked": False,
                    "hidden": False,
                    "group_id": None,
                    "region_id": None,
                    "slot_id": None,
                }
            ],
            "auto_labels": True,
        },
    )

    assert response.status_code == 200
    output_path = Path(response.json()["output_path"])
    assert output_path.exists()

    document = fitz.open(output_path)
    try:
        page = document.load_page(0)
        exported_text = page.get_text()
        layer_names = set(_layer_name_by_oc_xref(document).values())
        form_layer_names = set(_top_level_form_layer_names(document, page))
        image_layer_names = set(_image_layer_names(document, page))
    finally:
        document.close()

    assert layer_names == {
        "Graph/panel-1 [A]",
        "Asset/panel-2 asset.pdf",
        "Asset/panel-3 asset.png",
        "Text/text-1 Endpoint Overlay",
    }
    assert form_layer_names == {
        "Graph/panel-1 [A]",
        "Asset/panel-2 asset.pdf",
        "Text/text-1 Endpoint Overlay",
    }
    assert image_layer_names == {"Asset/panel-3 asset.png"}
    assert "Endpoint Graph" in exported_text
    assert "Endpoint Asset" in exported_text
    assert "Endpoint Overlay" in exported_text


def test_compose_preview_and_export_endpoints_match_overlap_z_order(tmp_path: Path) -> None:
    lower_path = _write_png(tmp_path / "lower.png", (230, 57, 70))
    upper_path = _write_png(tmp_path / "upper.png", (37, 99, 235))
    project_payload = {
        "version": 2,
        "mode": "composer",
        "canvas_width_mm": 180,
        "canvas_height_mm": 170,
        "grid_mm": 0.5,
        "layout_grid": {
            "columns": 3,
            "rows": 3,
            "cell_width_mm": 60,
            "cell_height_mm": 55,
            "frame_x_mm": 0,
            "frame_y_mm": 2.5,
            "frame_width_mm": 180,
            "frame_height_mm": 165,
        },
        "regions": [],
        "panels": [
            {
                "id": "panel-lower",
                "file_path": str(lower_path),
                "page_index": 0,
                "x_mm": 20,
                "y_mm": 20,
                "w_mm": 40,
                "h_mm": 30,
                "kind": "asset",
                "z_index": 0,
                "locked": False,
                "hidden": False,
                "group_id": None,
                "region_id": None,
                "slot_id": None,
                "crop_rect": {"x": 0, "y": 0, "width": 1, "height": 1},
            },
            {
                "id": "panel-upper",
                "file_path": str(upper_path),
                "page_index": 0,
                "x_mm": 30,
                "y_mm": 25,
                "w_mm": 40,
                "h_mm": 30,
                "kind": "asset",
                "z_index": 1,
                "locked": False,
                "hidden": False,
                "group_id": None,
                "region_id": None,
                "slot_id": None,
                "crop_rect": {"x": 0, "y": 0, "width": 1, "height": 1},
            },
        ],
        "texts": [],
        "auto_labels": True,
    }

    preview_response = client.post("/compose-preview", json=project_payload)
    assert preview_response.status_code == 200
    preview_image = _image_from_png_bytes(b64decode(preview_response.json()["png_base64"]))

    export_response = client.post("/compose-export", json=project_payload)
    assert export_response.status_code == 200
    export_image = _render_pdf_page_image(Path(export_response.json()["output_path"]), dpi=144)

    _assert_rgb_close(_sample_rgb_at_mm(preview_image, 40, 35), (37, 99, 235))
    _assert_rgb_close(_sample_rgb_at_mm(export_image, 40, 35), (37, 99, 235))
    _assert_rgb_close(_sample_rgb_at_mm(preview_image, 24, 24), (230, 57, 70))
    _assert_rgb_close(_sample_rgb_at_mm(export_image, 24, 24), (230, 57, 70))
