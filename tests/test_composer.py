from __future__ import annotations

import re
from io import BytesIO
from pathlib import Path

import fitz
from PIL import Image

from src.composer import (
    ComposerCropRect,
    ComposerPanel,
    ComposerProject,
    ComposerText,
    compose_export_pdf,
    compose_preview_png,
    import_panels_from_paths,
    validate_non_overlapping_panels,
)


def _write_pdf(path: Path, width_mm: float, height_mm: float) -> Path:
    document = fitz.open()
    document.new_page(width=width_mm / 25.4 * 72.0, height=height_mm / 25.4 * 72.0)
    document.save(path)
    document.close()
    return path


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


def _write_split_pdf(
    path: Path,
    width_mm: float,
    height_mm: float,
    left_color: tuple[int, int, int],
    right_color: tuple[int, int, int],
) -> Path:
    document = fitz.open()
    page = document.new_page(width=width_mm / 25.4 * 72.0, height=height_mm / 25.4 * 72.0)
    midpoint = page.rect.width / 2.0
    page.draw_rect(
        fitz.Rect(0, 0, midpoint, page.rect.height),
        color=None,
        fill=tuple(channel / 255.0 for channel in left_color),
    )
    page.draw_rect(
        fitz.Rect(midpoint, 0, page.rect.width, page.rect.height),
        color=None,
        fill=tuple(channel / 255.0 for channel in right_color),
    )
    document.save(path)
    document.close()
    return path


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


def test_import_graph_pdf_spans_two_cells_for_120x55(tmp_path: Path) -> None:
    graph_path = _write_pdf(tmp_path / "double-wide.pdf", 120.0, 55.0)

    project = import_panels_from_paths(ComposerProject(), [graph_path], kind="graph")

    assert len(project.regions) == 1
    assert project.regions[0].kind == "graph"
    assert project.regions[0].col_span == 2
    assert project.regions[0].row_span == 1
    assert project.panels[0].region_id == project.regions[0].id
    assert round(project.panels[0].w_mm, 1) == 120.0


def test_import_wide_nmr_creates_structure_slot(tmp_path: Path) -> None:
    graph_path = _write_pdf(tmp_path / "wide-nmr.pdf", 60.0, 110.0)

    project = import_panels_from_paths(ComposerProject(), [graph_path], kind="graph")

    assert len(project.regions) == 1
    assert project.regions[0].row_span == 2
    assert project.regions[0].slot_kind == "structure"
    assert project.panels[0].region_id == project.regions[0].id
    assert round(project.panels[0].h_mm, 1) == 110.0


def test_asset_can_overlap_graph_region(tmp_path: Path) -> None:
    graph_path = _write_pdf(tmp_path / "single.pdf", 60.0, 55.0)
    asset_path = _write_pdf(tmp_path / "asset.pdf", 70.0, 40.0)

    project = import_panels_from_paths(ComposerProject(), [graph_path], kind="graph")
    project = import_panels_from_paths(project, [asset_path], kind="asset")
    project.panels[-1].x_mm = project.panels[0].x_mm + 5
    project.panels[-1].y_mm = project.panels[0].y_mm + 5

    ok, reason = validate_non_overlapping_panels(project)

    assert ok, reason


def test_invalid_graph_size_requires_asset_mode(tmp_path: Path) -> None:
    graph_path = _write_pdf(tmp_path / "invalid.pdf", 70.0, 55.0)

    try:
        import_panels_from_paths(ComposerProject(), [graph_path], kind="graph")
    except ValueError as exc:
        assert "Use asset mode instead" in str(exc)
    else:
        raise AssertionError("Unexpectedly accepted an unsupported graph PDF size.")


def test_hidden_text_is_excluded_from_export_pdf(tmp_path: Path) -> None:
    output_path = tmp_path / "composer-export.pdf"
    project = ComposerProject(
        texts=[
            ComposerText(id="text-1", text="Visible", x_mm=10, y_mm=10),
            ComposerText(id="text-2", text="Hidden", x_mm=30, y_mm=20, hidden=True),
        ]
    )

    compose_export_pdf(project, output_path)

    document = fitz.open(output_path)
    try:
        exported_text = document.load_page(0).get_text()
    finally:
        document.close()

    assert "Visible" in exported_text
    assert "Hidden" not in exported_text


def test_export_pdf_preserves_pdf_xobjects_and_raster_images(tmp_path: Path) -> None:
    graph_path = _write_pdf_with_text(tmp_path / "graph.pdf", 60.0, 55.0, "Graph PDF")
    asset_pdf_path = _write_pdf_with_text(tmp_path / "asset.pdf", 60.0, 55.0, "Asset PDF")
    raster_path = _write_png(tmp_path / "asset.png", (220, 38, 38))
    hidden_pdf_path = _write_pdf_with_text(tmp_path / "hidden.pdf", 60.0, 55.0, "Hidden PDF")
    hidden_raster_path = _write_png(tmp_path / "hidden.png", (37, 99, 235))
    output_path = tmp_path / "composer-structure.pdf"
    project = ComposerProject(
        panels=[
            ComposerPanel(
                id="panel-graph",
                file_path=str(graph_path),
                page_index=0,
                x_mm=0,
                y_mm=0,
                w_mm=60,
                h_mm=55,
                kind="graph",
                z_index=0,
            ),
            ComposerPanel(
                id="panel-pdf",
                file_path=str(asset_pdf_path),
                page_index=0,
                x_mm=70,
                y_mm=0,
                w_mm=60,
                h_mm=55,
                kind="asset",
                z_index=1,
            ),
            ComposerPanel(
                id="panel-raster",
                file_path=str(raster_path),
                page_index=0,
                x_mm=0,
                y_mm=70,
                w_mm=30,
                h_mm=15,
                kind="asset",
                z_index=2,
            ),
            ComposerPanel(
                id="panel-hidden-pdf",
                file_path=str(hidden_pdf_path),
                page_index=0,
                x_mm=70,
                y_mm=70,
                w_mm=30,
                h_mm=15,
                kind="asset",
                z_index=3,
                hidden=True,
            ),
            ComposerPanel(
                id="panel-hidden-raster",
                file_path=str(hidden_raster_path),
                page_index=0,
                x_mm=110,
                y_mm=70,
                w_mm=30,
                h_mm=15,
                kind="asset",
                z_index=4,
                hidden=True,
            ),
        ],
        texts=[
            ComposerText(id="text-visible", text="Overlay Text", x_mm=10, y_mm=110, z_index=5),
            ComposerText(id="text-hidden", text="Hidden Overlay", x_mm=10, y_mm=120, z_index=6, hidden=True),
        ],
    )

    compose_export_pdf(project, output_path)

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
        "Graph/panel-graph [a]",
        "Asset/panel-pdf asset.pdf",
        "Asset/panel-raster asset.png",
        "Text/text-visible Overlay Text",
    }
    assert form_layer_names == {
        "Graph/panel-graph [a]",
        "Asset/panel-pdf asset.pdf",
        "Text/text-visible Overlay Text",
    }
    assert image_layer_names == {"Asset/panel-raster asset.png"}
    assert "Graph PDF" in exported_text
    assert "Asset PDF" in exported_text
    assert "Overlay Text" in exported_text
    assert "Hidden PDF" not in exported_text
    assert "Hidden Overlay" not in exported_text


def test_export_pdf_assigns_stable_layer_names_to_visible_drawables(tmp_path: Path) -> None:
    graph_path = _write_pdf_with_text(tmp_path / "graph.pdf", 60.0, 55.0, "Layer Graph")
    raster_path = _write_png(tmp_path / "asset.png", (54, 162, 235))
    output_path = tmp_path / "composer-layers.pdf"
    project = ComposerProject(
        panels=[
            ComposerPanel(
                id="panel-graph",
                file_path=str(graph_path),
                page_index=0,
                x_mm=0,
                y_mm=0,
                w_mm=60,
                h_mm=55,
                kind="graph",
                z_index=0,
            ),
            ComposerPanel(
                id="panel-raster",
                file_path=str(raster_path),
                page_index=0,
                x_mm=80,
                y_mm=10,
                w_mm=24,
                h_mm=12,
                kind="asset",
                z_index=1,
                slot_id="region-1:structure",
            ),
        ],
        texts=[
            ComposerText(id="text-visible", text="Overlay Text", x_mm=15, y_mm=90, z_index=2),
            ComposerText(id="text-hidden", text="Hidden Text", x_mm=15, y_mm=100, z_index=3, hidden=True),
        ],
    )

    compose_export_pdf(project, output_path)

    document = fitz.open(output_path)
    try:
        page = document.load_page(0)
        layer_names = set(_layer_name_by_oc_xref(document).values())
        form_layer_names = set(_top_level_form_layer_names(document, page))
        image_layer_names = set(_image_layer_names(document, page))
    finally:
        document.close()

    assert layer_names == {
        "Graph/panel-graph [a]",
        "Structure Asset/panel-raster asset.png",
        "Text/text-visible Overlay Text",
    }
    assert form_layer_names == {
        "Graph/panel-graph [a]",
        "Text/text-visible Overlay Text",
    }
    assert image_layer_names == {"Structure Asset/panel-raster asset.png"}


def test_preview_and_export_preserve_topmost_raster_z_order(tmp_path: Path) -> None:
    lower_path = _write_png(tmp_path / "lower.png", (230, 57, 70))
    upper_path = _write_png(tmp_path / "upper.png", (37, 99, 235))
    export_path = tmp_path / "overlap-export.pdf"
    project = ComposerProject(
        panels=[
            ComposerPanel(
                id="panel-lower",
                file_path=str(lower_path),
                page_index=0,
                x_mm=20,
                y_mm=20,
                w_mm=40,
                h_mm=30,
                kind="asset",
                z_index=0,
            ),
            ComposerPanel(
                id="panel-upper",
                file_path=str(upper_path),
                page_index=0,
                x_mm=30,
                y_mm=25,
                w_mm=40,
                h_mm=30,
                kind="asset",
                z_index=1,
            ),
        ]
    )

    preview_image = _image_from_png_bytes(compose_preview_png(project, dpi=144))
    compose_export_pdf(project, export_path)
    export_image = _render_pdf_page_image(export_path, dpi=144)

    _assert_rgb_close(_sample_rgb_at_mm(preview_image, 40, 35), (37, 99, 235))
    _assert_rgb_close(_sample_rgb_at_mm(export_image, 40, 35), (37, 99, 235))
    _assert_rgb_close(_sample_rgb_at_mm(preview_image, 24, 24), (230, 57, 70))
    _assert_rgb_close(_sample_rgb_at_mm(export_image, 24, 24), (230, 57, 70))


def test_preview_and_export_apply_pdf_crop_rect_consistently(tmp_path: Path) -> None:
    split_pdf_path = _write_split_pdf(
        tmp_path / "split.pdf",
        60.0,
        55.0,
        left_color=(230, 57, 70),
        right_color=(37, 99, 235),
    )
    export_path = tmp_path / "cropped-export.pdf"
    project = ComposerProject(
        panels=[
            ComposerPanel(
                id="panel-cropped-pdf",
                file_path=str(split_pdf_path),
                page_index=0,
                x_mm=20,
                y_mm=20,
                w_mm=40,
                h_mm=30,
                kind="asset",
                z_index=0,
                crop_rect=ComposerCropRect(x=0.5, y=0.0, width=0.5, height=1.0),
            ),
        ]
    )

    preview_image = _image_from_png_bytes(compose_preview_png(project, dpi=144))
    compose_export_pdf(project, export_path)
    export_image = _render_pdf_page_image(export_path, dpi=144)

    _assert_rgb_close(_sample_rgb_at_mm(preview_image, 30, 30), (37, 99, 235))
    _assert_rgb_close(_sample_rgb_at_mm(export_image, 30, 30), (37, 99, 235))
    _assert_rgb_close(_sample_rgb_at_mm(preview_image, 50, 40), (37, 99, 235))
    _assert_rgb_close(_sample_rgb_at_mm(export_image, 50, 40), (37, 99, 235))
