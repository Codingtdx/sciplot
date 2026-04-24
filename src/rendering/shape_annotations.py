from __future__ import annotations

import math
from collections.abc import Iterable, Mapping
from dataclasses import dataclass, replace
from typing import TypedDict

from matplotlib.axes import Axes
from matplotlib.patches import Ellipse, Rectangle

from src import plot_style
from src.rendering.advanced_plot_axes import primary_axis, secondary_y_axis
from src.rendering.axis_breaks import (
    axis_break_panel_axes,
    axis_break_panel_for_value,
    axis_break_panel_range,
    transform_axis_break_interval_segments,
    transform_axis_break_value,
    value_hidden_by_axis_break,
)
from src.rendering.models import QAReport, RenderedPlot, RenderOptions

_VALID_SHAPE_KINDS = frozenset({"rectangle", "ellipse", "bracket"})
_VALID_BRACKET_ORIENTATIONS = frozenset({"horizontal", "vertical"})
_VALID_Y_AXIS_TARGETS = frozenset({"y_primary", "y_secondary"})


class ShapeAnnotationPayloadDict(TypedDict):
    id: str
    enabled: bool
    kind: str
    bracket_orientation: str
    x_start: float
    x_end: float
    y_start: float
    y_end: float
    y_axis_target: str
    label: str | None


@dataclass(frozen=True)
class ShapeAnnotationOptions:
    id: str
    enabled: bool = True
    kind: str = "rectangle"
    bracket_orientation: str = "horizontal"
    x_start: float = 0.0
    x_end: float = 1.0
    y_start: float = 0.0
    y_end: float = 1.0
    y_axis_target: str = "y_primary"
    label: str | None = None


@dataclass(frozen=True)
class _AxisInterval:
    axis: Axes
    start: float
    end: float


def _string(value: object, *, field_name: str, default: str) -> str:
    cleaned = str(value if value is not None else default).strip() or default
    if not cleaned:
        raise ValueError(f"`{field_name}` must not be blank.")
    return cleaned


def _finite_float(value: object, *, field_name: str, default: float) -> float:
    if value is None:
        numeric = default
    elif isinstance(value, int | float | str):
        numeric = float(value)
    else:
        raise ValueError(f"`{field_name}` must be numeric.")
    if not math.isfinite(numeric):
        raise ValueError(f"`{field_name}` must be a finite number.")
    return numeric


def _enum(
    value: object,
    *,
    field_name: str,
    default: str,
    allowed: frozenset[str],
) -> str:
    resolved = _string(value, field_name=field_name, default=default).lower()
    if resolved not in allowed:
        raise ValueError(f"`{field_name}` must be one of {', '.join(sorted(allowed))}.")
    return resolved


def _normalized_label(value: object) -> str | None:
    if value is None:
        return None
    cleaned = str(value).strip()
    return cleaned or None


def _iter_annotation_maps(value: object) -> tuple[Mapping[str, object], ...]:
    if value is None:
        return ()
    if not isinstance(value, Iterable) or isinstance(value, (str, bytes, bytearray, Mapping)):
        raise ValueError("`shape_annotations` must be a list of mappings.")
    items: list[Mapping[str, object]] = []
    for item in value:
        if not isinstance(item, Mapping):
            raise ValueError("`shape_annotations` items must be mappings.")
        items.append(item)
    return tuple(items)


def normalize_shape_annotations_payload(value: object) -> tuple[ShapeAnnotationPayloadDict, ...] | None:
    items = _iter_annotation_maps(value)
    if not items:
        return None
    normalized: list[ShapeAnnotationPayloadDict] = []
    seen_ids: set[str] = set()
    for index, item in enumerate(items):
        annotation_id = _string(
            item.get("id"),
            field_name=f"shape_annotations[{index}].id",
            default=f"shape-annotation-{index + 1}",
        )
        if annotation_id in seen_ids:
            raise ValueError("`shape_annotations` ids must be unique.")
        seen_ids.add(annotation_id)
        x_start = _finite_float(
            item.get("x_start"),
            field_name=f"shape_annotations[{index}].x_start",
            default=0.0,
        )
        x_end = _finite_float(
            item.get("x_end"),
            field_name=f"shape_annotations[{index}].x_end",
            default=1.0,
        )
        y_start = _finite_float(
            item.get("y_start"),
            field_name=f"shape_annotations[{index}].y_start",
            default=0.0,
        )
        y_end = _finite_float(
            item.get("y_end"),
            field_name=f"shape_annotations[{index}].y_end",
            default=1.0,
        )
        if x_end < x_start:
            x_start, x_end = x_end, x_start
        if y_end < y_start:
            y_start, y_end = y_end, y_start
        normalized.append(
            {
                "id": annotation_id,
                "enabled": bool(item.get("enabled", True)),
                "kind": _enum(
                    item.get("kind"),
                    field_name=f"shape_annotations[{index}].kind",
                    default="rectangle",
                    allowed=_VALID_SHAPE_KINDS,
                ),
                "bracket_orientation": _enum(
                    item.get("bracket_orientation"),
                    field_name=f"shape_annotations[{index}].bracket_orientation",
                    default="horizontal",
                    allowed=_VALID_BRACKET_ORIENTATIONS,
                ),
                "x_start": x_start,
                "x_end": x_end,
                "y_start": y_start,
                "y_end": y_end,
                "y_axis_target": _enum(
                    item.get("y_axis_target"),
                    field_name=f"shape_annotations[{index}].y_axis_target",
                    default="y_primary",
                    allowed=_VALID_Y_AXIS_TARGETS,
                ),
                "label": _normalized_label(item.get("label")),
            }
        )
    return tuple(normalized)


def shape_annotations_from_payload(value: object) -> tuple[ShapeAnnotationOptions, ...]:
    payload = normalize_shape_annotations_payload(value)
    if payload is None:
        return ()
    return tuple(
        ShapeAnnotationOptions(
            id=item["id"],
            enabled=item["enabled"],
            kind=item["kind"],
            bracket_orientation=item["bracket_orientation"],
            x_start=item["x_start"],
            x_end=item["x_end"],
            y_start=item["y_start"],
            y_end=item["y_end"],
            y_axis_target=item["y_axis_target"],
            label=item["label"],
        )
        for item in payload
    )


def _annotation_y_axis(
    annotation: ShapeAnnotationOptions,
    *,
    rendered: RenderedPlot,
) -> Axes | None:
    if annotation.y_axis_target == "y_secondary":
        return secondary_y_axis(rendered)
    return primary_axis(rendered)


def _validate_log_coordinate(*, axis_label: str, value: float, scale: str, kind: str) -> None:
    if scale == "log" and value <= 0.0:
        raise ValueError(f"{kind} on a log {axis_label} axis requires positive values.")


def _validate_shape_annotation(annotation: ShapeAnnotationOptions, *, options: RenderOptions) -> None:
    kind_label = "Shape annotation"
    _validate_log_coordinate(axis_label="X", value=annotation.x_start, scale=options.xscale, kind=kind_label)
    _validate_log_coordinate(axis_label="X", value=annotation.x_end, scale=options.xscale, kind=kind_label)
    _validate_log_coordinate(axis_label="Y", value=annotation.y_start, scale=options.yscale, kind=kind_label)
    _validate_log_coordinate(axis_label="Y", value=annotation.y_end, scale=options.yscale, kind=kind_label)


def _pixel_offset_point(ax: Axes, *, x: float, y: float, dx: float = 0.0, dy: float = 0.0) -> tuple[float, float]:
    display_x, display_y = ax.transData.transform((x, y))
    mapped_x, mapped_y = ax.transData.inverted().transform((display_x + dx, display_y + dy))
    return float(mapped_x), float(mapped_y)


def _x_intervals(
    rendered: RenderedPlot,
    *,
    start: float,
    end: float,
) -> tuple[_AxisInterval, ...]:
    primary = primary_axis(rendered)
    if primary is None:
        return ()
    panel_axes = axis_break_panel_axes(rendered, axis_name="x")
    if len(panel_axes) > 1:
        intervals: list[_AxisInterval] = []
        for axis in panel_axes:
            visible_range = axis_break_panel_range(axis, axis_name="x")
            if visible_range is None:
                continue
            overlap_start = max(start, visible_range[0])
            overlap_end = min(end, visible_range[1])
            if overlap_end <= overlap_start:
                continue
            intervals.append(_AxisInterval(axis=axis, start=overlap_start, end=overlap_end))
        return tuple(intervals)
    segments = transform_axis_break_interval_segments(primary, axis_name="x", start=start, end=end)
    return tuple(
        _AxisInterval(axis=primary, start=segment[0], end=segment[1])
        for segment in segments
        if segment[1] > segment[0]
    )


def _y_intervals(
    rendered: RenderedPlot,
    *,
    axis: Axes,
    start: float,
    end: float,
) -> tuple[_AxisInterval, ...]:
    primary = primary_axis(rendered)
    if primary is None:
        return ()
    if axis is not primary:
        return (_AxisInterval(axis=axis, start=start, end=end),) if end > start else ()
    panel_axes = axis_break_panel_axes(rendered, axis_name="y")
    if len(panel_axes) > 1:
        intervals: list[_AxisInterval] = []
        for panel_axis in panel_axes:
            visible_range = axis_break_panel_range(panel_axis, axis_name="y")
            if visible_range is None:
                continue
            overlap_start = max(start, visible_range[0])
            overlap_end = min(end, visible_range[1])
            if overlap_end <= overlap_start:
                continue
            intervals.append(_AxisInterval(axis=panel_axis, start=overlap_start, end=overlap_end))
        return tuple(intervals)
    segments = transform_axis_break_interval_segments(primary, axis_name="y", start=start, end=end)
    return tuple(
        _AxisInterval(axis=primary, start=segment[0], end=segment[1])
        for segment in segments
        if segment[1] > segment[0]
    )


def _mapped_x_anchor(rendered: RenderedPlot, *, value: float) -> tuple[Axes, float] | None:
    primary = primary_axis(rendered)
    if primary is None:
        return None
    panel_axes = axis_break_panel_axes(rendered, axis_name="x")
    if len(panel_axes) > 1:
        panel_axis = axis_break_panel_for_value(rendered, axis_name="x", value=value)
        if panel_axis is None:
            return None
        return panel_axis, value
    if value_hidden_by_axis_break(primary, axis_name="x", value=value):
        return None
    mapped = transform_axis_break_value(primary, axis_name="x", value=value)
    if mapped is None:
        return None
    return primary, float(mapped)


def _mapped_y_anchor(
    rendered: RenderedPlot,
    *,
    axis: Axes,
    value: float,
) -> tuple[Axes, float] | None:
    primary = primary_axis(rendered)
    if primary is None:
        return None
    if axis is not primary:
        return axis, value
    panel_axes = axis_break_panel_axes(rendered, axis_name="y")
    if len(panel_axes) > 1:
        panel_axis = axis_break_panel_for_value(rendered, axis_name="y", value=value)
        if panel_axis is None:
            return None
        return panel_axis, value
    if value_hidden_by_axis_break(primary, axis_name="y", value=value):
        return None
    mapped = transform_axis_break_value(primary, axis_name="y", value=value)
    if mapped is None:
        return None
    return primary, float(mapped)


def _patch_label_target(
    drawn_regions: tuple[tuple[Axes, float, float, float, float], ...]
) -> tuple[Axes, float, float] | None:
    if not drawn_regions:
        return None
    best_axis, best_x0, best_x1, best_y0, best_y1 = max(
        drawn_regions,
        key=lambda item: abs(item[2] - item[1]) * abs(item[4] - item[3]),
    )
    return best_axis, (best_x0 + best_x1) / 2.0, (best_y0 + best_y1) / 2.0


def _draw_region_shape(
    annotation: ShapeAnnotationOptions,
    *,
    rendered: RenderedPlot,
    color: object,
    line_width: float,
    font_size: float,
) -> bool:
    target_axis = _annotation_y_axis(annotation, rendered=rendered)
    if target_axis is None:
        return False
    x_intervals = _x_intervals(rendered, start=annotation.x_start, end=annotation.x_end)
    y_intervals = _y_intervals(rendered, axis=target_axis, start=annotation.y_start, end=annotation.y_end)
    if not x_intervals or not y_intervals:
        return False

    drawn_regions: list[tuple[Axes, float, float, float, float]] = []
    for x_interval in x_intervals:
        for y_interval in y_intervals:
            draw_axis = y_interval.axis if y_interval.axis is not primary_axis(rendered) else x_interval.axis
            x0, x1 = x_interval.start, x_interval.end
            y0, y1 = y_interval.start, y_interval.end
            if x1 <= x0 or y1 <= y0:
                continue
            patch: Rectangle | Ellipse
            if annotation.kind == "ellipse":
                patch = Ellipse(
                    ((x0 + x1) / 2.0, (y0 + y1) / 2.0),
                    width=x1 - x0,
                    height=y1 - y0,
                    facecolor=color,
                    edgecolor=color,
                    alpha=0.12,
                    linewidth=line_width,
                    zorder=3.25,
                )
            else:
                patch = Rectangle(
                    (x0, y0),
                    width=x1 - x0,
                    height=y1 - y0,
                    facecolor=color,
                    edgecolor=color,
                    alpha=0.12,
                    linewidth=line_width,
                    zorder=3.25,
                )
            draw_axis.add_patch(patch)
            drawn_regions.append((draw_axis, x0, x1, y0, y1))

    label_target = _patch_label_target(tuple(drawn_regions))
    if annotation.label and label_target is not None:
        label_axis, label_x, label_y = label_target
        label_axis.text(
            label_x,
            label_y,
            annotation.label,
            ha="center",
            va="center",
            fontsize=font_size,
            color=color,
            zorder=3.35,
        )
    return bool(drawn_regions)


def _draw_horizontal_bracket(
    annotation: ShapeAnnotationOptions,
    *,
    rendered: RenderedPlot,
    anchor_axis: Axes,
    anchor_y: float,
    color: object,
    line_width: float,
    font_size: float,
) -> bool:
    x_intervals = _x_intervals(rendered, start=annotation.x_start, end=annotation.x_end)
    if not x_intervals:
        return False

    label_target: tuple[Axes, float, float] | None = None
    label_span = -1.0
    applied = False
    for interval in x_intervals:
        draw_axis = interval.axis
        x0, x1 = interval.start, interval.end
        if x1 <= x0:
            continue
        _, arm_y = _pixel_offset_point(draw_axis, x=x0, y=anchor_y, dy=12.0)
        draw_axis.plot(
            [x0, x0, x1, x1],
            [anchor_y, arm_y, arm_y, anchor_y],
            color=color,
            linewidth=line_width,
            alpha=0.9,
            zorder=3.5,
        )
        applied = True
        span = abs(x1 - x0)
        if span > label_span:
            label_span = span
            label_x = (x0 + x1) / 2.0
            _, label_y = _pixel_offset_point(draw_axis, x=label_x, y=arm_y, dy=5.0)
            label_target = (draw_axis, label_x, label_y)

    if annotation.label and label_target is not None:
        label_axis, label_x, label_y = label_target
        label_axis.text(
            label_x,
            label_y,
            annotation.label,
            ha="center",
            va="bottom",
            fontsize=font_size,
            color=color,
            zorder=3.55,
        )
    return applied


def _draw_vertical_bracket(
    annotation: ShapeAnnotationOptions,
    *,
    rendered: RenderedPlot,
    anchor_axis: Axes,
    anchor_x: float,
    color: object,
    line_width: float,
    font_size: float,
) -> bool:
    y_intervals = _y_intervals(rendered, axis=anchor_axis, start=annotation.y_start, end=annotation.y_end)
    if not y_intervals:
        return False

    label_target: tuple[Axes, float, float] | None = None
    label_span = -1.0
    applied = False
    for interval in y_intervals:
        draw_axis = interval.axis
        y0, y1 = interval.start, interval.end
        if y1 <= y0:
            continue
        arm_x, _ = _pixel_offset_point(draw_axis, x=anchor_x, y=y0, dx=12.0)
        draw_axis.plot(
            [anchor_x, arm_x, arm_x, anchor_x],
            [y0, y0, y1, y1],
            color=color,
            linewidth=line_width,
            alpha=0.9,
            zorder=3.5,
        )
        applied = True
        span = abs(y1 - y0)
        if span > label_span:
            label_span = span
            label_y = (y0 + y1) / 2.0
            label_x, _ = _pixel_offset_point(draw_axis, x=arm_x, y=label_y, dx=5.0)
            label_target = (draw_axis, label_x, label_y)

    if annotation.label and label_target is not None:
        label_axis, label_x, label_y = label_target
        label_axis.text(
            label_x,
            label_y,
            annotation.label,
            ha="left",
            va="center",
            fontsize=font_size,
            color=color,
            zorder=3.55,
        )
    return applied


def _draw_bracket_shape(
    annotation: ShapeAnnotationOptions,
    *,
    rendered: RenderedPlot,
    color: object,
    line_width: float,
    font_size: float,
) -> bool:
    target_axis = _annotation_y_axis(annotation, rendered=rendered)
    if target_axis is None:
        return False
    if annotation.bracket_orientation == "vertical":
        anchor = _mapped_x_anchor(rendered, value=annotation.x_start)
        if anchor is None:
            return False
        anchor_axis, anchor_x = anchor
        return _draw_vertical_bracket(
            annotation,
            rendered=rendered,
            anchor_axis=anchor_axis,
            anchor_x=anchor_x,
            color=color,
            line_width=line_width,
            font_size=font_size,
        )

    anchor = _mapped_y_anchor(rendered, axis=target_axis, value=annotation.y_start)
    if anchor is None:
        return False
    anchor_axis, anchor_y = anchor
    return _draw_horizontal_bracket(
        annotation,
        rendered=rendered,
        anchor_axis=anchor_axis,
        anchor_y=anchor_y,
        color=color,
        line_width=line_width,
        font_size=font_size,
    )


def apply_shape_annotations(rendered: RenderedPlot, *, options: RenderOptions) -> RenderedPlot:
    annotations = tuple(
        annotation
        for annotation in shape_annotations_from_payload(options.shape_annotations)
        if annotation.enabled
    )
    primary = primary_axis(rendered)
    if primary is None or not annotations:
        return rendered

    stroke = plot_style.current_stroke()
    typography = plot_style.current_typography()
    palette = plot_style.get_categorical_palette(options.palette_preset, n_colors=max(1, len(annotations)))
    line_width = max(0.85, stroke.line_width_pt * 0.8)
    applied = False

    for index, annotation in enumerate(annotations):
        _validate_shape_annotation(annotation, options=options)
        color = palette[index % len(palette)] if palette else "#111827"
        if annotation.kind == "bracket":
            applied = (
                _draw_bracket_shape(
                    annotation,
                    rendered=rendered,
                    color=color,
                    line_width=line_width,
                    font_size=typography.legend_font_size_pt,
                )
                or applied
            )
            continue
        applied = (
            _draw_region_shape(
                annotation,
                rendered=rendered,
                color=color,
                line_width=line_width,
                font_size=typography.legend_font_size_pt,
            )
            or applied
        )

    if not applied:
        return rendered
    if rendered.qa_report is not None:
        qa_report = replace(
            rendered.qa_report,
            autofixes_applied=tuple(rendered.qa_report.autofixes_applied) + ("shape_annotation_overlay",),
        )
    else:
        qa_report = QAReport(score=1.0, grade="solid", autofixes_applied=("shape_annotation_overlay",))
    return replace(rendered, qa_report=qa_report)


__all__ = [
    "ShapeAnnotationOptions",
    "ShapeAnnotationPayloadDict",
    "apply_shape_annotations",
    "normalize_shape_annotations_payload",
    "shape_annotations_from_payload",
]
