from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from PIL import Image, ImageDraw, ImageFont

from src.composer_project import region_rect_mm, region_slot_id, region_slot_rect_mm
from src.composer_types import PT_TO_MM, ComposerPanel, ComposerProject, ComposerText
from src.plot_contract import qa_profile
from src.rendering.models import QAIssue, QAReport

_TEXT_MEASURE_DPI = 144


@dataclass(frozen=True)
class ComposerSuggestedPatchOp:
    kind: str
    id: str
    patch: dict[str, Any]


@dataclass(frozen=True)
class DrawableRect:
    x_mm: float
    y_mm: float
    w_mm: float
    h_mm: float


def _font(size: int) -> ImageFont.ImageFont:
    try:
        return ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", size)
    except Exception:
        return ImageFont.load_default()


def _measure_text_rect(text: ComposerText) -> DrawableRect:
    image = Image.new("L", (1, 1), color=255)
    draw = ImageDraw.Draw(image)
    font = _font(max(8, int(round(text.font_size_pt * _TEXT_MEASURE_DPI / 72.0))))
    bbox = draw.textbbox((0, 0), text.text, font=font)
    width_mm = max((bbox[2] - bbox[0]) * 25.4 / _TEXT_MEASURE_DPI, 4.0)
    height_mm = max((bbox[3] - bbox[1]) * 25.4 / _TEXT_MEASURE_DPI, text.font_size_pt * PT_TO_MM * 0.85)
    x_mm = text.x_mm
    if text.align == "center":
        x_mm -= width_mm / 2.0
    elif text.align == "right":
        x_mm -= width_mm
    return DrawableRect(x_mm=x_mm, y_mm=text.y_mm, w_mm=width_mm, h_mm=height_mm)


def _panel_rect(panel: ComposerPanel) -> DrawableRect:
    return DrawableRect(x_mm=panel.x_mm, y_mm=panel.y_mm, w_mm=panel.w_mm, h_mm=panel.h_mm)


def _rect_intersects(a: DrawableRect, b: DrawableRect, *, margin_mm: float = 0.0) -> bool:
    return (
        a.x_mm < b.x_mm + b.w_mm + margin_mm
        and a.x_mm + a.w_mm > b.x_mm - margin_mm
        and a.y_mm < b.y_mm + b.h_mm + margin_mm
        and a.y_mm + a.h_mm > b.y_mm - margin_mm
    )


def _rect_inside(inner: DrawableRect, outer: DrawableRect, *, tolerance_mm: float = 0.0) -> bool:
    return (
        inner.x_mm >= outer.x_mm - tolerance_mm
        and inner.y_mm >= outer.y_mm - tolerance_mm
        and inner.x_mm + inner.w_mm <= outer.x_mm + outer.w_mm + tolerance_mm
        and inner.y_mm + inner.h_mm <= outer.y_mm + outer.h_mm + tolerance_mm
    )


def _canvas_rect(project: ComposerProject) -> DrawableRect:
    return DrawableRect(
        x_mm=0.0,
        y_mm=0.0,
        w_mm=project.canvas_width_mm,
        h_mm=project.canvas_height_mm,
    )


def _bound_rect(project: ComposerProject, *, region_id: str | None, slot_id: str | None) -> DrawableRect | None:
    if region_id is None:
        return None
    for region in project.regions:
        if region.id != region_id:
            continue
        if slot_id and slot_id == region_slot_id(region):
            slot_rect = region_slot_rect_mm(project, region)
            if slot_rect is not None:
                return DrawableRect(*slot_rect)
        return DrawableRect(*region_rect_mm(project, region))
    return None


def _clamp_rect(rect: DrawableRect, outer: DrawableRect) -> DrawableRect:
    x_mm = max(outer.x_mm, min(outer.x_mm + outer.w_mm - rect.w_mm, rect.x_mm))
    y_mm = max(outer.y_mm, min(outer.y_mm + outer.h_mm - rect.h_mm, rect.y_mm))
    return DrawableRect(x_mm=x_mm, y_mm=y_mm, w_mm=rect.w_mm, h_mm=rect.h_mm)


def _center_rect(rect: DrawableRect, outer: DrawableRect) -> DrawableRect:
    return DrawableRect(
        x_mm=outer.x_mm + max(outer.w_mm - rect.w_mm, 0.0) / 2.0,
        y_mm=outer.y_mm + max(outer.h_mm - rect.h_mm, 0.0) / 2.0,
        w_mm=min(rect.w_mm, outer.w_mm),
        h_mm=min(rect.h_mm, outer.h_mm),
    )


def _text_patch_from_rect(text: ComposerText, rect: DrawableRect) -> dict[str, Any]:
    if text.align == "center":
        x_mm = rect.x_mm + rect.w_mm / 2.0
    elif text.align == "right":
        x_mm = rect.x_mm + rect.w_mm
    else:
        x_mm = rect.x_mm
    return {
        "x_mm": round(x_mm / 0.5) * 0.5,
        "y_mm": round(rect.y_mm / 0.5) * 0.5,
    }


def _panel_patch_from_rect(rect: DrawableRect) -> dict[str, Any]:
    return {
        "x_mm": round(rect.x_mm / 0.5) * 0.5,
        "y_mm": round(rect.y_mm / 0.5) * 0.5,
        "w_mm": round(rect.w_mm / 0.5) * 0.5,
        "h_mm": round(rect.h_mm / 0.5) * 0.5,
    }


def _finalize_report(issues: list[QAIssue]) -> QAReport:
    penalty = 0.0
    for issue in issues:
        penalty += {"info": 3.0, "warning": 8.0, "critical": 18.0}.get(issue.severity, 8.0)
    score = max(0.0, min(100.0, 100.0 - penalty))
    grade = "excellent" if score >= 90.0 else "solid" if score >= 75.0 else "needs_cleanup"
    return QAReport(score=round(score, 1), grade=grade, issues=tuple(issues), autofixes_applied=())


def analyze_composer_project(
    project: ComposerProject,
) -> tuple[QAReport, tuple[ComposerSuggestedPatchOp, ...]]:
    profile = qa_profile("composer")
    min_text_size_pt = float(profile.get("min_text_size_pt", 6.0))
    overlap_margin_mm = float(profile.get("text_overlap_margin_mm", 1.0))
    canvas_margin_mm = float(profile.get("canvas_margin_mm", 0.5))
    binding_tolerance_mm = float(profile.get("binding_overflow_tolerance_mm", 0.25))

    issues: list[QAIssue] = []
    patch_map: dict[tuple[str, str], ComposerSuggestedPatchOp] = {}
    canvas_rect = _canvas_rect(project)

    text_rects = [
        (text, _measure_text_rect(text))
        for text in project.texts
        if not text.hidden
    ]

    for panel in project.panels:
        if panel.hidden:
            continue
        rect = _panel_rect(panel)
        expanded_canvas = DrawableRect(
            x_mm=-canvas_margin_mm,
            y_mm=-canvas_margin_mm,
            w_mm=project.canvas_width_mm + canvas_margin_mm * 2.0,
            h_mm=project.canvas_height_mm + canvas_margin_mm * 2.0,
        )
        if not _rect_inside(rect, expanded_canvas):
            issues.append(
                QAIssue(
                    id="drawable_outside_canvas",
                    severity="warning",
                    metric_value=panel.id,
                    target="inside_canvas",
                    message="A drawable extends outside the Composer canvas.",
                )
            )
            if not panel.locked:
                patch_map[("panel", panel.id)] = ComposerSuggestedPatchOp(
                    kind="panel",
                    id=panel.id,
                    patch=_panel_patch_from_rect(_clamp_rect(rect, canvas_rect)),
                )
        bound_rect = _bound_rect(project, region_id=panel.region_id, slot_id=panel.slot_id)
        if bound_rect is not None and not _rect_inside(rect, bound_rect, tolerance_mm=binding_tolerance_mm):
            issues.append(
                QAIssue(
                    id="bound_drawable_overflow",
                    severity="warning",
                    metric_value=panel.id,
                    target="inside_binding",
                    message="A bound drawable drifted outside its region or slot.",
                )
            )
            if not panel.locked:
                snapped = _center_rect(rect, bound_rect)
                patch_map[("panel", panel.id)] = ComposerSuggestedPatchOp(
                    kind="panel",
                    id=panel.id,
                    patch=_panel_patch_from_rect(snapped),
                )

    for text, rect in text_rects:
        expanded_canvas = DrawableRect(
            x_mm=-canvas_margin_mm,
            y_mm=-canvas_margin_mm,
            w_mm=project.canvas_width_mm + canvas_margin_mm * 2.0,
            h_mm=project.canvas_height_mm + canvas_margin_mm * 2.0,
        )
        if not _rect_inside(rect, expanded_canvas):
            issues.append(
                QAIssue(
                    id="text_outside_canvas",
                    severity="warning",
                    metric_value=text.id,
                    target="inside_canvas",
                    message="A text box extends outside the Composer canvas.",
                )
            )
            if not text.locked:
                patch_map[("text", text.id)] = ComposerSuggestedPatchOp(
                    kind="text",
                    id=text.id,
                    patch=_text_patch_from_rect(text, _clamp_rect(rect, canvas_rect)),
                )
        if text.font_size_pt < min_text_size_pt:
            issues.append(
                QAIssue(
                    id="micro_text",
                    severity="warning",
                    metric_value=round(text.font_size_pt, 2),
                    target=min_text_size_pt,
                    message="Text size fell below the minimum editorial floor.",
                )
            )
            if not text.locked:
                patch = dict(patch_map.get(("text", text.id), ComposerSuggestedPatchOp("text", text.id, {})).patch)
                patch["font_size_pt"] = min_text_size_pt
                patch_map[("text", text.id)] = ComposerSuggestedPatchOp(kind="text", id=text.id, patch=patch)
        bound_rect = _bound_rect(project, region_id=text.region_id, slot_id=text.slot_id)
        if bound_rect is not None and not _rect_inside(rect, bound_rect, tolerance_mm=binding_tolerance_mm):
            issues.append(
                QAIssue(
                    id="bound_text_overflow",
                    severity="warning",
                    metric_value=text.id,
                    target="inside_binding",
                    message="A bound text box drifted outside its region or slot.",
                )
            )
            if not text.locked:
                snapped = _center_rect(rect, bound_rect)
                patch = dict(patch_map.get(("text", text.id), ComposerSuggestedPatchOp("text", text.id, {})).patch)
                patch.update(_text_patch_from_rect(text, snapped))
                patch_map[("text", text.id)] = ComposerSuggestedPatchOp(kind="text", id=text.id, patch=patch)

    for idx, (text, rect) in enumerate(text_rects):
        for other_text, other_rect in text_rects[idx + 1 :]:
            if not _rect_intersects(rect, other_rect, margin_mm=overlap_margin_mm):
                continue
            issues.append(
                QAIssue(
                    id="text_collision",
                    severity="warning",
                    metric_value=f"{text.id}:{other_text.id}",
                    target="separated",
                    message="Two text boxes overlap in the Composer canvas.",
                )
            )
            if other_text.locked:
                continue
            shifted = DrawableRect(
                x_mm=other_rect.x_mm,
                y_mm=rect.y_mm + rect.h_mm + overlap_margin_mm,
                w_mm=other_rect.w_mm,
                h_mm=other_rect.h_mm,
            )
            shifted = _clamp_rect(shifted, canvas_rect)
            existing_patch = patch_map.get(
                ("text", other_text.id),
                ComposerSuggestedPatchOp("text", other_text.id, {}),
            )
            patch = dict(existing_patch.patch)
            patch.update(_text_patch_from_rect(other_text, shifted))
            patch_map[("text", other_text.id)] = ComposerSuggestedPatchOp(kind="text", id=other_text.id, patch=patch)

    report = _finalize_report(issues)
    return report, tuple(patch_map.values())
