from app.sidecar.server import app

import make_plot


def test_make_plot_shim_exposes_cli_main() -> None:
    assert callable(make_plot.main)
    assert callable(make_plot._coerce_sheet)


def test_sidecar_shim_exposes_active_app() -> None:
    assert app.title == "SciPlot God Sidecar"
