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
