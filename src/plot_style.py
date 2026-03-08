from __future__ import annotations

from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.figure import Figure
import seaborn as sns
import scienceplots  # noqa: F401

MM_TO_INCH = 1 / 25.4
PANEL_WIDTH_MM = 60
PANEL_HEIGHT_MM = 55

LEFT_MARGIN_MM = 11.5
RIGHT_MARGIN_MM = 3.5
BOTTOM_MARGIN_MM = 10.5
TOP_MARGIN_MM = 4.5

FONT_SIZE_PT = 7
AXIS_LINEWIDTH_PT = 1.0
TICK_WIDTH_PT = 1.0
TICK_LENGTH_PT = 3.5
MINOR_TICK_WIDTH_PT = 0.8
MINOR_TICK_LENGTH_PT = 2.0
LINE_WIDTH_PT = 1.3
LINE_ALPHA = 0.70
MARKER_ALPHA = 0.80
FILL_ALPHA = 0.40
MAX_FILL_ALPHA = 0.50


def mm_to_inch(value_mm: float) -> float:
    return value_mm * MM_TO_INCH


def _margin_fraction(total_mm: float, edge_mm: float) -> float:
    return edge_mm / total_mm


def use_nature_style() -> None:
    """Apply a Nature-like style tuned for 60 mm-wide panels."""
    plt.style.use(["science", "nature", "no-latex"])
    sns.set_theme(
        context="paper",
        style="ticks",
        palette="colorblind",
        rc={
            "figure.dpi": 150,
            "savefig.dpi": 300,
            "savefig.format": "pdf",
            "savefig.bbox": None,
            "pdf.fonttype": 42,
            "ps.fonttype": 42,
            "font.family": "sans-serif",
            "font.sans-serif": ["Arial", "Helvetica", "DejaVu Sans"],
            "mathtext.fontset": "custom",
            "mathtext.default": "regular",
            "mathtext.rm": "Arial",
            "mathtext.it": "Arial:italic",
            "mathtext.bf": "Arial:bold",
            "mathtext.sf": "Arial",
            "font.size": FONT_SIZE_PT,
            "axes.labelsize": FONT_SIZE_PT,
            "axes.titlesize": FONT_SIZE_PT,
            "axes.labelpad": 2.0,
            "xtick.labelsize": FONT_SIZE_PT,
            "ytick.labelsize": FONT_SIZE_PT,
            "xtick.major.pad": 1.5,
            "ytick.major.pad": 1.5,
            "legend.fontsize": 6,
            "axes.labelweight": "normal",
            "axes.titleweight": "normal",
            "axes.linewidth": AXIS_LINEWIDTH_PT,
            "axes.spines.top": False,
            "axes.spines.right": False,
            "xtick.direction": "out",
            "ytick.direction": "out",
            "xtick.major.width": TICK_WIDTH_PT,
            "ytick.major.width": TICK_WIDTH_PT,
            "xtick.major.size": TICK_LENGTH_PT,
            "ytick.major.size": TICK_LENGTH_PT,
            "xtick.minor.width": MINOR_TICK_WIDTH_PT,
            "ytick.minor.width": MINOR_TICK_WIDTH_PT,
            "xtick.minor.size": MINOR_TICK_LENGTH_PT,
            "ytick.minor.size": MINOR_TICK_LENGTH_PT,
            "lines.linewidth": LINE_WIDTH_PT,
            "lines.markersize": 3.8,
            "legend.frameon": False,
        },
    )


def create_panel_figure(
    width_mm: float = PANEL_WIDTH_MM,
    height_mm: float = PANEL_HEIGHT_MM,
    *,
    left_margin_mm: float = LEFT_MARGIN_MM,
    right_margin_mm: float = RIGHT_MARGIN_MM,
    bottom_margin_mm: float = BOTTOM_MARGIN_MM,
    top_margin_mm: float = TOP_MARGIN_MM,
) -> tuple[Figure, plt.Axes]:
    """Create a 60x55 mm panel with a slightly rectangular internal plotting layer."""
    fig, ax = plt.subplots(
        figsize=(mm_to_inch(width_mm), mm_to_inch(height_mm)),
        constrained_layout=False,
    )
    fig.subplots_adjust(
        left=_margin_fraction(width_mm, left_margin_mm),
        right=1 - _margin_fraction(width_mm, right_margin_mm),
        bottom=_margin_fraction(height_mm, bottom_margin_mm),
        top=1 - _margin_fraction(height_mm, top_margin_mm),
    )
    return fig, ax


def save_pdf(fig: plt.Figure, output_path: str | Path) -> Path:
    """Save a figure as PDF while preserving the configured panel size."""
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(path, format="pdf", bbox_inches=None, pad_inches=0.0)
    return path
