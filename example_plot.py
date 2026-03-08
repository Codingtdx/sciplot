from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

from src.data_loader import CurveSeries, load_curve_table, load_replicate_table
from src.plot_style import save_pdf, use_nature_style
from src.plotting import (
    plot_bar,
    plot_box,
    plot_curves,
    plot_frequency_sweep,
    plot_stress_relaxation,
    plot_temperature_sweep,
    plot_tensile_curve,
)


def make_series(sample: str, x: np.ndarray, y: np.ndarray, x_label: str, y_label: str, x_unit: str, y_unit: str) -> CurveSeries:
    return CurveSeries(
        sample=sample,
        x_label=x_label,
        y_label=y_label,
        x_unit=x_unit,
        y_unit=y_unit,
        data=pd.DataFrame({"x": x, "y": y}),
    )


def main() -> None:
    use_nature_style()
    curves = load_curve_table(Path("examples") / "curve_table.csv")
    groups = load_replicate_table(Path("examples") / "replicate_table.csv")
    outdir = Path("figures")

    fig, _ = plot_curves(curves)
    print(f"Saved plot to {save_pdf(fig, outdir / 'curve_demo.pdf')}")
    plt.close(fig)

    fig, _ = plot_box(groups)
    print(f"Saved plot to {save_pdf(fig, outdir / 'box_demo.pdf')}")
    plt.close(fig)

    fig, _ = plot_bar(groups)
    print(f"Saved plot to {save_pdf(fig, outdir / 'bar_demo.pdf')}")
    plt.close(fig)

    freq_x = np.logspace(-1, 2, 80)
    freq_series = [
        make_series("G'", freq_x, 2e3 * freq_x**0.32, "Frequency", "Modulus", r"rad$\cdot$s$^{-1}$", "Pa"),
        make_series('G"', freq_x, 8e2 * freq_x**0.21, "Frequency", "Modulus", r"rad$\cdot$s$^{-1}$", "Pa"),
    ]
    fig, _ = plot_frequency_sweep(freq_series)
    print(f"Saved plot to {save_pdf(fig, outdir / 'frequency_sweep_demo.pdf')}")
    plt.close(fig)

    temp_x = np.linspace(30, 220, 120)
    temp_series = [
        make_series("Sample A", temp_x, 10 ** (5.6 - 0.0048 * temp_x), "Temperature", "Complex Viscosity", "°C", "Pa s"),
        make_series("Sample B", temp_x, 10 ** (5.2 - 0.0039 * temp_x), "Temperature", "Complex Viscosity", "°C", "Pa s"),
    ]
    fig, _ = plot_temperature_sweep(temp_series)
    print(f"Saved plot to {save_pdf(fig, outdir / 'temperature_sweep_demo.pdf')}")
    plt.close(fig)

    relax_x = np.logspace(-1, 3, 90)
    relax_series = [
        make_series("Sample A", relax_x, 1.8 * np.exp(-np.log10(relax_x + 1) / 1.6) + 0.15, "Time", "Stress", "s", "MPa"),
        make_series("Sample B", relax_x, 1.5 * np.exp(-np.log10(relax_x + 1) / 1.9) + 0.12, "Time", "Stress", "s", "MPa"),
    ]
    fig, _ = plot_stress_relaxation(relax_series)
    print(f"Saved plot to {save_pdf(fig, outdir / 'stress_relaxation_demo.pdf')}")
    plt.close(fig)

    tensile_x = np.linspace(0, 220, 180)
    tensile_series = [
        make_series("Sample A", tensile_x, 0.09 * tensile_x + 8 * np.tanh((tensile_x - 25) / 35), "Strain", "Stress", "%", "MPa"),
        make_series("Sample B", tensile_x, 0.085 * tensile_x + 6.5 * np.tanh((tensile_x - 20) / 32), "Strain", "Stress", "%", "MPa"),
    ]
    fig, _ = plot_tensile_curve(tensile_series)
    print(f"Saved plot to {save_pdf(fig, outdir / 'tensile_curve_demo.pdf')}")
    plt.close(fig)


if __name__ == "__main__":
    main()
