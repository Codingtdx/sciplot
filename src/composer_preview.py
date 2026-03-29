from __future__ import annotations

from io import BytesIO
from pathlib import Path
from typing import Literal, cast

import fitz
from PIL import Image, ImageDraw, ImageFont

from src.composer_assets import is_pdf_path, is_raster_path
from src.composer_project import normalize_project, resolve_panel_labels
from src.composer_types import ComposerCropRect, ComposerPanel, ComposerProject, ComposerText, mm_to_px

PANEL_LABEL_OFFSET_X_MM = 1.0
PANEL_LABEL_OFFSET_Y_MM = 0.8
PANEL_LABEL_FONT_SIZE_PT = 9.0


def _font(size: int) -> ImageFont.ImageFont:
    try:
        return ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", size)
    except Exception:
        return ImageFont.load_default()


def panel_thumbnail_png(
    file_path: str | Path,
    page_index: int = 0,
    *,
    max_side_px: int = 640,
) -> bytes:
    if is_pdf_path(file_path):
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
    if is_raster_path(file_path):
        with Image.open(file_path) as image:
            image = image.convert("RGBA")
            image.thumbnail((max_side_px, max_side_px), Image.Resampling.LANCZOS)
            output = BytesIO()
            image.save(output, format="PNG")
            return output.getvalue()
    raise ValueError(f"Unsupported panel asset type: {file_path}")


def crop_image(image: Image.Image, crop_rect: ComposerCropRect) -> Image.Image:
    width, height = image.size
    left = int(round(crop_rect.x * width))
    top = int(round(crop_rect.y * height))
    right = int(round((crop_rect.x + crop_rect.width) * width))
    bottom = int(round((crop_rect.y + crop_rect.height) * height))
    right = max(left + 1, min(right, width))
    bottom = max(top + 1, min(bottom, height))
    return image.crop((left, top, right, bottom))


def sorted_drawables(
    project: ComposerProject,
) -> list[tuple[Literal["panel", "text"], ComposerPanel | ComposerText]]:
    drawables: list[tuple[Literal["panel", "text"], ComposerPanel | ComposerText]] = []
    for panel in project.panels:
        drawables.append(("panel", panel))
    for text in project.texts:
        drawables.append(("text", text))
    drawables.sort(key=lambda item: (item[1].z_index, 0 if item[0] == "panel" else 1, item[1].id))
    return drawables


def draw_text(draw: ImageDraw.ImageDraw, text: ComposerText, dpi: float) -> None:
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


def panel_label_text(project: ComposerProject, panel: ComposerPanel) -> str:
    return resolve_panel_labels(project).get(panel.id, "")


def panel_label_origin_mm(project: ComposerProject, panel: ComposerPanel) -> tuple[float, float]:
    del project
    return (
        max(panel.x_mm + PANEL_LABEL_OFFSET_X_MM, 0.0),
        max(panel.y_mm + PANEL_LABEL_OFFSET_Y_MM, 0.0),
    )


def compose_preview_png(project: ComposerProject, *, dpi: int = 144) -> bytes:
    normalized = normalize_project(project)
    canvas_width_px = mm_to_px(normalized.canvas_width_mm, dpi)
    canvas_height_px = mm_to_px(normalized.canvas_height_mm, dpi)
    canvas_image = Image.new("RGBA", (canvas_width_px, canvas_height_px), (255, 255, 255, 255))
    draw = ImageDraw.Draw(canvas_image)
    label_font = _font(max(10, int(round(PANEL_LABEL_FONT_SIZE_PT * dpi / 72.0))))

    for kind, drawable in sorted_drawables(normalized):
        if kind == "panel":
            panel = cast(ComposerPanel, drawable)
            if panel.hidden:
                continue
            source = Image.open(BytesIO(panel_thumbnail_png(panel.file_path, panel.page_index))).convert("RGBA")
            panel_image = crop_image(source, panel.crop_rect)
            target_width_px = mm_to_px(panel.w_mm, dpi)
            target_height_px = mm_to_px(panel.h_mm, dpi)
            panel_image = panel_image.resize((target_width_px, target_height_px), Image.Resampling.LANCZOS)
            x_px = mm_to_px(panel.x_mm, dpi)
            y_px = mm_to_px(panel.y_mm, dpi)
            canvas_image.alpha_composite(panel_image, (x_px, y_px))
            if panel.kind == "graph":
                label = panel_label_text(normalized, panel)
                if label:
                    label_x_mm, label_y_mm = panel_label_origin_mm(normalized, panel)
                    draw.text(
                        (mm_to_px(label_x_mm, dpi), mm_to_px(label_y_mm, dpi)),
                        label,
                        font=label_font,
                        fill=(24, 24, 24),
                    )
        else:
            text = cast(ComposerText, drawable)
            if text.hidden:
                continue
            draw_text(draw, text, dpi)

    output = BytesIO()
    canvas_image.convert("RGB").save(output, format="PNG")
    return output.getvalue()


__all__ = [
    "compose_preview_png",
    "crop_image",
    "draw_text",
    "panel_label_origin_mm",
    "panel_label_text",
    "panel_thumbnail_png",
    "PANEL_LABEL_FONT_SIZE_PT",
    "PANEL_LABEL_OFFSET_X_MM",
    "PANEL_LABEL_OFFSET_Y_MM",
    "sorted_drawables",
]
