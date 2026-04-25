from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from src.rendering.expression_engine import ExpressionError, evaluate_expression, evaluate_variables


def test_expression_engine_supports_complex_columns_and_variables() -> None:
    frame = pd.DataFrame(
        {
            "Storage Modulus": [10.0, 20.0],
            "Loss Modulus": [3.0, 4.0],
        }
    )
    variables = evaluate_variables(
        [
            {"id": "scale", "enabled": True, "kind": "scalar", "value": 2.0},
            {
                "id": "baseline",
                "enabled": True,
                "kind": "expression",
                "expression": "var('scale') + 1",
            },
        ],
        frame=frame,
    )

    result = evaluate_expression(
        "sqrt(col('Storage Modulus') * col('Storage Modulus')) / var('baseline')",
        frame=frame,
        variables=variables,
    )

    assert np.allclose(result, [10.0 / 3.0, 20.0 / 3.0])


def test_expression_engine_boolean_mask_rejects_unsafe_calls() -> None:
    frame = pd.DataFrame({"x": [1.0, 2.0, 3.0], "group": ["A", "B", "A"]})

    mask = evaluate_expression(
        "(col('x') >= 2) & (col('group') == 'A')",
        frame=frame,
        expect="boolean",
    )

    assert mask.tolist() == [False, False, True]
    with pytest.raises(ExpressionError, match="unsafe expression"):
        evaluate_expression("__import__('os').system('echo no')", frame=frame)

