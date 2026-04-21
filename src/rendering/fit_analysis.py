from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np
import statsmodels.api as sm

from src.data_loader import CurveSeries


@dataclass(frozen=True)
class LinearFitDerivedRow:
    row_index: int
    x: float
    y: float
    y_fit: float
    residual: float


@dataclass(frozen=True)
class LinearFitResult:
    x_label: str
    y_label: str
    slope: float
    intercept: float
    r_squared: float
    rmse: float
    point_count: int
    derived_rows: tuple[LinearFitDerivedRow, ...]

    @property
    def equation_display(self) -> str:
        intercept = self.intercept
        sign = "+" if intercept >= 0 else "-"
        return f"y = {self.slope:.3g}x {sign} {abs(intercept):.3g}"

    @property
    def legend_label(self) -> str:
        return f"fit: {self.equation_display}"

    @property
    def x_line(self) -> np.ndarray:
        if not self.derived_rows:
            return np.asarray([], dtype=float)
        x_values = np.asarray([row.x for row in self.derived_rows], dtype=float)
        return np.linspace(float(np.min(x_values)), float(np.max(x_values)), 120, dtype=float)

    @property
    def y_line(self) -> np.ndarray:
        x_line = self.x_line
        return self.slope * x_line + self.intercept


def _finite_points(series_list: list[CurveSeries]) -> tuple[np.ndarray, np.ndarray, str, str]:
    x_blocks: list[np.ndarray] = []
    y_blocks: list[np.ndarray] = []
    x_label = ""
    y_label = ""
    for series in series_list:
        frame = series.data.dropna(subset=["x", "y"])
        if frame.empty:
            continue
        x_values = frame["x"].to_numpy(dtype=float)
        y_values = frame["y"].to_numpy(dtype=float)
        valid = np.isfinite(x_values) & np.isfinite(y_values)
        if not np.any(valid):
            continue
        if not x_label:
            x_label = str(series.x_label)
        if not y_label:
            y_label = str(series.y_label)
        x_blocks.append(x_values[valid])
        y_blocks.append(y_values[valid])
    if not x_blocks:
        raise ValueError("No valid X/Y series found.")
    x_all = np.concatenate(x_blocks)
    y_all = np.concatenate(y_blocks)
    if x_all.size < 2:
        raise ValueError("At least two points are required to compute a deterministic linear fit.")
    if np.allclose(x_all, x_all[0]):
        raise ValueError("Linear fit cannot be computed when all x values are identical.")
    return x_all, y_all, x_label, y_label


def fit_linear_series_list(series_list: list[CurveSeries]) -> LinearFitResult:
    x_all, y_all, x_label, y_label = _finite_points(series_list)
    design_matrix = sm.add_constant(x_all, has_constant="add")
    model = sm.OLS(y_all, design_matrix).fit()
    intercept = float(model.params[0])
    slope = float(model.params[1])
    predicted = slope * x_all + intercept
    residuals = y_all - predicted
    rmse = math.sqrt(float(np.mean(np.square(residuals))))
    derived_rows = tuple(
        LinearFitDerivedRow(
            row_index=index,
            x=float(x_value),
            y=float(y_value),
            y_fit=float(y_fit),
            residual=float(residual),
        )
        for index, (x_value, y_value, y_fit, residual) in enumerate(
            zip(x_all, y_all, predicted, residuals, strict=True)
        )
    )
    return LinearFitResult(
        x_label=x_label or "x",
        y_label=y_label or "y",
        slope=slope,
        intercept=intercept,
        r_squared=float(model.rsquared),
        rmse=rmse,
        point_count=int(x_all.size),
        derived_rows=derived_rows,
    )


__all__ = [
    "LinearFitDerivedRow",
    "LinearFitResult",
    "fit_linear_series_list",
]
