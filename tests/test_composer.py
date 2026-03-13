from __future__ import annotations

from pathlib import Path

import fitz

from src.composer import (
    ComposerProject,
    ComposerText,
    compose_export_pdf,
    import_panels_from_paths,
    validate_non_overlapping_panels,
)


def _write_pdf(path: Path, width_mm: float, height_mm: float) -> Path:
    document = fitz.open()
    document.new_page(width=width_mm / 25.4 * 72.0, height=height_mm / 25.4 * 72.0)
    document.save(path)
    document.close()
    return path


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
        assert "请改用 asset 模式导入" in str(exc)
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
