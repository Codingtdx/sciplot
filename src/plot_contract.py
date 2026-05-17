from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any

CONTRACT_PATH = Path(__file__).with_name("plot_contract.json")
DOC_PATH = Path(__file__).resolve().parents[1] / "docs" / "plot_contract.md"


@dataclass(frozen=True)
class DefaultsSpec:
    style_preset: str
    palette_preset: str


@dataclass(frozen=True)
class GlobalFrameSpec:
    panel_width_mm: float
    panel_height_mm: float
    left_margin_mm: float
    right_margin_mm: float
    bottom_margin_mm: float
    top_margin_mm: float


@dataclass(frozen=True)
class AxisPolicySpec:
    linear_nice_steps: tuple[float, ...]
    linear_outer_padding_fraction: float
    linear_force_visible_labeled_endpoints: bool
    log_display_steps: tuple[float, ...]
    log_label_mode: str
    log_allow_unlabeled_outer_padding: bool
    bar_zero_baseline_no_lower_padding: bool
    tensile_y_include_zero: bool
    stacked_x_use_standard_endpoint_policy: bool


@dataclass(frozen=True)
class SizePresetSpec:
    label: str
    width_mm: float
    height_mm: float


@dataclass(frozen=True)
class TypographyContract:
    font_family: tuple[str, ...]
    font_size_pt: float
    legend_font_size_pt: float
    panel_label_size_pt: float
    panel_label_weight: str


@dataclass(frozen=True)
class StrokeContract:
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
class SpacingContract:
    axes_labelpad: float
    xtick_major_pad: float
    ytick_major_pad: float
    legend_inset_fraction: float


@dataclass(frozen=True)
class AnnotationContract:
    legend_frameon: bool
    legend_tightness: str
    label_tightness: str


@dataclass(frozen=True)
class AxisFrameContract:
    left: bool
    bottom: bool
    top: bool
    right: bool


@dataclass(frozen=True)
class ExportContract:
    figure_dpi: int
    savefig_dpi: int
    savefig_format: str
    pdf_fonttype: int
    ps_fonttype: int
    color_space: str
    vector_preferred: bool
    accessibility_note: str


@dataclass(frozen=True)
class StyleContract:
    label: str
    public: bool
    display_group: str
    description: str
    hard_constraints: bool
    preset_note: str
    recommended_palette_preset: str
    recommended_visual_theme_id: str | None
    typography: TypographyContract
    stroke: StrokeContract
    spacing: SpacingContract
    annotation: AnnotationContract
    axis_frame: AxisFrameContract
    export: ExportContract


@dataclass(frozen=True)
class PaletteContract:
    label: str
    public: bool
    description: str
    categorical: tuple[str, ...]
    sequential: str
    diverging: str


@dataclass(frozen=True)
class TemplateContract:
    label: str
    description: str
    category: str
    presentation_kind: str
    default_size: str
    allowed_sizes: tuple[str, ...]
    editable_options: tuple[str, ...]
    default_options: dict[str, Any]
    available_styles: tuple[str, ...]
    available_palettes: tuple[str, ...]
    hard_rules: tuple[str, ...]
    soft_rules: tuple[str, ...]


@dataclass(frozen=True)
class ValidationRuleContract:
    label: str
    description: str
    severity: str
    tolerance_mm: float | None = None


@dataclass(frozen=True)
class PlotContract:
    version: int
    defaults: DefaultsSpec
    style_aliases: dict[str, str]
    global_frame: GlobalFrameSpec
    axis_policy: AxisPolicySpec
    size_presets: dict[str, SizePresetSpec]
    special_layouts: dict[str, dict[str, Any]]
    qa_profiles: dict[str, dict[str, Any]]
    styles: dict[str, StyleContract]
    palettes: dict[str, PaletteContract]
    templates: dict[str, TemplateContract]
    validation_rules: dict[str, ValidationRuleContract]


def _tuple_of_strings(values: list[str] | tuple[str, ...]) -> tuple[str, ...]:
    return tuple(str(value) for value in values)


def _load_raw_contract() -> dict[str, Any]:
    return json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))


@lru_cache(maxsize=1)
def load_plot_contract() -> PlotContract:
    raw = _load_raw_contract()
    return PlotContract(
        version=int(raw["version"]),
        defaults=DefaultsSpec(**raw["defaults"]),
        style_aliases=dict(raw.get("aliases", {}).get("style_presets", {})),
        global_frame=GlobalFrameSpec(**raw["global_frame"]),
        axis_policy=AxisPolicySpec(
            linear_nice_steps=tuple(float(value) for value in raw["axis_policy"]["linear_nice_steps"]),
            linear_outer_padding_fraction=float(raw["axis_policy"]["linear_outer_padding_fraction"]),
            linear_force_visible_labeled_endpoints=bool(
                raw["axis_policy"]["linear_force_visible_labeled_endpoints"]
            ),
            log_display_steps=tuple(float(value) for value in raw["axis_policy"]["log_display_steps"]),
            log_label_mode=str(raw["axis_policy"]["log_label_mode"]),
            log_allow_unlabeled_outer_padding=bool(raw["axis_policy"]["log_allow_unlabeled_outer_padding"]),
            bar_zero_baseline_no_lower_padding=bool(raw["axis_policy"]["bar_zero_baseline_no_lower_padding"]),
            tensile_y_include_zero=bool(raw["axis_policy"]["tensile_y_include_zero"]),
            stacked_x_use_standard_endpoint_policy=bool(raw["axis_policy"]["stacked_x_use_standard_endpoint_policy"]),
        ),
        size_presets={
            key: SizePresetSpec(**value)
            for key, value in raw["size_presets"].items()
        },
        special_layouts={
            key: dict(value)
            for key, value in raw.get("special_layouts", {}).items()
        },
        qa_profiles={
            key: dict(value)
            for key, value in raw.get("qa_profiles", {}).items()
        },
        styles={
            key: StyleContract(
                label=value["label"],
                public=bool(value["public"]),
                display_group=str(value.get("display_group", "publication")),
                description=value["description"],
                hard_constraints=bool(value["hard_constraints"]),
                preset_note=value["preset_note"],
                recommended_palette_preset=value["recommended_palette_preset"],
                recommended_visual_theme_id=value.get("recommended_visual_theme_id"),
                typography=TypographyContract(
                    font_family=_tuple_of_strings(value["typography"]["font_family"]),
                    font_size_pt=float(value["typography"]["font_size_pt"]),
                    legend_font_size_pt=float(value["typography"]["legend_font_size_pt"]),
                    panel_label_size_pt=float(value["typography"]["panel_label_size_pt"]),
                    panel_label_weight=value["typography"]["panel_label_weight"],
                ),
                stroke=StrokeContract(**value["stroke"]),
                spacing=SpacingContract(**value["spacing"]),
                annotation=AnnotationContract(**value["annotation"]),
                axis_frame=AxisFrameContract(**value["axis_frame"]),
                export=ExportContract(**value["export"]),
            )
            for key, value in raw["styles"].items()
        },
        palettes={
            key: PaletteContract(
                label=value["label"],
                public=bool(value["public"]),
                description=value["description"],
                categorical=_tuple_of_strings(value["categorical"]),
                sequential=value["sequential"],
                diverging=value["diverging"],
            )
            for key, value in raw["palettes"].items()
        },
        templates={
            key: TemplateContract(
                label=value["label"],
                description=value["description"],
                category=value["category"],
                presentation_kind=value["presentation_kind"],
                default_size=value["default_size"],
                allowed_sizes=_tuple_of_strings(value["allowed_sizes"]),
                editable_options=_tuple_of_strings(value["editable_options"]),
                default_options=dict(value.get("default_options", {})),
                available_styles=_tuple_of_strings(value["available_styles"]),
                available_palettes=_tuple_of_strings(value["available_palettes"]),
                hard_rules=_tuple_of_strings(value["hard_rules"]),
                soft_rules=_tuple_of_strings(value["soft_rules"]),
            )
            for key, value in raw["templates"].items()
        },
        validation_rules={
            key: ValidationRuleContract(
                label=value["label"],
                description=value["description"],
                severity=value["severity"],
                tolerance_mm=float(value["tolerance_mm"])
                if value.get("tolerance_mm") is not None
                else None,
            )
            for key, value in raw["validation_rules"].items()
        },
    )


def plot_contract_dict(*, public_only: bool = False) -> dict[str, Any]:
    contract = load_plot_contract()
    data = {
        "version": contract.version,
        "defaults": asdict(contract.defaults),
        "aliases": {"style_presets": dict(contract.style_aliases)},
        "global_frame": asdict(contract.global_frame),
        "axis_policy": asdict(contract.axis_policy),
        "size_presets": {key: asdict(value) for key, value in contract.size_presets.items()},
        "special_layouts": contract.special_layouts,
        "qa_profiles": contract.qa_profiles,
        "styles": {
            key: {
                **asdict(value),
                "typography": asdict(value.typography),
                "stroke": asdict(value.stroke),
                "spacing": asdict(value.spacing),
                "annotation": asdict(value.annotation),
                "export": asdict(value.export),
            }
            for key, value in contract.styles.items()
            if not public_only or value.public
        },
        "palettes": {
            key: asdict(value)
            for key, value in contract.palettes.items()
            if not public_only or value.public
        },
        "templates": {
            key: asdict(value)
            for key, value in contract.templates.items()
        },
        "validation_rules": {
            key: asdict(value)
            for key, value in contract.validation_rules.items()
        },
    }
    return data


def template_contract(template: str) -> TemplateContract:
    contract = load_plot_contract()
    try:
        return contract.templates[template]
    except KeyError as exc:
        raise ValueError(f"Unknown template contract: {template}") from exc


def size_preset_contract(size_name: str) -> SizePresetSpec:
    contract = load_plot_contract()
    try:
        return contract.size_presets[size_name]
    except KeyError as exc:
        raise ValueError(f"Unknown size preset: {size_name}") from exc


def validation_rule(rule_name: str) -> ValidationRuleContract:
    contract = load_plot_contract()
    try:
        return contract.validation_rules[rule_name]
    except KeyError as exc:
        raise ValueError(f"Unknown validation rule: {rule_name}") from exc


def qa_profile(profile_name: str) -> dict[str, Any]:
    contract = load_plot_contract()
    try:
        return dict(contract.qa_profiles[profile_name])
    except KeyError as exc:
        raise ValueError(f"Unknown QA profile: {profile_name}") from exc


def public_style_names() -> tuple[str, ...]:
    contract = load_plot_contract()
    return tuple(name for name, spec in contract.styles.items() if spec.public)


def public_palette_names() -> tuple[str, ...]:
    contract = load_plot_contract()
    return tuple(name for name, spec in contract.palettes.items() if spec.public)


def style_names() -> tuple[str, ...]:
    return tuple(load_plot_contract().styles.keys())


def palette_names() -> tuple[str, ...]:
    return tuple(load_plot_contract().palettes.keys())


def template_names() -> tuple[str, ...]:
    return tuple(load_plot_contract().templates.keys())


def size_names() -> tuple[str, ...]:
    return tuple(load_plot_contract().size_presets.keys())


def default_size_for_template(template: str) -> str:
    return template_contract(template).default_size


def default_options_for_template(template: str) -> dict[str, Any]:
    return dict(template_contract(template).default_options)


def style_contract(style_name: str) -> StyleContract:
    contract = load_plot_contract()
    normalized = normalize_style_alias(style_name)
    try:
        return contract.styles[normalized]
    except KeyError as exc:
        raise ValueError(f"Unknown style contract: {style_name}") from exc


def lint_public_template_contract(contract: PlotContract | None = None) -> tuple[str, ...]:
    resolved = contract or load_plot_contract()
    valid_styles = set(public_style_names())
    valid_palettes = set(public_palette_names())
    from src.rendering.themes import visual_theme_ids

    valid_theme_ids = set(visual_theme_ids())
    issues: list[str] = []

    for template_id, spec in resolved.templates.items():
        defaults = dict(spec.default_options)
        for key in ("style_preset", "palette_preset", "visual_theme_id"):
            if defaults.get(key) in {None, ""}:
                issues.append(f"Template `{template_id}` is missing default_options.{key}.")
        if not spec.available_styles:
            issues.append(f"Template `{template_id}` must expose at least one available style.")
        if not spec.available_palettes:
            issues.append(f"Template `{template_id}` must expose at least one available palette.")
        if spec.default_size not in spec.allowed_sizes:
            issues.append(f"Template `{template_id}` default_size must also appear in allowed_sizes.")
        style_default = defaults.get("style_preset")
        if style_default is not None and style_default not in spec.available_styles:
            issues.append(
                f"Template `{template_id}` default style `{style_default}` is not listed in available_styles."
            )
        palette_default = defaults.get("palette_preset")
        if palette_default is not None and palette_default not in spec.available_palettes:
            issues.append(
                f"Template `{template_id}` default palette `{palette_default}` is not listed in available_palettes."
            )
        if style_default is not None and style_default not in valid_styles:
            issues.append(f"Template `{template_id}` default style `{style_default}` is not public.")
        if palette_default is not None and palette_default not in valid_palettes:
            issues.append(f"Template `{template_id}` default palette `{palette_default}` is not public.")
        theme_default = defaults.get("visual_theme_id")
        if theme_default is not None and theme_default not in valid_theme_ids:
            issues.append(f"Template `{template_id}` default visual theme `{theme_default}` is unknown.")
        for style_id in spec.available_styles:
            if style_id not in valid_styles:
                issues.append(f"Template `{template_id}` lists unknown style `{style_id}`.")
        for palette_id in spec.available_palettes:
            if palette_id not in valid_palettes:
                issues.append(f"Template `{template_id}` lists unknown palette `{palette_id}`.")

    return tuple(issues)


def normalize_style_alias(style_name: str | None) -> str:
    contract = load_plot_contract()
    candidate = (style_name or contract.defaults.style_preset).strip()
    return contract.style_aliases.get(candidate, candidate)


def capability_catalog_payload() -> list[dict[str, Any]]:
    from src.rendering.capability_registry import capability_catalog_payload as runtime_capability_catalog_payload

    return runtime_capability_catalog_payload()

    object_schema = {"type": "object"}
    no_payload_schema = {"type": "object", "additionalProperties": False}

    def capability(
        *,
        id: str,
        label: str,
        status: str,
        owner: str,
        surface: str,
        help: str,
        introduced_in: str = "phase_2",
        typed_payload_schema: dict[str, Any] | None = None,
        test_requirements: list[str] | None = None,
    ) -> dict[str, Any]:
        return {
            "id": id,
            "label": label,
            "status": status,
            "owner": owner,
            "surface": surface,
            "typed_payload_schema": typed_payload_schema or object_schema,
            "help": help,
            "introduced_in": introduced_in,
            "test_requirements": test_requirements or ["schema_decode", "metadata_presence"],
        }

    return [
        {
            "id": "data_containers",
            "label": "Data Containers",
            "description": "Typed table, matrix, transformed view, fit result, and notebook output containers.",
            "capabilities": [
                capability(
                    id="data.table",
                    label="Table",
                    status="enabled",
                    owner="sidecar",
                    surface="plot,data_studio",
                    help="Structured tabular source and preview payloads are available through sidecar routes.",
                ),
                capability(
                    id="data.matrix",
                    label="Matrix",
                    status="coming_soon",
                    owner="sidecar",
                    surface="plot,data_studio",
                    help="Matrix/scalar-field containers are planned for contour and heatmap workflows.",
                ),
                capability(
                    id="data.transformed_view",
                    label="Transformed View",
                    status="enabled",
                    owner="sidecar",
                    surface="plot",
                    help="Typed data_variables and data_transforms already produce transformed previews.",
                ),
                capability(
                    id="data.statistics_summary",
                    label="Statistics Summary",
                    status="experimental",
                    owner="sidecar",
                    surface="plot,data_studio",
                    help="Statistics summary containers are schema/catalog/project landings pending broader UI wiring.",
                ),
                capability(
                    id="data.fit_result",
                    label="Fit Result",
                    status="experimental",
                    owner="sidecar",
                    surface="plot,data_studio",
                    help="Fit result payloads exist and will move onto the shared analysis envelope.",
                ),
                capability(
                    id="data.notebook_output",
                    label="Notebook Output",
                    status="coming_soon",
                    owner="sidecar",
                    surface="code_console",
                    help="Code Console generated figures and tables will become graph-addressable outputs.",
                ),
            ],
        },
        {
            "id": "plot_objects",
            "label": "Plot Objects",
            "description": "Graph-addressable plot scene objects and render payload features.",
            "capabilities": [
                capability(
                    id="plot.series",
                    label="Series",
                    status="enabled",
                    owner="shared",
                    surface="plot",
                    help="Series style, order, and interaction metadata are represented by typed payloads.",
                ),
                capability(
                    id="plot.axis",
                    label="Axis",
                    status="enabled",
                    owner="shared",
                    surface="plot",
                    help="Axis ranges, scales, ticks, extra axes, and breaks are edited through typed payloads.",
                ),
                capability(
                    id="plot.legend",
                    label="Legend",
                    status="enabled",
                    owner="shared",
                    surface="plot",
                    help="Legend behavior is available through plot render options and inspector state.",
                ),
                capability(
                    id="plot.guide.line",
                    label="Reference Guide",
                    status="enabled",
                    owner="shared",
                    surface="plot",
                    help="Reference guide lines and bands are persisted in render_options.reference_guides.",
                ),
                capability(
                    id="plot.guide",
                    label="Guide Object",
                    status="enabled",
                    owner="shared",
                    surface="plot",
                    help="Guide objects are graph-addressable wrappers for line and region guide payloads.",
                ),
                capability(
                    id="plot.annotation.text",
                    label="Text Annotation",
                    status="enabled",
                    owner="shared",
                    surface="plot",
                    help="Text notes and callouts are persisted in render_options.text_annotations.",
                ),
                capability(
                    id="plot.annotation.shape",
                    label="Shape Annotation",
                    status="enabled",
                    owner="shared",
                    surface="plot",
                    help="Shape overlays are persisted in render_options.shape_annotations.",
                ),
                capability(
                    id="plot.layer.function",
                    label="Function Layer",
                    status="enabled",
                    owner="sidecar",
                    surface="plot",
                    help="Function layers use backend expression parsing through analytical_layers.",
                ),
                capability(
                    id="plot.axis.extra",
                    label="Extra Axis",
                    status="enabled",
                    owner="shared",
                    surface="plot",
                    help="Extra x/y axes are persisted through extra_x_axis and extra_y_axis payloads.",
                ),
                capability(
                    id="plot.axis.break",
                    label="Broken Axis",
                    status="enabled",
                    owner="sidecar",
                    surface="plot",
                    help="Broken axis intervals are persisted through x_axis_breaks and y_axis_breaks.",
                ),
                capability(
                    id="plot.fit_overlay",
                    label="Fit Overlay",
                    status="enabled",
                    owner="sidecar",
                    surface="plot,data_studio",
                    help="Fit overlays are graph-addressable objects backed by the analysis result envelope.",
                ),
                capability(
                    id="plot.page",
                    label="Plot Page",
                    status="enabled",
                    owner="shared",
                    surface="plot,composer",
                    help="Plot page objects provide stable graph identity for figure/page-level state.",
                ),
                capability(
                    id="plot.plot_area",
                    label="Plot Area",
                    status="enabled",
                    owner="shared",
                    surface="plot",
                    help="Plot area objects provide stable graph identity for scene-local layout and selection.",
                ),
            ],
        },
        {
            "id": "analysis_operations",
            "label": "Analysis Operations",
            "description": "Sidecar-owned numerical operations with a future common result envelope.",
            "capabilities": [
                capability(
                    id="analysis.fit",
                    label="Fit",
                    status="enabled",
                    owner="sidecar",
                    surface="plot,data_studio",
                    help="Current fit models are available through POST /fit-analysis.",
                ),
                capability(
                    id="analysis.smoothing",
                    label="Smoothing",
                    status="coming_soon",
                    owner="sidecar",
                    surface="plot,data_studio",
                    help="Smoothing will use SciPlot-owned numerical implementations and fixtures.",
                ),
                capability(
                    id="analysis.interpolation",
                    label="Interpolation",
                    status="coming_soon",
                    owner="sidecar",
                    surface="plot,data_studio",
                    help="Interpolation will use typed operation payloads and numerical fixtures before UI exposure.",
                ),
                capability(
                    id="analysis.differentiation",
                    label="Differentiation",
                    status="coming_soon",
                    owner="sidecar",
                    surface="plot,data_studio",
                    help="Differentiation will be implemented behind the common analysis result envelope.",
                ),
                capability(
                    id="analysis.integration",
                    label="Integration",
                    status="coming_soon",
                    owner="sidecar",
                    surface="plot,data_studio",
                    help="Integration will be implemented behind the common analysis result envelope.",
                ),
                capability(
                    id="analysis.fft",
                    label="FFT",
                    status="experimental",
                    owner="sidecar",
                    surface="plot,data_studio",
                    help="FFT and Fourier filtering are planned behind typed analysis operation payloads.",
                ),
                capability(
                    id="analysis.fourier_filter",
                    label="Fourier Filter",
                    status="coming_soon",
                    owner="sidecar",
                    surface="plot,data_studio",
                    help="Fourier filtering requires numerical fixtures before runtime exposure.",
                ),
                capability(
                    id="analysis.correlation",
                    label="Correlation",
                    status="coming_soon",
                    owner="sidecar",
                    surface="plot,data_studio",
                    help="Correlation will land as a typed analysis operation with result containers.",
                ),
                capability(
                    id="analysis.convolution",
                    label="Convolution",
                    status="coming_soon",
                    owner="sidecar",
                    surface="plot,data_studio",
                    help="Convolution will land as a typed analysis operation with result containers.",
                ),
                capability(
                    id="analysis.baseline",
                    label="Baseline Correction",
                    status="coming_soon",
                    owner="sidecar",
                    surface="plot,data_studio",
                    help="Baseline correction requires fixtures and overlay/result-table checks before UI exposure.",
                ),
                capability(
                    id="analysis.peak_detection",
                    label="Peak Detection",
                    status="coming_soon",
                    owner="sidecar",
                    surface="plot,data_studio",
                    help="Peak detection requires numerical fixtures and overlay integration before UI exposure.",
                ),
                capability(
                    id="analysis.kde",
                    label="KDE",
                    status="coming_soon",
                    owner="sidecar",
                    surface="plot,data_studio",
                    help="KDE and statistical tests will be added only with numerical fixture coverage.",
                ),
                capability(
                    id="analysis.statistical_tests",
                    label="Statistical Tests",
                    status="coming_soon",
                    owner="sidecar",
                    surface="plot,data_studio",
                    help="Statistical tests will use typed results and explicit assumptions/diagnostics.",
                ),
                capability(
                    id="analysis.distribution_fitting",
                    label="Distribution Fitting",
                    status="coming_soon",
                    owner="sidecar",
                    surface="plot,data_studio",
                    help="Distribution fitting requires reference fixtures before becoming available.",
                ),
                capability(
                    id="analysis.peak_fitting",
                    label="Peak Fitting",
                    status="coming_soon",
                    owner="sidecar",
                    surface="plot,data_studio",
                    help="Peak fitting requires fixture coverage and overlay integration before UI exposure.",
                ),
                capability(
                    id="analysis.growth_models",
                    label="Growth Models",
                    status="coming_soon",
                    owner="sidecar",
                    surface="plot,data_studio",
                    help="Growth models will extend the fit family after numerical validation.",
                ),
            ],
        },
        {
            "id": "import_filters",
            "label": "Import Filters",
            "description": "Source preview and import filters with typed options and diagnostics.",
            "capabilities": [
                capability(
                    id="import.csv",
                    label="CSV/TSV/TXT",
                    status="enabled",
                    owner="sidecar",
                    surface="plot,data_studio",
                    help="Delimited text import is available through inspect and source preview routes.",
                ),
                capability(
                    id="import.excel",
                    label="Excel",
                    status="enabled",
                    owner="sidecar",
                    surface="plot,data_studio",
                    help="Workbook import is available through current table preview and Data Studio flows.",
                ),
                capability(
                    id="import.json",
                    label="JSON",
                    status="coming_soon",
                    owner="sidecar",
                    surface="plot,data_studio",
                    help="JSON import needs an explicit preview/options schema before runtime exposure.",
                ),
                capability(
                    id="import.sql",
                    label="SQL",
                    status="coming_soon",
                    owner="sidecar",
                    surface="data_studio",
                    help="SQL import will require safe connection options and preview-only diagnostics.",
                ),
                capability(
                    id="import.hdf5",
                    label="HDF5",
                    status="coming_soon",
                    owner="sidecar",
                    surface="plot,data_studio",
                    help="HDF5 will be implemented as an explicit import filter with preview diagnostics.",
                ),
                capability(
                    id="import.netcdf",
                    label="NetCDF",
                    status="coming_soon",
                    owner="sidecar",
                    surface="plot,data_studio",
                    help="NetCDF support is planned for matrix/scalar-field workflows.",
                ),
                capability(
                    id="import.fits",
                    label="FITS",
                    status="coming_soon",
                    owner="sidecar",
                    surface="plot,data_studio",
                    help="FITS import is cataloged for scientific image/table workflows pending fixtures.",
                ),
                capability(
                    id="import.ods",
                    label="ODS",
                    status="coming_soon",
                    owner="sidecar",
                    surface="plot,data_studio",
                    help="ODS import needs a license-compatible parser and source preview fixtures.",
                ),
                capability(
                    id="import.readstat",
                    label="SAS/Stata/SPSS",
                    status="coming_soon",
                    owner="sidecar",
                    surface="data_studio",
                    help="ReadStat-backed SAS/Stata/SPSS import is cataloged behind safe Python libraries.",
                ),
                capability(
                    id="import.binary_raw",
                    label="Binary/Raw",
                    status="coming_soon",
                    owner="sidecar",
                    surface="plot,data_studio",
                    help="Binary/raw import requires explicit dtype, shape, endian, and preview diagnostics.",
                ),
                capability(
                    id="import.origin_scidavis_eval",
                    label="Origin/SciDAVis Evaluation",
                    status="disabled",
                    owner="sidecar",
                    surface="project",
                    help="Origin/SciDAVis-style project import is an evaluation backlog item, not runtime support.",
                ),
                capability(
                    id="import.image_digitizer",
                    label="Image Digitizer",
                    status="coming_soon",
                    owner="sidecar",
                    surface="plot",
                    help="Image digitizer support requires a dedicated workflow and validation fixtures.",
                ),
            ],
        },
        {
            "id": "export_targets",
            "label": "Export Targets",
            "description": "Figure, data, project, comparison, and artifact export targets.",
            "capabilities": [
                capability(
                    id="export.figure.pdf",
                    label="Figure PDF",
                    status="enabled",
                    owner="sidecar",
                    surface="plot,composer,code_console",
                    help="PDF figure export is the authoritative vector output path.",
                ),
                capability(
                    id="export.figure.tiff",
                    label="Figure TIFF",
                    status="enabled",
                    owner="sidecar",
                    surface="plot,composer,code_console",
                    help="TIFF figure export is the authoritative raster publication output path.",
                ),
                capability(
                    id="export.data_workbook",
                    label="Data Workbook",
                    status="experimental",
                    owner="sidecar",
                    surface="plot,data_studio",
                    help="Data workbook export is cataloged for container-backed worksheet outputs.",
                ),
                capability(
                    id="export.project_bundle",
                    label="Project Bundle",
                    status="enabled",
                    owner="sidecar",
                    surface="all",
                    help=".sciplot project bundles are the app-level self-contained project format.",
                ),
                capability(
                    id="export.comparison_bundle",
                    label="Comparison Bundle",
                    status="enabled",
                    owner="sidecar",
                    surface="data_studio",
                    help="Data Studio comparison export emits workbooks, figures, and filtered standard outputs.",
                ),
                capability(
                    id="export.artifact_manifest",
                    label="Artifact Manifest",
                    status="coming_soon",
                    owner="sidecar",
                    surface="all",
                    help="Manifest-driven artifact sets will unify multi-file export reporting.",
                ),
                capability(
                    id="export.code_console_figure_set",
                    label="Code Console Figure Set",
                    status="experimental",
                    owner="sidecar",
                    surface="code_console",
                    help="Code Console generated figure sets are cataloged for manifest-backed export.",
                ),
            ],
        },
        {
            "id": "project_bundle_features",
            "label": "Project Bundle Features",
            "description": "Project save/open features exposed for compatibility and migration handling.",
            "capabilities": [
                capability(
                    id="project_bundle.document_graph",
                    label="Document Graph",
                    status="enabled",
                    owner="sidecar",
                    surface="all",
                    help="Project bundles include an internal document_graph for durable object identity.",
                ),
                capability(
                    id="project_bundle.embedded_sources",
                    label="Embedded Sources",
                    status="enabled",
                    owner="sidecar",
                    surface="all",
                    help="Project restore uses embedded bundle sources instead of original absolute paths.",
                ),
            ],
        },
        {
            "id": "native_preview_features",
            "label": "Native Preview Features",
            "description": "Contract-gated macOS native preview and interaction capabilities.",
            "capabilities": [
                capability(
                    id="native_preview.curve_hit_testing",
                    label="Curve Hit Testing",
                    status="experimental",
                    owner="shared",
                    surface="plot",
                    help="Curve hit testing uses backend interaction metadata when available.",
                ),
                capability(
                    id="native_preview.unavailable_fallback",
                    label="Backend Fallback",
                    status="enabled",
                    owner="shared",
                    surface="plot",
                    typed_payload_schema=no_payload_schema,
                    help="Unsupported native preview cases fall back to backend bitmap/PDF preview.",
                ),
            ],
        },
    ]


def meta_payload() -> dict[str, Any]:
    contract = load_plot_contract()
    return {
        "version": contract.version,
        "defaults": asdict(contract.defaults),
        "global_frame": asdict(contract.global_frame),
        "sizes": [
            {
                "id": key,
                **asdict(value),
            }
            for key, value in contract.size_presets.items()
        ],
        "styles": [
            {
                "id": key,
                "label": value.label,
                "public": value.public,
                "display_group": value.display_group,
                "description": value.description,
                "hard_constraints": value.hard_constraints,
                "preset_note": value.preset_note,
                "recommended_palette_preset": value.recommended_palette_preset,
                "recommended_visual_theme_id": value.recommended_visual_theme_id,
            }
            for key, value in contract.styles.items()
        ],
        "palettes": [
            {
                "id": key,
                "label": value.label,
                "public": value.public,
                "description": value.description,
                "swatches": list(value.categorical[:6]),
            }
            for key, value in contract.palettes.items()
        ],
        "templates": [
            {
                "id": key,
                "label": value.label,
                "description": value.description,
                "category": value.category,
                "presentation_kind": value.presentation_kind,
                "default_size": value.default_size,
                "allowed_sizes": list(value.allowed_sizes),
                "editable_options": list(value.editable_options),
                "default_options": dict(value.default_options),
                "available_styles": list(value.available_styles),
                "available_palettes": list(value.available_palettes),
            }
            for key, value in contract.templates.items()
        ],
        "capability_catalogs": capability_catalog_payload(),
    }


def render_contract_markdown(contract: PlotContract | None = None) -> str:
    resolved = contract or load_plot_contract()
    lines = [
        "# SciPlot Plot Contract",
        "",
        f"- Version: `{resolved.version}`",
        f"- Default style: `{resolved.defaults.style_preset}`",
        f"- Default palette: `{resolved.defaults.palette_preset}`",
        "",
        "## Global Frame",
        "",
        (
            f"- Standard panel: `{resolved.global_frame.panel_width_mm:.1f} x "
            f"{resolved.global_frame.panel_height_mm:.1f} mm`"
        ),
        (
            f"- Margins: left `{resolved.global_frame.left_margin_mm:.1f} mm`, "
            f"right `{resolved.global_frame.right_margin_mm:.1f} mm`, "
            f"bottom `{resolved.global_frame.bottom_margin_mm:.1f} mm`, "
            f"top `{resolved.global_frame.top_margin_mm:.1f} mm`"
        ),
        "",
        "## Axis Policy",
        "",
        (
            "- Linear axis nice steps: "
            + ", ".join(f"`{value:g}`" for value in resolved.axis_policy.linear_nice_steps)
        ),
        (
            f"- Linear outer padding: "
            f"`{resolved.axis_policy.linear_outer_padding_fraction * 100:.1f}%` on standard axes"
        ),
        (
            f"- Force labeled linear endpoints visible: "
            f"`{resolved.axis_policy.linear_force_visible_labeled_endpoints}`"
        ),
        (
            "- Log display steps: "
            + ", ".join(f"`{value:g}`" for value in resolved.axis_policy.log_display_steps)
        ),
        f"- Log label mode: `{resolved.axis_policy.log_label_mode}`",
        (
            f"- Log allows unlabeled outer padding: "
            f"`{resolved.axis_policy.log_allow_unlabeled_outer_padding}`"
        ),
        (
            f"- Bar zero-baseline lower padding disabled: "
            f"`{resolved.axis_policy.bar_zero_baseline_no_lower_padding}`"
        ),
        f"- Tensile y-axis includes zero: `{resolved.axis_policy.tensile_y_include_zero}`",
        (
            f"- Stacked x-axis uses standard endpoint policy: "
            f"`{resolved.axis_policy.stacked_x_use_standard_endpoint_policy}`"
        ),
        "",
        "## Styles",
        "",
    ]

    for name, style_spec in resolved.styles.items():
        lines.extend(
            [
                f"### `{name}` / {style_spec.label}",
                "",
                f"- Description: {style_spec.description}",
                f"- Hard constraints: `{style_spec.hard_constraints}`",
                f"- Recommended palette: `{style_spec.recommended_palette_preset}`",
                (
                    f"- Recommended visual theme: "
                    f"`{style_spec.recommended_visual_theme_id or 'None'}`"
                ),
                (
                    "- Axis frame: "
                    f"left=`{style_spec.axis_frame.left}`, "
                    f"bottom=`{style_spec.axis_frame.bottom}`, "
                    f"top=`{style_spec.axis_frame.top}`, "
                    f"right=`{style_spec.axis_frame.right}`"
                ),
                f"- Preset note: {style_spec.preset_note}",
                "",
            ]
        )

    lines.extend(
        [
        "## Templates",
        "",
        ]
    )

    if resolved.qa_profiles:
        lines.extend(["## QA Profiles", ""])
        for name, profile_spec in resolved.qa_profiles.items():
            tokens = ", ".join(f"`{key}`={value!r}" for key, value in profile_spec.items())
            lines.append(f"- `{name}`: {tokens}")
        lines.append("")

    for name, template_spec in resolved.templates.items():
        lines.extend(
            [
                f"### `{name}` / {template_spec.label}",
                "",
                f"- Category: `{template_spec.category}`",
                f"- Presentation kind: `{template_spec.presentation_kind}`",
                f"- Default size: `{template_spec.default_size}`",
                f"- Allowed sizes: {', '.join(f'`{item}`' for item in template_spec.allowed_sizes)}",
                f"- Editable options: {', '.join(f'`{item}`' for item in template_spec.editable_options)}",
                f"- Description: {template_spec.description}",
                f"- Hard rules: {', '.join(f'`{item}`' for item in template_spec.hard_rules) or 'None'}",
                f"- Soft rules: {', '.join(f'`{item}`' for item in template_spec.soft_rules) or 'None'}",
                "",
            ]
        )

    lines.extend(["## Validation Rules", ""])
    for name, rule in resolved.validation_rules.items():
        tolerance_text = (
            f", tolerance `{rule.tolerance_mm:.2f} mm`"
            if rule.tolerance_mm is not None
            else ""
        )
        lines.append(
            f"- `{name}`: {rule.label} ({rule.severity}{tolerance_text}) - {rule.description}"
        )

    return "\n".join(lines) + "\n"


def write_contract_markdown(path: Path | None = None) -> Path:
    destination = path or DOC_PATH
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(render_contract_markdown(), encoding="utf-8")
    return destination
