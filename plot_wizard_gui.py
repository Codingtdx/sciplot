from __future__ import annotations

from io import BytesIO
import subprocess
import sys
import traceback
from dataclasses import asdict
from pathlib import Path
from typing import Any

from PySide6.QtCore import QObject, QRunnable, QThreadPool, QTimer, Qt, Signal
from PySide6.QtGui import QAction, QColor, QDragEnterEvent, QDropEvent, QPixmap
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
    QPushButton,
    QScrollArea,
    QSplitter,
    QStackedWidget,
    QToolBar,
    QToolButton,
    QVBoxLayout,
    QWidget,
)

import interactive_plot as terminal_wizard
from make_plot import (
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


APP_TITLE = "绘图精灵 3.0"
APP_SUBTITLE = "拖入数据，程序先判断、先推荐，你拍板后直接出图。"
RECENT_FILES_KEY = "recent_files"
MAX_RECENT_FILES = 8
PREVIEW_DEBOUNCE_MS = 260
PREVIEW_BASE_DPI = 160
MENU_ITEMS = terminal_wizard.MENU_ITEMS
TEMPLATE_LABELS = terminal_wizard.TEMPLATE_LABELS


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
                use_sidecar=self.option_values.get("use_sidecar"),
            )
            self.signals.finished.emit(self.token, rendered, dict(self.option_values))
        except Exception as exc:  # pragma: no cover - GUI error path
            self.signals.failed.emit(self.token, f"{exc}\n\n{traceback.format_exc(limit=3)}")


class PlotWizardWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle(APP_TITLE)
        self.resize(1540, 980)
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
        self.last_output_dir: Path | None = None
        self.preview_token = 0
        self.preview_running = False
        self.preview_pending = False
        self._applying_defaults = False
        self._current_preview_message = "右侧会在你选定文件和参数后自动出现实时预览。"
        self._preview_mode = "fit_page"
        self._preview_scale_value = 1.0

        self._build_ui()
        self._apply_styles()
        self._apply_shadows()
        self._refresh_recent_files()
        self._go_to_page("file")
        self._show_preview_message("右侧会在你选定文件和参数后自动出现实时预览。")

    def closeEvent(self, event) -> None:  # noqa: N802
        close_rendered_plots(self.current_rendered)
        super().closeEvent(event)

    def _build_ui(self) -> None:
        self._build_toolbar()

        root = QWidget()
        root_layout = QHBoxLayout(root)
        root_layout.setContentsMargins(20, 18, 20, 18)
        root_layout.setSpacing(16)

        splitter = QSplitter(Qt.Orientation.Horizontal)
        splitter.setChildrenCollapsible(False)
        root_layout.addWidget(splitter)
        self.setCentralWidget(root)

        self.sidebar = self._build_sidebar()
        self.center_panel = self._build_center_panel()
        self.preview_panel = self._build_preview_panel()

        splitter.addWidget(self.sidebar)
        splitter.addWidget(self.center_panel)
        splitter.addWidget(self.preview_panel)
        splitter.setStretchFactor(0, 0)
        splitter.setStretchFactor(1, 1)
        splitter.setStretchFactor(2, 1)
        splitter.setSizes([210, 470, 860])

    def _build_toolbar(self) -> None:
        toolbar = QToolBar()
        toolbar.setMovable(False)
        toolbar.setObjectName("MainToolbar")
        self.addToolBar(Qt.ToolBarArea.TopToolBarArea, toolbar)

        open_action = QAction("打开文件", self)
        open_action.triggered.connect(self._choose_file)
        toolbar.addAction(open_action)

        export_action = QAction("导出 PDF", self)
        export_action.triggered.connect(self._export_current)
        toolbar.addAction(export_action)

        refresh_action = QAction("刷新预览", self)
        refresh_action.triggered.connect(self.schedule_preview)
        toolbar.addAction(refresh_action)

        toolbar.addSeparator()
        toolbar.addWidget(QLabel("Codex 风格三栏绘图精灵"))

    def _build_sidebar(self) -> QWidget:
        frame = QFrame()
        frame.setObjectName("Sidebar")
        layout = QVBoxLayout(frame)
        layout.setContentsMargins(18, 18, 18, 18)
        layout.setSpacing(16)

        title = QLabel(APP_TITLE)
        title.setObjectName("SidebarTitle")
        subtitle = QLabel("课题组标准出图工具")
        subtitle.setObjectName("MutedText")

        self.current_file_label = QLabel("当前文件：未选择")
        self.current_file_label.setWordWrap(True)
        self.current_file_label.setObjectName("SidebarValue")
        self.current_sheet_label = QLabel("当前 Sheet：-")
        self.current_sheet_label.setObjectName("SidebarValue")

        steps_title = QLabel("步骤")
        steps_title.setObjectName("CardTitle")
        self.steps_list = QListWidget()
        self.steps_list.setObjectName("SidebarList")
        self.steps_list.setFocusPolicy(Qt.FocusPolicy.NoFocus)
        for step in ("1. 文件", "2. 识别", "3. 选项", "4. 检查", "5. 导出"):
            self.steps_list.addItem(QListWidgetItem(step))
        self.steps_list.setCurrentRow(0)

        self.recent_toggle_button = QPushButton("显示最近文件")
        self.recent_toggle_button.setCheckable(True)
        self.recent_toggle_button.toggled.connect(self._toggle_recent_files)
        self.recent_list = QListWidget()
        self.recent_list.setObjectName("SidebarList")
        self.recent_list.itemActivated.connect(self._open_recent_file)
        self.recent_list.hide()

        layout.addWidget(title)
        layout.addWidget(subtitle)
        layout.addSpacing(6)
        layout.addWidget(self.current_file_label)
        layout.addWidget(self.current_sheet_label)
        layout.addSpacing(10)
        layout.addWidget(steps_title)
        layout.addWidget(self.steps_list, 1)
        layout.addWidget(self.recent_toggle_button)
        layout.addWidget(self.recent_list, 2)
        return frame

    def _build_center_panel(self) -> QWidget:
        container = QWidget()
        layout = QVBoxLayout(container)
        layout.setContentsMargins(4, 4, 4, 4)
        layout.setSpacing(14)

        self.center_title = QLabel("先拖入一个数据文件")
        self.center_title.setObjectName("CenterHero")
        self.center_subtitle = QLabel("程序会先识别输入模型，再给出一个推荐。你每一步只需要做一个决定。")
        self.center_subtitle.setObjectName("MutedText")
        self.center_subtitle.setWordWrap(True)
        layout.addWidget(self.center_title)
        layout.addWidget(self.center_subtitle)

        self.center_stack = QStackedWidget()
        layout.addWidget(self.center_stack, 1)

        file_page = QWidget()
        file_layout = QVBoxLayout(file_page)
        file_layout.setContentsMargins(0, 0, 0, 0)
        file_layout.setSpacing(14)
        self.drop_card = DropCard(self._choose_file)
        self.drop_card.fileDropped.connect(self._handle_dropped_path)
        file_layout.addWidget(self.drop_card)
        self.sheet_card, sheet_body = self._make_card("工作表")
        self.sheet_hint = QLabel("如果文件包含多个 sheet，这里会先让你决定读哪一个。")
        self.sheet_hint.setWordWrap(True)
        self.sheet_combo = QComboBox()
        self.sheet_combo.currentIndexChanged.connect(self._on_sheet_changed)
        sheet_body.addWidget(self.sheet_hint)
        sheet_body.addWidget(self.sheet_combo)
        file_layout.addWidget(self.sheet_card)
        file_layout.addStretch(1)
        self.center_stack.addWidget(file_page)

        recognition_page = QWidget()
        recognition_layout = QVBoxLayout(recognition_page)
        recognition_layout.setContentsMargins(0, 0, 0, 0)
        recognition_layout.setSpacing(14)
        self.recognition_card, recognition_body = self._make_card("识别结果")
        self.model_value = QLabel("等待文件")
        self.recommended_template_value = QLabel("—")
        self.reason_value = QLabel("程序会先识别输入模型，再给一个推荐。")
        self.reason_value.setWordWrap(True)
        self.signals_value = QLabel("—")
        self.signals_value.setWordWrap(True)
        recognition_body.addWidget(QLabel("输入模型"))
        recognition_body.addWidget(self.model_value)
        recognition_body.addWidget(QLabel("推荐图类型"))
        recognition_body.addWidget(self.recommended_template_value)
        recognition_body.addWidget(QLabel("推荐理由"))
        recognition_body.addWidget(self.reason_value)
        recognition_body.addWidget(QLabel("程序这样判断"))
        recognition_body.addWidget(self.signals_value)
        recognition_layout.addWidget(self.recognition_card)
        recognition_actions = QHBoxLayout()
        self.recognition_accept_button = QPushButton("采用推荐")
        self.recognition_accept_button.clicked.connect(self._accept_recommendation)
        self.recognition_tune_button = QPushButton("我想调参数")
        self.recognition_tune_button.clicked.connect(lambda: self._go_to_page("options"))
        self.recognition_sheet_button = QPushButton("重选 Sheet")
        self.recognition_sheet_button.clicked.connect(lambda: self._go_to_page("file"))
        recognition_actions.addWidget(self.recognition_accept_button)
        recognition_actions.addWidget(self.recognition_tune_button)
        recognition_actions.addWidget(self.recognition_sheet_button)
        recognition_actions.addStretch(1)
        recognition_layout.addLayout(recognition_actions)
        recognition_layout.addStretch(1)
        self.center_stack.addWidget(recognition_page)

        options_page = QWidget()
        options_layout = QVBoxLayout(options_page)
        options_layout.setContentsMargins(0, 0, 0, 0)
        options_layout.setSpacing(14)
        self.controls_card, controls_body = self._make_card("图形设置")
        self.template_combo = QComboBox()
        for template, label in MENU_ITEMS:
            self.template_combo.addItem(f"{label} / {template}", userData=template)
        self.template_combo.currentIndexChanged.connect(self._on_template_changed)
        self.size_combo = QComboBox()
        self.size_combo.addItems(list(terminal_wizard.SIZE_CHOICES))
        self.size_combo.currentTextChanged.connect(self._on_option_changed)
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

        self.option_rows: dict[str, QWidget] = {}
        controls_body.addWidget(self._option_row("图类型", self.template_combo, "template"))
        controls_body.addWidget(self._option_row("尺寸", self.size_combo, "size"))
        controls_body.addWidget(self._option_row("x 轴", self.xscale_combo, "xscale"))
        controls_body.addWidget(self._option_row("y 轴", self.yscale_combo, "yscale"))
        controls_body.addWidget(self._option_row("", self.reverse_x_checkbox, "reverse_x"))
        controls_body.addWidget(self._option_row("基线修正", self.baseline_combo, "baseline"))
        controls_body.addWidget(self._option_row("", self.show_colorbar_checkbox, "show_colorbar"))
        controls_body.addWidget(self._option_row("", self.use_sidecar_checkbox, "use_sidecar"))
        options_layout.addWidget(self.controls_card)
        options_actions = QHBoxLayout()
        self.options_back_button = QPushButton("返回识别结果")
        self.options_back_button.clicked.connect(lambda: self._go_to_page("recognition"))
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
        self.preflight_card, preflight_body = self._make_card("预检查")
        self.preflight_status = QLabel("等待识别结果")
        self.preflight_status.setWordWrap(True)
        self.preflight_details = QLabel("—")
        self.preflight_details.setWordWrap(True)
        preflight_body.addWidget(self.preflight_status)
        preflight_body.addWidget(self.preflight_details)
        preflight_layout.addWidget(self.preflight_card)

        self.export_card, export_body = self._make_card("导出")
        self.output_mode_combo = QComboBox()
        self.output_mode_combo.addItem("工作目录 / workspace", userData="workspace")
        self.output_mode_combo.addItem("数据同级目录 / data_dir", userData="data_dir")
        self.output_mode_combo.currentIndexChanged.connect(self._update_output_dir_label)
        self.output_dir_label = QLabel("输出目录：-")
        self.output_dir_label.setWordWrap(True)
        self.export_button = QPushButton("导出 PDF")
        self.export_button.clicked.connect(self._export_current)
        self.export_button.setEnabled(False)
        export_body.addWidget(self._option_row("输出模式", self.output_mode_combo, "output_mode"))
        export_body.addWidget(self.output_dir_label)
        export_body.addWidget(self.export_button, 0, Qt.AlignmentFlag.AlignLeft)
        preflight_layout.addWidget(self.export_card)
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
            "recognition": 1,
            "options": 2,
            "preflight": 3,
            "result": 4,
        }
        self.center_stack.setCurrentIndex(self.page_indices["file"])
        return container

    def _build_preview_panel(self) -> QWidget:
        frame = QFrame()
        frame.setObjectName("PreviewPanel")
        layout = QVBoxLayout(frame)
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(12)

        header_row = QHBoxLayout()
        title = QLabel("实时预览")
        title.setObjectName("PreviewTitle")
        self.preview_status_label = QLabel("等待文件")
        self.preview_status_label.setObjectName("MutedText")
        header_row.addWidget(title)
        header_row.addStretch(1)
        header_row.addWidget(self.preview_status_label)

        controls_row = QHBoxLayout()
        controls_row.setSpacing(8)
        self.preview_prev_button = QToolButton()
        self.preview_prev_button.setText("‹")
        self.preview_prev_button.clicked.connect(lambda: self._step_preview_index(-1))
        self.preview_selector = QComboBox()
        self.preview_selector.currentIndexChanged.connect(self._show_selected_preview)
        self.preview_next_button = QToolButton()
        self.preview_next_button.setText("›")
        self.preview_next_button.clicked.connect(lambda: self._step_preview_index(1))
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
        self.preview_selector.setEnabled(False)
        controls_row.addWidget(self.preview_prev_button)
        controls_row.addWidget(self.preview_selector, 1)
        controls_row.addWidget(self.preview_next_button)
        controls_row.addSpacing(10)
        controls_row.addWidget(self.zoom_out_button)
        controls_row.addWidget(self.zoom_combo)
        controls_row.addWidget(self.zoom_in_button)

        self.preview_surface = QFrame()
        self.preview_surface.setObjectName("PreviewSurface")
        self.preview_surface_layout = QVBoxLayout(self.preview_surface)
        self.preview_surface_layout.setContentsMargins(12, 12, 12, 12)
        self.preview_placeholder = QLabel()
        self.preview_placeholder.setWordWrap(True)
        self.preview_placeholder.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.preview_placeholder.setObjectName("PreviewPlaceholder")
        self.preview_image_label = QLabel()
        self.preview_image_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.preview_scroll = QScrollArea()
        self.preview_scroll.setWidget(self.preview_image_label)
        self.preview_scroll.setWidgetResizable(False)
        self.preview_scroll.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.preview_scroll.setFrameShape(QFrame.Shape.NoFrame)
        self.preview_surface_layout.addWidget(self.preview_placeholder)
        self.preview_surface_layout.addWidget(self.preview_scroll)
        self.preview_scroll.hide()

        layout.addLayout(header_row)
        layout.addLayout(controls_row)
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
                    stop: 0 #d8e9f8,
                    stop: 0.45 #edf3f8,
                    stop: 1 #dce7f2
                );
            }
            QToolBar#MainToolbar {
                spacing: 10px;
                background: rgba(255, 255, 255, 0.74);
                border: 1px solid rgba(206, 220, 236, 0.9);
                border-radius: 18px;
                padding: 12px;
                margin: 12px 18px 6px 18px;
            }
            QToolButton, QPushButton {
                background: rgba(255, 255, 255, 0.92);
                border: 1px solid #d5e0ea;
                border-radius: 12px;
                padding: 8px 14px;
                font-size: 13px;
            }
            QPushButton:hover, QToolButton:hover {
                border-color: #8fc4f4;
            }
            QFrame#Sidebar {
                background: rgba(229, 241, 250, 0.82);
                border: 1px solid rgba(190, 209, 226, 0.95);
                border-radius: 28px;
            }
            QLabel#SidebarTitle {
                font-size: 26px;
                font-weight: 700;
                color: #0f2537;
            }
            QLabel#CenterHero {
                font-size: 30px;
                font-weight: 700;
                color: #10283c;
                padding-left: 6px;
            }
            QLabel#PreviewTitle {
                font-size: 20px;
                font-weight: 700;
                color: #14283a;
            }
            QLabel#CardTitle {
                font-size: 18px;
                font-weight: 650;
                color: #16293b;
            }
            QLabel#MutedText, QLabel#SidebarValue {
                color: #587086;
            }
            QFrame#Card, QFrame#DropCard {
                background: rgba(255, 255, 255, 0.88);
                border: 1px solid #d8e4ef;
                border-radius: 22px;
            }
            QFrame#PreviewPanel {
                background: rgba(238, 245, 251, 0.95);
                border: 1px solid #d6e1eb;
                border-radius: 28px;
            }
            QFrame#PreviewSurface {
                background: white;
                border: 1px solid #dce6ef;
                border-radius: 20px;
            }
            QListWidget#SidebarList, QListWidget#ResultFiles, QComboBox, QScrollArea#CenterScroll {
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
                font-size: 14px;
                padding: 16px;
            }
            """
        )

    def _apply_shadows(self) -> None:
        for widget, blur, offset_y in (
            (self.sidebar, 30, 12),
            (self.preview_surface, 28, 10),
            (self.drop_card, 18, 8),
            (self.recognition_card, 18, 8),
            (self.controls_card, 18, 8),
            (self.preflight_card, 18, 8),
            (self.export_card, 18, 8),
            (self.result_card, 18, 8),
        ):
            shadow = QGraphicsDropShadowEffect(self)
            shadow.setBlurRadius(blur)
            shadow.setOffset(0, offset_y)
            shadow.setColor(QColor(32, 60, 82, 28))
            widget.setGraphicsEffect(shadow)

    def _current_template(self) -> str:
        return str(self.template_combo.currentData())

    def _current_output_mode(self) -> str:
        return str(self.output_mode_combo.currentData())

    def _current_option_values(self) -> dict[str, Any]:
        return {
            "size": self.size_combo.currentText(),
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
        self.recent_list.clear()
        for path in _load_recent_files():
            item = QListWidgetItem(path.name)
            item.setToolTip(str(path))
            item.setData(Qt.ItemDataRole.UserRole, str(path))
            self.recent_list.addItem(item)

    def _toggle_recent_files(self, checked: bool) -> None:
        self.recent_list.setVisible(checked)
        self.recent_toggle_button.setText("隐藏最近文件" if checked else "显示最近文件")

    def _set_step(self, row: int) -> None:
        self.steps_list.setCurrentRow(max(0, min(row, self.steps_list.count() - 1)))

    def _go_to_page(self, page: str) -> None:
        index = self.page_indices[page]
        self.center_stack.setCurrentIndex(index)
        titles = {
            "file": ("先选一个文件", "你现在只需要决定读哪个文件、哪个 sheet。"),
            "recognition": ("先看程序推荐", "程序已经识别了输入结构。先看结论，再决定是否接受。"),
            "options": ("只改必要选项", "这里只放当前图真正有用的参数，不再把所有信息一次摊开。"),
            "preflight": ("出图前检查一下", "这里会告诉你能不能直接出图，以及还需要注意什么。"),
            "result": ("图已经画好了", "你现在可以继续重画、换文件，或者直接结束。"),
        }
        title, subtitle = titles[page]
        self.center_title.setText(title)
        self.center_subtitle.setText(subtitle)
        step_map = {"file": 0, "recognition": 1, "options": 2, "preflight": 3, "result": 4}
        self._set_step(step_map[page])

    def _show_preview_message(self, message: str) -> None:
        self.preview_selector.blockSignals(True)
        self.preview_selector.clear()
        self.preview_selector.setEnabled(False)
        self.preview_selector.blockSignals(False)
        self.preview_prev_button.setEnabled(False)
        self.preview_next_button.setEnabled(False)
        self.preview_status_label.setText(message)
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

    def _open_recent_file(self, item: QListWidgetItem) -> None:
        raw = item.data(Qt.ItemDataRole.UserRole)
        if raw:
            self._open_input_file(Path(str(raw)))

    def _open_input_file(self, path: Path) -> None:
        try:
            input_path = _ensure_input_path(str(path))
        except Exception as exc:
            self._show_error_dialog(f"无法打开文件：{exc}")
            return

        self.last_output_dir = None
        self.result_open_folder_button.setEnabled(False)
        self.current_input_path = input_path
        self.current_file_label.setText(f"当前文件：{input_path.name}")
        _remember_recent_file(input_path)
        self._refresh_recent_files()
        self._populate_sheet_combo()
        self._inspect_current_file()

    def _populate_sheet_combo(self) -> None:
        self.sheet_combo.blockSignals(True)
        self.sheet_combo.clear()
        if self.current_input_path is None:
            self.sheet_combo.addItem("0", userData=0)
            self.sheet_combo.setEnabled(False)
            self.current_sheet = 0
            self.sheet_card.setVisible(False)
        else:
            names = list_sheet_names(self.current_input_path)
            if not names:
                self.sheet_combo.addItem("0", userData=0)
                self.sheet_combo.setEnabled(False)
                self.current_sheet = 0
                self.sheet_card.setVisible(False)
            else:
                for index, name in enumerate(names):
                    self.sheet_combo.addItem(f"{index} · {name}", userData=index)
                self.sheet_combo.setEnabled(True)
                self.current_sheet = 0
                self.sheet_card.setVisible(True)
                self.sheet_hint.setText("检测到多个 sheet。先选一个再继续，程序会基于这个 sheet 给推荐。")
        self.sheet_combo.setCurrentIndex(0)
        self.sheet_combo.blockSignals(False)
        self.current_sheet_label.setText(f"当前 Sheet：{self.current_sheet}")

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
            self.signals_value.setText("请检查文件格式是否已整理到约定结构。")
            self.export_button.setEnabled(False)
            self._go_to_page("file")
            self._show_preview_message("当前文件还没有通过识别，右侧暂不生成预览。")
            return

        self.current_inspection = inspection
        self.model_value.setText(inspection.model_label)
        self.recommended_template_value.setText(
            f"{TEMPLATE_LABELS.get(inspection.recommendation.template, inspection.recommendation.template)} / {inspection.recommendation.template}"
        )
        self.reason_value.setText(inspection.recommendation.reason)
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
            self.xscale_combo.setCurrentText(str(defaults.get("xscale", "linear")))
            self.yscale_combo.setCurrentText(str(defaults.get("yscale", "linear")))
            self.reverse_x_checkbox.setChecked(bool(defaults.get("reverse_x", False)))
            self.baseline_combo.setCurrentText(str(defaults.get("baseline", "none")))
            self.show_colorbar_checkbox.setChecked(bool(defaults.get("show_colorbar", True)))
            self.use_sidecar_checkbox.setChecked(bool(defaults.get("use_sidecar", False)))
            self._sync_option_visibility()
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
        self.current_sheet_label.setText(f"当前 Sheet：{self.current_sheet}")
        self._inspect_current_file()

    def _on_template_changed(self) -> None:
        if self._applying_defaults:
            return
        template = self._current_template()
        defaults = terminal_wizard._recommended_defaults(template, None)
        self._apply_defaults_to_controls(template, defaults)
        self._update_preflight_and_preview()
        self._go_to_page("options")

    def _on_option_changed(self) -> None:
        if self._applying_defaults:
            return
        self._sync_option_visibility()
        self._update_preflight_and_preview()

    def _accept_recommendation(self) -> None:
        if self.current_inspection is None:
            return
        self._go_to_page("preflight")

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
            use_sidecar=option_values.get("use_sidecar"),
        )
        preflight = preflight_render_request(template, self.current_input_path, self.current_sheet, options)
        self.current_preflight = preflight
        self._render_preflight_card(preflight)
        self._update_output_dir_label()
        self.export_button.setEnabled(not preflight.errors)
        if preflight.errors:
            self._show_preview_message("预检查还没通过。右侧暂不生成预览。")
            return
        self.schedule_preview()

    def _render_preflight_card(self, preflight: Any) -> None:
        if preflight.errors:
            self._set_step(3)
            self.preflight_status.setText("当前不能直接出图，需要先修改。")
            self.preflight_details.setText(_html_bullets(preflight.errors))
        elif preflight.warnings:
            self._set_step(3)
            content = list(preflight.warnings)
            if preflight.output_filenames:
                content.append(f"预计输出：{', '.join(preflight.output_filenames)}")
            self.preflight_status.setText("当前可以继续，但建议先注意这些事项。")
            self.preflight_details.setText(_html_bullets(content))
        else:
            self._set_step(3)
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
        self._set_step(4)

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
        self.preview_selector.blockSignals(True)
        self.preview_selector.clear()
        for index, rendered in enumerate(self.current_rendered):
            self.preview_selector.addItem(rendered.filename, userData=index)
        self.preview_selector.setEnabled(bool(self.current_rendered))
        self.preview_selector.setCurrentIndex(0)
        self.preview_selector.blockSignals(False)
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
        self.preview_prev_button.setEnabled(index > 0)
        self.preview_next_button.setEnabled(index < len(self.current_rendered) - 1)
        self._refresh_preview_image()

    def _step_preview_index(self, step: int) -> None:
        if not self.current_rendered:
            return
        next_index = self.preview_selector.currentIndex() + step
        if 0 <= next_index < self.preview_selector.count():
            self.preview_selector.setCurrentIndex(next_index)

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
        index = self.preview_selector.currentIndex()
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
        self.preview_status_label.setText(f"预览：{rendered.filename}")

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
        self.result_summary.setText(
            f"已导出 {len(outputs)} 个 PDF。\n图类型：{TEMPLATE_LABELS.get(template, template)} / {template}\n输出目录：{output_dir.resolve()}"
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
    window = PlotWizardWindow()
    window.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
