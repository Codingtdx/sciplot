from __future__ import annotations

from pathlib import Path

import fitz
from PIL import Image

from src.composer_types import RASTER_EXTENSIONS


def is_pdf_path(file_path: str | Path) -> bool:
    return Path(file_path).suffix.lower() == ".pdf"


def is_raster_path(file_path: str | Path) -> bool:
    return Path(file_path).suffix.lower() in RASTER_EXTENSIONS


def pdf_page_size_pt(file_path: str | Path, page_index: int = 0) -> tuple[float, float]:
    document = fitz.open(str(file_path))
    try:
        page = document.load_page(page_index)
        return float(page.rect.width), float(page.rect.height)
    finally:
        document.close()


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
    if is_pdf_path(file_path):
        return pdf_page_aspect_ratio(file_path, page_index)
    if is_raster_path(file_path):
        return image_aspect_ratio(file_path)
    raise ValueError(f"Unsupported panel asset type: {file_path}")


__all__ = [
    "image_aspect_ratio",
    "is_pdf_path",
    "is_raster_path",
    "panel_aspect_ratio",
    "pdf_page_aspect_ratio",
    "pdf_page_size_pt",
]
