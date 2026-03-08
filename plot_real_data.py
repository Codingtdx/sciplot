from __future__ import annotations

from pathlib import Path

import matplotlib.pyplot as plt

from src.data_loader import CurveSeries
from src.plot_style import save_pdf, use_nature_style
from src.plotting import plot_frequency_sweep, plot_stress_relaxation, plot_temperature_sweep
from src.rheology_loader import (
    load_frequency_sweep_metrics,
    load_stress_relaxation_metric,
    load_temperature_sweep_metrics,
)


def _to_curve_series(series_list: list) -> list[CurveSeries]:
    return [
        CurveSeries(
            sample=series.sample,
            x_label=series.x_label,
            y_label=series.y_label,
            x_unit=series.x_unit,
            y_unit=series.y_unit,
            data=series.data,
        )
        for series in series_list
    ]


def main() -> None:
    use_nature_style()
    outdir = Path("figures") / "real_data"
    outdir.mkdir(parents=True, exist_ok=True)

    freq_path = Path("/Users/dongxutian/Library/CloudStorage/OneDrive-HKUST(Guangzhou)/1 Vitrimer/3 D PA/流变/freq/1/freq1.xlsx")
    relax_path = Path("/Users/dongxutian/Library/CloudStorage/OneDrive-HKUST(Guangzhou)/1 Vitrimer/3 D PA/流变/stresss relaxation/1/stress relaxation.xlsx")
    temp_path = Path("/Users/dongxutian/Library/CloudStorage/OneDrive-HKUST(Guangzhou)/1 Vitrimer/3 D PA/流变/temp/1/temp1.xlsx")

    freq_metrics = load_frequency_sweep_metrics(freq_path)
    metric_filenames = {
        "storage_modulus": "freq_storage_modulus.pdf",
        "loss_modulus": "freq_loss_modulus.pdf",
        "loss_factor": "freq_loss_factor.pdf",
        "complex_viscosity": "freq_complex_viscosity.pdf",
    }
    for metric_name, filename in metric_filenames.items():
        fig, _ = plot_frequency_sweep(_to_curve_series(freq_metrics[metric_name]))
        print(save_pdf(fig, outdir / filename))
        plt.close(fig)

    temp_metrics = load_temperature_sweep_metrics(temp_path)
    temp_filenames = {
        "storage_modulus": "temp_storage_modulus.pdf",
        "complex_viscosity": "temp_complex_viscosity.pdf",
    }
    for metric_name, filename in temp_filenames.items():
        fig, _ = plot_temperature_sweep(_to_curve_series(temp_metrics[metric_name]))
        print(save_pdf(fig, outdir / filename))
        plt.close(fig)

    relax_series = _to_curve_series(load_stress_relaxation_metric(relax_path, metric_name="σ/σ₀"))
    fig, _ = plot_stress_relaxation(relax_series, y_padding_top=0.12, y_padding_bottom=0.04)
    print(save_pdf(fig, outdir / "stress_relaxation_sigma_over_sigma0.pdf"))
    plt.close(fig)


if __name__ == "__main__":
    main()
