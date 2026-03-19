from __future__ import annotations

import html
from io import BytesIO
from pathlib import Path
from typing import Literal, cast

import fitz
from PIL import Image, ImageDraw, ImageFont

from src.composer_ops import (
    _is_pdf_path,
    _is_raster_path,
    _normalize_crop_rect,
    normalize_project,
    resolve_panel_labels,
)
from src.composer_types import (
    PT_TO_MM,
    ComposerCropRect,
    ComposerPanel,
    ComposerProject,
    ComposerText,
    mm_to_pt,
    mm_to_px,
)


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
            image = image.convert("RGBA")
            image.thumbnail((max_side_px, max_side_px), Image.Resampling.LANCZOS)
            output = BytesIO()
            image.save(output, format="PNG")
            return output.getvalue()
    raise ValueError(f"Unsupported panel asset type: {file_path}")


def _crop_image(image: Image.Image, crop_rect: ComposerCropRect) -> Image.Image:
    width, height = image.size
    left = int(round(crop_rect.x * width))
    top = int(round(crop_rect.y * height))
    right = int(round((crop_rect.x + crop_rect.width) * width))
    bottom = int(round((crop_rect.y + crop_rect.height) * height))
    right = max(left + 1, min(right, width))
    bottom = max(top + 1, min(bottom, height))
    return image.crop((left, top, right, bottom))


def _sorted_drawables(
    project: ComposerProject,
) -> list[tuple[Literal["panel", "text"], ComposerPanel | ComposerText]]:
    drawables: list[tuple[Literal["panel", "text"], ComposerPanel | ComposerText]] = []
    for panel in project.panels:
        drawables.append(("panel", panel))
    for text in project.texts:
        drawables.append(("text", text))
    drawables.sort(
        key=lambda item: (item[1].z_index, 0 if item[0] == "panel" else 1, item[1].id)
    )
    return drawables


def _draw_text(draw: ImageDraw.ImageDraw, text: ComposerText, dpi: float) -> None:
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


def _panel_label_text(project: ComposerProject, panel: ComposerPanel) -> str:
    return resolve_panel_labels(project).get(panel.id, "")


def compose_preview_png(project: ComposerProject, *, dpi: int = 144) -> bytes:
    normalized = normalize_project(project)
    canvas_width_px = mm_to_px(normalized.canvas_width_mm, dpi)
    canvas_height_px = mm_to_px(normalized.canvas_height_mm, dpi)
    canvas_image = Image.new(
        "RGBA",
        (canvas_width_px, canvas_height_px),
        (255, 255, 255, 255),
    )
    draw = ImageDraw.Draw(canvas_image)
    label_font = _font(max(10, int(round(9 * dpi / 72.0))))

    for kind, drawable in _sorted_drawables(normalized):
        if kind == "panel":
            panel = cast(ComposerPanel, drawable)
            if panel.hidden:
                continue
            source = Image.open(
                BytesIO(panel_thumbnail_png(panel.file_path, panel.page_index))
            ).convert("RGBA")
            panel_image = _crop_image(source, panel.crop_rect)
            target_width_px = mm_to_px(panel.w_mm, dpi)
            target_height_px = mm_to_px(panel.h_mm, dpi)
            panel_image = panel_image.resize(
                (target_width_px, target_height_px),
                Image.Resampling.LANCZOS,
            )
            x_px = mm_to_px(panel.x_mm, dpi)
            y_px = mm_to_px(panel.y_mm, dpi)
            canvas_image.alpha_composite(panel_image, (x_px, y_px))
            if normalized.auto_labels and panel.kind == "graph":
                label = _panel_label_text(normalized, panel)
                if label:
                    draw.text((x_px + 8, y_px + 8), label, font=label_font, fill=(24, 24, 24))
        else:
            text = cast(ComposerText, drawable)
            if text.hidden:
                continue
            _draw_text(draw, text, dpi)

    output = BytesIO()
    canvas_image.convert("RGB").save(output, format="PNG")
    return output.getvalue()


def _pdf_clip_rect(panel: ComposerPanel, source_rect: fitz.Rect) -> fitz.Rect:
    crop = _normalize_crop_rect(panel.crop_rect)
    return fitz.Rect(
        source_rect.x0 + source_rect.width * crop.x,
        source_rect.y0 + source_rect.height * crop.y,
        source_rect.x0 + source_rect.width * (crop.x + crop.width),
        source_rect.y0 + source_rect.height * (crop.y + crop.height),
    )


def _raster_stream_for_panel(panel: ComposerPanel) -> bytes:
    with Image.open(panel.file_path) as image:
        rgba = image.convert("RGBA")
        cropped = _crop_image(rgba, panel.crop_rect)
        output = BytesIO()
        cropped.save(output, format="PNG")
        return output.getvalue()


def _draw_text_pdf_with_oc(page: fitz.Page, text: ComposerText, oc_xref: int) -> None:
    text_length = fitz.get_text_length(
        text.text,
        fontname="helv",
        fontsize=text.font_size_pt,
    )
    x_pt = mm_to_pt(text.x_mm)
    if text.align == "center":
        x_pt -= text_length / 2.0
    elif text.align == "right":
        x_pt -= text_length
    y_pt = mm_to_pt(text.y_mm)
    text_rect = fitz.Rect(
        x_pt,
        y_pt,
        x_pt + max(text_length + 4.0, text.font_size_pt),
        y_pt + text.font_size_pt * 1.8,
    )
    escaped_text = html.escape(text.text).replace("\n", "<br/>")
    page.insert_htmlbox(
        text_rect,
        (
            "<div "
            f"style=\"font-family: Helvetica; font-size: {text.font_size_pt}pt; "
            "color: rgb(26, 26, 31); margin: 0; padding: 0; "
            f"text-align: {text.align};\">"
            f"{escaped_text}"
            "</div>"
        ),
        oc=oc_xref,
        overlay=True,
    )


def _clean_layer_fragment(value: str | None, fallback: str) -> str:
    normalized = " ".join((value or "").split())
    if not normalized:
        return fallback
    return normalized[:72]


def _panel_layer_name(project: ComposerProject, panel: ComposerPanel) -> str:
    if panel.kind == "graph":
        label = _panel_label_text(project, panel)
        suffix = f" [{label}]" if label else ""
        return f"Graph/{panel.id}{suffix}"
    prefix = "Structure Asset" if panel.slot_id else "Asset"
    leaf = _clean_layer_fragment(panel.label or Path(panel.file_path).name, panel.id)
    return f"{prefix}/{panel.id} {leaf}"


def _text_layer_name(text: ComposerText) -> str:
    prefix = "Structure Text" if text.slot_id else "Text"
    snippet = _clean_layer_fragment(text.text, text.id)
    return f"{prefix}/{text.id} {snippet}"


def _ensure_ocg(document: fitz.Document, cache: dict[str, int], name: str) -> int:
    existing = cache.get(name)
    if existing is not None:
        return existing
    ocg_xref = int(document.add_ocg(name))
    cache[name] = ocg_xref
    return ocg_xref


def compose_export_pdf(project: ComposerProject, output_path: str | Path) -> Path:
    normalized = normalize_project(project)
    output = Path(output_path).expanduser()
    output.parent.mkdir(parents=True, exist_ok=True)

    document = fitz.open()
    page = document.new_page(
        width=mm_to_pt(normalized.canvas_width_mm),
        height=mm_to_pt(normalized.canvas_height_mm),
    )
    ocg_cache: dict[str, int] = {}

    for kind, drawable in _sorted_drawables(normalized):
        if kind == "panel":
            panel = cast(ComposerPanel, drawable)
            if panel.hidden:
                continue
            panel_ocg = _ensure_ocg(document, ocg_cache, _panel_layer_name(normalized, panel))
            target_rect = fitz.Rect(
                mm_to_pt(panel.x_mm),
                mm_to_pt(panel.y_mm),
                mm_to_pt(panel.x_mm + panel.w_mm),
                mm_to_pt(panel.y_mm + panel.h_mm),
            )
            if _is_pdf_path(panel.file_path):
                source_document = fitz.open(panel.file_path)
                try:
                    source_page = source_document.load_page(panel.page_index)
                    page.show_pdf_page(
                        target_rect,
                        source_document,
                        panel.page_index,
                        clip=_pdf_clip_rect(panel, source_page.rect),
                        keep_proportion=False,
                        oc=panel_ocg,
                        overlay=True,
                    )
                finally:
                    source_document.close()
            elif _is_raster_path(panel.file_path):
                page.insert_image(
                    target_rect,
                    stream=_raster_stream_for_panel(panel),
                    keep_proportion=False,
                    oc=panel_ocg,
                    overlay=True,
                )
            else:
                raise ValueError(f"Unsupported panel asset type: {panel.file_path}")

            if normalized.auto_labels and panel.kind == "graph":
                label = _panel_label_text(normalized, panel)
                if label:
                    _draw_text_pdf_with_oc(
                        page,
                        ComposerText(
                            id=f"{panel.id}:label",
                            text=label,
                            x_mm=panel.x_mm + (8.0 * PT_TO_MM),
                            y_mm=panel.y_mm + (3.0 * PT_TO_MM),
                            font_size_pt=9,
                            align="left",
                        ),
                        panel_ocg,
                    )
        else:
            text = cast(ComposerText, drawable)
            if text.hidden:
                continue
            text_ocg = _ensure_ocg(document, ocg_cache, _text_layer_name(text))
            _draw_text_pdf_with_oc(page, text, text_ocg)

    document.save(output)
    document.close()
    return output
