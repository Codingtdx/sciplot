from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np
import statsmodels.api as sm

from src.data_loader import CurveSeries

SUPPORTED_FIT_MODEL_IDS = ("linear", "polynomial_2", "polynomial_3")


@dataclass(frozen=True)
class FitOptions:
    enabled: bool = False
    model_id: str = "linear"


@dataclass(frozen=True)
class FitDerivedRow:
    row_index: int
    x: float
    y: float
    y_fit: float
    residual: float


@dataclass(frozen=True)
class FitSeriesResult:
    series_id: str
    series_label: str
    model_id: str
    x_label: str
    y_label: str
    coefficients: tuple[float, ...]
    r_squared: float
    rmse: float
    point_count: int
    derived_rows: tuple[FitDerivedRow, ...]
    warnings: tuple[str, ...] = ()

    @property
    def degree(self) -> int:
        if self.model_id == "linear":
            return 1
        if self.model_id == "polynomial_2":
            return 2
        if self.model_id == "polynomial_3":
            return 3
        raise ValueError(f"Unsupported fit model: {self.model_id}")

    @property
    def slope(self) -> float | None:
        if self.model_id != "linear":
            return None
        return self.coefficients[0]

    @property
    def intercept(self) -> float | None:
        if self.model_id != "linear":
            return None
        return self.coefficients[1]

    @property
    def equation_display(self) -> str:
        if self.model_id == "linear":
            slope = self.slope or 0.0
            intercept = self.intercept or 0.0
            sign = "+" if intercept >= 0 else "-"
            return f"y = {slope:.3g}x {sign} {abs(intercept):.3g}"
        terms: list[tuple[str, str]] = []
        degree = self.degree
        for index, coefficient in enumerate(self.coefficients):
            power = degree - index
            magnitude = abs(coefficient)
            if power == 0:
                token = f"{magnitude:.3g}"
            elif power == 1:
                token = f"{magnitude:.3g}x"
            else:
                token = f"{magnitude:.3g}x^{power}"
            sign = "-" if coefficient < 0 else "+"
            terms.append((sign, token))
        if not terms:
            return "y = 0"
        first_sign, first_token = terms[0]
        expression = f"-{first_token}" if first_sign == "-" else first_token
        for sign, token in terms[1:]:
            expression += f" {sign} {token}"
        return f"y = {expression}"

    @property
    def legend_label(self) -> str:
        if self.model_id == "linear":
            return f"fit: {self.equation_display}"
        return f"{self.series_label} fit"

    def predict(self, x_values: np.ndarray) -> np.ndarray:
        if self.model_id == "linear":
            slope = self.slope or 0.0
            intercept = self.intercept or 0.0
            return slope * x_values + intercept
        return np.polyval(np.asarray(self.coefficients, dtype=float), x_values)

    @property
    def x_line(self) -> np.ndarray:
        if not self.derived_rows:
            return np.asarray([], dtype=float)
        x_values = np.asarray([row.x for row in self.derived_rows], dtype=float)
        return np.linspace(float(np.min(x_values)), float(np.max(x_values)), 120, dtype=float)

    @property
    def y_line(self) -> np.ndarray:
        return self.predict(self.x_line)


@dataclass(frozen=True)
class FitAnalysisResult:
    model_id: str
    x_label: str
    y_label: str
    series_results: tuple[FitSeriesResult, ...]
    warnings: tuple[str, ...] = ()

    def selected_series(self, series_id: str | None = None) -> FitSeriesResult:
        if not self.series_results:
            raise ValueError("No fit series results are available.")
        if series_id:
            for result in self.series_results:
                if result.series_id == series_id:
                    return result
            raise ValueError(f"Unknown fit series: {series_id}")
        return self.series_results[0]


def normalize_fit_options_payload(value: object) -> dict[str, object]:
    if isinstance(value, FitOptions):
        return {"enabled": value.enabled, "model_id": value.model_id}
    if not isinstance(value, dict):
        return {"enabled": False, "model_id": "linear"}
    enabled = bool(value.get("enabled", False))
    model_id = str(value.get("model_id", "linear")).strip() or "linear"
    if model_id not in SUPPORTED_FIT_MODEL_IDS:
        model_id = "linear"
    return {"enabled": enabled, "model_id": model_id}


def fit_options_from_payload(value: object) -> FitOptions:
    payload = normalize_fit_options_payload(value)
    return FitOptions(
        enabled=bool(payload.get("enabled", False)),
        model_id=str(payload.get("model_id", "linear")),
    )


def _finite_points_for_series(series: CurveSeries) -> tuple[np.ndarray, np.ndarray, str, str]:
    frame = series.data.dropna(subset=["x", "y"])
    if frame.empty:
        raise ValueError("No valid X/Y points found.")
    x_values = frame["x"].to_numpy(dtype=float)
    y_values = frame["y"].to_numpy(dtype=float)
    valid = np.isfinite(x_values) & np.isfinite(y_values)
    if not np.any(valid):
        raise ValueError("No finite X/Y points found.")
    x_all = x_values[valid]
    y_all = y_values[valid]
    if x_all.size < 2:
        raise ValueError("At least two points are required to compute a fit.")
    if np.allclose(x_all, x_all[0]):
        raise ValueError("Fit cannot be computed when all x values are identical.")
    x_label = str(series.x_label or "x")
    y_label = str(series.y_label or "y")
    return x_all, y_all, x_label, y_label


def _series_identifier(series: CurveSeries, *, index: int, seen: set[str]) -> tuple[str, str]:
    label = str(series.sample or f"Series {index + 1}").strip() or f"Series {index + 1}"
    identifier = label
    suffix = 2
    while identifier in seen:
        identifier = f"{label} ({suffix})"
        suffix += 1
    seen.add(identifier)
    return identifier, label


def _linear_fit(x_all: np.ndarray, y_all: np.ndarray) -> tuple[tuple[float, ...], np.ndarray, float]:
    design_matrix = sm.add_constant(x_all, has_constant="add")
    model = sm.OLS(y_all, design_matrix).fit()
    intercept = float(model.params[0])
    slope = float(model.params[1])
    predicted = slope * x_all + intercept
    return (slope, intercept), predicted, float(model.rsquared)


def _polynomial_fit(
    x_all: np.ndarray,
    y_all: np.ndarray,
    *,
    degree: int,
) -> tuple[tuple[float, ...], np.ndarray, float]:
    if x_all.size < degree + 1:
        raise ValueError(f"At least {degree + 1} points are required to fit a polynomial of degree {degree}.")
    coefficients = np.polyfit(x_all, y_all, deg=degree)
    predicted = np.polyval(coefficients, x_all)
    residuals = y_all - predicted
    total_variance = float(np.sum(np.square(y_all - np.mean(y_all))))
    residual_variance = float(np.sum(np.square(residuals)))
    if math.isclose(total_variance, 0.0):
        r_squared = 1.0 if math.isclose(residual_variance, 0.0) else 0.0
    else:
        r_squared = max(0.0, 1.0 - residual_variance / total_variance)
    return tuple(float(value) for value in coefficients), predicted, r_squared


def fit_series(series: CurveSeries, *, model_id: str, series_id: str, series_label: str) -> FitSeriesResult:
    if model_id not in SUPPORTED_FIT_MODEL_IDS:
        raise ValueError(f"Unsupported fit model: {model_id}")
    x_all, y_all, x_label, y_label = _finite_points_for_series(series)
    if model_id == "linear":
        coefficients, predicted, r_squared = _linear_fit(x_all, y_all)
    elif model_id == "polynomial_2":
        coefficients, predicted, r_squared = _polynomial_fit(x_all, y_all, degree=2)
    else:
        coefficients, predicted, r_squared = _polynomial_fit(x_all, y_all, degree=3)
    residuals = y_all - predicted
    rmse = math.sqrt(float(np.mean(np.square(residuals))))
    derived_rows = tuple(
        FitDerivedRow(
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
    return FitSeriesResult(
        series_id=series_id,
        series_label=series_label,
        model_id=model_id,
        x_label=x_label,
        y_label=y_label,
        coefficients=coefficients,
        r_squared=r_squared,
        rmse=rmse,
        point_count=int(x_all.size),
        derived_rows=derived_rows,
    )


def fit_series_list(
    series_list: list[CurveSeries],
    *,
    model_id: str,
) -> FitAnalysisResult:
    if model_id not in SUPPORTED_FIT_MODEL_IDS:
        raise ValueError(f"Unsupported fit model: {model_id}")
    seen_ids: set[str] = set()
    warnings: list[str] = []
    results: list[FitSeriesResult] = []
    for index, series in enumerate(series_list):
        series_id, series_label = _series_identifier(series, index=index, seen=seen_ids)
        try:
            results.append(
                fit_series(
                    series,
                    model_id=model_id,
                    series_id=series_id,
                    series_label=series_label,
                )
            )
        except ValueError as exc:
            warnings.append(f"{series_label}: {exc}")
    if not results:
        if warnings:
            raise ValueError(" ".join(warnings))
        raise ValueError("No valid X/Y series found.")
    first = results[0]
    return FitAnalysisResult(
        model_id=model_id,
        x_label=first.x_label,
        y_label=first.y_label,
        series_results=tuple(results),
        warnings=tuple(warnings),
    )


def fit_linear_series_list(series_list: list[CurveSeries]) -> FitSeriesResult:
    return fit_series_list(series_list, model_id="linear").selected_series()


__all__ = [
    "FitAnalysisResult",
    "FitDerivedRow",
    "FitOptions",
    "FitSeriesResult",
    "SUPPORTED_FIT_MODEL_IDS",
    "fit_linear_series_list",
    "fit_options_from_payload",
    "fit_series",
    "fit_series_list",
    "normalize_fit_options_payload",
]
