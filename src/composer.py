from __future__ import annotations

from dataclasses import asdict, dataclass, field
from io import BytesIO
from pathlib import Path
from string import ascii_lowercase
from typing import Any

import fitz
from PIL import Image, ImageDraw, ImageFont
from pypdf import PageObject, PdfReader, PdfWriter, Transformation
from reportlab.lib.colors import Color
from reportlab.lib.utils import ImageReader
from reportlab.pdfgen import canvas as pdf_canvas


MM_TO_PT = 72.0 / 25.4
COMPOSER_GRID_COLUMNS = 3
COMPOSER_GRID_ROWS = 3
COMPOSER_CELL_WIDTH_MM = 60.0
RASTER_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tif", ".tiff"}


def mm_to_pt(value_mm: float) -> float:
    return value_mm * MM_TO_PT


def mm_to_px(value_mm: float, dpi: float) -> int:
    return max(1, int(round(value_mm / 25.4 * dpi)))


@dataclass
class ComposerPanel:
    id: str
    file_path: str
    page_index: int
    x_mm: float
    y_mm: float
    w_mm: float
    h_mm: float
    locked: bool = False
    label: str | None = None
    kind: str = "graph"


@dataclass
class ComposerText:
    id: str
    text: str
    x_mm: float
    y_mm: float
    font_size_pt: float = 8.0
    align: str = "left"


@dataclass
class ComposerProject:
    version: int = 1
    mode: str = "composer"
    canvas_width_mm: float = 180.0
    canvas_height_mm: float = 170.0
    grid_mm: float = 0.5
    panels: list[ComposerPanel] = field(default_factory=list)
    texts: list[ComposerText] = field(default_factory=list)
    auto_labels: bool = True

    def to_dict(self) -> dict[str, Any]:
        return {
            "version": self.version,
            "mode": self.mode,
            "composer": {
                "canvas_mm": {
                    "width": self.canvas_width_mm,
                    "height": self.canvas_height_mm,
                    "grid": self.grid_mm,
                },
                "items": [asdict(panel) for panel in self.panels],
                "texts": [asdict(text) for text in self.texts],
                "auto_labels": self.auto_labels,
            },
        }


def project_from_dict(data: dict[str, Any]) -> ComposerProject:
    composer = data.get("composer", data)
    canvas_mm = composer.get("canvas_mm", {})
    items = composer.get("items", [])
    texts = composer.get("texts", [])
    return ComposerProject(
        version=int(data.get("version", 1)),
        mode=str(data.get("mode", "composer")),
        canvas_width_mm=float(canvas_mm.get("width", 180.0)),
        canvas_height_mm=float(canvas_mm.get("height", 170.0)),
        grid_mm=float(canvas_mm.get("grid", 0.5)),
        panels=[ComposerPanel(**item) for item in items],
        texts=[ComposerText(**text) for text in texts],
        auto_labels=bool(composer.get("auto_labels", True)),
    )


def _font(size: int) -> ImageFont.ImageFont:
    try:
        return ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", size)
    except Exception:
        return ImageFont.load_default()


def _is_pdf_path(file_path: str | Path) -> bool:
    return Path(file_path).suffix.lower() == ".pdf"


def _is_raster_path(file_path: str | Path) -> bool:
    return Path(file_path).suffix.lower() in RASTER_EXTENSIONS


def pdf_page_size_pt(file_path: str | Path, page_index: int = 0) -> tuple[float, float]:
    reader = PdfReader(str(file_path))
    page = reader.pages[page_index]
    return float(page.mediabox.width), float(page.mediabox.height)


def pdf_page_aspect_ratio(file_path: str | Path, page_index: int = 0) -> float:
    width_pt, height_pt = pdf_page_size_pt(file_path, page_index)
    if width_pt <= 0 or height_pt <= 0:
        return 1.0
    return width_pt / height_pt


def image_aspect_ratio(file_path: str | Path) -> float:
    with Image.open(file_path) as image:
        width_px, height_px = image.size
    if width_px <= 0 or height_px <= 0:
        return 1.0
    return width_px / height_px


def panel_aspect_ratio(file_path: str | Path, page_index: int = 0) -> float:
    if _is_pdf_path(file_path):
        return pdf_page_aspect_ratio(file_path, page_index)
    if _is_raster_path(file_path):
        return image_aspect_ratio(file_path)
    raise ValueError(f"Unsupported panel asset type: {file_path}")


def composer_cell_height_mm(project: ComposerProject) -> float:
    return project.canvas_height_mm / COMPOSER_GRID_ROWS


def _graph_panel_size_mm(file_path: str | Path, project: ComposerProject, page_index: int = 0) -> tuple[float, float]:
    width_mm = COMPOSER_CELL_WIDTH_MM
    aspect_ratio = panel_aspect_ratio(file_path, page_index)
    height_mm = width_mm / max(aspect_ratio, 1e-6)
    return width_mm, min(max(18.0, height_mm), composer_cell_height_mm(project) - 1.0)


def _asset_panel_size_mm(file_path: str | Path, project: ComposerProject, page_index: int = 0) -> tuple[float, float]:
    cell_height = composer_cell_height_mm(project)
    max_width = COMPOSER_CELL_WIDTH_MM - 6.0
    max_height = cell_height - 6.0
    aspect_ratio = panel_aspect_ratio(file_path, page_index)
    width_mm = max_width
    height_mm = width_mm / max(aspect_ratio, 1e-6)
    if height_mm > max_height:
        height_mm = max_height
        width_mm = height_mm * max(aspect_ratio, 1e-6)
    return max(12.0, width_mm), max(12.0, height_mm)


def _graph_cell_origin(project: ComposerProject, index: int) -> tuple[float, float]:
    column = index % COMPOSER_GRID_COLUMNS
    row = (index // COMPOSER_GRID_COLUMNS) % COMPOSER_GRID_ROWS
    return column * COMPOSER_CELL_WIDTH_MM, row * composer_cell_height_mm(project)


def _graph_cell_index(panel: ComposerPanel, project: ComposerProject) -> int:
    column = int(round(panel.x_mm / COMPOSER_CELL_WIDTH_MM))
    row = int(round(panel.y_mm / composer_cell_height_mm(project)))
    column = min(max(column, 0), COMPOSER_GRID_COLUMNS - 1)
    row = min(max(row, 0), COMPOSER_GRID_ROWS - 1)
    return row * COMPOSER_GRID_COLUMNS + column


def _next_free_graph_index(project: ComposerProject) -> int:
    occupied = {
        _graph_cell_index(panel, project)
        for panel in project.panels
        if getattr(panel, "kind", "graph") == "graph"
    }
    for index in range(COMPOSER_GRID_COLUMNS * COMPOSER_GRID_ROWS):
        if index not in occupied:
            return index
    return len([panel for panel in project.panels if getattr(panel, "kind", "graph") == "graph"])


def import_panels_from_paths(
    project: ComposerProject,
    file_paths: list[str | Path],
    *,
    kind: str,
) -> list[ComposerPanel]:
    next_panels = list(project.panels)
    graph_count = len([panel for panel in next_panels if getattr(panel, "kind", "graph") == "graph"])
    asset_count = len([panel for panel in next_panels if getattr(panel, "kind", "graph") == "asset"])
    for file_path in file_paths:
        normalized = Path(file_path).expanduser()
        if kind == "graph":
            index = _next_free_graph_index(
                ComposerProject(
                    version=project.version,
                    mode=project.mode,
                    canvas_width_mm=project.canvas_width_mm,
                    canvas_height_mm=project.canvas_height_mm,
                    grid_mm=project.grid_mm,
                    panels=next_panels,
                    texts=list(project.texts),
                    auto_labels=project.auto_labels,
                )
            )
            x_mm, y_mm = _graph_cell_origin(project, index)
            w_mm, h_mm = _graph_panel_size_mm(normalized, project, 0)
            graph_count += 1
            next_panels.append(
                ComposerPanel(
                    id=f"panel-{graph_count}",
                    file_path=str(normalized),
                    page_index=0,
                    x_mm=x_mm,
                    y_mm=y_mm,
                    w_mm=w_mm,
                    h_mm=h_mm,
                    kind="graph",
                )
            )
        else:
            index = _next_free_graph_index(
                ComposerProject(
                    version=project.version,
                    mode=project.mode,
                    canvas_width_mm=project.canvas_width_mm,
                    canvas_height_mm=project.canvas_height_mm,
                    grid_mm=project.grid_mm,
                    panels=next_panels,
                    texts=list(project.texts),
                    auto_labels=project.auto_labels,
                )
            )
            cell_x, cell_y = _graph_cell_origin(project, index)
            w_mm, h_mm = _asset_panel_size_mm(normalized, project, 0)
            asset_count += 1
            next_panels.append(
                ComposerPanel(
                    id=f"asset-{asset_count}",
                    file_path=str(normalized),
                    page_index=0,
                    x_mm=cell_x + (COMPOSER_CELL_WIDTH_MM - w_mm) / 2.0,
                    y_mm=cell_y + (composer_cell_height_mm(project) - h_mm) / 2.0,
                    w_mm=w_mm,
                    h_mm=h_mm,
                    kind="asset",
                )
            )
    return next_panels


def resolve_panel_labels(project: ComposerProject) -> dict[str, str]:
    if not project.auto_labels:
        return {panel.id: panel.label or "" for panel in project.panels}
    ordered = sorted(
        project.panels,
        key=lambda panel: (round(panel.y_mm, 3), round(panel.x_mm, 3), panel.id),
    )
    return {
        panel.id: ascii_lowercase[index] if index < len(ascii_lowercase) else chr(ord("a") + index)
        for index, panel in enumerate(ordered)
    }


def panel_thumbnail_png(file_path: str | Path, page_index: int = 0, *, max_side_px: int = 640) -> bytes:
    if _is_pdf_path(file_path):
        document = fitz.open(str(file_path))
        try:
            page = document.load_page(page_index)
            rect = page.rect
            scale = max_side_px / max(rect.width, rect.height)
            scale = max(scale, 0.2)
            pix = page.get_pixmap(matrix=fitz.Matrix(scale, scale), alpha=False)
            return pix.tobytes("png")
        finally:
            document.close()
    if _is_raster_path(file_path):
        with Image.open(file_path) as image:
            image = image.convert("RGB")
            image.thumbnail((max_side_px, max_side_px), Image.Resampling.LANCZOS)
            output = BytesIO()
            image.save(output, format="PNG")
            return output.getvalue()
    raise ValueError(f"Unsupported panel asset type: {file_path}")


def three_up_panels_from_paths(file_paths: list[str | Path]) -> list[ComposerPanel]:
    panels: list[ComposerPanel] = []
    labels = "abcdefghijklmnopqrstuvwxyz"
    for index, file_path in enumerate(file_paths[:3]):
        aspect_ratio = pdf_page_aspect_ratio(file_path, 0)
        width_mm = 60.0
        height_mm = max(20.0, width_mm / max(aspect_ratio, 1e-6))
        panels.append(
            ComposerPanel(
                id=f"panel-{index + 1}",
                file_path=str(Path(file_path).expanduser()),
                page_index=0,
                x_mm=index * 60.0,
                y_mm=0.0,
                w_mm=width_mm,
                h_mm=height_mm,
                label=labels[index],
                kind="graph",
            )
        )
    return panels


def _draw_text(draw: ImageDraw.ImageDraw, text: ComposerText, dpi: float, canvas_height_px: int) -> None:
    x_px = mm_to_px(text.x_mm, dpi)
    y_px = mm_to_px(text.y_mm, dpi)
    font = _font(max(8, int(round(text.font_size_pt * dpi / 72.0))))
    bbox = draw.textbbox((0, 0), text.text, font=font)
    width = bbox[2] - bbox[0]
    anchor_x = x_px
    if text.align == "center":
        anchor_x -= width // 2
    elif text.align == "right":
        anchor_x -= width
    draw.text((anchor_x, y_px), text.text, font=font, fill=(24, 24, 24))


def compose_preview_png(project: ComposerProject, *, dpi: int = 144) -> bytes:
    canvas_width_px = mm_to_px(project.canvas_width_mm, dpi)
    canvas_height_px = mm_to_px(project.canvas_height_mm, dpi)
    canvas_image = Image.new("RGB", (canvas_width_px, canvas_height_px), (250, 250, 252))
    draw = ImageDraw.Draw(canvas_image)
    label_font = _font(max(10, int(round(9 * dpi / 72.0))))
    label_fill = (24, 24, 24)
    panel_border = (208, 214, 224)
    resolved_labels = resolve_panel_labels(project)

    for panel in project.panels:
        thumbnail = panel_thumbnail_png(panel.file_path, panel.page_index)
        panel_image = Image.open(BytesIO(thumbnail)).convert("RGB")
        target_width_px = mm_to_px(panel.w_mm, dpi)
        target_height_px = mm_to_px(panel.h_mm, dpi)
        panel_image = panel_image.resize((target_width_px, target_height_px), Image.Resampling.LANCZOS)

        x_px = mm_to_px(panel.x_mm, dpi)
        y_px = mm_to_px(panel.y_mm, dpi)
        canvas_image.paste(panel_image, (x_px, y_px))
        draw.rounded_rectangle(
            (x_px, y_px, x_px + target_width_px, y_px + target_height_px),
            radius=max(4, int(round(dpi / 36))),
            outline=panel_border,
            width=max(1, int(round(dpi / 160))),
        )
        if project.auto_labels:
            label = resolved_labels.get(panel.id, "")
            if label:
                draw.text((x_px + 8, y_px + 8), label, font=label_font, fill=label_fill)

    for text in project.texts:
        _draw_text(draw, text, dpi, canvas_height_px)

    output = BytesIO()
    canvas_image.save(output, format="PNG")
    return output.getvalue()


def _overlay_pdf_bytes(project: ComposerProject) -> bytes:
    buffer = BytesIO()
    canvas_width_pt = mm_to_pt(project.canvas_width_mm)
    canvas_height_pt = mm_to_pt(project.canvas_height_mm)
    c = pdf_canvas.Canvas(buffer, pagesize=(canvas_width_pt, canvas_height_pt))
    c.setFillColor(Color(0.1, 0.1, 0.12, alpha=1))
    resolved_labels = resolve_panel_labels(project)
    for panel in project.panels:
        if _is_raster_path(panel.file_path):
            x_pt = mm_to_pt(panel.x_mm)
            y_pt = canvas_height_pt - mm_to_pt(panel.y_mm + panel.h_mm)
            c.drawImage(
                ImageReader(panel.file_path),
                x_pt,
                y_pt,
                width=mm_to_pt(panel.w_mm),
                height=mm_to_pt(panel.h_mm),
                preserveAspectRatio=True,
                mask="auto",
            )
    if project.auto_labels:
        c.setFont("Helvetica-Bold", 9)
        for panel in project.panels:
            label = resolved_labels.get(panel.id, "")
            if not label:
                continue
            x_pt = mm_to_pt(panel.x_mm) + 3
            y_pt = canvas_height_pt - mm_to_pt(panel.y_mm) - 10
            c.drawString(x_pt, y_pt, label)
    for text in project.texts:
        font_name = "Helvetica"
        c.setFont(font_name, text.font_size_pt)
        x_pt = mm_to_pt(text.x_mm)
        y_pt = canvas_height_pt - mm_to_pt(text.y_mm) - text.font_size_pt
        if text.align == "center":
            c.drawCentredString(x_pt, y_pt, text.text)
        elif text.align == "right":
            c.drawRightString(x_pt, y_pt, text.text)
        else:
            c.drawString(x_pt, y_pt, text.text)
    c.showPage()
    c.save()
    buffer.seek(0)
    return buffer.getvalue()


def compose_export_pdf(project: ComposerProject, output_path: str | Path) -> Path:
    output = Path(output_path).expanduser()
    output.parent.mkdir(parents=True, exist_ok=True)

    canvas_width_pt = mm_to_pt(project.canvas_width_mm)
    canvas_height_pt = mm_to_pt(project.canvas_height_mm)
    merged_page = PageObject.create_blank_page(width=canvas_width_pt, height=canvas_height_pt)

    for panel in project.panels:
        if not _is_pdf_path(panel.file_path):
            continue
        reader = PdfReader(str(panel.file_path))
        source_page = reader.pages[panel.page_index]
        source_width = float(source_page.mediabox.width)
        source_height = float(source_page.mediabox.height)
        target_width = mm_to_pt(panel.w_mm)
        target_height = mm_to_pt(panel.h_mm)
        target_x = mm_to_pt(panel.x_mm)
        target_y = canvas_height_pt - mm_to_pt(panel.y_mm + panel.h_mm)
        transform = (
            Transformation()
            .scale(target_width / max(source_width, 1e-6), target_height / max(source_height, 1e-6))
            .translate(target_x, target_y)
        )
        merged_page.merge_transformed_page(source_page, transform, over=True)

    overlay_reader = PdfReader(BytesIO(_overlay_pdf_bytes(project)))
    merged_page.merge_page(overlay_reader.pages[0], over=True)

    writer = PdfWriter()
    writer.add_page(merged_page)
    with output.open("wb") as handle:
        writer.write(handle)
    return output


def clamp_panel_to_canvas(panel: ComposerPanel, project: ComposerProject) -> ComposerPanel:
    panel.x_mm = min(max(panel.x_mm, 0.0), max(0.0, project.canvas_width_mm - panel.w_mm))
    panel.y_mm = min(max(panel.y_mm, 0.0), max(0.0, project.canvas_height_mm - panel.h_mm))
    return panel


def panels_overlap(panel_a: ComposerPanel, panel_b: ComposerPanel) -> bool:
    return not (
        panel_a.x_mm + panel_a.w_mm <= panel_b.x_mm
        or panel_b.x_mm + panel_b.w_mm <= panel_a.x_mm
        or panel_a.y_mm + panel_a.h_mm <= panel_b.y_mm
        or panel_b.y_mm + panel_b.h_mm <= panel_a.y_mm
    )


def validate_non_overlapping_panels(project: ComposerProject) -> tuple[bool, str | None]:
    for index, panel in enumerate(project.panels):
        clamp_panel_to_canvas(panel, project)
        for other in project.panels[index + 1 :]:
            if panels_overlap(panel, other):
                return False, f"Panels {panel.id} and {other.id} overlap."
    return True, None
