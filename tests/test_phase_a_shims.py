import make_plot
from app.sidecar.server import app


def test_make_plot_entrypoint_exposes_cli_main() -> None:
    assert callable(make_plot.main)
    assert callable(make_plot._coerce_sheet)


def test_sidecar_entrypoint_exposes_active_app() -> None:
    assert app.title == "SciPlot God Sidecar"
