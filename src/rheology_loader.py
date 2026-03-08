from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import pandas as pd


@dataclass
class RheologySeries:
    sample: str
    x_label: str
    y_label: str
    x_unit: str
    y_unit: str
    data: pd.DataFrame


FREQ_LABEL_MAP = {
    "Angular Frequency": "ω",
    "Storage Modulus": "G'",
    "Loss Modulus": 'G"',
    "Loss Factor": "tanδ",
    "Complex Viscosity": "|η*|",
}

FREQ_UNIT_MAP = {
    "rad/s": r"rad$\cdot$s$^{-1}$",
    "mPa·s": r"mPa$\cdot$s",
}

RELAX_LABEL_MAP = {
    "Time": "t",
    "Shear Strain": "γ",
    "Shear Stress": "σ",
    "σ/σ0": r"$\sigma/\sigma_0$",
}

RELAX_UNIT_MAP = {
    "[s]": "s",
    "[%]": "%",
    "[Pa]": "Pa",
}


def _clean_text(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, float) and pd.isna(value):
        return ""
    return str(value).strip()


def _read_excel(path: str | Path, sheet_name: str | int = 0) -> pd.DataFrame:
    raw = pd.read_excel(path, sheet_name=sheet_name, header=None)
    return raw.dropna(axis=1, how="all")


def load_frequency_sweep_metrics(path: str | Path, sheet_name: str | int = 0) -> dict[str, list[RheologySeries]]:
    raw = _read_excel(path, sheet_name=sheet_name)
    if raw.shape[1] % 5 != 0:
        raise ValueError("Frequency sweep table must contain 5 columns per sample.")

    metric_series: dict[str, list[RheologySeries]] = {
        "storage_modulus": [],
        "loss_modulus": [],
        "loss_factor": [],
        "complex_viscosity": [],
    }
    metric_map = [
        ("storage_modulus", 1),
        ("loss_modulus", 2),
        ("loss_factor", 3),
        ("complex_viscosity", 4),
    ]

    for start in range(0, raw.shape[1], 5):
        labels = [_clean_text(raw.iloc[0, start + idx]) for idx in range(5)]
        sample = _clean_text(raw.iloc[1, start])
        units = [_clean_text(raw.iloc[2, start + idx]) for idx in range(5)]
        block = raw.iloc[3:, start : start + 5].copy().reset_index(drop=True)
        block.columns = ["x", "storage_modulus", "loss_modulus", "loss_factor", "complex_viscosity"]
        block = block.apply(pd.to_numeric, errors="coerce").dropna(how="all")

        x_label = FREQ_LABEL_MAP.get(labels[0], labels[0] or "ω")
        x_unit = FREQ_UNIT_MAP.get(units[0], units[0])

        for key, offset in metric_map:
            y_label = FREQ_LABEL_MAP.get(labels[offset], labels[offset] or key)
            y_unit = FREQ_UNIT_MAP.get(units[offset], units[offset])
            pair = block[["x", key]].dropna().rename(columns={key: "y"}).reset_index(drop=True)
            if pair.empty:
                continue
            metric_series[key].append(
                RheologySeries(
                    sample=sample or f"Sample_{start // 5 + 1}",
                    x_label=x_label,
                    y_label=y_label,
                    x_unit=x_unit,
                    y_unit=y_unit,
                    data=pair,
                )
            )

    return metric_series


def load_temperature_sweep_metrics(path: str | Path, sheet_name: str | int = 0) -> dict[str, list[RheologySeries]]:
    raw = _read_excel(path, sheet_name=sheet_name)
    if raw.shape[1] % 5 != 0:
        raise ValueError("Temperature sweep table must contain 5 columns per sample.")

    metric_series: dict[str, list[RheologySeries]] = {
        "storage_modulus": [],
        "complex_viscosity": [],
    }
    metric_map = [
        ("storage_modulus", 1),
        ("complex_viscosity", 4),
    ]

    for start in range(0, raw.shape[1], 5):
        labels = [_clean_text(raw.iloc[0, start + idx]) for idx in range(5)]
        sample = _clean_text(raw.iloc[1, start])
        units = [_clean_text(raw.iloc[2, start + idx]) for idx in range(5)]
        block = raw.iloc[3:, start : start + 5].copy().reset_index(drop=True)
        block.columns = ["x", "storage_modulus", "loss_modulus", "loss_factor", "complex_viscosity"]
        block = block.apply(pd.to_numeric, errors="coerce").dropna(how="all")

        x_label = "T"
        x_unit = units[0] or "°C"

        for key, offset in metric_map:
            y_label = FREQ_LABEL_MAP.get(labels[offset], labels[offset] or key)
            y_unit = FREQ_UNIT_MAP.get(units[offset], units[offset])
            pair = block[["x", key]].dropna().rename(columns={key: "y"}).reset_index(drop=True)
            if pair.empty:
                continue
            metric_series[key].append(
                RheologySeries(
                    sample=sample or f"Sample_{start // 5 + 1}",
                    x_label=x_label,
                    y_label=y_label,
                    x_unit=x_unit,
                    y_unit=y_unit,
                    data=pair,
                )
            )

    return metric_series


def load_stress_relaxation_metric(
    path: str | Path,
    metric_name: str = "σ/σ₀",
    sheet_name: str | int = 0,
) -> list[RheologySeries]:
    raw = _read_excel(path, sheet_name=sheet_name)
    if raw.shape[1] % 4 != 0:
        raise ValueError("Stress relaxation table must contain 4 columns per sample.")

    metric_aliases = {
        "σ/σ0": r"$\sigma/\sigma_0$",
        "σ/σ₀": r"$\sigma/\sigma_0$",
        r"$\sigma/\sigma_0$": r"$\sigma/\sigma_0$",
    }
    metric_key = metric_aliases.get(metric_name, metric_name)

    series_list: list[RheologySeries] = []
    for start in range(0, raw.shape[1], 4):
        labels = [_clean_text(raw.iloc[0, start + idx]) for idx in range(4)]
        sample_candidates = [_clean_text(raw.iloc[1, start + idx]) for idx in range(4)]
        sample = next((value for value in sample_candidates if value), "")
        units = [_clean_text(raw.iloc[2, start + idx]) for idx in range(4)]
        block = raw.iloc[3:, start : start + 4].copy().reset_index(drop=True)
        block.columns = ["time", "strain", "stress", "normalized_stress"]
        block = block.apply(pd.to_numeric, errors="coerce").dropna(how="all")

        y_label_lookup = [RELAX_LABEL_MAP.get(label, label) for label in labels]
        try:
            y_index = y_label_lookup.index(metric_key)
        except ValueError as exc:
            raise ValueError(f"Metric {metric_key!r} not found in stress relaxation table.") from exc

        metric_column = ["time", "strain", "stress", "normalized_stress"][y_index]
        pair = block[["time", metric_column]].dropna().rename(columns={"time": "x", metric_column: "y"}).reset_index(drop=True)
        if pair.empty:
            continue

        series_list.append(
            RheologySeries(
                sample=sample or f"Sample_{start // 4 + 1}",
                x_label=RELAX_LABEL_MAP.get(labels[0], labels[0] or "t"),
                y_label=metric_key,
                x_unit=RELAX_UNIT_MAP.get(units[0], units[0]),
                y_unit=RELAX_UNIT_MAP.get(units[y_index], units[y_index]),
                data=pair,
            )
        )

    return series_list
