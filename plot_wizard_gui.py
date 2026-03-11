from __future__ import annotations

from io import BytesIO
import subprocess
import sys
import traceback
from pathlib import Path
from typing import Any

from PySide6.QtCore import QEvent, QObject, QRunnable, QThreadPool, QTimer, Qt, Signal
from PySide6.QtGui import QColor, QDragEnterEvent, QDropEvent, QFont, QFontDatabase, QPixmap
from PySide6.QtWidgets import (
    QApplication,
    QCheckBox,
    QComboBox,
    QFileDialog,
    QFrame,
    QGraphicsDropShadowEffect,
    QHBoxLayout,
    QLabel,
    QListWidget,
    QListWidgetItem,
    QMainWindow,
    QMenu,
    QPushButton,
    QScrollArea,
    QSplitter,
    QStackedWidget,
    QToolButton,
    QVBoxLayout,
    QWidget,
)

import interactive_plot as terminal_wizard
from make_plot import (
    PALETTE_PRESET_CHOICES,
    RenderedPlot,
    _ensure_input_path,
    _resolve_render_options,
    build_rendered_plots,
    close_rendered_plots,
    export_rendered_plots,
    inspect_input_file,
    list_sheet_names,
    normalize_input_path_text,
    preflight_render_request,
    resolve_output_dir,
)
from src import plot_style


APP_TITLE = "绘图精灵"
RECENT_FILES_KEY = "recent_files"
MAX_RECENT_FILES = 8
PREVIEW_DEBOUNCE_MS = 260
PREVIEW_BASE_DPI = 160
MENU_ITEMS = terminal_wizard.MENU_ITEMS
TEMPLATE_LABELS = terminal_wizard.TEMPLATE_LABELS
GUI_PALETTE_PRESET_CHOICES = ("colorblind_safe", "deep", "muted", "mono")


def _pick_app_font() -> QFont:
    preferred_families = [
        "PingFang SC",
        "SF Pro Text",
        "Helvetica Neue",
        "Helvetica",
        "Arial",
        "Noto Sans CJK SC",
        "DejaVu Sans",
    ]
    try:
        available = set(QFontDatabase.families())
    except TypeError:
        available = set(QFontDatabase().families())
    for family in preferred_families:
        if family in available:
            return QFont(family, 12)
    return QFont("Arial", 12)


def _html_bullets(items: tuple[str, ...] | list[str]) -> str:
    if not items:
        return "无"
    return "<br/>".join(f"• {item}" for item in items)


def _load_recent_files() -> list[Path]:
    state = terminal_wizard._load_state()
    recent_files = []
    for raw in state.get(RECENT_FILES_KEY, []):
        path = Path(raw).expanduser()
        if path.exists() and path.is_file():
            recent_files.append(path)
    return recent_files[:MAX_RECENT_FILES]


def _remember_recent_file(path: Path) -> None:
    state = terminal_wizard._load_state()
    current = [str(item) for item in state.get(RECENT_FILES_KEY, []) if Path(item).expanduser() != path]
    state[RECENT_FILES_KEY] = [str(path)] + current[: MAX_RECENT_FILES - 1]
    terminal_wizard._save_state(state)


class DropCard(QFrame):
    fileDropped = Signal(str)

    def __init__(self, open_handler, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setObjectName("DropCard")
        self.setAcceptDrops(True)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(18, 18, 18, 18)
        layout.setSpacing(10)

        title = QLabel("把数据文件拖到这里")
        title.setObjectName("CardTitle")
        subtitle = QLabel("也可以点击下面按钮选择文件。支持 csv / txt / xlsx / xlsm。")
        subtitle.setWordWrap(True)
        subtitle.setObjectName("MutedText")

        button = QPushButton("选择文件")
        button.clicked.connect(open_handler)

        layout.addWidget(title)
        layout.addWidget(subtitle)
        layout.addWidget(button, 0, Qt.AlignmentFlag.AlignLeft)

    def dragEnterEvent(self, event: QDragEnterEvent) -> None:  # noqa: N802
        if event.mimeData().hasUrls():
            event.acceptProposedAction()
            return
        super().dragEnterEvent(event)

    def dropEvent(self, event: QDropEvent) -> None:  # noqa: N802
        urls = event.mimeData().urls()
        if urls:
            local_file = urls[0].toLocalFile()
            if local_file:
                self.fileDropped.emit(local_file)
                event.acceptProposedAction()
                return
        super().dropEvent(event)


class PreviewSignals(QObject):
    finished = Signal(int, object, object)
    failed = Signal(int, str)


class PreviewWorker(QRunnable):
    def __init__(
        self,
        token: int,
        template: str,
        input_path: Path,
        sheet: str | int,
        option_values: dict[str, Any],
    ) -> None:
        super().__init__()
        self.token = token
        self.template = template
        self.input_path = input_path
        self.sheet = sheet
        self.option_values = dict(option_values)
        self.signals = PreviewSignals()

    def run(self) -> None:
        try:
            rendered = build_rendered_plots(
                self.template,
                self.input_path,
                self.sheet,
                size=self.option_values.get("size"),
                xscale=self.option_values.get("xscale"),
                yscale=self.option_values.get("yscale"),
                reverse_x=bool(self.option_values.get("reverse_x", False)),
                baseline=self.option_values.get("baseline"),
                show_colorbar=self.option_values.get("show_colorbar"),
                style_preset=self.option_values.get("style_preset", plot_style.DEFAULT_STYLE_PRESET),
                palette_preset=self.option_values.get("palette_preset", plot_style.DEFAULT_PALETTE_PRESET),
                use_sidecar=self.option_values.get("use_sidecar"),
            )
            self.signals.finished.emit(self.token, rendered, dict(self.option_values))
        except Exception as exc:  # pragma: no cover - GUI error path
            self.signals.failed.emit(self.token, f"{exc}\n\n{traceback.format_exc(limit=3)}")


class PlotWizardWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle(APP_TITLE)
        self.resize(1720, 980)
        self.setMinimumSize(1080, 620)
        self.threadpool = QThreadPool.globalInstance()
        self.preview_timer = QTimer(self)
        self.preview_timer.setSingleShot(True)
        self.preview_timer.setInterval(PREVIEW_DEBOUNCE_MS)
        self.preview_timer.timeout.connect(self._dispatch_preview)

        self.current_input_path: Path | None = None
        self.current_sheet: str | int = 0
        self.current_inspection: Any | None = None
        self.current_preflight: Any | None = None
        self.current_rendered: list[RenderedPlot] = []
        self.current_preview_key: tuple[Any, ...] | None = None
        self.current_preview_index = 0
        self.last_output_dir: Path | None = None
        self.recent_paths: list[Path] = []
        self.preview_token = 0
        self.preview_running = False
        self.preview_pending = False
        self._applying_defaults = False
        self._current_preview_message = "预览会跟着当前步骤自动刷新。"
        self._preview_mode = "fit_page"
        self._preview_scale_value = 1.0

        self._build_ui()
        self._apply_styles()
        self._apply_shadows()
        self._refresh_recent_files()
        self._go_to_page("file")
        self._show_preview_message("预览会跟着当前步骤自动刷新。")

    def closeEvent(self, event) -> None:  # noqa: N802
        close_rendered_plots(self.current_rendered)
        super().closeEvent(event)

    def _build_ui(self) -> None:
        root = QWidget()
        root_layout = QVBoxLayout(root)
        root_layout.setContentsMargins(14, 14, 14, 14)
        root_layout.setSpacing(0)
        self.setCentralWidget(root)

        self.shell = QFrame()
        self.shell.setObjectName("Shell")
        shell_layout = QHBoxLayout(self.shell)
        shell_layout.setContentsMargins(0, 0, 0, 0)
        shell_layout.setSpacing(0)

        self.wizard_header = self._build_wizard_header()
        self.progress_strip = self._build_progress_strip()
        self.center_panel = self._build_center_panel()
        self.preview_panel = self._build_preview_panel()
        self.wizard_panel = QFrame()
        self.wizard_panel.setObjectName("WizardPanel")
        self.wizard_panel.setMinimumWidth(520)
        wizard_layout = QVBoxLayout(self.wizard_panel)
        wizard_layout.setContentsMargins(18, 18, 18, 18)
        wizard_layout.setSpacing(10)
        wizard_layout.addWidget(self.wizard_header)
        wizard_layout.addWidget(self.progress_strip)
        wizard_layout.addWidget(self.center_panel, 1)
        self.preview_panel.setMinimumWidth(560)

        self.splitter = QSplitter(Qt.Orientation.Horizontal)
        self.splitter.setChildrenCollapsible(False)
        self.splitter.setHandleWidth(10)
        self.splitter.addWidget(self.wizard_panel)
        self.splitter.addWidget(self.preview_panel)
        self.splitter.setStretchFactor(0, 3)
        self.splitter.setStretchFactor(1, 4)
        self.splitter.setSizes([620, 1100])

        shell_layout.addWidget(self.splitter)
        root_layout.addWidget(self.shell, 1)

    def _build_wizard_header(self) -> QWidget:
        frame = QFrame()
        frame.setObjectName("WizardTopBar")
        layout = QHBoxLayout(frame)
        layout.setContentsMargins(14, 10, 14, 10)
        layout.setSpacing(10)

        app_title = QLabel("绘图精灵")
        app_title.setObjectName("HeaderTitle")

        self.current_file_label = QLabel("未选择文件")
        self.current_file_label.setWordWrap(False)
        self.current_file_label.setObjectName("MetaPill")
        self.current_file_label.setToolTip("")
        self.current_sheet_label = QLabel("Sheet · -")
        self.current_sheet_label.setObjectName("MetaPill")

        self.recent_button = QToolButton()
        self.recent_button.setObjectName("RecentButton")
        self.recent_button.setText("最近")
        self.recent_button.clicked.connect(self._show_recent_menu)

        layout.addWidget(app_title, 0)
        layout.addWidget(self.current_file_label, 1)
        layout.addWidget(self.current_sheet_label, 0)
        layout.addWidget(self.recent_button, 0)
        return frame

    def _build_progress_strip(self) -> QWidget:
        frame = QFrame()
        frame.setObjectName("ProgressStrip")
        layout = QHBoxLayout(frame)
        layout.setContentsMargins(20, 10, 20, 10)
        layout.setSpacing(6)
        self.step_items = []
        for title in ("文件", "Sheet", "识别", "图型", "参数", "检查", "导出"):
            step = self._build_step_item(title)
            step.setSizePolicy(step.sizePolicy().horizontalPolicy(), step.sizePolicy().verticalPolicy())
            layout.addWidget(step, 1, Qt.AlignmentFlag.AlignCenter)
        return frame

    def _build_center_panel(self) -> QWidget:
        container = QWidget()
        layout = QVBoxLayout(container)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(8)

        self.center_title = QLabel("选择文件")
        self.center_title.setObjectName("CenterHero")
        self.center_subtitle = QLabel("当前只做这一步。")
        self.center_subtitle.setObjectName("MutedText")
        self.center_subtitle.setWordWrap(True)
        layout.addWidget(self.center_title)
        layout.addWidget(self.center_subtitle)

        self.center_scroll = QScrollArea()
        self.center_scroll.setObjectName("CenterScroll")
        self.center_scroll.setWidgetResizable(True)
        self.center_scroll.setFrameShape(QFrame.Shape.NoFrame)
        self.center_scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        self.center_scroll_content = QWidget()
        self.center_scroll_layout = QVBoxLayout(self.center_scroll_content)
        self.center_scroll_layout.setContentsMargins(2, 2, 2, 2)
        self.center_scroll_layout.setSpacing(6)
        self.center_stack = QStackedWidget()
        self.center_scroll_layout.addWidget(self.center_stack)
        self.center_scroll_layout.addStretch(1)
        self.center_scroll.setWidget(self.center_scroll_content)
        layout.addWidget(self.center_scroll, 1)

        file_page = QWidget()
        file_layout = QVBoxLayout(file_page)
        file_layout.setContentsMargins(0, 0, 0, 0)
        file_layout.setSpacing(14)
        self.drop_card = DropCard(self._choose_file)
        self.drop_card.fileDropped.connect(self._handle_dropped_path)
        file_layout.addWidget(self.drop_card)
        file_layout.addStretch(1)
        self.center_stack.addWidget(file_page)

        sheet_page = QWidget()
        sheet_layout = QVBoxLayout(sheet_page)
        sheet_layout.setContentsMargins(0, 0, 0, 0)
        sheet_layout.setSpacing(14)
        self.sheet_card, sheet_body = self._make_card("选择工作表")
        self.sheet_hint = QLabel("如果有多个 sheet，这一步只决定读哪一个。")
        self.sheet_hint.setWordWrap(True)
        self.sheet_combo = QComboBox()
        self.sheet_combo.currentIndexChanged.connect(self._on_sheet_changed)
        self.sheet_summary = QLabel("当前将按这个 sheet 继续。")
        self.sheet_summary.setObjectName("MutedText")
        self.sheet_summary.setWordWrap(True)
        sheet_body.addWidget(self.sheet_hint)
        sheet_body.addWidget(self.sheet_combo)
        sheet_body.addWidget(self.sheet_summary)
        sheet_layout.addWidget(self.sheet_card)
        sheet_actions = QHBoxLayout()
        self.sheet_back_button = QPushButton("换一个文件")
        self.sheet_back_button.clicked.connect(lambda: self._go_to_page("file"))
        self.sheet_continue_button = QPushButton("继续")
        self.sheet_continue_button.clicked.connect(self._confirm_sheet)
        sheet_actions.addWidget(self.sheet_back_button)
        sheet_actions.addWidget(self.sheet_continue_button)
        sheet_actions.addStretch(1)
        sheet_layout.addLayout(sheet_actions)
        sheet_layout.addStretch(1)
        self.center_stack.addWidget(sheet_page)

        recognition_page = QWidget()
        recognition_layout = QVBoxLayout(recognition_page)
        recognition_layout.setContentsMargins(0, 0, 0, 0)
        recognition_layout.setSpacing(14)
        self.recognition_card, recognition_body = self._make_card("程序推荐")
        self.model_value = QLabel("等待文件")
        self.recommended_template_value = QLabel("—")
        self.recommendation_summary_value = QLabel("程序会先识别输入模型，再给一个推荐。")
        self.recommendation_summary_value.setWordWrap(True)
        self.reason_value = QLabel("程序会先识别输入模型，再给一个推荐。")
        self.reason_value.setWordWrap(True)
        self.signals_value = QLabel("—")
        self.signals_value.setWordWrap(True)
        self.recognition_detail_button = QPushButton("为什么这样推荐")
        self.recognition_detail_button.setCheckable(True)
        self.recognition_detail_button.toggled.connect(self._toggle_recognition_details)
        self.recognition_detail_frame = QFrame()
        self.recognition_detail_frame.setObjectName("SubtlePanel")
        self.recognition_detail_frame.hide()
        recognition_detail_layout = QVBoxLayout(self.recognition_detail_frame)
        recognition_detail_layout.setContentsMargins(12, 12, 12, 12)
        recognition_detail_layout.setSpacing(8)
        recognition_detail_layout.addWidget(QLabel("输入模型"))
        recognition_detail_layout.addWidget(self.model_value)
        recognition_detail_layout.addWidget(QLabel("程序这样判断"))
        recognition_detail_layout.addWidget(self.signals_value)
        recognition_body.addWidget(QLabel("推荐图类型"))
        recognition_body.addWidget(self.recommended_template_value)
        recognition_body.addWidget(self.reason_value)
        recognition_body.addWidget(self.recommendation_summary_value)
        recognition_body.addWidget(self.recognition_detail_button, 0, Qt.AlignmentFlag.AlignLeft)
        recognition_body.addWidget(self.recognition_detail_frame)
        recognition_layout.addWidget(self.recognition_card)
        recognition_actions = QHBoxLayout()
        self.recognition_accept_button = QPushButton("继续")
        self.recognition_accept_button.clicked.connect(self._accept_recommendation)
        self.recognition_tune_button = QPushButton("换一种图")
        self.recognition_tune_button.clicked.connect(lambda: self._go_to_page("template"))
        self.recognition_sheet_button = QPushButton("重选 Sheet")
        self.recognition_sheet_button.clicked.connect(lambda: self._go_to_page("sheet"))
        recognition_actions.addWidget(self.recognition_accept_button)
        recognition_actions.addWidget(self.recognition_tune_button)
        recognition_actions.addWidget(self.recognition_sheet_button)
        recognition_actions.addStretch(1)
        recognition_layout.addLayout(recognition_actions)
        recognition_layout.addStretch(1)
        self.center_stack.addWidget(recognition_page)

        self.template_combo = QComboBox()
        for template, label in MENU_ITEMS:
            self.template_combo.addItem(f"{label} / {template}", userData=template)
        self.template_combo.currentIndexChanged.connect(self._on_template_changed)

        template_page = QWidget()
        template_layout = QVBoxLayout(template_page)
        template_layout.setContentsMargins(0, 0, 0, 0)
        template_layout.setSpacing(14)
        self.template_card, template_body = self._make_card("确认图类型")
        self.template_summary_label = QLabel("这里只决定图类型。")
        self.template_summary_label.setObjectName("MutedText")
        self.template_summary_label.setWordWrap(True)
        template_body.addWidget(self.template_combo)
        template_body.addWidget(self.template_summary_label)
        template_layout.addWidget(self.template_card)
        template_actions = QHBoxLayout()
        self.template_back_button = QPushButton("返回推荐")
        self.template_back_button.clicked.connect(lambda: self._go_to_page("recognition"))
        self.template_continue_button = QPushButton("继续调参数")
        self.template_continue_button.clicked.connect(lambda: self._go_to_page("options"))
        template_actions.addWidget(self.template_back_button)
        template_actions.addWidget(self.template_continue_button)
        template_actions.addStretch(1)
        template_layout.addLayout(template_actions)
        template_layout.addStretch(1)
        self.center_stack.addWidget(template_page)

        options_page = QWidget()
        options_layout = QVBoxLayout(options_page)
        options_layout.setContentsMargins(0, 0, 0, 0)
        options_layout.setSpacing(14)
        self.controls_card, controls_body = self._make_card("必要参数")
        self.size_combo = QComboBox()
        self.size_combo.addItems(list(terminal_wizard.SIZE_CHOICES))
        self.size_combo.currentTextChanged.connect(self._on_option_changed)
        self.palette_combo = QComboBox()
        self.palette_combo.addItems([name for name in PALETTE_PRESET_CHOICES if name in GUI_PALETTE_PRESET_CHOICES])
        self.palette_combo.currentTextChanged.connect(self._on_option_changed)
        self.xscale_combo = QComboBox()
        self.xscale_combo.addItems(["linear", "log"])
        self.xscale_combo.currentTextChanged.connect(self._on_option_changed)
        self.yscale_combo = QComboBox()
        self.yscale_combo.addItems(["linear", "log"])
        self.yscale_combo.currentTextChanged.connect(self._on_option_changed)
        self.reverse_x_checkbox = QCheckBox("反向 x 轴")
        self.reverse_x_checkbox.stateChanged.connect(self._on_option_changed)
        self.baseline_combo = QComboBox()
        self.baseline_combo.addItems(["none", "linear_endpoints"])
        self.baseline_combo.currentTextChanged.connect(self._on_option_changed)
        self.show_colorbar_checkbox = QCheckBox("显示 colorbar")
        self.show_colorbar_checkbox.stateChanged.connect(self._on_option_changed)
        self.use_sidecar_checkbox = QCheckBox("使用 sidecar（断轴/高亮/编号）")
        self.use_sidecar_checkbox.stateChanged.connect(self._on_option_changed)
        self.style_note_label = QLabel("风格：当前默认科研风格。")
        self.style_note_label.setObjectName("MutedText")
        self.style_note_label.setWordWrap(True)
        self.palette_note_label = QLabel("默认安全配色。")
        self.palette_note_label.setObjectName("MutedText")
        self.palette_note_label.setWordWrap(True)
        self.palette_swatches_label = QLabel("")
        self.palette_swatches_label.setObjectName("MutedText")
        self.palette_swatches_label.setTextFormat(Qt.TextFormat.RichText)
        self.option_rows: dict[str, QWidget] = {}
        self.appearance_toggle = QToolButton()
        self.appearance_toggle.setObjectName("InlineToggle")
        self.appearance_toggle.setText("高级选项")
        self.appearance_toggle.setCheckable(True)
        self.appearance_toggle.setChecked(False)
        self.appearance_toggle.toggled.connect(self._toggle_appearance_panel)
        self.appearance_panel = QFrame()
        self.appearance_panel.setObjectName("SubtlePanel")
        self.appearance_panel.hide()
        appearance_layout = QVBoxLayout(self.appearance_panel)
        appearance_layout.setContentsMargins(12, 12, 12, 12)
        appearance_layout.setSpacing(10)
        appearance_layout.addWidget(self._option_row("配色", self.palette_combo, "palette_preset"))
        appearance_layout.addWidget(self.style_note_label)
        appearance_layout.addWidget(self.palette_note_label)
        appearance_layout.addWidget(self.palette_swatches_label)

        controls_body.addWidget(self._option_row("尺寸", self.size_combo, "size"))
        controls_body.addWidget(self._option_row("x 轴", self.xscale_combo, "xscale"))
        controls_body.addWidget(self._option_row("y 轴", self.yscale_combo, "yscale"))
        controls_body.addWidget(self._option_row("", self.reverse_x_checkbox, "reverse_x"))
        controls_body.addWidget(self._option_row("基线修正", self.baseline_combo, "baseline"))
        controls_body.addWidget(self._option_row("", self.show_colorbar_checkbox, "show_colorbar"))
        controls_body.addWidget(self._option_row("", self.use_sidecar_checkbox, "use_sidecar"))
        controls_body.addWidget(self.appearance_toggle, 0, Qt.AlignmentFlag.AlignLeft)
        controls_body.addWidget(self.appearance_panel)
        options_layout.addWidget(self.controls_card)
        options_actions = QHBoxLayout()
        self.options_back_button = QPushButton("返回图类型")
        self.options_back_button.clicked.connect(lambda: self._go_to_page("template"))
        self.options_continue_button = QPushButton("继续检查")
        self.options_continue_button.clicked.connect(lambda: self._go_to_page("preflight"))
        options_actions.addWidget(self.options_back_button)
        options_actions.addWidget(self.options_continue_button)
        options_actions.addStretch(1)
        options_layout.addLayout(options_actions)
        options_layout.addStretch(1)
        self.center_stack.addWidget(options_page)

        preflight_page = QWidget()
        preflight_layout = QVBoxLayout(preflight_page)
        preflight_layout.setContentsMargins(0, 0, 0, 0)
        preflight_layout.setSpacing(14)
        self.preflight_card, preflight_body = self._make_card("出图前检查")
        self.preflight_status = QLabel("等待识别结果")
        self.preflight_status.setWordWrap(True)
        self.preflight_details = QLabel("—")
        self.preflight_details.setWordWrap(True)
        preflight_body.addWidget(self.preflight_status)
        preflight_body.addWidget(self.preflight_details)
        self.output_mode_combo = QComboBox()
        self.output_mode_combo.addItem("工作目录 / workspace", userData="workspace")
        self.output_mode_combo.addItem("数据同级目录 / data_dir", userData="data_dir")
        self.output_mode_combo.currentIndexChanged.connect(self._update_output_dir_label)
        self.output_dir_label = QLabel("输出目录：-")
        self.output_dir_label.setWordWrap(True)
        self.export_button = QPushButton("导出 PDF")
        self.export_button.clicked.connect(self._export_current)
        self.export_button.setEnabled(False)
        preflight_body.addWidget(self._option_row("输出模式", self.output_mode_combo, "output_mode"))
        preflight_body.addWidget(self.output_dir_label)
        preflight_body.addWidget(self.export_button, 0, Qt.AlignmentFlag.AlignLeft)
        preflight_layout.addWidget(self.preflight_card)
        preflight_actions = QHBoxLayout()
        self.preflight_back_button = QPushButton("返回调整")
        self.preflight_back_button.clicked.connect(lambda: self._go_to_page("options"))
        preflight_actions.addWidget(self.preflight_back_button)
        preflight_actions.addStretch(1)
        preflight_layout.addLayout(preflight_actions)
        preflight_layout.addStretch(1)
        self.center_stack.addWidget(preflight_page)

        result_page = QWidget()
        result_layout = QVBoxLayout(result_page)
        result_layout.setContentsMargins(0, 0, 0, 0)
        result_layout.setSpacing(14)
        self.result_card, result_body = self._make_card("结果")
        self.result_summary = QLabel("还没有导出。")
        self.result_summary.setWordWrap(True)
        self.result_files = QListWidget()
        self.result_files.setObjectName("ResultFiles")
        result_body.addWidget(self.result_summary)
        result_body.addWidget(self.result_files)
        result_layout.addWidget(self.result_card)
        result_actions = QHBoxLayout()
        self.result_redo_button = QPushButton("用同一文件重画")
        self.result_redo_button.clicked.connect(lambda: self._go_to_page("options"))
        self.result_new_button = QPushButton("换一个文件")
        self.result_new_button.clicked.connect(self._choose_file)
        self.result_open_folder_button = QPushButton("打开输出目录")
        self.result_open_folder_button.clicked.connect(self._open_last_output_dir)
        self.result_open_folder_button.setEnabled(False)
        self.result_close_button = QPushButton("退出")
        self.result_close_button.clicked.connect(self.close)
        result_actions.addWidget(self.result_redo_button)
        result_actions.addWidget(self.result_new_button)
        result_actions.addWidget(self.result_open_folder_button)
        result_actions.addWidget(self.result_close_button)
        result_actions.addStretch(1)
        result_layout.addLayout(result_actions)
        result_layout.addStretch(1)
        self.center_stack.addWidget(result_page)

        self.page_indices = {
            "file": 0,
            "sheet": 1,
            "recognition": 2,
            "template": 3,
            "options": 4,
            "preflight": 5,
            "result": 6,
        }
        self.center_stack.setCurrentIndex(self.page_indices["file"])
        return container

    def _build_preview_panel(self) -> QWidget:
        frame = QFrame()
        frame.setObjectName("PreviewPanel")
        frame.setMinimumWidth(460)
        layout = QVBoxLayout(frame)
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(10)

        header_row = QHBoxLayout()
        title = QLabel("实时预览")
        title.setObjectName("PreviewTitle")
        self.preview_status_label = QLabel("等待预览")
        self.preview_status_label.setObjectName("MutedText")
        header_row.addWidget(title)
        header_row.addStretch(1)
        header_row.addWidget(self.preview_status_label)

        controls_row = QHBoxLayout()
        controls_row.setSpacing(8)
        self.preview_prev_button = QToolButton()
        self.preview_prev_button.setText("‹")
        self.preview_prev_button.clicked.connect(lambda: self._step_preview_index(-1))
        self.preview_next_button = QToolButton()
        self.preview_next_button.setText("›")
        self.preview_next_button.clicked.connect(lambda: self._step_preview_index(1))
        self.preview_page_label = QLabel("— / —")
        self.preview_page_label.setObjectName("MutedText")
        self.zoom_out_button = QToolButton()
        self.zoom_out_button.setText("−")
        self.zoom_out_button.clicked.connect(self._zoom_out)
        self.zoom_combo = QComboBox()
        self.zoom_combo.addItem("适配页面", userData="fit_page")
        self.zoom_combo.addItem("适配宽度", userData="fit_width")
        for label, value in (
            ("75%", 0.75),
            ("100%", 1.0),
            ("125%", 1.25),
            ("150%", 1.5),
            ("200%", 2.0),
        ):
            self.zoom_combo.addItem(label, userData=value)
        self.zoom_combo.currentIndexChanged.connect(self._on_zoom_changed)
        self.zoom_combo.setCurrentIndex(0)
        self.zoom_in_button = QToolButton()
        self.zoom_in_button.setText("+")
        self.zoom_in_button.clicked.connect(self._zoom_in)
        controls_row.addWidget(self.preview_prev_button)
        controls_row.addWidget(self.preview_next_button)
        controls_row.addWidget(self.preview_page_label)
        controls_row.addStretch(1)
        controls_row.addWidget(self.zoom_out_button)
        controls_row.addWidget(self.zoom_combo)
        controls_row.addWidget(self.zoom_in_button)

        self.preview_surface = QFrame()
        self.preview_surface.setObjectName("PreviewSurface")
        self.preview_surface_layout = QVBoxLayout(self.preview_surface)
        self.preview_surface_layout.setContentsMargins(10, 10, 10, 10)
        self.preview_placeholder = QLabel()
        self.preview_placeholder.setWordWrap(True)
        self.preview_placeholder.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.preview_placeholder.setObjectName("PreviewPlaceholder")
        self.preview_image_label = QLabel()
        self.preview_image_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.preview_image_label.installEventFilter(self)
        self.preview_scroll = QScrollArea()
        self.preview_scroll.setWidget(self.preview_image_label)
        self.preview_scroll.setWidgetResizable(False)
        self.preview_scroll.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.preview_scroll.setFrameShape(QFrame.Shape.NoFrame)
        self.preview_scroll.viewport().installEventFilter(self)
        self.preview_file_label = QLabel("—")
        self.preview_file_label.setWordWrap(True)
        self.preview_file_label.setObjectName("MutedText")
        self.preview_surface_layout.addWidget(self.preview_placeholder)
        self.preview_surface_layout.addWidget(self.preview_scroll)
        self.preview_scroll.hide()

        layout.addLayout(header_row)
        layout.addLayout(controls_row)
        layout.addWidget(self.preview_file_label)
        layout.addWidget(self.preview_surface, 1)
        return frame

    def _make_card(self, title: str) -> tuple[QFrame, QVBoxLayout]:
        frame = QFrame()
        frame.setObjectName("Card")
        layout = QVBoxLayout(frame)
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(10)
        title_label = QLabel(title)
        title_label.setObjectName("CardTitle")
        layout.addWidget(title_label)
        return frame, layout

    def _build_step_item(self, title: str) -> QWidget:
        row = QWidget()
        row.setObjectName("ProgressStep")
        layout = QVBoxLayout(row)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(2)
        dot = QLabel("●")
        dot.setObjectName("ProgressDot")
        dot.setAlignment(Qt.AlignmentFlag.AlignCenter)
        text = QLabel(title)
        text.setObjectName("ProgressText")
        text.setAlignment(Qt.AlignmentFlag.AlignCenter)
        text.setWordWrap(False)
        layout.addWidget(dot)
        layout.addWidget(text)
        self.step_items.append((dot, text))
        return row

    def _option_row(self, label_text: str, control: QWidget, key: str) -> QWidget:
        row = QWidget()
        layout = QHBoxLayout(row)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(12)
        if label_text:
            label = QLabel(label_text)
            label.setMinimumWidth(80)
            layout.addWidget(label)
        else:
            spacer = QLabel("")
            spacer.setMinimumWidth(80)
            layout.addWidget(spacer)
        layout.addWidget(control, 1)
        self.option_rows[key] = row
        return row

    def _apply_styles(self) -> None:
        self.setStyleSheet(
            """
            QMainWindow {
                background: qlineargradient(
                    x1: 0, y1: 0, x2: 1, y2: 1,
                    stop: 0 #dbe8f4,
                    stop: 0.48 #eef4f8,
                    stop: 1 #e3ebf3
                );
            }
            QToolButton, QPushButton {
                background: rgba(255, 255, 255, 0.96);
                border: 1px solid #d8e1ea;
                border-radius: 12px;
                padding: 8px 12px;
                font-size: 13px;
            }
            QPushButton:hover, QToolButton:hover {
                border-color: #8fc4f4;
            }
            QFrame#Shell {
                background: transparent;
            }
            QFrame#WizardPanel, QFrame#PreviewPanel {
                background: rgba(247, 250, 253, 0.92);
                border: 1px solid rgba(209, 220, 230, 0.92);
                border-radius: 24px;
            }
            QFrame#WizardTopBar {
                background: rgba(255, 255, 255, 0.72);
                border: 1px solid rgba(218, 228, 237, 0.88);
                border-radius: 16px;
            }
            QLabel#HeaderTitle {
                font-size: 16px;
                font-weight: 700;
                color: #10283c;
            }
            QLabel#MetaPill {
                background: rgba(255, 255, 255, 0.84);
                border: 1px solid rgba(212, 224, 236, 0.94);
                border-radius: 11px;
                color: #4d657a;
                font-size: 12px;
                padding: 6px 10px;
            }
            QLabel#ProgressDot {
                color: #b4c1cd;
                font-size: 9px;
            }
            QLabel#ProgressText {
                color: #7a8b99;
                font-size: 10px;
                font-weight: 600;
            }
            QFrame#ProgressStrip {
                background: rgba(255, 255, 255, 0.58);
                border: 1px solid rgba(216, 226, 235, 0.86);
                border-radius: 14px;
            }
            QToolButton#RecentButton {
                background: rgba(255, 255, 255, 0.76);
                padding: 7px 10px;
            }
            QToolButton#InlineToggle {
                background: rgba(246, 250, 253, 0.92);
                border: 1px solid #d6e3ee;
                border-radius: 10px;
                padding: 7px 10px;
            }
            QLabel#CenterHero {
                font-size: 18px;
                font-weight: 700;
                color: #10283c;
            }
            QLabel#PreviewTitle {
                font-size: 16px;
                font-weight: 700;
                color: #14283a;
            }
            QLabel#CardTitle {
                font-size: 15px;
                font-weight: 650;
                color: #16293b;
            }
            QLabel#MutedText {
                color: #587086;
            }
            QFrame#Card, QFrame#DropCard {
                background: rgba(255, 255, 255, 0.90);
                border: 1px solid #dce5ee;
                border-radius: 20px;
            }
            QFrame#SubtlePanel {
                background: rgba(245, 249, 252, 0.92);
                border: 1px solid #dbe6f0;
                border-radius: 16px;
            }
            QFrame#PreviewSurface {
                background: white;
                border: 1px solid #dce6ef;
                border-radius: 18px;
            }
            QSplitter::handle {
                background: transparent;
                width: 10px;
            }
            QListWidget#ResultFiles, QComboBox, QScrollArea#CenterScroll {
                background: rgba(255, 255, 255, 0.72);
                border: 1px solid #d8e4ef;
                border-radius: 14px;
                padding: 6px;
            }
            QScrollArea {
                background: transparent;
                border: none;
            }
            QComboBox {
                min-height: 34px;
                padding-left: 10px;
            }
            QListWidget::item {
                padding: 8px 10px;
                border-radius: 10px;
            }
            QListWidget::item:selected {
                background: rgba(110, 186, 246, 0.22);
                color: #10324a;
            }
            QLabel {
                color: #132636;
            }
            QLabel#PreviewPlaceholder {
                color: #5e7486;
                font-size: 13px;
                padding: 12px;
            }
            """
        )

    def _apply_shadows(self) -> None:
        for widget, blur, offset_y in (
            (self.wizard_panel, 24, 10),
            (self.preview_panel, 24, 10),
            (self.wizard_header, 12, 4),
            (self.preview_surface, 22, 8),
            (self.progress_strip, 10, 3),
            (self.drop_card, 18, 8),
            (self.sheet_card, 18, 8),
            (self.recognition_card, 18, 8),
            (self.template_card, 18, 8),
            (self.controls_card, 18, 8),
            (self.preflight_card, 18, 8),
            (self.result_card, 18, 8),
        ):
            shadow = QGraphicsDropShadowEffect(self)
            shadow.setBlurRadius(blur)
            shadow.setOffset(0, offset_y)
            shadow.setColor(QColor(32, 60, 82, 28))
            widget.setGraphicsEffect(shadow)

    def _toggle_appearance_panel(self, checked: bool) -> None:
        self.appearance_panel.setVisible(checked)
        self.appearance_toggle.setText("收起高级选项" if checked else "高级选项")

    def _current_template(self) -> str:
        return str(self.template_combo.currentData())

    def _current_output_mode(self) -> str:
        return str(self.output_mode_combo.currentData())

    def _current_option_values(self) -> dict[str, Any]:
        return {
            "size": self.size_combo.currentText(),
            "style_preset": plot_style.DEFAULT_STYLE_PRESET,
            "palette_preset": self.palette_combo.currentText() or plot_style.DEFAULT_PALETTE_PRESET,
            "xscale": self.xscale_combo.currentText(),
            "yscale": self.yscale_combo.currentText(),
            "reverse_x": self.reverse_x_checkbox.isChecked(),
            "baseline": self.baseline_combo.currentText(),
            "show_colorbar": self.show_colorbar_checkbox.isChecked(),
            "use_sidecar": self.use_sidecar_checkbox.isChecked(),
        }

    def _current_render_key(self) -> tuple[Any, ...] | None:
        if self.current_input_path is None:
            return None
        options = self._current_option_values()
        return (
            str(self.current_input_path),
            self.current_sheet,
            self._current_template(),
            tuple(sorted(options.items())),
        )

    def _refresh_recent_files(self) -> None:
        self.recent_paths = _load_recent_files()

    def _show_recent_menu(self) -> None:
        menu = QMenu(self)
        if not getattr(self, "recent_paths", None):
            empty_action = menu.addAction("暂无最近文件")
            empty_action.setEnabled(False)
        else:
            for path in self.recent_paths:
                action = menu.addAction(path.name)
                action.setToolTip(str(path))
                action.triggered.connect(lambda _checked=False, p=path: self._open_input_file(p))
        menu.exec(self.recent_button.mapToGlobal(self.recent_button.rect().bottomLeft()))

    def _set_step(self, row: int) -> None:
        current = max(0, min(row, len(self.step_items) - 1))
        for index, (dot, text) in enumerate(self.step_items):
            if index < current:
                dot.setStyleSheet("color: #2f7ec9;")
                text.setStyleSheet("color: #244b72; font-weight: 650;")
            elif index == current:
                dot.setStyleSheet("color: #0f6bdc;")
                text.setStyleSheet("color: #0f2b42; font-weight: 700;")
            else:
                dot.setStyleSheet("color: #b4c1cd;")
                text.setStyleSheet("color: #7a8b99; font-weight: 600;")

    def _go_to_page(self, page: str) -> None:
        index = self.page_indices[page]
        self.center_stack.setCurrentIndex(index)
        titles = {
            "file": ("选择文件", "先把数据交给程序。"),
            "sheet": ("选择工作表", "只做这一个决定。"),
            "recognition": ("程序推荐", "先看程序怎么判断。"),
            "template": ("确认图类型", "如果推荐没问题，基本只要继续。"),
            "options": ("调整参数", "这里只保留必要选项。"),
            "preflight": ("出图前检查", "确认现在能稳稳画出来。"),
            "result": ("导出完成", "可以重画、换文件，或者结束。"),
        }
        title, subtitle = titles[page]
        self.center_title.setText(title)
        self.center_subtitle.setText(subtitle)
        step_map = {
            "file": 0,
            "sheet": 1,
            "recognition": 2,
            "template": 3,
            "options": 4,
            "preflight": 5,
            "result": 6,
        }
        self._set_step(step_map[page])

    def _show_preview_message(self, message: str) -> None:
        self.current_preview_index = 0
        self.preview_prev_button.setEnabled(False)
        self.preview_next_button.setEnabled(False)
        self.preview_status_label.setText("等待预览")
        self.preview_page_label.setText("— / —")
        self.preview_file_label.setText("—")
        self._current_preview_message = message
        self.preview_placeholder.setText(message)
        self.preview_placeholder.show()
        self.preview_scroll.hide()
        self.preview_image_label.clear()

    def _choose_file(self) -> None:
        filename, _ = QFileDialog.getOpenFileName(
            self,
            "选择数据文件",
            str(Path.cwd()),
            "Data files (*.csv *.txt *.tsv *.xlsx *.xlsm);;All files (*)",
        )
        if filename:
            self._open_input_file(Path(filename))

    def _handle_dropped_path(self, raw_path: str) -> None:
        cleaned = normalize_input_path_text(raw_path)
        self._open_input_file(Path(cleaned))

    def _open_input_file(self, path: Path) -> None:
        try:
            input_path = _ensure_input_path(str(path))
        except Exception as exc:
            self._show_error_dialog(f"无法打开文件：{exc}")
            return

        close_rendered_plots(self.current_rendered)
        self.current_rendered = []
        self.current_preview_key = None
        self.last_output_dir = None
        self.result_open_folder_button.setEnabled(False)
        self.current_input_path = input_path
        self.current_file_label.setText(input_path.name)
        self.current_file_label.setToolTip(str(input_path.resolve()))
        _remember_recent_file(input_path)
        self._refresh_recent_files()
        self._populate_sheet_combo()
        if self.sheet_combo.isEnabled():
            self._go_to_page("sheet")
            self._show_preview_message("先确认要读取哪个 sheet，预览随后会自动刷新。")
        else:
            self._inspect_current_file()

    def _populate_sheet_combo(self) -> None:
        self.sheet_combo.blockSignals(True)
        self.sheet_combo.clear()
        if self.current_input_path is None:
            self.sheet_combo.addItem("0", userData=0)
            self.sheet_combo.setEnabled(False)
            self.current_sheet = 0
            self.sheet_summary.setText("当前文件没有可选 sheet。")
        else:
            names = list_sheet_names(self.current_input_path)
            if len(names) <= 1:
                self.sheet_combo.addItem("0", userData=0)
                self.sheet_combo.setEnabled(False)
                self.current_sheet = 0
                if names:
                    self.sheet_combo.setItemText(0, f"0 · {names[0]}")
                self.sheet_summary.setText("这个文件只有一个可用 sheet，程序会直接继续。")
            else:
                for index, name in enumerate(names):
                    self.sheet_combo.addItem(f"{index} · {name}", userData=index)
                self.sheet_combo.setEnabled(True)
                self.current_sheet = 0
                self.sheet_hint.setText("检测到多个 sheet。先选一个再继续，程序会基于这个 sheet 给推荐。")
                self.sheet_summary.setText("当前将按这个 sheet 做识别和推荐。")
        self.sheet_combo.setCurrentIndex(0)
        self.sheet_combo.blockSignals(False)
        self.current_sheet_label.setText(f"Sheet · {self.current_sheet}")

    def _inspect_current_file(self) -> None:
        if self.current_input_path is None:
            return
        try:
            inspection = inspect_input_file(self.current_input_path, self.current_sheet)
        except Exception as exc:
            self.current_inspection = None
            self.model_value.setText("无法识别")
            self.recommended_template_value.setText("—")
            self.reason_value.setText(str(exc))
            self.recommendation_summary_value.setText("请先检查文件格式是否已经整理到约定结构。")
            self.signals_value.setText("请检查文件格式是否已整理到约定结构。")
            self.export_button.setEnabled(False)
            self._go_to_page("file")
            self._show_preview_message("当前文件还没有通过识别，暂不生成预览。")
            return

        self.current_inspection = inspection
        self.recognition_detail_button.setChecked(False)
        self.recognition_detail_frame.hide()
        self.model_value.setText(inspection.model_label)
        self.recommended_template_value.setText(
            f"{TEMPLATE_LABELS.get(inspection.recommendation.template, inspection.recommendation.template)} / {inspection.recommendation.template}"
        )
        self.reason_value.setText(inspection.recommendation.reason)
        summary_parts = [
            inspection.recommendation.size or "默认尺寸",
            f"x: {inspection.recommendation.xscale or 'linear'}",
            f"y: {inspection.recommendation.yscale or 'linear'}",
        ]
        if inspection.recommendation.reverse_x:
            summary_parts.append("反向 x")
        if inspection.recommendation.baseline and inspection.recommendation.baseline != "none":
            summary_parts.append(f"baseline: {inspection.recommendation.baseline}")
        if inspection.recommendation.use_sidecar:
            summary_parts.append("需要 sidecar")
        self.recommendation_summary_value.setText("推荐参数： " + " · ".join(summary_parts))
        self.signals_value.setText(_html_bullets(list(inspection.signals) + list(inspection.warnings)))
        defaults = terminal_wizard._recommended_defaults(inspection.recommendation.template, inspection.recommendation)
        self._apply_defaults_to_controls(inspection.recommendation.template, defaults)
        self._update_preflight_and_preview()
        self._go_to_page("recognition")

    def _apply_defaults_to_controls(self, template: str, defaults: dict[str, Any]) -> None:
        self._applying_defaults = True
        try:
            self.template_combo.blockSignals(True)
            target_index = self.template_combo.findData(template)
            if target_index >= 0:
                self.template_combo.setCurrentIndex(target_index)
            self.template_combo.blockSignals(False)

            self.size_combo.setCurrentText(str(defaults.get("size", "60x55")))
            requested_palette = str(defaults.get("palette_preset", plot_style.DEFAULT_PALETTE_PRESET))
            if requested_palette not in GUI_PALETTE_PRESET_CHOICES:
                requested_palette = plot_style.DEFAULT_PALETTE_PRESET
            self.palette_combo.setCurrentText(requested_palette)
            self.xscale_combo.setCurrentText(str(defaults.get("xscale", "linear")))
            self.yscale_combo.setCurrentText(str(defaults.get("yscale", "linear")))
            self.reverse_x_checkbox.setChecked(bool(defaults.get("reverse_x", False)))
            self.baseline_combo.setCurrentText(str(defaults.get("baseline", "none")))
            self.show_colorbar_checkbox.setChecked(bool(defaults.get("show_colorbar", True)))
            self.use_sidecar_checkbox.setChecked(bool(defaults.get("use_sidecar", False)))
            self._sync_option_visibility()
            self._update_template_summary()
            self._update_style_palette_summary()
        finally:
            self._applying_defaults = False

    def _sync_option_visibility(self) -> None:
        template = self._current_template()
        curve_like = template in {"curve", "point_line", "scatter"}
        self.option_rows["xscale"].setVisible(curve_like)
        self.option_rows["yscale"].setVisible(curve_like)
        self.option_rows["reverse_x"].setVisible(template in {"curve", "point_line", "scatter", "stacked_curve", "segmented_stacked_curve"})
        self.option_rows["baseline"].setVisible(template in {"stacked_curve", "segmented_stacked_curve"})
        self.option_rows["show_colorbar"].setVisible(template == "heatmap")
        self.option_rows["use_sidecar"].setVisible(template == "segmented_stacked_curve")

    def _on_sheet_changed(self) -> None:
        if self._applying_defaults or self.current_input_path is None:
            return
        self.current_sheet = self.sheet_combo.currentData() if self.sheet_combo.currentData() is not None else 0
        self.current_sheet_label.setText(f"Sheet · {self.current_sheet}")
        self.sheet_summary.setText(f"当前将按 sheet {self.current_sheet} 做识别和推荐。")

    def _confirm_sheet(self) -> None:
        self._inspect_current_file()

    def _on_template_changed(self) -> None:
        if self._applying_defaults:
            return
        template = self._current_template()
        defaults = terminal_wizard._recommended_defaults(template, None)
        self._apply_defaults_to_controls(template, defaults)
        self._update_preflight_and_preview()
        self._update_template_summary()

    def _on_option_changed(self) -> None:
        if self._applying_defaults:
            return
        self._sync_option_visibility()
        self._update_style_palette_summary()
        self._update_preflight_and_preview()

    def _update_style_palette_summary(self) -> None:
        palette_name = self.palette_combo.currentText() or plot_style.DEFAULT_PALETTE_PRESET
        palette_note = plot_style.get_palette_description(palette_name)
        self.style_note_label.setText("风格：当前默认科研风格。")
        self.style_note_label.setToolTip(plot_style.get_style_description(plot_style.DEFAULT_STYLE_PRESET))
        self.palette_note_label.setText(f"配色：{palette_note}")
        self.palette_note_label.setToolTip(plot_style.get_palette_description(palette_name))
        swatches = plot_style.get_palette_swatches(palette_name, limit=6)
        chips = " ".join(
            f'<span style="display:inline-block;width:12px;height:12px;border-radius:6px;background:{color};margin-right:6px;border:1px solid rgba(0,0,0,0.08);"></span>'
            for color in swatches
        )
        self.palette_swatches_label.setText(chips)

    def _accept_recommendation(self) -> None:
        if self.current_inspection is None:
            return
        self._go_to_page("template")

    def _toggle_recognition_details(self, checked: bool) -> None:
        self.recognition_detail_frame.setVisible(checked)
        self.recognition_detail_button.setText("收起细节" if checked else "为什么这样推荐")

    def _update_template_summary(self) -> None:
        template = self._current_template()
        descriptions = {
            "curve": "普通曲线，适合单条或多条曲线直接对比。",
            "point_line": "点线图，适合流变、应力松弛等需要同时看点和线的曲线。",
            "stacked_curve": "堆积曲线图，适合 FTIR / NMR / XRD / DSC 这类谱图。",
            "segmented_stacked_curve": "分段堆积曲线图，适合带断轴、高亮和 sidecar 的高级谱图。",
            "bar": "柱状图，固定从 0 开始，适合均值 + 误差棒。",
            "box": "箱线图，适合看分布和离群值。",
            "violin": "小提琴图，适合看分布形状。",
            "scatter": "散点图，默认不连线。",
            "heatmap": "热图，适合 X/Y/Z 长表数据。",
        }
        self.template_summary_label.setText(descriptions.get(template, "请选择一种合适的图类型。"))

    def _update_preflight_and_preview(self) -> None:
        if self.current_input_path is None:
            return
        template = self._current_template()
        option_values = self._current_option_values()
        options = _resolve_render_options(
            template=template,
            size=option_values.get("size"),
            xscale=option_values.get("xscale"),
            yscale=option_values.get("yscale"),
            reverse_x=bool(option_values.get("reverse_x", False)),
            baseline=option_values.get("baseline"),
            show_colorbar=option_values.get("show_colorbar"),
            style_preset=str(option_values.get("style_preset", plot_style.DEFAULT_STYLE_PRESET)),
            palette_preset=str(option_values.get("palette_preset", plot_style.DEFAULT_PALETTE_PRESET)),
            use_sidecar=option_values.get("use_sidecar"),
        )
        preflight = preflight_render_request(template, self.current_input_path, self.current_sheet, options)
        self.current_preflight = preflight
        self._render_preflight_card(preflight)
        self._update_output_dir_label()
        self.export_button.setEnabled(not preflight.errors)
        if preflight.errors:
            self._show_preview_message("预检查还没通过，暂不生成预览。")
            return
        self.schedule_preview()

    def _render_preflight_card(self, preflight: Any) -> None:
        if preflight.errors:
            self.preflight_status.setText("当前不能直接出图，需要先修改。")
            self.preflight_details.setText(_html_bullets(preflight.errors))
        elif preflight.warnings:
            content = list(preflight.warnings)
            if preflight.output_filenames:
                content.append(f"预计输出：{', '.join(preflight.output_filenames)}")
            self.preflight_status.setText("当前可以继续，但建议先注意这些事项。")
            self.preflight_details.setText(_html_bullets(content))
        else:
            details = [f"预计输出：{', '.join(preflight.output_filenames)}"] if preflight.output_filenames else []
            self.preflight_status.setText("当前检查通过，可以直接预览和导出。")
            self.preflight_details.setText(_html_bullets(details))

    def _update_output_dir_label(self) -> None:
        if self.current_input_path is None:
            self.output_dir_label.setText("输出目录：-")
            return
        output_dir = resolve_output_dir(self.current_input_path, None, self._current_output_mode())
        self.output_dir_label.setText(f"输出目录：{output_dir.resolve()}")

    def schedule_preview(self) -> None:
        if self.current_input_path is None or (self.current_preflight and self.current_preflight.errors):
            return
        self.preview_timer.start()

    def _dispatch_preview(self) -> None:
        if self.current_input_path is None or (self.current_preflight and self.current_preflight.errors):
            return
        if self.preview_running:
            self.preview_pending = True
            return
        self.preview_running = True
        self.preview_pending = False
        self.preview_token += 1
        token = self.preview_token
        template = self._current_template()
        option_values = self._current_option_values()
        self.preview_status_label.setText("正在生成预览…")

        worker = PreviewWorker(token, template, self.current_input_path, self.current_sheet, option_values)
        worker.signals.finished.connect(self._handle_preview_finished)
        worker.signals.failed.connect(self._handle_preview_failed)
        self.threadpool.start(worker)

    def _handle_preview_finished(self, token: int, rendered_plots: object, option_values: object) -> None:
        if token != self.preview_token:
            close_rendered_plots(list(rendered_plots))
            return
        self.preview_running = False
        close_rendered_plots(self.current_rendered)
        self.current_rendered = list(rendered_plots)
        self.current_preview_key = self._current_render_key()
        self.current_preview_index = 0
        self.preview_prev_button.setEnabled(False)
        self.preview_next_button.setEnabled(len(self.current_rendered) > 1)
        self._show_selected_preview(0)
        self.preview_status_label.setText("预览已更新")
        if self.preview_pending:
            self.preview_pending = False
            self.schedule_preview()

    def _handle_preview_failed(self, token: int, message: str) -> None:
        if token != self.preview_token:
            return
        self.preview_running = False
        self.preview_status_label.setText("预览失败")
        self._show_preview_message(message)
        if self.preview_pending:
            self.preview_pending = False
            self.schedule_preview()

    def _show_selected_preview(self, index: int) -> None:
        if index < 0 or index >= len(self.current_rendered):
            return
        self.current_preview_index = index
        self.preview_prev_button.setEnabled(index > 0)
        self.preview_next_button.setEnabled(index < len(self.current_rendered) - 1)
        self.preview_page_label.setText(f"{index + 1} / {len(self.current_rendered)}")
        self._refresh_preview_image()

    def _step_preview_index(self, step: int) -> None:
        if not self.current_rendered:
            return
        next_index = self.current_preview_index + step
        if 0 <= next_index < len(self.current_rendered):
            self._show_selected_preview(next_index)

    def _on_zoom_changed(self) -> None:
        value = self.zoom_combo.currentData()
        if isinstance(value, str):
            self._preview_mode = value
        else:
            self._preview_mode = "fixed"
            self._preview_scale_value = float(value)
        self._refresh_preview_image()

    def _zoom_out(self) -> None:
        index = self.zoom_combo.currentIndex()
        if index > 0:
            self.zoom_combo.setCurrentIndex(index - 1)

    def _zoom_in(self) -> None:
        index = self.zoom_combo.currentIndex()
        if index < self.zoom_combo.count() - 1:
            self.zoom_combo.setCurrentIndex(index + 1)

    def eventFilter(self, watched: QObject, event: QEvent) -> bool:
        if watched in {self.preview_image_label, self.preview_scroll.viewport()} and self.current_rendered:
            if event.type() == QEvent.Type.MouseButtonDblClick:
                if self._preview_mode == "fit_width":
                    target = self.zoom_combo.findData(1.0)
                else:
                    target = self.zoom_combo.findData("fit_width")
                if target >= 0:
                    self.zoom_combo.setCurrentIndex(target)
                return True
            if event.type() == QEvent.Type.Wheel:
                delta = event.angleDelta().y()  # type: ignore[attr-defined]
                if delta > 0:
                    self._zoom_in()
                elif delta < 0:
                    self._zoom_out()
                return True
        return super().eventFilter(watched, event)

    def _resolve_preview_scale(self, rendered: RenderedPlot) -> float:
        width_in, height_in = rendered.figure.get_size_inches()
        base_width = max(1.0, width_in * PREVIEW_BASE_DPI)
        base_height = max(1.0, height_in * PREVIEW_BASE_DPI)
        viewport_width = max(120, self.preview_scroll.viewport().width() - 24)
        viewport_height = max(120, self.preview_scroll.viewport().height() - 24)

        if self._preview_mode == "fit_width":
            return max(0.35, min(4.0, viewport_width / base_width))
        if self._preview_mode == "fit_page":
            return max(0.35, min(4.0, min(viewport_width / base_width, viewport_height / base_height)))
        return self._preview_scale_value

    def _build_preview_pixmap(self, rendered: RenderedPlot) -> QPixmap:
        scale = self._resolve_preview_scale(rendered)
        dpi = PREVIEW_BASE_DPI * scale
        buffer = BytesIO()
        rendered.figure.savefig(buffer, format="png", dpi=dpi, facecolor="white")
        pixmap = QPixmap()
        pixmap.loadFromData(buffer.getvalue())
        return pixmap

    def _refresh_preview_image(self) -> None:
        index = self.current_preview_index
        if index < 0 or index >= len(self.current_rendered):
            if self._current_preview_message:
                self._show_preview_message(self._current_preview_message)
            return
        rendered = self.current_rendered[index]
        pixmap = self._build_preview_pixmap(rendered)
        self.preview_image_label.setPixmap(pixmap)
        self.preview_image_label.resize(pixmap.size())
        self.preview_placeholder.hide()
        self.preview_scroll.show()
        self.preview_status_label.setText("预览已更新")
        self.preview_file_label.setText(rendered.filename)

    def _export_current(self) -> None:
        if self.current_input_path is None or (self.current_preflight and self.current_preflight.errors):
            return
        template = self._current_template()
        option_values = self._current_option_values()
        render_key = self._current_render_key()
        reuse_preview = bool(self.current_rendered) and render_key == self.current_preview_key
        output_dir = resolve_output_dir(self.current_input_path, None, self._current_output_mode())

        try:
            if reuse_preview:
                outputs = export_rendered_plots(self.current_rendered, output_dir, close=False)
            else:
                rendered = build_rendered_plots(
                    template,
                    self.current_input_path,
                    self.current_sheet,
                    size=option_values.get("size"),
                    xscale=option_values.get("xscale"),
                    yscale=option_values.get("yscale"),
                    reverse_x=bool(option_values.get("reverse_x", False)),
                    baseline=option_values.get("baseline"),
                    show_colorbar=option_values.get("show_colorbar"),
                    style_preset=option_values.get("style_preset", plot_style.DEFAULT_STYLE_PRESET),
                    palette_preset=option_values.get("palette_preset", plot_style.DEFAULT_PALETTE_PRESET),
                    use_sidecar=option_values.get("use_sidecar"),
                )
                outputs = export_rendered_plots(rendered, output_dir, close=True)
            terminal_wizard._remember_defaults(template, option_values)
        except Exception as exc:  # pragma: no cover - GUI error path
            self._show_error_dialog(f"导出失败：{exc}")
            return

        self._go_to_page("result")
        self.last_output_dir = output_dir
        self.result_open_folder_button.setEnabled(True)
        style_name = option_values.get("style_preset", plot_style.DEFAULT_STYLE_PRESET)
        palette_name = option_values.get("palette_preset", plot_style.DEFAULT_PALETTE_PRESET)
        self.result_summary.setText(
            f"已导出 {len(outputs)} 个 PDF。\n图类型：{TEMPLATE_LABELS.get(template, template)} / {template}\n风格：{style_name} · 配色：{palette_name}\n输出目录：{output_dir.resolve()}"
        )
        self.result_files.clear()
        for output in outputs:
            item = QListWidgetItem(output.name)
            item.setToolTip(str(output.resolve()))
            self.result_files.addItem(item)

    def _show_error_dialog(self, message: str) -> None:
        self.result_summary.setText(message)
        self.preview_status_label.setText("发生错误")
        if self.current_input_path is None:
            self._go_to_page("file")
        else:
            self._go_to_page("preflight")
        self._show_preview_message(message)

    def resizeEvent(self, event) -> None:  # noqa: N802
        super().resizeEvent(event)
        if self._preview_mode in {"fit_page", "fit_width"} and self.current_rendered:
            self._refresh_preview_image()

    def _open_last_output_dir(self) -> None:
        if self.last_output_dir is None:
            return
        try:
            subprocess.run(["open", str(self.last_output_dir.resolve())], check=False)
        except Exception as exc:  # pragma: no cover - GUI error path
            self._show_error_dialog(f"无法打开输出目录：{exc}")


def main() -> int:
    app = QApplication(sys.argv)
    app.setApplicationName(APP_TITLE)
    app.setStyle("Fusion")
    app.setFont(_pick_app_font())
    window = PlotWizardWindow()
    window.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
