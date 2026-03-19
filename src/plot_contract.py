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
    description: str
    hard_constraints: bool
    preset_note: str
    typography: TypographyContract
    stroke: StrokeContract
    spacing: SpacingContract
    annotation: AnnotationContract
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
                description=value["description"],
                hard_constraints=bool(value["hard_constraints"]),
                preset_note=value["preset_note"],
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


def normalize_style_alias(style_name: str | None) -> str:
    contract = load_plot_contract()
    candidate = (style_name or contract.defaults.style_preset).strip()
    return contract.style_aliases.get(candidate, candidate)


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
                "description": value.description,
                "hard_constraints": value.hard_constraints,
                "preset_note": value.preset_note,
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
                "default_size": value.default_size,
                "allowed_sizes": list(value.allowed_sizes),
                "editable_options": list(value.editable_options),
                "default_options": dict(value.default_options),
                "available_styles": list(value.available_styles),
                "available_palettes": list(value.available_palettes),
            }
            for key, value in contract.templates.items()
        ],
    }


def render_contract_markdown(contract: PlotContract | None = None) -> str:
    resolved = contract or load_plot_contract()
    lines = [
        "# CodeGod Plot Contract",
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
        "## Templates",
        "",
    ]

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
