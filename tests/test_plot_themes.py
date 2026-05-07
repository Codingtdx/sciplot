from __future__ import annotations

import zipfile
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd
from fastapi.testclient import TestClient
from matplotlib.colors import to_hex

from app.sidecar.server import app
from src import plot_style
from src.rendering.custom_themes import normalize_custom_theme_package

client = TestClient(app)


def _curve_csv(path: Path) -> None:
    pd.DataFrame(
        [
            ["X", "Y"],
            ["s", "MPa"],
            ["Sample A", "Sample A"],
            [0.0, 1.0],
            [1.0, 3.0],
            [2.0, 5.0],
        ]
    ).to_csv(path, header=False, index=False)


def _multi_curve_csv(path: Path) -> None:
    pd.DataFrame(
        [
            ["Time", "Stress", "Time", "Stress"],
            ["s", "MPa", "s", "MPa"],
            ["Sample A", "Sample A", "Sample B", "Sample B"],
            [0.0, 1.0, 0.0, 1.5],
            [1.0, 3.0, 1.0, 2.7],
            [2.0, 5.0, 2.0, 4.8],
        ]
    ).to_csv(path, header=False, index=False)


def _theme_payload(theme_id: str = "user/nature_plus") -> dict[str, object]:
    return {
        "id": theme_id,
        "label": "Nature Plus",
        "base_style_id": "nature",
        "palette_preset": "colorblind_safe",
        "visual_theme_id": "clean_light",
        "palette": {
            "categorical": ["#0ea5e9", "#f97316", "#16a34a"],
        },
        "hard_overrides": {
            "typography": {"font_size_pt": 7.2, "legend_font_size_pt": 6.8},
            "stroke": {"line_width_pt": 1.35, "marker_size_pt": 3.2},
        },
        "soft_overrides": {
            "axes.facecolor": "#fbfdff",
            "axes.grid": True,
            "grid.alpha": 0.24,
        },
        "expert_rcparams": {
            "grid.linestyle": ":",
            "legend.fancybox": True,
        },
    }


def test_custom_theme_normalization_blocks_protected_and_non_allowlisted_rcparams() -> None:
    theme = _theme_payload()
    theme["expert_rcparams"] = {
        "font.size": 20,
        "grid.linestyle": "--",
        "backend": "agg",
    }
    theme["soft_overrides"] = {
        "axes.facecolor": "#ffffff",
        "lines.linewidth": 5.0,
    }

    normalized = normalize_custom_theme_package(theme)

    assert normalized.package.base_style_id == "nature"
    assert normalized.package.expert_rcparams == {"grid.linestyle": "--"}
    assert normalized.package.soft_overrides == {"axes.facecolor": "#ffffff"}
    assert "font.size" in normalized.blocked_keys
    assert "lines.linewidth" in normalized.blocked_keys
    assert "backend" in normalized.blocked_keys
    assert any("blocked" in warning.lower() for warning in normalized.warnings)


def test_custom_theme_hard_overrides_do_not_mutate_frozen_nature_style() -> None:
    before = plot_style.get_style_spec("nature")

    normalized = normalize_custom_theme_package(_theme_payload())

    after = plot_style.get_style_spec("nature")
    assert after == before
    assert normalized.package.hard_overrides["typography"]["font_size_pt"] == 7.2


def test_plot_theme_endpoints_save_list_preview_and_delete(tmp_path: Path, monkeypatch) -> None:
    from src.rendering import custom_theme_store

    monkeypatch.setattr(custom_theme_store, "USER_THEME_DIR", tmp_path / "themes")

    preview_response = client.post("/plot-themes/preview", json={"theme": _theme_payload()})
    assert preview_response.status_code == 200, preview_response.text
    preview_payload = preview_response.json()
    assert preview_payload["theme"]["id"] == "user/nature_plus"
    assert preview_payload["warnings"] == []

    save_response = client.post("/plot-themes", json={"theme": _theme_payload()})
    assert save_response.status_code == 200, save_response.text
    assert (tmp_path / "themes" / "user__nature_plus.json").exists()

    list_response = client.get("/plot-themes")
    assert list_response.status_code == 200, list_response.text
    themes = list_response.json()["themes"]
    assert any(item["id"] == "nature" and item["builtin"] for item in themes)
    assert any(item["id"] == "user/nature_plus" and not item["builtin"] for item in themes)

    delete_response = client.delete("/plot-themes/user/nature_plus")
    assert delete_response.status_code == 200, delete_response.text
    assert not (tmp_path / "themes" / "user__nature_plus.json").exists()


def test_render_preview_accepts_custom_theme_draft(tmp_path: Path) -> None:
    input_path = tmp_path / "curve.csv"
    _curve_csv(input_path)
    plot_style.apply_style("nature", "colorblind_safe")
    baseline_font_size = plt.rcParams["font.size"]

    response = client.post(
        "/render-preview",
        json={
            "input_path": str(input_path),
            "sheet": 0,
            "template": "curve",
            "options": {
                "custom_theme_draft": _theme_payload(),
            },
        },
    )

    assert response.status_code == 200, response.text
    payload = response.json()
    assert payload["preview"]["png_base64"]
    assert payload["submission_report"]["style_preset"] == "nature"
    assert plot_style.current_style_preset() == "nature"
    assert plot_style.current_palette_preset() == "colorblind_safe"
    assert plt.rcParams["font.size"] == baseline_font_size


def test_custom_theme_palette_drives_rendered_series_colors(tmp_path: Path) -> None:
    from src.rendering.options import resolve_render_options
    from src.rendering.render_service import build_rendered_plots_from_options, close_rendered_plots

    input_path = tmp_path / "curves.csv"
    _multi_curve_csv(input_path)
    options = resolve_render_options(
        template="curve",
        style_preset="nature",
        palette_preset="colorblind_safe",
        visual_theme_id="clean_light",
        custom_theme_draft=_theme_payload(),
    )

    rendered = build_rendered_plots_from_options("curve", input_path, 0, options)
    try:
        line_colors = [to_hex(line.get_color()).lower() for line in rendered[0].figure.axes[0].lines]
        assert line_colors[:2] == ["#0ea5e9", "#f97316"]
    finally:
        close_rendered_plots(rendered)


def test_project_bundle_embeds_custom_theme_used_by_plot(tmp_path: Path, monkeypatch) -> None:
    from src.rendering import custom_theme_store

    monkeypatch.setattr(custom_theme_store, "USER_THEME_DIR", tmp_path / "themes")
    custom_theme_store.save_custom_theme(_theme_payload(), overwrite=True)

    source_path = tmp_path / "curve.csv"
    project_path = tmp_path / "curve.sciplotgod"
    _curve_csv(source_path)

    save_response = client.post(
        "/save-project",
        json={
            "project_path": str(project_path),
            "source_path": str(source_path),
            "payload": {
                "version": 2,
                "selected_workbench": "plot",
                "plot": {
                    "session_kind": "plot",
                    "source_filename": source_path.name,
                    "source_media_type": "text/csv",
                    "embedded_source_relpath": f"sources/plot/primary/{source_path.name}",
                    "source_sha256": "",
                    "sheet": 0,
                    "selected_template_id": "curve",
                    "render_options": {
                        "style_preset": "nature",
                        "palette_preset": "colorblind_safe",
                        "visual_theme_id": "clean_light",
                        "custom_theme_id": "user/nature_plus",
                    },
                },
                "data_studio": {
                    "session_kind": "data_studio",
                    "version": 2,
                    "workbook_paths": [str(source_path)],
                    "figure_preferences": [
                        {
                            "family_id": "representative_curve",
                            "selected_template_id": "curve",
                            "options_by_template": {
                                "curve": {
                                    "style_preset": "nature",
                                    "palette_preset": "colorblind_safe",
                                    "visual_theme_id": "clean_light",
                                    "custom_theme_id": "user/nature_plus",
                                }
                            },
                        }
                    ],
                },
                "composer": None,
                "code_console": None,
                "artifacts": {},
            },
        },
    )
    assert save_response.status_code == 200, save_response.text

    with zipfile.ZipFile(project_path) as archive:
        names = set(archive.namelist())
        assert "artifacts/custom_themes/user__nature_plus.json" in names
        assert archive.read("artifacts/custom_themes/user__nature_plus.json")

    (tmp_path / "themes" / "user__nature_plus.json").unlink()

    open_response = client.post("/open-project", json={"project_path": str(project_path)})
    assert open_response.status_code == 200, open_response.text
    payload = open_response.json()["payload"]
    assert payload["plot"]["render_options"]["custom_theme_id"] == "user/nature_plus"
    assert payload["plot"]["render_options"]["custom_theme_draft"]["id"] == "user/nature_plus"
    data_studio_options = payload["data_studio"]["figure_preferences"][0]["options_by_template"]["curve"]
    assert data_studio_options["custom_theme_id"] == "user/nature_plus"
    assert data_studio_options["custom_theme_draft"]["id"] == "user/nature_plus"
