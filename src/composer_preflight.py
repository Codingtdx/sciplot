from __future__ import annotations

from pathlib import Path
from typing import Any

from PIL import Image

from src.composer_assets import is_pdf_path, is_raster_path
from src.composer_types import ComposerPanel, ComposerProject

_MIN_RASTER_DPI = 120.0
_WARN_RASTER_DPI = 220.0


def _diagnostic(
    diagnostic_id: str,
    *,
    severity: str,
    message: str,
    panel: ComposerPanel | None = None,
    help_text: str = "",
    source_module: str | None = None,
) -> dict[str, Any]:
    asset_ref = panel.asset_ref if panel is not None else None
    return {
        "id": diagnostic_id,
        "severity": severity,
        "message": message,
        "panel_id": panel.id if panel is not None else None,
        "source_module": source_module or (asset_ref or {}).get("source_module"),
        "help": help_text or message,
    }


def _panel_raster_dpi(panel: ComposerPanel) -> float:
    with Image.open(panel.file_path) as image:
        width_px, height_px = image.size
    width_in = max(panel.w_mm / 25.4, 1e-6)
    height_in = max(panel.h_mm / 25.4, 1e-6)
    return min(width_px / width_in, height_px / height_in)


def _checksum_stale(panel: ComposerPanel) -> bool:
    # The artifact manifest is authoritative for checksum validation during project
    # restore. Composer preflight only gives a lightweight warning here because
    # callers can pass remote/placeholder checksums before the artifact is bundled.
    asset_ref = panel.asset_ref or {}
    return bool(asset_ref.get("sha256")) and str(asset_ref.get("sha256")) in {"missing", "stale"}


def build_composer_export_preflight(project: ComposerProject) -> dict[str, Any]:
    diagnostics: list[dict[str, Any]] = []
    blocking_panel_ids: list[str] = []

    for panel in project.panels:
        if panel.hidden:
            continue
        panel_path = Path(panel.file_path).expanduser()
        if not panel_path.exists():
            blocking_panel_ids.append(panel.id)
            diagnostics.append(
                _diagnostic(
                    "missing_asset",
                    severity="critical",
                    message=f"Missing Composer asset for panel {panel.id}.",
                    panel=panel,
                    help_text="Restore the linked artifact or remove the panel before exporting.",
                )
            )
            continue
        if not is_pdf_path(panel_path) and not is_raster_path(panel_path):
            blocking_panel_ids.append(panel.id)
            diagnostics.append(
                _diagnostic(
                    "unsupported_format",
                    severity="critical",
                    message=f"Unsupported Composer asset format: {panel_path.suffix or panel_path.name}.",
                    panel=panel,
                    help_text="Use PDF, PNG, JPEG, TIFF, BMP, or WebP assets for Composer export.",
                )
            )
            continue
        if is_raster_path(panel_path):
            dpi = _panel_raster_dpi(panel)
            if dpi < _MIN_RASTER_DPI:
                severity = "critical" if panel.asset_ref is not None else "warning"
                if severity == "critical":
                    blocking_panel_ids.append(panel.id)
                diagnostics.append(
                    _diagnostic(
                        "low_resolution_raster",
                        severity=severity,
                        message=f"Panel {panel.id} uses a low-resolution raster ({dpi:.0f} dpi).",
                        panel=panel,
                        help_text="Use a higher-resolution raster or a PDF figure before exporting.",
                    )
                )
            elif dpi < _WARN_RASTER_DPI:
                diagnostics.append(
                    _diagnostic(
                        "low_resolution_raster",
                        severity="warning",
                        message=f"Panel {panel.id} raster resolution is modest ({dpi:.0f} dpi).",
                        panel=panel,
                        help_text="A higher-resolution source will export more cleanly.",
                    )
                )
        if panel.x_mm < 0 or panel.y_mm < 0:
            diagnostics.append(
                _diagnostic(
                    "page_bleed",
                    severity="warning",
                    message=f"Panel {panel.id} extends outside the Composer page.",
                    panel=panel,
                    help_text="Move the panel inside the page or confirm the crop intentionally bleeds.",
                )
            )
        if _checksum_stale(panel):
            diagnostics.append(
                _diagnostic(
                    "stale_linked_source",
                    severity="warning",
                    message=f"Panel {panel.id} may reference a stale linked artifact.",
                    panel=panel,
                    help_text="Refresh the linked artifact if the source module changed.",
                )
            )

    if blocking_panel_ids:
        status = "blocked"
        help_text = "Composer export is blocked by critical preflight diagnostics."
    elif any(item["severity"] == "warning" for item in diagnostics):
        status = "warning"
        help_text = "Composer export has warnings but can continue."
    else:
        status = "ready"
        help_text = "Composer export preflight passed."
    return {
        "status": status,
        "diagnostics": diagnostics,
        "blocking_panel_ids": list(dict.fromkeys(blocking_panel_ids)),
        "help": help_text,
    }


def composer_export_blocker_message(preflight: dict[str, Any]) -> str:
    diagnostics = preflight.get("diagnostics") or []
    critical_messages = [
        str(item.get("message"))
        for item in diagnostics
        if isinstance(item, dict) and item.get("severity") == "critical"
    ]
    if critical_messages:
        return "; ".join(critical_messages)
    return str(preflight.get("help") or "Composer export is blocked by preflight diagnostics.")


__all__ = ["build_composer_export_preflight", "composer_export_blocker_message"]
