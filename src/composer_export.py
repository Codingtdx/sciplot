from __future__ import annotations

import html
from io import BytesIO
from pathlib import Path
from typing import cast

import fitz
from PIL import Image

from src.composer_assets import is_pdf_path, is_raster_path
from src.composer_project import normalize_crop_rect, normalize_project
from src.composer_preview import crop_image, panel_label_text, panel_thumbnail_png, sorted_drawables
from src.composer_types import PT_TO_MM, ComposerPanel, ComposerProject, ComposerText, mm_to_pt


def pdf_clip_rect(panel: ComposerPanel, source_rect: fitz.Rect) -> fitz.Rect:
    crop = normalize_crop_rect(panel.crop_rect)
    return fitz.Rect(
        source_rect.x0 + source_rect.width * crop.x,
        source_rect.y0 + source_rect.height * crop.y,
        source_rect.x0 + source_rect.width * (crop.x + crop.width),
        source_rect.y0 + source_rect.height * (crop.y + crop.height),
    )


def raster_stream_for_panel(panel: ComposerPanel) -> bytes:
    with Image.open(panel.file_path) as image:
        rgba = image.convert("RGBA")
        cropped = crop_image(rgba, panel.crop_rect)
        output = BytesIO()
        cropped.save(output, format="PNG")
        return output.getvalue()


def draw_text_pdf_with_oc(page: fitz.Page, text: ComposerText, oc_xref: int) -> None:
    text_length = fitz.get_text_length(text.text, fontname="helv", fontsize=text.font_size_pt)
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


def clean_layer_fragment(value: str | None, fallback: str) -> str:
    normalized = " ".join((value or "").split())
    if not normalized:
        return fallback
    return normalized[:72]


def panel_layer_name(project: ComposerProject, panel: ComposerPanel) -> str:
    if panel.kind == "graph":
        label = panel_label_text(project, panel)
        suffix = f" [{label}]" if label else ""
        return f"Graph/{panel.id}{suffix}"
    prefix = "Structure Asset" if panel.slot_id else "Asset"
    leaf = clean_layer_fragment(panel.label or Path(panel.file_path).name, panel.id)
    return f"{prefix}/{panel.id} {leaf}"


def text_layer_name(text: ComposerText) -> str:
    prefix = "Structure Text" if text.slot_id else "Text"
    snippet = clean_layer_fragment(text.text, text.id)
    return f"{prefix}/{text.id} {snippet}"


def ensure_ocg(document: fitz.Document, cache: dict[str, int], name: str) -> int:
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

    for kind, drawable in sorted_drawables(normalized):
        if kind == "panel":
            panel = cast(ComposerPanel, drawable)
            if panel.hidden:
                continue
            panel_ocg = ensure_ocg(document, ocg_cache, panel_layer_name(normalized, panel))
            target_rect = fitz.Rect(
                mm_to_pt(panel.x_mm),
                mm_to_pt(panel.y_mm),
                mm_to_pt(panel.x_mm + panel.w_mm),
                mm_to_pt(panel.y_mm + panel.h_mm),
            )
            if is_pdf_path(panel.file_path):
                source_document = fitz.open(panel.file_path)
                try:
                    source_page = source_document.load_page(panel.page_index)
                    page.show_pdf_page(
                        target_rect,
                        source_document,
                        panel.page_index,
                        clip=pdf_clip_rect(panel, source_page.rect),
                        keep_proportion=False,
                        oc=panel_ocg,
                        overlay=True,
                    )
                finally:
                    source_document.close()
            elif is_raster_path(panel.file_path):
                page.insert_image(
                    target_rect,
                    stream=raster_stream_for_panel(panel),
                    keep_proportion=False,
                    oc=panel_ocg,
                    overlay=True,
                )
            else:
                raise ValueError(f"Unsupported panel asset type: {panel.file_path}")

            if normalized.auto_labels and panel.kind == "graph":
                label = panel_label_text(normalized, panel)
                if label:
                    draw_text_pdf_with_oc(
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
            text_ocg = ensure_ocg(document, ocg_cache, text_layer_name(text))
            draw_text_pdf_with_oc(page, text, text_ocg)

    document.save(output)
    document.close()
    return output


__all__ = [
    "clean_layer_fragment",
    "compose_export_pdf",
    "draw_text_pdf_with_oc",
    "ensure_ocg",
    "panel_layer_name",
    "pdf_clip_rect",
    "raster_stream_for_panel",
    "text_layer_name",
]
