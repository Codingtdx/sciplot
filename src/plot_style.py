from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from src import mpl_backend  # noqa: F401
import matplotlib.pyplot as plt
from matplotlib.figure import Figure
import scienceplots  # noqa: F401
import seaborn as sns


MM_TO_INCH = 1 / 25.4
PANEL_WIDTH_MM = 60
PANEL_HEIGHT_MM = 55

# Keep a single physical axis frame across panel types so exported figures align
# cleanly when compared side-by-side or composed into a board.
LEFT_MARGIN_MM = 14.0
RIGHT_MARGIN_MM = 4.5
BOTTOM_MARGIN_MM = 11.0
TOP_MARGIN_MM = 5.5

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

DEFAULT_STYLE_PRESET = "default"
DEFAULT_PALETTE_PRESET = "colorblind_safe"
STYLE_PRESET_ALIASES = {
    "lab_default": "default",
}


@dataclass(frozen=True)
class TypographySpec:
    font_family: tuple[str, ...]
    font_size_pt: float
    legend_font_size_pt: float
    panel_label_size_pt: float
    panel_label_weight: str


@dataclass(frozen=True)
class StrokeSpec:
    axis_linewidth_pt: float
    tick_width_pt: float
    tick_length_pt: float
    minor_tick_width_pt: float
    minor_tick_length_pt: float
    line_width_pt: float
    line_alpha: float
    marker_alpha: float
    fill_alpha: float
    max_fill_alpha: float
    marker_size_pt: float


@dataclass(frozen=True)
class SpacingSpec:
    panel_width_mm: float
    panel_height_mm: float
    left_margin_mm: float
    right_margin_mm: float
    bottom_margin_mm: float
    top_margin_mm: float
    axes_labelpad: float
    xtick_major_pad: float
    ytick_major_pad: float
    legend_inset_fraction: float


@dataclass(frozen=True)
class AnnotationSpec:
    legend_frameon: bool
    legend_tightness: str
    label_tightness: str


@dataclass(frozen=True)
class ExportSpec:
    figure_dpi: int
    savefig_dpi: int
    savefig_format: str
    pdf_fonttype: int
    ps_fonttype: int
    color_space: str
    vector_preferred: bool
    accessibility_note: str


@dataclass(frozen=True)
class JournalStyleSpec:
    name: str
    description: str
    hard_constraints: bool
    preset_note: str
    typography: TypographySpec
    stroke: StrokeSpec
    spacing: SpacingSpec
    annotation: AnnotationSpec
    export: ExportSpec


@dataclass(frozen=True)
class PaletteSpec:
    name: str
    description: str
    categorical: tuple[str, ...]
    sequential: str
    diverging: str


def mm_to_inch(value_mm: float) -> float:
    return value_mm * MM_TO_INCH


def _margin_fraction(total_mm: float, edge_mm: float) -> float:
    return edge_mm / total_mm


def _hex_palette(name: str, n_colors: int = 10) -> tuple[str, ...]:
    return tuple(sns.color_palette(name, n_colors=n_colors).as_hex())


_BASE_TYPOGRAPHY = TypographySpec(
    font_family=("Arial", "Helvetica", "DejaVu Sans"),
    font_size_pt=FONT_SIZE_PT,
    legend_font_size_pt=6.0,
    panel_label_size_pt=8.0,
    panel_label_weight="bold",
)
_BASE_STROKE = StrokeSpec(
    axis_linewidth_pt=AXIS_LINEWIDTH_PT,
    tick_width_pt=TICK_WIDTH_PT,
    tick_length_pt=TICK_LENGTH_PT,
    minor_tick_width_pt=MINOR_TICK_WIDTH_PT,
    minor_tick_length_pt=MINOR_TICK_LENGTH_PT,
    line_width_pt=LINE_WIDTH_PT,
    line_alpha=LINE_ALPHA,
    marker_alpha=MARKER_ALPHA,
    fill_alpha=FILL_ALPHA,
    max_fill_alpha=MAX_FILL_ALPHA,
    marker_size_pt=3.8,
)
_BASE_SPACING = SpacingSpec(
    panel_width_mm=PANEL_WIDTH_MM,
    panel_height_mm=PANEL_HEIGHT_MM,
    left_margin_mm=LEFT_MARGIN_MM,
    right_margin_mm=RIGHT_MARGIN_MM,
    bottom_margin_mm=BOTTOM_MARGIN_MM,
    top_margin_mm=TOP_MARGIN_MM,
    axes_labelpad=2.0,
    xtick_major_pad=1.5,
    ytick_major_pad=1.5,
    legend_inset_fraction=0.025,
)
_BASE_ANNOTATION = AnnotationSpec(
    legend_frameon=False,
    legend_tightness="balanced",
    label_tightness="balanced",
)
_BASE_EXPORT = ExportSpec(
    figure_dpi=150,
    savefig_dpi=300,
    savefig_format="pdf",
    pdf_fonttype=42,
    ps_fonttype=42,
    color_space="RGB",
    vector_preferred=True,
    accessibility_note="Avoid red-green collisions and rainbow scales when possible.",
)


STYLE_PRESETS: dict[str, JournalStyleSpec] = {
    "default": JournalStyleSpec(
        name="default",
        description="默认：沿用当前最稳的 60 mm 面板风格。",
        hard_constraints=False,
        preset_note="当前默认科研风格，优先稳定性和可用性。",
        typography=_BASE_TYPOGRAPHY,
        stroke=_BASE_STROKE,
        spacing=_BASE_SPACING,
        annotation=_BASE_ANNOTATION,
        export=_BASE_EXPORT,
    ),
    "nature": JournalStyleSpec(
        name="nature",
        description="Nature：官方约束优先的紧凑科研图风格。",
        hard_constraints=True,
        preset_note="基于 Nature 当前公开图像规范的硬约束实现。",
        typography=TypographySpec(
            font_family=("Arial", "Helvetica", "DejaVu Sans"),
            font_size_pt=6.5,
            legend_font_size_pt=5.8,
            panel_label_size_pt=8.0,
            panel_label_weight="bold",
        ),
        stroke=StrokeSpec(
            axis_linewidth_pt=1.0,
            tick_width_pt=1.0,
            tick_length_pt=3.4,
            minor_tick_width_pt=0.8,
            minor_tick_length_pt=2.0,
            line_width_pt=1.2,
            line_alpha=0.92,
            marker_alpha=0.95,
            fill_alpha=0.34,
            max_fill_alpha=0.45,
            marker_size_pt=3.4,
        ),
        spacing=SpacingSpec(
            panel_width_mm=PANEL_WIDTH_MM,
            panel_height_mm=PANEL_HEIGHT_MM,
            left_margin_mm=LEFT_MARGIN_MM,
            right_margin_mm=RIGHT_MARGIN_MM,
            bottom_margin_mm=BOTTOM_MARGIN_MM,
            top_margin_mm=TOP_MARGIN_MM,
            axes_labelpad=2.0,
            xtick_major_pad=1.4,
            ytick_major_pad=1.4,
            legend_inset_fraction=0.025,
        ),
        annotation=AnnotationSpec(
            legend_frameon=False,
            legend_tightness="tight",
            label_tightness="tight",
        ),
        export=ExportSpec(
            figure_dpi=150,
            savefig_dpi=300,
            savefig_format="pdf",
            pdf_fonttype=42,
            ps_fonttype=42,
            color_space="RGB",
            vector_preferred=True,
            accessibility_note="Sans-serif, 5-7 pt text, RGB, vector PDF, avoid red-green conflicts.",
        ),
    ),
    "science_editorial": JournalStyleSpec(
        name="science_editorial",
        description="Science：更克制、注释更少、观感更开阔。",
        hard_constraints=False,
        preset_note="软风格 preset，抽象自 Science 常见编辑风格，不是投稿合规保证。",
        typography=TypographySpec(
            font_family=("Arial", "Helvetica Neue", "Helvetica", "DejaVu Sans"),
            font_size_pt=7.0,
            legend_font_size_pt=6.0,
            panel_label_size_pt=8.0,
            panel_label_weight="bold",
        ),
        stroke=StrokeSpec(
            axis_linewidth_pt=0.95,
            tick_width_pt=0.95,
            tick_length_pt=3.2,
            minor_tick_width_pt=0.75,
            minor_tick_length_pt=1.9,
            line_width_pt=1.15,
            line_alpha=0.88,
            marker_alpha=0.92,
            fill_alpha=0.30,
            max_fill_alpha=0.42,
            marker_size_pt=3.5,
        ),
        spacing=SpacingSpec(
            panel_width_mm=PANEL_WIDTH_MM,
            panel_height_mm=PANEL_HEIGHT_MM,
            left_margin_mm=LEFT_MARGIN_MM,
            right_margin_mm=RIGHT_MARGIN_MM,
            bottom_margin_mm=BOTTOM_MARGIN_MM,
            top_margin_mm=TOP_MARGIN_MM,
            axes_labelpad=2.4,
            xtick_major_pad=1.8,
            ytick_major_pad=1.8,
            legend_inset_fraction=0.024,
        ),
        annotation=AnnotationSpec(
            legend_frameon=False,
            legend_tightness="airy",
            label_tightness="balanced",
        ),
        export=_BASE_EXPORT,
    ),
    "jacs_analytical": JournalStyleSpec(
        name="jacs_analytical",
        description="JACS：更紧凑、分析图观感更硬朗。",
        hard_constraints=False,
        preset_note="软风格 preset，抽象自 ACS/JACS 常见分析图语言，不是投稿合规保证。",
        typography=TypographySpec(
            font_family=("Arial", "Helvetica", "DejaVu Sans"),
            font_size_pt=6.8,
            legend_font_size_pt=5.9,
            panel_label_size_pt=8.0,
            panel_label_weight="bold",
        ),
        stroke=StrokeSpec(
            axis_linewidth_pt=1.05,
            tick_width_pt=1.05,
            tick_length_pt=3.5,
            minor_tick_width_pt=0.85,
            minor_tick_length_pt=2.0,
            line_width_pt=1.4,
            line_alpha=0.86,
            marker_alpha=0.95,
            fill_alpha=0.28,
            max_fill_alpha=0.40,
            marker_size_pt=3.6,
        ),
        spacing=SpacingSpec(
            panel_width_mm=PANEL_WIDTH_MM,
            panel_height_mm=PANEL_HEIGHT_MM,
            left_margin_mm=LEFT_MARGIN_MM,
            right_margin_mm=RIGHT_MARGIN_MM,
            bottom_margin_mm=BOTTOM_MARGIN_MM,
            top_margin_mm=TOP_MARGIN_MM,
            axes_labelpad=1.8,
            xtick_major_pad=1.4,
            ytick_major_pad=1.4,
            legend_inset_fraction=0.022,
        ),
        annotation=AnnotationSpec(
            legend_frameon=False,
            legend_tightness="tight",
            label_tightness="tight",
        ),
        export=_BASE_EXPORT,
    ),
    "advanced_materials_spacious": JournalStyleSpec(
        name="advanced_materials_spacious",
        description="Advanced Materials：留白更宽、展示感更强。",
        hard_constraints=False,
        preset_note="软风格 preset，抽象自 Advanced Materials 常见版面语言，不是投稿合规保证。",
        typography=TypographySpec(
            font_family=("Arial", "Helvetica Neue", "Helvetica", "DejaVu Sans"),
            font_size_pt=7.0,
            legend_font_size_pt=6.2,
            panel_label_size_pt=8.0,
            panel_label_weight="bold",
        ),
        stroke=StrokeSpec(
            axis_linewidth_pt=0.95,
            tick_width_pt=0.95,
            tick_length_pt=3.2,
            minor_tick_width_pt=0.75,
            minor_tick_length_pt=1.9,
            line_width_pt=1.18,
            line_alpha=0.90,
            marker_alpha=0.96,
            fill_alpha=0.33,
            max_fill_alpha=0.44,
            marker_size_pt=3.8,
        ),
        spacing=SpacingSpec(
            panel_width_mm=PANEL_WIDTH_MM,
            panel_height_mm=PANEL_HEIGHT_MM,
            left_margin_mm=LEFT_MARGIN_MM,
            right_margin_mm=RIGHT_MARGIN_MM,
            bottom_margin_mm=BOTTOM_MARGIN_MM,
            top_margin_mm=TOP_MARGIN_MM,
            axes_labelpad=2.6,
            xtick_major_pad=1.8,
            ytick_major_pad=1.8,
            legend_inset_fraction=0.026,
        ),
        annotation=AnnotationSpec(
            legend_frameon=False,
            legend_tightness="airy",
            label_tightness="airy",
        ),
        export=_BASE_EXPORT,
    ),
}


PALETTE_PRESETS: dict[str, PaletteSpec] = {
    "colorblind_safe": PaletteSpec(
        name="colorblind_safe",
        description="默认安全配色：分类色用 colorblind，连续色用 cividis。",
        categorical=_hex_palette("colorblind"),
        sequential="cividis",
        diverging="vlag",
    ),
    "deep": PaletteSpec(
        name="deep",
        description="Seaborn deep：平衡、沉稳、通用。",
        categorical=_hex_palette("deep"),
        sequential="crest",
        diverging="vlag",
    ),
    "muted": PaletteSpec(
        name="muted",
        description="Seaborn muted：克制柔和，适合多组对比。",
        categorical=_hex_palette("muted"),
        sequential="rocket",
        diverging="coolwarm",
    ),
    "bright": PaletteSpec(
        name="bright",
        description="Seaborn bright：高饱和、对比更强。",
        categorical=_hex_palette("bright"),
        sequential="mako",
        diverging="icefire",
    ),
    "mono": PaletteSpec(
        name="mono",
        description="灰阶单色：适合硬朗分析图和黑白打印。",
        categorical=("#111827", "#374151", "#6B7280", "#9CA3AF", "#D1D5DB"),
        sequential="Greys",
        diverging="Greys",
    ),
    "okabe_ito": PaletteSpec(
        name="okabe_ito",
        description="Okabe-Ito：经典色盲友好科研配色。",
        categorical=("#000000", "#E69F00", "#56B4E9", "#009E73", "#F0E442", "#0072B2", "#D55E00", "#CC79A7"),
        sequential="cividis",
        diverging="PuOr",
    ),
    "tol_muted": PaletteSpec(
        name="tol_muted",
        description="Paul Tol muted：低刺激、均衡的分类配色。",
        categorical=("#332288", "#88CCEE", "#44AA99", "#117733", "#999933", "#DDCC77", "#CC6677", "#882255", "#AA4499"),
        sequential="YlGnBu",
        diverging="BrBG",
    ),
    "materials_warm": PaletteSpec(
        name="materials_warm",
        description="暖色科研展示配色：更偏材料展示风格。",
        categorical=("#355070", "#6D597A", "#B56576", "#E56B6F", "#EAAC8B", "#F6BD60", "#84A59D"),
        sequential="rocket",
        diverging="Spectral",
    ),
}


_CURRENT_STYLE_PRESET = DEFAULT_STYLE_PRESET
_CURRENT_PALETTE_PRESET = DEFAULT_PALETTE_PRESET


def normalize_style_preset(style_preset: str | None) -> str:
    preset = (style_preset or DEFAULT_STYLE_PRESET).strip()
    return STYLE_PRESET_ALIASES.get(preset, preset)


def get_style_spec(style_preset: str | None = None) -> JournalStyleSpec:
    preset = normalize_style_preset(style_preset or _CURRENT_STYLE_PRESET)
    try:
        return STYLE_PRESETS[preset]
    except KeyError as exc:
        raise ValueError(f"Unknown style preset: {preset}.") from exc


def get_palette_spec(palette_preset: str | None = None) -> PaletteSpec:
    preset = palette_preset or _CURRENT_PALETTE_PRESET
    try:
        return PALETTE_PRESETS[preset]
    except KeyError as exc:
        raise ValueError(f"Unknown palette preset: {preset}.") from exc


def list_style_presets() -> tuple[str, ...]:
    return tuple(STYLE_PRESETS.keys())


def list_public_style_presets() -> tuple[str, ...]:
    return ("default", "nature")


def list_palette_presets() -> tuple[str, ...]:
    return tuple(PALETTE_PRESETS.keys())


def current_style_preset() -> str:
    return _CURRENT_STYLE_PRESET


def current_palette_preset() -> str:
    return _CURRENT_PALETTE_PRESET


def get_style_description(style_preset: str | None = None) -> str:
    spec = get_style_spec(style_preset)
    return spec.description


def get_palette_description(palette_preset: str | None = None) -> str:
    spec = get_palette_spec(palette_preset)
    return spec.description


def get_style_note(style_preset: str | None = None) -> str:
    spec = get_style_spec(style_preset)
    return spec.preset_note


def get_palette_swatches(palette_preset: str | None = None, limit: int = 6) -> tuple[str, ...]:
    spec = get_palette_spec(palette_preset)
    return spec.categorical[:limit]


def get_categorical_palette(
    palette_preset: str | None = None,
    *,
    n_colors: int | None = None,
) -> list[tuple[float, float, float]]:
    spec = get_palette_spec(palette_preset)
    colors = spec.categorical
    if n_colors is None or n_colors <= len(colors):
        return sns.color_palette(colors, n_colors=n_colors)
    return sns.color_palette(colors, n_colors=n_colors)


def get_sequential_cmap(palette_preset: str | None = None) -> str:
    return get_palette_spec(palette_preset).sequential


def get_diverging_cmap(palette_preset: str | None = None) -> str:
    return get_palette_spec(palette_preset).diverging


def current_spacing() -> SpacingSpec:
    return get_style_spec().spacing


def current_stroke() -> StrokeSpec:
    return get_style_spec().stroke


def current_typography() -> TypographySpec:
    return get_style_spec().typography


def apply_style(
    style_preset: str = DEFAULT_STYLE_PRESET,
    palette_preset: str = DEFAULT_PALETTE_PRESET,
) -> None:
    global _CURRENT_STYLE_PRESET, _CURRENT_PALETTE_PRESET

    normalized_style = normalize_style_preset(style_preset)
    style_spec = get_style_spec(normalized_style)
    palette_spec = get_palette_spec(palette_preset)

    _CURRENT_STYLE_PRESET = normalized_style
    _CURRENT_PALETTE_PRESET = palette_preset

    plt.style.use(["science", "nature", "no-latex"])
    sns.set_theme(
        context="paper",
        style="ticks",
        palette=palette_spec.categorical,
        rc={
            "figure.dpi": style_spec.export.figure_dpi,
            "savefig.dpi": style_spec.export.savefig_dpi,
            "savefig.format": style_spec.export.savefig_format,
            "savefig.bbox": None,
            "pdf.fonttype": style_spec.export.pdf_fonttype,
            "ps.fonttype": style_spec.export.ps_fonttype,
            "font.family": "sans-serif",
            "font.sans-serif": list(style_spec.typography.font_family),
            "mathtext.fontset": "custom",
            "mathtext.default": "regular",
            "mathtext.rm": "Arial",
            "mathtext.it": "Arial:italic",
            "mathtext.bf": "Arial:bold",
            "mathtext.sf": "Arial",
            "font.size": style_spec.typography.font_size_pt,
            "axes.labelsize": style_spec.typography.font_size_pt,
            "axes.titlesize": style_spec.typography.font_size_pt,
            "axes.labelpad": style_spec.spacing.axes_labelpad,
            "xtick.labelsize": style_spec.typography.font_size_pt,
            "ytick.labelsize": style_spec.typography.font_size_pt,
            "xtick.major.pad": style_spec.spacing.xtick_major_pad,
            "ytick.major.pad": style_spec.spacing.ytick_major_pad,
            "legend.fontsize": style_spec.typography.legend_font_size_pt,
            "axes.labelweight": "normal",
            "axes.titleweight": "normal",
            "axes.linewidth": style_spec.stroke.axis_linewidth_pt,
            "axes.spines.top": False,
            "axes.spines.right": False,
            "xtick.direction": "out",
            "ytick.direction": "out",
            "xtick.major.width": style_spec.stroke.tick_width_pt,
            "ytick.major.width": style_spec.stroke.tick_width_pt,
            "xtick.major.size": style_spec.stroke.tick_length_pt,
            "ytick.major.size": style_spec.stroke.tick_length_pt,
            "xtick.minor.width": style_spec.stroke.minor_tick_width_pt,
            "ytick.minor.width": style_spec.stroke.minor_tick_width_pt,
            "xtick.minor.size": style_spec.stroke.minor_tick_length_pt,
            "ytick.minor.size": style_spec.stroke.minor_tick_length_pt,
            "lines.linewidth": style_spec.stroke.line_width_pt,
            "lines.markersize": style_spec.stroke.marker_size_pt,
            "legend.frameon": style_spec.annotation.legend_frameon,
        },
    )


def use_nature_style() -> None:
    apply_style("nature", DEFAULT_PALETTE_PRESET)


def create_panel_figure(
    width_mm: float | None = None,
    height_mm: float | None = None,
    *,
    left_margin_mm: float | None = None,
    right_margin_mm: float | None = None,
    bottom_margin_mm: float | None = None,
    top_margin_mm: float | None = None,
) -> tuple[Figure, plt.Axes]:
    spacing = current_spacing()
    panel_width_mm = spacing.panel_width_mm if width_mm is None else width_mm
    panel_height_mm = spacing.panel_height_mm if height_mm is None else height_mm
    left_mm = spacing.left_margin_mm if left_margin_mm is None else left_margin_mm
    right_mm = spacing.right_margin_mm if right_margin_mm is None else right_margin_mm
    bottom_mm = spacing.bottom_margin_mm if bottom_margin_mm is None else bottom_margin_mm
    top_mm = spacing.top_margin_mm if top_margin_mm is None else top_margin_mm

    fig, ax = plt.subplots(
        figsize=(mm_to_inch(panel_width_mm), mm_to_inch(panel_height_mm)),
        constrained_layout=False,
    )
    fig.subplots_adjust(
        left=_margin_fraction(panel_width_mm, left_mm),
        right=1 - _margin_fraction(panel_width_mm, right_mm),
        bottom=_margin_fraction(panel_height_mm, bottom_mm),
        top=1 - _margin_fraction(panel_height_mm, top_mm),
    )
    return fig, ax


def save_pdf(fig: plt.Figure, output_path: str | Path) -> Path:
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(path, format="pdf", bbox_inches=None, pad_inches=0.0)
    return path


apply_style(DEFAULT_STYLE_PRESET, DEFAULT_PALETTE_PRESET)
