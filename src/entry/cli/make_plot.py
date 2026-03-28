from __future__ import annotations

import argparse
import sys

from src import (
    mpl_backend,  # noqa: F401
    plot_style,
)
from src.core.application.render import (
    DEFAULT_SIZE_BY_TEMPLATE,
    PALETTE_PRESET_CHOICES,
    SIZE_CHOICES,
    STYLE_PRESET_CHOICES,
    TEMPLATE_CHOICES,
    InputInspection,
    PreflightResult,
    Recommendation,
    RenderedPlot,
    RenderOptions,
    TemplateRenderer,
    build_rendered_plots,
    close_rendered_plots,
    coerce_sheet,
    ensure_input_path,
    export_rendered_plots,
    inspect_input_file,
    list_sheet_names,
    normalize_input_path_text,
    preflight_render_request,
    render_template,
    resolve_output_dir,
    resolve_render_options,
    validate_template_name,
)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate research plots from graph-family templates.",
    )
    parser.add_argument("--template", required=True, help="Graph-family template to use.")
    parser.add_argument("--input", required=True, help="Path to the input data file.")
    parser.add_argument(
        "--output-dir",
        help="Directory for generated PDF files. Overrides --output-mode when given.",
    )
    parser.add_argument(
        "--output-mode",
        choices=("workspace", "data_dir"),
        default="workspace",
        help="Default output location when --output-dir is not given. Default: workspace",
    )
    parser.add_argument("--sheet", default="0", help="Excel sheet index or sheet name. Default: 0")
    parser.add_argument("--size", help="Panel size preset: 60x55, 120x55, or 60x110.")
    parser.add_argument("--xscale", choices=("linear", "log"), help="X-axis scale for curve-like plots.")
    parser.add_argument("--yscale", choices=("linear", "log"), help="Y-axis scale for curve-like plots.")
    parser.add_argument("--reverse-x", action="store_true", help="Reverse the x axis.")
    parser.add_argument("--baseline", choices=("none", "linear_endpoints"), help="Baseline mode for stacked curves.")
    parser.add_argument(
        "--show-colorbar",
        dest="show_colorbar",
        action="store_true",
        help="Force colorbar on for heatmaps.",
    )
    parser.add_argument(
        "--hide-colorbar",
        dest="show_colorbar",
        action="store_false",
        help="Hide the colorbar for heatmaps.",
    )
    parser.add_argument(
        "--style-preset",
        default=plot_style.DEFAULT_STYLE_PRESET,
        help="Style preset. Default: default",
    )
    parser.add_argument(
        "--palette-preset",
        choices=PALETTE_PRESET_CHOICES,
        default=plot_style.DEFAULT_PALETTE_PRESET,
        help="Color palette preset. Default: colorblind_safe",
    )
    parser.set_defaults(show_colorbar=None)
    return parser.parse_args()


def main() -> int:
    args = _parse_args()

    try:
        validated_template = validate_template_name(args.template)
        input_path = ensure_input_path(args.input)
        output_dir = resolve_output_dir(input_path, args.output_dir, args.output_mode)
        sheet = coerce_sheet(args.sheet)
        options = resolve_render_options(
            template=validated_template,
            size=args.size,
            xscale=args.xscale,
            yscale=args.yscale,
            reverse_x=args.reverse_x,
            baseline=args.baseline,
            show_colorbar=args.show_colorbar,
            style_preset=args.style_preset,
            palette_preset=args.palette_preset,
        )
        preflight = preflight_render_request(validated_template, input_path, sheet, options)
        if preflight.errors:
            raise ValueError(preflight.errors[0])
        for warning in preflight.warnings:
            print(f"Warning: {warning}", file=sys.stderr)
        outputs = render_template(
            validated_template,
            input_path,
            output_dir,
            sheet,
            size=args.size,
            xscale=args.xscale,
            yscale=args.yscale,
            reverse_x=args.reverse_x,
            baseline=args.baseline,
            show_colorbar=args.show_colorbar,
            style_preset=args.style_preset,
            palette_preset=args.palette_preset,
        )
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    for output in outputs:
        print(output.resolve())
    return 0


_coerce_sheet = coerce_sheet
_ensure_input_path = ensure_input_path
_resolve_render_options = resolve_render_options


__all__ = [
    "DEFAULT_SIZE_BY_TEMPLATE",
    "InputInspection",
    "PALETTE_PRESET_CHOICES",
    "PreflightResult",
    "Recommendation",
    "RenderOptions",
    "RenderedPlot",
    "SIZE_CHOICES",
    "STYLE_PRESET_CHOICES",
    "TEMPLATE_CHOICES",
    "TemplateRenderer",
    "_coerce_sheet",
    "_ensure_input_path",
    "_resolve_render_options",
    "build_rendered_plots",
    "close_rendered_plots",
    "export_rendered_plots",
    "inspect_input_file",
    "list_sheet_names",
    "main",
    "normalize_input_path_text",
    "preflight_render_request",
    "render_template",
    "resolve_output_dir",
]


if __name__ == "__main__":
    raise SystemExit(main())
