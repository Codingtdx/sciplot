from __future__ import annotations

import pandas as pd
import pytest

from src.rendering.data_transforms import DataTransformError, apply_data_transforms_to_frame


def test_derived_column_uses_safe_column_expression() -> None:
    frame = pd.DataFrame(
        [
            ["x", "y"],
            [3.0, 4.0],
            [5.0, 12.0],
        ]
    )

    transformed = apply_data_transforms_to_frame(
        frame,
        [
            {
                "id": "radius",
                "kind": "derived_column",
                "target_column": "radius",
                "expression": "sqrt(x*x + y*y)",
            }
        ],
    )

    assert transformed.iloc[0].tolist() == ["x", "y", "radius"]
    assert transformed.iloc[1:, 2].tolist() == [5.0, 13.0]


def test_row_filter_between_preserves_header_and_filters_data_rows() -> None:
    frame = pd.DataFrame(
        [
            ["x", "stress"],
            [0.0, 10.0],
            [1.0, 20.0],
            [2.0, 30.0],
        ]
    )

    transformed = apply_data_transforms_to_frame(
        frame,
        [
            {
                "id": "window",
                "kind": "row_filter",
                "column": "stress",
                "operator": "between",
                "lower": 15,
                "upper": 25,
            }
        ],
    )

    assert transformed.iloc[:, 0].tolist() == ["x", 1.0]
    assert transformed.iloc[:, 1].tolist() == ["stress", 20.0]


def test_pivot_matrix_outputs_heatmap_xyz_long_table() -> None:
    frame = pd.DataFrame(
        [
            ["angle", "radius", "signal"],
            [0, 1, 10],
            [90, 1, 20],
            [0, 2, 30],
            [90, 2, 40],
        ]
    )

    transformed = apply_data_transforms_to_frame(
        frame,
        [
            {
                "id": "field",
                "kind": "pivot_matrix",
                "x_column": "angle",
                "y_column": "radius",
                "z_column": "signal",
                "output_mode": "xyz_long",
            }
        ],
    )

    assert transformed.iloc[:3].values.tolist() == [
        ["x", "y", "z"],
        ["angle", "radius", "signal"],
        ["", "", ""],
    ]
    assert transformed.iloc[3:].values.tolist() == [
        [0, 1, 10],
        [90, 1, 20],
        [0, 2, 30],
        [90, 2, 40],
    ]


def test_unsafe_expression_is_rejected_with_user_facing_error() -> None:
    frame = pd.DataFrame([["x"], [1.0]])

    with pytest.raises(DataTransformError, match="unsafe expression"):
        apply_data_transforms_to_frame(
            frame,
            [
                {
                    "id": "bad",
                    "kind": "derived_column",
                    "target_column": "oops",
                    "expression": "__import__('os').system('echo no')",
                }
            ],
        )


def test_unknown_column_is_rejected_with_transform_context() -> None:
    frame = pd.DataFrame([["x"], [1.0]])

    with pytest.raises(DataTransformError, match="unknown column `missing`"):
        apply_data_transforms_to_frame(
            frame,
            [
                {
                    "id": "missing",
                    "kind": "derived_column",
                    "target_column": "oops",
                    "expression": "missing + 1",
                }
            ],
        )


def test_transforms_support_variables_masks_and_complex_column_names() -> None:
    frame = pd.DataFrame(
        [
            ["time", "Storage Modulus", "group"],
            [0.0, 10.0, "A"],
            [1.0, 20.0, "B"],
            [2.0, 30.0, "A"],
        ]
    )

    transformed = apply_data_transforms_to_frame(
        frame,
        [
            {
                "id": "scaled",
                "kind": "derived_column",
                "target_column": "scaled",
                "expression": "col('Storage Modulus') / var('scale')",
            },
            {
                "id": "mask",
                "kind": "mask_filter",
                "expression": "(col('scaled') >= 10) & (col('group') == 'A')",
            },
        ],
        variables=[{"id": "scale", "kind": "scalar", "value": 2.0}],
    )

    assert transformed.iloc[0].tolist() == ["time", "Storage Modulus", "group", "scaled"]
    assert transformed.iloc[1:].values.tolist() == [[2.0, 30.0, "A", 15.0]]


def test_sort_select_type_cast_bin_aggregate_and_rolling_transforms() -> None:
    frame = pd.DataFrame(
        [
            ["group", "x", "signal"],
            ["B", "2", "10"],
            ["A", "0", "2"],
            ["A", "1", "4"],
            ["B", "3", "12"],
        ]
    )

    transformed = apply_data_transforms_to_frame(
        frame,
        [
            {"id": "cast", "kind": "type_cast", "columns": ["x", "signal"], "target_type": "number"},
            {"id": "sort", "kind": "sort_rows", "columns": ["group", "x"], "ascending": True},
            {"id": "smooth", "kind": "rolling_window", "column": "signal", "target_column": "smooth", "window": 2},
            {"id": "bins", "kind": "bin_column", "column": "signal", "target_column": "signal_bin", "bins": 2},
            {"id": "select", "kind": "select_columns", "columns": ["group", "x", "smooth", "signal_bin"]},
        ],
    )

    assert transformed.iloc[0].tolist() == ["group", "x", "smooth", "signal_bin"]
    assert transformed.iloc[1:, 0].tolist() == ["A", "A", "B", "B"]
    assert transformed.iloc[1:, 2].tolist() == [2.0, 3.0, 7.0, 11.0]
    assert transformed.iloc[1:, 3].tolist() == ["2-7", "2-7", "7-12", "7-12"]

    aggregated = apply_data_transforms_to_frame(
        frame,
        [
            {"id": "cast", "kind": "type_cast", "columns": ["signal"], "target_type": "number"},
            {
                "id": "agg",
                "kind": "aggregate_summary",
                "group_by": ["group"],
                "value_columns": ["signal"],
                "statistics": ["mean", "sd", "sem", "min", "max", "count"],
            },
        ],
    )

    assert aggregated.iloc[0].tolist() == [
        "group",
        "signal_mean",
        "signal_sd",
        "signal_sem",
        "signal_min",
        "signal_max",
        "signal_count",
    ]
    assert aggregated.iloc[1:].values.tolist() == [
        ["A", 3.0, pytest.approx(1.41421356237), 1.0, 2.0, 4.0, 2],
        ["B", 11.0, pytest.approx(1.41421356237), 1.0, 10.0, 12.0, 2],
    ]


def test_pivot_matrix_can_materialize_matrix_table() -> None:
    frame = pd.DataFrame(
        [
            ["x", "y", "z"],
            [0, 0, 1],
            [1, 0, 2],
            [0, 1, 3],
            [1, 1, 4],
        ]
    )

    transformed = apply_data_transforms_to_frame(
        frame,
        [
            {
                "id": "matrix",
                "kind": "pivot_matrix",
                "x_column": "x",
                "y_column": "y",
                "z_column": "z",
                "output_mode": "matrix",
            }
        ],
    )

    assert transformed.values.tolist() == [
        ["y/x", 0.0, 1.0],
        [0.0, 1.0, 2.0],
        [1.0, 3.0, 4.0],
    ]
