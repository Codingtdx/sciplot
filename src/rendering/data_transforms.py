from __future__ import annotations

import ast
import math
from collections.abc import Mapping, Sequence
from typing import Any

import numpy as np
import pandas as pd


class DataTransformError(ValueError):
    """Raised for user-facing typed data transform errors."""


DataTransformPayload = Mapping[str, Any]

_ALLOWED_FUNCTIONS = {
    "sin": np.sin,
    "cos": np.cos,
    "tan": np.tan,
    "exp": np.exp,
    "log": np.log,
    "sqrt": np.sqrt,
    "pow": np.power,
    "abs": np.abs,
    "min": np.minimum,
    "max": np.maximum,
}
_ALLOWED_OPERATORS = {"eq", "ne", "lt", "lte", "gt", "gte", "between"}


def _cell_text(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, float) and pd.isna(value):
        return ""
    return str(value).strip()


def _looks_numeric(value: object) -> bool:
    text = _cell_text(value)
    if not text:
        return False
    try:
        numeric = float(text)
    except ValueError:
        return False
    return math.isfinite(numeric)


def _row_numeric_count(frame: pd.DataFrame, row_index: int) -> int:
    if row_index < 0 or row_index >= frame.shape[0]:
        return 0
    return sum(1 for value in frame.iloc[row_index].tolist() if _looks_numeric(value))


def _infer_data_start(frame: pd.DataFrame) -> int:
    if frame.empty:
        return 0
    if (
        frame.shape[0] >= 4
        and _row_numeric_count(frame, 3) >= 2
        and (_row_numeric_count(frame, 1) < 2 or _row_numeric_count(frame, 2) < 2)
    ):
        first_rows = frame.iloc[:3]
        non_numeric_headers = sum(
            1
            for value in first_rows.to_numpy().ravel().tolist()
            if _cell_text(value) and not _looks_numeric(value)
        )
        if non_numeric_headers >= 2:
            return 3
    return 1 if frame.shape[0] > 1 else 0


def _headers_for(frame: pd.DataFrame) -> list[str]:
    if frame.empty:
        return []
    headers: list[str] = []
    seen: dict[str, int] = {}
    for index, value in enumerate(frame.iloc[0].tolist()):
        label = _cell_text(value) or f"Column {index + 1}"
        if label in seen:
            seen[label] += 1
            label = f"Column {index + 1}"
        else:
            seen[label] = 1
        headers.append(label)
    return headers


def _series_by_column(frame: pd.DataFrame, *, headers: Sequence[str], data_start: int) -> dict[str, pd.Series]:
    data = frame.iloc[data_start:].reset_index(drop=True)
    columns: dict[str, pd.Series] = {}
    for index, header in enumerate(headers):
        if index >= data.shape[1]:
            continue
        series = data.iloc[:, index]
        columns[header] = series
        columns[f"Column {index + 1}"] = series
    return columns


def _column_series(
    frame: pd.DataFrame,
    *,
    headers: Sequence[str],
    data_start: int,
    column: object,
    transform_label: str,
) -> pd.Series:
    name = str(column or "").strip()
    if not name:
        raise DataTransformError(f"{transform_label}: column must not be empty.")
    columns = _series_by_column(frame, headers=headers, data_start=data_start)
    if name not in columns:
        raise DataTransformError(f"{transform_label}: unknown column `{name}`.")
    return columns[name].reset_index(drop=True)


def _safe_expression_result(
    expression: object,
    *,
    columns: Mapping[str, pd.Series],
    row_count: int,
    transform_label: str,
) -> pd.Series:
    expression_text = str(expression or "").strip()
    if not expression_text:
        raise DataTransformError(f"{transform_label}: expression must not be empty.")
    try:
        tree = ast.parse(expression_text, mode="eval")
    except SyntaxError as exc:
        raise DataTransformError(f"{transform_label}: unsafe expression `{expression_text}`.") from exc

    def evaluate(node: ast.AST) -> Any:
        if isinstance(node, ast.Expression):
            return evaluate(node.body)
        if isinstance(node, ast.Constant) and isinstance(node.value, int | float):
            return float(node.value)
        if isinstance(node, ast.Name):
            if node.id in columns:
                return pd.to_numeric(columns[node.id], errors="coerce")
            if node.id in _ALLOWED_FUNCTIONS:
                return _ALLOWED_FUNCTIONS[node.id]
            raise DataTransformError(f"{transform_label}: unknown column `{node.id}`.")
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.UAdd, ast.USub)):
            value = evaluate(node.operand)
            return value if isinstance(node.op, ast.UAdd) else -value
        if isinstance(node, ast.BinOp) and isinstance(
            node.op,
            (ast.Add, ast.Sub, ast.Mult, ast.Div, ast.Pow, ast.Mod),
        ):
            left = evaluate(node.left)
            right = evaluate(node.right)
            if isinstance(node.op, ast.Add):
                return left + right
            if isinstance(node.op, ast.Sub):
                return left - right
            if isinstance(node.op, ast.Mult):
                return left * right
            if isinstance(node.op, ast.Div):
                return left / right
            if isinstance(node.op, ast.Pow):
                return np.power(left, right)
            return left % right
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
            function = _ALLOWED_FUNCTIONS.get(node.func.id)
            if function is None:
                raise DataTransformError(f"{transform_label}: unsafe expression uses `{node.func.id}`.")
            if node.keywords:
                raise DataTransformError(f"{transform_label}: unsafe expression uses keyword arguments.")
            args = [evaluate(arg) for arg in node.args]
            return function(*args)
        raise DataTransformError(f"{transform_label}: unsafe expression `{expression_text}`.")

    result = evaluate(tree)
    if isinstance(result, pd.Series):
        numeric = pd.to_numeric(result, errors="coerce")
    elif isinstance(result, np.ndarray):
        if result.size != row_count:
            raise DataTransformError(f"{transform_label}: expression result length does not match the table.")
        numeric = pd.Series(result)
    elif isinstance(result, int | float):
        numeric = pd.Series([float(result)] * row_count)
    else:
        raise DataTransformError(f"{transform_label}: expression produced a nonnumeric result.")
    if len(numeric) != row_count:
        raise DataTransformError(f"{transform_label}: expression result length does not match the table.")
    if numeric.isna().any():
        raise DataTransformError(f"{transform_label}: expression produced a nonnumeric result.")
    return numeric.reset_index(drop=True)


def _target_column_index(headers: Sequence[str], target_column: str) -> int | None:
    try:
        return list(headers).index(target_column)
    except ValueError:
        return None


def _apply_derived_column(frame: pd.DataFrame, transform: DataTransformPayload, *, index: int) -> pd.DataFrame:
    label = _transform_label(transform, index)
    target = str(transform.get("target_column") or "").strip()
    if not target:
        raise DataTransformError(f"{label}: target_column must not be empty.")
    data_start = _infer_data_start(frame)
    headers = _headers_for(frame)
    columns = _series_by_column(frame, headers=headers, data_start=data_start)
    row_count = max(0, frame.shape[0] - data_start)
    result = _safe_expression_result(
        transform.get("expression"),
        columns=columns,
        row_count=row_count,
        transform_label=label,
    )
    output = frame.copy(deep=True).astype(object)
    existing_index = _target_column_index(headers, target)
    if existing_index is not None:
        output.iloc[data_start:, existing_index] = result.tolist()
        return output
    next_col = output.shape[1]
    output[next_col] = pd.Series([""] * output.shape[0], dtype=object)
    output.iat[0, next_col] = target
    if data_start >= 3 and output.shape[0] > 2:
        output.iat[2, next_col] = target
    output.iloc[data_start:, next_col] = result.tolist()
    return output


def _compare_filter(series: pd.Series, transform: DataTransformPayload, *, label: str) -> pd.Series:
    operator = str(transform.get("operator") or "").strip().lower()
    if operator not in _ALLOWED_OPERATORS:
        allowed = ", ".join(sorted(_ALLOWED_OPERATORS))
        raise DataTransformError(f"{label}: row_filter.operator must be one of {allowed}.")
    if operator in {"eq", "ne"}:
        value = transform.get("value")
        numeric = pd.to_numeric(series, errors="coerce")
        try:
            compare_value = float(str(value))
            if numeric.notna().any():
                mask = numeric == compare_value
            else:
                mask = series.map(_cell_text) == _cell_text(value)
        except ValueError:
            mask = series.map(_cell_text) == _cell_text(value)
        return ~mask if operator == "ne" else mask
    numeric_series = pd.to_numeric(series, errors="coerce")
    if numeric_series.isna().any():
        raise DataTransformError(f"{label}: row_filter column must be numeric for operator `{operator}`.")
    if operator == "between":
        lower = transform.get("lower")
        upper = transform.get("upper")
        if lower is None or upper is None:
            raise DataTransformError(f"{label}: between row_filter requires lower and upper.")
        return (numeric_series >= float(lower)) & (numeric_series <= float(upper))
    value = transform.get("value")
    if value is None:
        raise DataTransformError(f"{label}: row_filter requires value for operator `{operator}`.")
    numeric_value = float(value)
    if operator == "lt":
        return numeric_series < numeric_value
    if operator == "lte":
        return numeric_series <= numeric_value
    if operator == "gt":
        return numeric_series > numeric_value
    return numeric_series >= numeric_value


def _apply_row_filter(frame: pd.DataFrame, transform: DataTransformPayload, *, index: int) -> pd.DataFrame:
    label = _transform_label(transform, index)
    data_start = _infer_data_start(frame)
    headers = _headers_for(frame)
    series = _column_series(
        frame,
        headers=headers,
        data_start=data_start,
        column=transform.get("column"),
        transform_label=label,
    )
    mask = _compare_filter(series, transform, label=label).reset_index(drop=True)
    data = frame.iloc[data_start:].reset_index(drop=True)
    filtered = data.loc[mask.tolist()].reset_index(drop=True)
    if filtered.empty:
        raise DataTransformError(f"{label}: row_filter removed every data row.")
    header = frame.iloc[:data_start].reset_index(drop=True)
    return pd.concat([header, filtered], ignore_index=True)


def _apply_pivot_matrix(frame: pd.DataFrame, transform: DataTransformPayload, *, index: int) -> pd.DataFrame:
    label = _transform_label(transform, index)
    output_mode = str(transform.get("output_mode") or "xyz_long").strip().lower()
    if output_mode != "xyz_long":
        raise DataTransformError(f"{label}: pivot_matrix.output_mode currently supports only `xyz_long`.")
    data_start = _infer_data_start(frame)
    headers = _headers_for(frame)
    x_series = _column_series(
        frame,
        headers=headers,
        data_start=data_start,
        column=transform.get("x_column"),
        transform_label=label,
    )
    y_series = _column_series(
        frame,
        headers=headers,
        data_start=data_start,
        column=transform.get("y_column"),
        transform_label=label,
    )
    z_series = _column_series(
        frame,
        headers=headers,
        data_start=data_start,
        column=transform.get("z_column"),
        transform_label=label,
    )
    data = pd.DataFrame(
        {
            "x": pd.to_numeric(x_series, errors="coerce"),
            "y": pd.to_numeric(y_series, errors="coerce"),
            "z": pd.to_numeric(z_series, errors="coerce"),
        }
    ).dropna(subset=["x", "y", "z"])
    if data.empty:
        raise DataTransformError(f"{label}: invalid pivot roles; X, Y and Z must contain numeric values.")
    duplicate_pairs = data.duplicated(subset=["x", "y"], keep=False)
    if duplicate_pairs.any():
        raise DataTransformError(f"{label}: invalid pivot roles; duplicate X/Y cells are not supported in v1.")
    header_rows = pd.DataFrame(
        [
            ["x", "y", "z"],
            [
                str(transform.get("x_column") or "X"),
                str(transform.get("y_column") or "Y"),
                str(transform.get("z_column") or "Z"),
            ],
            ["", "", ""],
        ]
    )
    data_rows = data.reset_index(drop=True)
    data_rows.columns = [0, 1, 2]
    return pd.concat([header_rows, data_rows], ignore_index=True)


def _transform_label(transform: DataTransformPayload, index: int) -> str:
    label = str(transform.get("label") or transform.get("id") or f"transform {index + 1}").strip()
    return f"data_transforms[{index}] {label}"


def normalize_data_transforms_payload(value: object) -> tuple[dict[str, Any], ...] | None:
    if value is None:
        return None
    if not isinstance(value, Sequence) or isinstance(value, (str, bytes, bytearray)):
        raise DataTransformError("`data_transforms` must be a list of mappings.")
    normalized: list[dict[str, Any]] = []
    seen: set[str] = set()
    for index, item in enumerate(value):
        if not isinstance(item, Mapping):
            raise DataTransformError(f"`data_transforms[{index}]` must be a mapping.")
        transform = dict(item)
        transform_id = str(transform.get("id") or "").strip()
        if not transform_id:
            raise DataTransformError(f"`data_transforms[{index}].id` must not be empty.")
        if transform_id in seen:
            raise DataTransformError("`data_transforms` ids must be unique.")
        seen.add(transform_id)
        kind = str(transform.get("kind") or "").strip().lower()
        if kind not in {"derived_column", "row_filter", "pivot_matrix"}:
            raise DataTransformError(
                f"`data_transforms[{index}].kind` must be one of derived_column, row_filter, pivot_matrix."
            )
        transform["id"] = transform_id
        transform["kind"] = kind
        transform["enabled"] = bool(transform.get("enabled", True))
        transform["label"] = str(transform.get("label") or "").strip() or None
        normalized.append(transform)
    return tuple(normalized) if normalized else None


def apply_data_transforms_to_frame(
    frame: pd.DataFrame,
    transforms: object,
) -> pd.DataFrame:
    normalized = normalize_data_transforms_payload(transforms)
    if normalized is None:
        return frame.copy(deep=True)
    output = frame.copy(deep=True).astype(object)
    for index, transform in enumerate(normalized):
        if not transform.get("enabled", True):
            continue
        kind = transform["kind"]
        if kind == "derived_column":
            output = _apply_derived_column(output, transform, index=index)
        elif kind == "row_filter":
            output = _apply_row_filter(output, transform, index=index)
        elif kind == "pivot_matrix":
            output = _apply_pivot_matrix(output, transform, index=index)
        else:  # pragma: no cover - normalized above
            raise DataTransformError(f"{_transform_label(transform, index)}: unsupported transform kind `{kind}`.")
    return output


__all__ = [
    "DataTransformError",
    "DataTransformPayload",
    "apply_data_transforms_to_frame",
    "normalize_data_transforms_payload",
]
