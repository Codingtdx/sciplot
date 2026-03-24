from src.rendering.cache import clear_input_cache
from src.rendering.code_console import (
    AI_BUNDLE_VERSION,
    CODE_CONSOLE_RUN_TIMEOUT_SECONDS,
    export_code_console_bundle,
    generate_code_console_payload,
    run_code_console_python,
)
from src.rendering.constants import (
    DEFAULT_SIZE_BY_TEMPLATE,
    PALETTE_PRESET_CHOICES,
    SIZE_CHOICES,
    STYLE_PRESET_CHOICES,
    TEMPLATE_CHOICES,
)
from src.rendering.data_templates import (
    data_template_catalog,
    materialize_data_template,
    materialize_data_template_folder,
    plot_template_folder_catalog,
)
from src.rendering.dataset_models import NormalizedDataset, build_normalized_dataset
from src.rendering.io import (
    coerce_sheet,
    default_output_dir,
    ensure_input_path,
    list_sheet_names,
    normalize_input_path_text,
    resolve_output_dir,
)
from src.rendering.local_storage import (
    cleanup_managed_storage,
    managed_storage_snapshot,
    prepare_managed_plot_export_dir,
)
from src.rendering.models import (
    InputInspection,
    PreflightResult,
    Recommendation,
    RenderedPlot,
    RenderOptions,
    TemplateRenderer,
)
from src.rendering.options import resolve_render_options, validate_template_name
from src.rendering.preflight import preflight_render_request
from src.rendering.recommendation import inspect_input_file
from src.rendering.recommender_models import TemplateRecommendation
from src.rendering.render import (
    TEMPLATE_RENDERERS,
    build_rendered_plots,
    close_rendered_plots,
    export_rendered_plots,
    render_template,
)
from src.rendering.tensile_compare import (
    export_tensile_comparison_bundle,
    inspect_tensile_workbook,
)

__all__ = [
    "DEFAULT_SIZE_BY_TEMPLATE",
    "InputInspection",
    "AI_BUNDLE_VERSION",
    "NormalizedDataset",
    "CODE_CONSOLE_RUN_TIMEOUT_SECONDS",
    "PALETTE_PRESET_CHOICES",
    "PreflightResult",
    "Recommendation",
    "TemplateRecommendation",
    "RenderOptions",
    "RenderedPlot",
    "SIZE_CHOICES",
    "STYLE_PRESET_CHOICES",
    "TEMPLATE_CHOICES",
    "TEMPLATE_RENDERERS",
    "TemplateRenderer",
    "build_rendered_plots",
    "build_normalized_dataset",
    "clear_input_cache",
    "close_rendered_plots",
    "coerce_sheet",
    "data_template_catalog",
    "default_output_dir",
    "ensure_input_path",
    "export_code_console_bundle",
    "export_rendered_plots",
    "export_tensile_comparison_bundle",
    "generate_code_console_payload",
    "inspect_input_file",
    "inspect_tensile_workbook",
    "list_sheet_names",
    "materialize_data_template",
    "materialize_data_template_folder",
    "managed_storage_snapshot",
    "normalize_input_path_text",
    "plot_template_folder_catalog",
    "preflight_render_request",
    "prepare_managed_plot_export_dir",
    "render_template",
    "resolve_output_dir",
    "resolve_render_options",
    "run_code_console_python",
    "cleanup_managed_storage",
    "validate_template_name",
]
