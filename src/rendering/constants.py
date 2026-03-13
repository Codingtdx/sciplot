from __future__ import annotations

from pathlib import Path

from src import plot_style
from src.plot_contract import (
    default_size_for_template,
    palette_names,
    size_names,
    template_names,
)

WORKSPACE_OUTPUT_DIR = Path("figures") / "debug_outputs"

TEMPLATE_CHOICES = template_names()
SIZE_CHOICES = size_names()
STYLE_PRESET_CHOICES = plot_style.list_public_style_presets()
PALETTE_PRESET_CHOICES = palette_names()
DEFAULT_SIZE_BY_TEMPLATE: dict[str, str] = {
    name: default_size_for_template(name)
    for name in TEMPLATE_CHOICES
}
LEGACY_TEMPLATE_HINTS = {
    "box_bar_plots": "请改用 `bar` 或 `box`，需要时再用 `violin`。",
    "frequency_sweep": "请改用 `point_line`。",
    "temperature_sweep": "请改用 `point_line`。",
    "stress_relaxation": "请改用 `point_line`。",
    "tensile_curve": "请改用 `curve` 或 `point_line`。",
    "ftir": "请改用 `stacked_curve`。",
    "nmr": "请改用 `stacked_curve`。",
    "wide_nmr": "请改用 `segmented_stacked_curve`。",
    "xrd": "请改用 `stacked_curve`。",
    "dsc": "请改用 `stacked_curve`。",
    "tga": "请改用 `curve`。",
    "dma": "请改用 `curve`。",
}

FREQUENCY_OUTPUTS = {
    "storage_modulus": "freq_storage_modulus.pdf",
    "loss_modulus": "freq_loss_modulus.pdf",
    "loss_factor": "freq_loss_factor.pdf",
    "complex_viscosity": "freq_complex_viscosity.pdf",
}
TEMPERATURE_OUTPUTS = {
    "storage_modulus": "temp_storage_modulus.pdf",
    "complex_viscosity": "temp_complex_viscosity.pdf",
}
