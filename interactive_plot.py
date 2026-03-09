from __future__ import annotations

import sys
from pathlib import Path

from make_plot import (
    SIZE_CHOICES,
    TEMPLATE_CHOICES,
    _coerce_sheet,
    _ensure_input_path,
    normalize_input_path_text,
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


def _default_size_for(template: str) -> str:
    if template == "segmented_stacked_curve":
        return "60x110"
    return "60x55"


def _print_menu() -> None:
    print("请选择图类型：")
    for key, (template, label) in MENU.items():
        print(f"  {key}. {label} / {template}")


def _prompt_template() -> str:
    while True:
        _print_menu()
        choice = input(f"请输入 1-{len(MENU)}：").strip()
        item = MENU.get(choice)
        if item:
            return item[0]
        print(f"输入无效，请输入 1 到 {len(MENU)}。\n")


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


def _prompt_size(template: str) -> str:
    default = _default_size_for(template)
    print("可选尺寸：")
    for index, size in enumerate(SIZE_CHOICES, start=1):
        print(f"  {index}. {size}")
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


def _prompt_sheet() -> str | int:
    raw = input("Sheet 索引或名称 [default: 0]：").strip()
    if not raw:
        return 0
    return _coerce_sheet(raw)


def _prompt_options(template: str) -> dict[str, object]:
    options: dict[str, object] = {"size": _prompt_size(template)}
    if template in {"curve", "point_line", "scatter"}:
        options["xscale"] = _prompt_choice("x 轴类型", ("linear", "log"), "linear")
        options["yscale"] = _prompt_choice("y 轴类型", ("linear", "log"), "linear")
        options["reverse_x"] = _prompt_yes_no("是否反向 x 轴", default=False)
    elif template == "stacked_curve":
        options["reverse_x"] = _prompt_yes_no("是否反向 x 轴", default=False)
        options["baseline"] = _prompt_choice(
            "堆积基线修正",
            ("none", "linear_endpoints"),
            "none",
        )
    elif template == "segmented_stacked_curve":
        options["reverse_x"] = _prompt_yes_no("是否反向 x 轴", default=True)
        need_breaks = _prompt_yes_no("是否需要断轴/高亮等高级配置（需同目录 sidecar）", default=True)
        options["use_sidecar"] = need_breaks
        options["baseline"] = _prompt_choice(
            "基线修正",
            ("none", "linear_endpoints"),
            "linear_endpoints",
        )
    elif template == "heatmap":
        options["show_colorbar"] = _prompt_yes_no("是否显示 colorbar", default=True)
    return options


def main() -> int:
    try:
        print("Interactive PDF plot generator v2")
        print(f"支持图类型：{', '.join(TEMPLATE_CHOICES)}\n")
        template = _prompt_template()
        options = _prompt_options(template)
        input_path = _prompt_input_path()
        sheet = _prompt_sheet()
        output_dir = resolve_output_dir(input_path, None, "workspace")
        outputs = render_template(template, input_path, output_dir, sheet, **options)

        print(f"\n完成。PDF 输出目录：{output_dir.resolve()}")
        for output in outputs:
            print(output.resolve())
        return 0
    except KeyboardInterrupt:
        print("\n已取消。", file=sys.stderr)
        return 130
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
