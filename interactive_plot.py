from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

from make_plot import (
    SIZE_CHOICES,
    _ensure_input_path,
    _resolve_render_options,
    inspect_input_file,
    list_sheet_names,
    normalize_input_path_text,
    preflight_render_request,
    render_template,
    resolve_output_dir,
)

MENU_ITEMS = [
    ("curve", "曲线图"),
    ("point_line", "点线图"),
    ("stacked_curve", "堆积曲线图"),
    ("segmented_stacked_curve", "分段堆积曲线图"),
    ("bar", "柱状图"),
    ("box", "箱线图"),
    ("violin", "小提琴图"),
    ("scatter", "散点图"),
    ("heatmap", "热图"),
]
MENU = {str(index): item for index, item in enumerate(MENU_ITEMS, start=1)}
TEMPLATE_LABELS = {template: label for template, label in MENU_ITEMS}
STATE_PATH = Path(__file__).resolve().with_name(".plot_wizard_state.json")
STATE_FIELDS = ("size", "xscale", "yscale", "reverse_x", "baseline", "show_colorbar", "use_sidecar")


def _template_defaults(template: str) -> dict[str, Any]:
    defaults: dict[str, Any] = {"size": "60x110" if template == "segmented_stacked_curve" else "60x55"}
    if template in {"curve", "point_line", "scatter"}:
        defaults.update({"xscale": "linear", "yscale": "linear", "reverse_x": False})
    elif template == "stacked_curve":
        defaults.update({"reverse_x": False, "baseline": "none"})
    elif template == "segmented_stacked_curve":
        defaults.update({"reverse_x": True, "baseline": "linear_endpoints", "use_sidecar": True})
    elif template == "heatmap":
        defaults.update({"show_colorbar": True})
    return defaults


def _load_state() -> dict[str, Any]:
    if not STATE_PATH.exists():
        return {"templates": {}}
    try:
        return json.loads(STATE_PATH.read_text(encoding="utf-8"))
    except Exception:
        return {"templates": {}}


def _save_state(state: dict[str, Any]) -> None:
    STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")


def _recent_defaults_for(template: str) -> dict[str, Any]:
    state = _load_state()
    templates = state.get("templates", {})
    saved = templates.get(template, {})
    return {key: saved[key] for key in STATE_FIELDS if key in saved}


def _remember_defaults(template: str, options: dict[str, Any]) -> None:
    state = _load_state()
    templates = state.setdefault("templates", {})
    templates[template] = {key: options[key] for key in STATE_FIELDS if key in options}
    _save_state(state)


def _recommended_defaults(template: str, recommendation: Any | None = None) -> dict[str, Any]:
    defaults = _template_defaults(template)
    defaults.update(_recent_defaults_for(template))
    if recommendation is not None and recommendation.template == template:
        for key in STATE_FIELDS:
            value = getattr(recommendation, key, None)
            if value is not None:
                defaults[key] = value
    return defaults


def _print_menu(default_template: str | None = None) -> None:
    print("可选图类型：")
    for key, (template, label) in MENU.items():
        default_mark = " (推荐)" if template == default_template else ""
        print(f"  {key}. {label} / {template}{default_mark}")


def _print_section(title: str) -> None:
    print(f"\n{title}")
    print("-" * len(title))


def _prompt_template(default_template: str | None = None) -> str:
    default_key = next((key for key, (template, _) in MENU.items() if template == default_template), "")
    while True:
        _print_menu(default_template)
        suffix = f" [default: {default_key}]" if default_key else ""
        choice = input(f"请选择图类型{suffix}：").strip()
        if not choice and default_template:
            return default_template
        item = MENU.get(choice)
        if item:
            return item[0]
        print("输入无效，请重新选择。\n")


def _prompt_choice(prompt: str, allowed: tuple[str, ...], default: str) -> str:
    allowed_text = "/".join(allowed)
    while True:
        value = input(f"{prompt} [{default}] ({allowed_text}): ").strip().lower()
        if not value:
            return default
        if value in allowed:
            return value
        print(f"输入无效，请输入 {allowed_text}。\n")


def _prompt_yes_no(prompt: str, default: bool = False) -> bool:
    default_text = "y" if default else "n"
    while True:
        value = input(f"{prompt} [default: {default_text}] (y/n): ").strip().lower()
        if not value:
            return default
        if value in {"y", "yes"}:
            return True
        if value in {"n", "no"}:
            return False
        print("输入无效，请输入 y 或 n。\n")


def _prompt_size(default: str) -> str:
    print("可选尺寸：")
    for index, size in enumerate(SIZE_CHOICES, start=1):
        mark = " (推荐)" if size == default else ""
        print(f"  {index}. {size}{mark}")
    index_map = {str(index): size for index, size in enumerate(SIZE_CHOICES, start=1)}
    while True:
        raw = input(f"请选择尺寸 [default: {default}]：").strip()
        if not raw:
            return default
        if raw in index_map:
            return index_map[raw]
        if raw in SIZE_CHOICES:
            return raw
        print(f"输入无效，请输入 1-{len(SIZE_CHOICES)} 或具体尺寸值。\n")


def _prompt_input_path() -> Path:
    while True:
        raw = input("把数据文件拖到终端后回车：")
        cleaned = normalize_input_path_text(raw)
        try:
            return _ensure_input_path(cleaned)
        except FileNotFoundError as exc:
            print(f"{exc}\n")


def _format_sheet_value(sheet: str | int, sheet_names: list[str]) -> str:
    if isinstance(sheet, int) and 0 <= sheet < len(sheet_names):
        return f"{sheet} ({sheet_names[sheet]})"
    return str(sheet)


def _prompt_sheet(input_path: Path, default_sheet: str | int | None = None) -> str | int:
    sheet_names = list_sheet_names(input_path)
    if not sheet_names:
        return 0
    _print_section("工作表")
    print("检测到 Excel 工作表：")
    for index, name in enumerate(sheet_names):
        print(f"  {index}. {name}")
    default_text = _format_sheet_value(default_sheet, sheet_names) if default_sheet is not None else "0"
    while True:
        raw = input(f"请选择 sheet [default: {default_text}]：").strip()
        if not raw:
            return default_sheet if default_sheet is not None else 0
        if raw.isdigit():
            index = int(raw)
            if 0 <= index < len(sheet_names):
                return index
        if raw in sheet_names:
            return raw
        print("输入无效，请输入 sheet 索引或工作表名称。\n")


def _print_inspection(input_path: Path, sheet: str | int, inspection: Any) -> None:
    _print_section("识别结果")
    print(f"  文件：{input_path}")
    print(f"  Sheet：{sheet}")
    print(f"  输入模型：{inspection.model_label}")
    print(f"  推荐图类型：{TEMPLATE_LABELS.get(inspection.recommendation.template, inspection.recommendation.template)} / {inspection.recommendation.template}")
    print(f"  推荐理由：{inspection.recommendation.reason}")
    if getattr(inspection, "signals", ()):
        print("  程序这样判断：")
        for signal in inspection.signals:
            print(f"    - {signal}")
    if inspection.warnings:
        print("  识别提醒：")
        for warning in inspection.warnings:
            print(f"    - {warning}")


def _print_selected_options(template: str, defaults: dict[str, Any]) -> None:
    _print_section("当前建议设置")
    print(f"  图类型：{TEMPLATE_LABELS.get(template, template)} / {template}")
    print(f"  尺寸：{defaults.get('size')}")
    if template in {"curve", "point_line", "scatter"}:
        print(f"  x 轴：{defaults.get('xscale')}")
        print(f"  y 轴：{defaults.get('yscale')}")
        print(f"  反向 x：{'是' if defaults.get('reverse_x') else '否'}")
    elif template == "stacked_curve":
        print(f"  反向 x：{'是' if defaults.get('reverse_x') else '否'}")
        print(f"  基线修正：{defaults.get('baseline')}")
    elif template == "segmented_stacked_curve":
        print(f"  反向 x：{'是' if defaults.get('reverse_x') else '否'}")
        print(f"  基线修正：{defaults.get('baseline')}")
        print(f"  sidecar：{'需要' if defaults.get('use_sidecar', True) else '不使用'}")
    elif template == "heatmap":
        print(f"  colorbar：{'显示' if defaults.get('show_colorbar', True) else '隐藏'}")


def _prompt_options(template: str, defaults: dict[str, Any]) -> dict[str, Any]:
    options = dict(defaults)
    options["size"] = _prompt_size(str(defaults.get("size", _template_defaults(template)["size"])))
    if template in {"curve", "point_line", "scatter"}:
        options["xscale"] = _prompt_choice("x 轴类型", ("linear", "log"), str(defaults.get("xscale", "linear")))
        options["yscale"] = _prompt_choice("y 轴类型", ("linear", "log"), str(defaults.get("yscale", "linear")))
        options["reverse_x"] = _prompt_yes_no("是否反向 x 轴", bool(defaults.get("reverse_x", False)))
    elif template == "stacked_curve":
        options["reverse_x"] = _prompt_yes_no("是否反向 x 轴", bool(defaults.get("reverse_x", False)))
        options["baseline"] = _prompt_choice(
            "堆积基线修正",
            ("none", "linear_endpoints"),
            str(defaults.get("baseline", "none")),
        )
    elif template == "segmented_stacked_curve":
        options["reverse_x"] = _prompt_yes_no("是否反向 x 轴", bool(defaults.get("reverse_x", True)))
        options["baseline"] = _prompt_choice(
            "基线修正",
            ("none", "linear_endpoints"),
            str(defaults.get("baseline", "linear_endpoints")),
        )
        options["use_sidecar"] = _prompt_yes_no(
            "是否使用同目录 sidecar（断轴/高亮/编号）",
            bool(defaults.get("use_sidecar", True)),
        )
    elif template == "heatmap":
        options["show_colorbar"] = _prompt_yes_no("是否显示 colorbar", bool(defaults.get("show_colorbar", True)))
    return options


def _build_render_options(template: str, option_values: dict[str, Any]):
    return _resolve_render_options(
        template=template,
        size=option_values.get("size"),
        xscale=option_values.get("xscale"),
        yscale=option_values.get("yscale"),
        reverse_x=bool(option_values.get("reverse_x", False)),
        baseline=option_values.get("baseline"),
        show_colorbar=option_values.get("show_colorbar"),
        use_sidecar=option_values.get("use_sidecar"),
    )


def _print_preflight(preflight: Any) -> None:
    _print_section("预检查结果")
    if preflight.errors:
        print("  当前不能直接出图，需要先修改：")
        for error in preflight.errors:
            print(f"    - {error}")
    else:
        print("  当前检查通过，可以直接出图。")
    if preflight.warnings:
        print("  建议先注意：")
        for warning in preflight.warnings:
            print(f"    - {warning}")
    if preflight.output_filenames:
        print("  预计输出：")
        for name in preflight.output_filenames:
            print(f"    - {name}")


def _prompt_action(title: str, items: list[tuple[str, str]], default_key: str) -> str:
    actions = {str(index): value for index, (value, _) in enumerate(items, start=1)}
    _print_section(title)
    for index, (_, label) in enumerate(items, start=1):
        default_mark = " [default]" if str(index) == default_key else ""
        print(f"  {index}. {label}{default_mark}")
    while True:
        choice = input(f"请选择 1-{len(items)} [default: {default_key}]：").strip()
        if not choice:
            return actions[default_key]
        if choice in actions:
            return actions[choice]
        print(f"输入无效，请输入 1-{len(items)}。\n")

def _prompt_recommendation_action(default_template: str) -> str:
    return _prompt_action(
        "下一步",
        [
            ("accept", f"直接采用推荐设置并预检查 ({TEMPLATE_LABELS.get(default_template, default_template)})"),
            ("tweak", "在推荐图类型上微调参数"),
            ("change_template", "改成别的图类型"),
            ("change_sheet", "重新选择 sheet"),
            ("new_file", "换一个文件"),
        ],
        default_key="1",
    )


def _prompt_post_render_action() -> str:
    return _prompt_action(
        "已完成",
        [
            ("same", "用同一文件调整参数重画"),
            ("new", "换一个新文件"),
            ("exit", "退出"),
        ],
        default_key="3",
    )


def _run_file_wizard(input_path: Path) -> str:
    current_sheet: str | int | None = None
    while True:
        current_sheet = _prompt_sheet(input_path, current_sheet)
        try:
            inspection = inspect_input_file(input_path, current_sheet)
        except Exception as exc:
            print(f"\n无法识别当前文件：{exc}\n")
            if _prompt_yes_no("是否重新选择 sheet", default=True):
                continue
            return "new"

        _print_inspection(input_path, current_sheet, inspection)
        recommended_template = inspection.recommendation.template

        while True:
            action = _prompt_recommendation_action(recommended_template)
            if action == "change_sheet":
                break
            if action == "new_file":
                return "new"

            if action == "accept":
                template = recommended_template
                option_values = _recommended_defaults(recommended_template, inspection.recommendation)
                _print_selected_options(template, option_values)
            elif action == "tweak":
                template = recommended_template
                option_values = _prompt_options(
                    template,
                    _recommended_defaults(template, inspection.recommendation),
                )
            else:
                template = _prompt_template(default_template=recommended_template)
                option_values = _prompt_options(
                    template,
                    _recommended_defaults(template, inspection.recommendation),
                )

            render_options = _build_render_options(template, option_values)
            preflight = preflight_render_request(template, input_path, current_sheet, render_options)
            _print_preflight(preflight)
            print(f"  输出目录：{resolve_output_dir(input_path, None, 'workspace').resolve()}")

            if preflight.errors:
                if _prompt_yes_no("预检查失败，是否继续调整当前文件的设置", default=True):
                    recommended_template = template
                    continue
                return "new"

            if not _prompt_yes_no("开始出图", default=True):
                if _prompt_yes_no("是否继续调整当前文件的设置", default=True):
                    recommended_template = template
                    continue
                return "new"

            output_dir = resolve_output_dir(input_path, None, "workspace")
            outputs = render_template(template, input_path, output_dir, current_sheet, **option_values)
            _remember_defaults(template, option_values)

            _print_section("出图完成")
            print(f"  输出目录：{output_dir.resolve()}")
            print(f"  最终图类型：{TEMPLATE_LABELS.get(template, template)} / {template}")
            print(f"  Sheet：{current_sheet}")
            print("  生成文件：")
            for output in outputs:
                print(f"    - {output.resolve()}")

            next_action = _prompt_post_render_action()
            if next_action == "same":
                recommended_template = template
                break
            return next_action

        if current_sheet is not None and _prompt_yes_no("是否继续使用当前文件", default=True):
            continue
        return "new"


def main() -> int:
    try:
        print("绘图精灵 2.5")
        print("流程：拖文件 -> 程序识别并推荐 -> 你确认 -> 预检查 -> 出图\n")
        while True:
            input_path = _prompt_input_path()
            action = _run_file_wizard(input_path)
            if action == "new":
                continue
            return 0
    except KeyboardInterrupt:
        print("\n已取消。", file=sys.stderr)
        return 130
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
