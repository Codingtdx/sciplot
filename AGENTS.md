# SciPlot God 开发入口说明

这个仓库已经收敛为单一受支持桌面链路：`app/macos + app/sidecar + src/*`。  
以后不管是人还是 AI，先看本文件，再改代码。

## 当前产品模型

- app-level primary workbench 固定为：
  - `Plot`
  - `Data Studio`
  - `Composer`
  - `Code Console`
- `Start / Home / Project / Settings` 只能作为 utility affordance，不得恢复为一级产品区。

## 目录职责（当前真相）

- `src/rendering/`：绘图服务层（inspect/recommend/preflight/render/cache/options/io）。
- `src/plotting.py`：公开 plotting 兼容门面，内部实现不要反向依赖这里的私有 helper。
- `src/plotting_curves.py` / `src/plotting_stats.py` / `src/plotting_heatmap.py` / `src/plotting_wide_nmr.py`：图族实现。
- `src/composer.py`：Composer v2 唯一 Python 入口与真相源门面。
- `src/data_studio/`：Data Studio intake/template/workbook/compare 真相源。
- `src/code_console_service.py` + `src/code_console_runtime.py`：Code Console context/prompt/runner 真相源。
- `src/infrastructure/persistence/`：managed artifacts 的目录策略与 retention。
- `make_plot.py`：CLI 唯一入口（真实逻辑，不是转发壳）。
- `app/sidecar/server.py`：sidecar 唯一 app factory 与启动入口。
- `app/sidecar/routes_*.py` + `schemas_*.py`：sidecar route surface 与显式请求/响应模型。
- `app/macos/`：唯一受支持桌面前端（SwiftUI + sidecar runtime）。
- `data_studio_templates/`：Data Studio 模板根目录（builtin + user）。

## 已删除链路（不要恢复）

- `app/desktop/**`：已彻底删除。
- `src/entry/**`：双入口壳层已删除。
- `src/composer_ops.py` / `src/composer_render.py`：已删除，不要再引入 facade 层。
- sidecar 旧兼容接口已删除：
  - `POST /recommend-render`
  - `POST /data-studio/source-preview`
  - `/preprocess-tensile-replicates`
  - `/inspect-tensile-workbook`
  - `/export-tensile-comparison`
- inspection 旧兼容字段已删除：`inspection.recommendation`

## 唯一事实源

- 绘图契约唯一事实源：`src/plot_contract.json`
- typed loader：`src/plot_contract.py`
- sidecar `/meta`、`/plot-contract`、渲染/预检/smoke 一律消费同一份契约。
- GUI 不得维护模板、尺寸、palette/style、本地默认值的第二套常量。
- public `style_preset` 当前允许：`nature`、`editorial`、`presentation`、`poster`。
- `nature` 是冻结 public style：
  - legacy style alias 仍然一律归一化到 `nature`；
  - `nature` 的字体、字号、线宽、间距、axis frame、导出规格不可漂移。
- 非 `nature` public style 可以调整 hard metrics（例如字号、线宽、marker、padding），但仍必须通过 contract 暴露，不能在前端本地偷配第二套数值。
- 每个 public style 都必须在 contract 显式声明 `recommended_palette_preset` 和 `recommended_visual_theme_id`；当调用方显式切换 style 且未显式覆盖 palette/theme 时，sidecar 与 macOS 都必须回落到这组 style 推荐值，而不是各自猜默认值。
- `palette_preset` 与 `visual_theme_id` 是独立 public 维度：
  - palette 负责颜色；
  - theme 只允许做软视觉变化（背景、网格、legend/panel 气质），不得改字体、线宽、间距、axis frame、导出规格。
- 每个 public template 的推荐 `style_preset + palette_preset + visual_theme_id` 默认值都必须写在 contract `default_options`，并由 `/meta`、`/plot-contract`、sidecar、macOS 统一消费；这些默认值必须和该 template 默认 style 的 style-level 推荐保持一致，不要在 GUI 侧再拼一套推荐逻辑。
- `scripts/smoke_check.py` 必须维护 public surface 的固定 guardrail：
  - contract lint，检查每个 public template 显式提供 `default_options.style_preset / palette_preset / visual_theme_id`；
  - style/theme/template 固定矩阵，至少覆盖代表性 `curve / area_curve / step_line / bar / scatter / heatmap`，并同时验证 `nature` 与至少一个非 `nature` style；
  - 不要因为新增模板或 catalog 扩面而删弱这组 matrix。
- 旧 style id（`default`、`lab_default`、`science_editorial`、`jacs_analytical`、`advanced_materials_spacious`）只能在入口兼容层被接受，并且必须立刻归一化成 `nature`，不能再向外发射。
- public template surface 只能暴露显式模板；`scatter_with_fit`、`replicate_curves_with_band`、`grouped_bar_error`、`grouped_bar_compare`、`distribution_compare` 都只能作为入口兼容 id，不能再出现在 `/meta`、`/plot-contract`、recommendation、Data Studio recipe/export、macOS gallery 或持久化状态里。
- 当前 public template 扩面已包含 `area_curve`、`step_line`、`stacked_area`、`density_area`；它们必须继续走显式 contract/catalog/recommendation/render/output-naming 路径，不能退化成隐藏 alias。
- 模板的展示元数据（例如 macOS gallery thumbnail kind）必须由 contract `/meta` 提供并由前端直接消费；禁止再按 template id 字符串做本地猜测。
- `distribution_compare` 只能在兼容迁移层被解析为显式模板：优先按当前数据解析成 `violin` / `box_strip` / `box`，拿不到源数据时保守回退到 `box`。

## Sidecar 与前端边界

- Plot 检查与推荐统一走 `POST /inspect-file`。
- Plot / Data Studio 原始表格分析统一走 `POST /source-table-preview`，按分页返回列头、rows、检测到的 encoding/delimiter/segments、column profiles、候选角色和检测到的 x/y 标签；预览参数允许 `encoding/delimiter/header_row(_index)/unit_row(_index)/data_start_row(_index)/segment_id`。不要把全量 workbook 表格塞回 inspect/session payload。
- Data Studio 用户导入模板统一是 v2 no-code table mapping：`output_kind`、`source_format`、`segment_policy`、`segment_selectors`、`field_bindings`、`match_conditions` 是唯一模板结构；旧用户模板 parser 不保留，不要恢复 `POST /data-studio/source-preview` 或 `source_path + accepted_candidate_ids` 创建路径。
- Data Studio `output_kind=curve_metrics` 必须显式携带 `comparison_enabled`：默认 `false` 表示仅整理原始列为曲线（`All_Curves`）；只有 `comparison_enabled=true` 才输出 representative/metrics compare 所需 sheet。
- Data Studio `output_kind=curve_metrics` 导出的 workbook 不再写 `DataStudio_Metadata` sheet；样品名默认取源文件名（不拼 segment 文案），并允许在模板编辑页按曲线逐项确认/改名。
- Data Studio 导入/建表完成后，如果 compare context 没有任何 `supported` recipe（即“无对比可做”），必须自动走既有 `Open in Plot` 链路切到 Plot，并以 focused workbook 的 `preferred_sheet` 作为打开 sheet。
- Data Studio 未保存模板草稿必须先走 `POST /data-studio/template-preview` 做真实解析，返回 normalized output preview、missing required roles、segment 曲线/指标数量；`build-workbook` 只消费保存后的 v2 template id。
- Data Studio 模板自动采用统一走 `POST /data-studio/template-recommendations`：resolver 只可按 ranked matches 自动预选第一项；当推荐为空时必须保持未选择状态并要求用户手动选择，禁止回退到 builtin/tensile 之类的“瞎猜默认”。
- Data Studio workbook 输出允许多形态：曲线+指标、纯指标表、矩阵/heatmap；compare recipes 必须按 workbook shape 暴露可用 figure，unsupported 入口要禁用并解释。
- Plot / Data Studio 拟合分析统一走 `POST /fit-analysis`；当前支持 `linear`、`polynomial_2`、`polynomial_3`。图上的 fit overlay、方程和分析结果表必须共用同一份后端拟合 helper，禁止前端或第二条 Python 路径偷偷重算。
- Plot 高级 secondary axis 统一走 `render_options.extra_x_axis / extra_y_axis` 这条 typed payload 链路；preview、export、save/open project 必须共用同一份归一化结果，禁止前端本地维护第二套 extra-axis 状态或重算换算语义。`extra_x_axis` 只允许换算轴；`extra_y_axis` 额外支持 `binding_mode=series_assignment`，用来做 DataGraph 风格的 double-Y / series ownership。
- Plot 高级 broken axis 统一走 `render_options.x_axis_breaks / y_axis_breaks` 这条 typed payload 链路；preview、export、save/open project 必须共用同一份归一化结果，禁止前端本地维护第二套 broken-axis 状态或重算坐标语义。当前支持 `display_mode=compress|split`：`compress` 是单图内压缩式 break overlay，`split` 是 joined multi-panel 布局；只允许在线性轴上启用，当前版本不能与 enabled `extra_x_axis / extra_y_axis` 共存，并且同一时刻只允许一个轴处于 active split 布局。
- Plot 高级 guide overlay 统一走 `render_options.reference_guides` 这条 typed payload 链路；它是 DataGraph 风格的可堆叠 guide/region 命令层，preview、export、save/open project 必须共用同一份归一化结果，禁止前端本地维护第二套 reference guide 状态或重算 overlay 语义。
- Plot 高级 text annotation overlay 统一走 `render_options.text_annotations` 这条 typed payload 链路；当前支持普通 note 与带 connector 的 callout，并允许绑定 `primary y / secondary y`，preview、export、save/open project 必须共用同一份归一化结果，禁止前端本地维护第二套 annotation 状态或重算坐标语义。
- Plot 高级 shape annotation overlay 统一走 `render_options.shape_annotations` 这条 typed payload 链路；当前支持 `rectangle / ellipse / bracket`，并允许绑定 `primary y / secondary y`、复用 broken-axis panel/坐标映射，preview、export、save/open project 必须共用同一份归一化结果，禁止前端本地维护第二套 shape overlay 状态或重算几何语义。
- Code Console context 统一走 `POST /code-console/context`，返回稳定 `context_id`（输入签名 + mtime）。
- Code Console run 优先走 `POST /code-console/run` 的 `context_id` 快速路径；`context` 字段仅作兼容兜底。
- 模板选择与默认配置只消费 ranked recommendations：
  - `recommendations`
  - `primary_recommendation`
  - `alternative_recommendations`
  - `advanced_templates`
  - `recommendation_confidence`
  - `recommendation_summary`
- Data Studio specimen filter 统一复用 `POST /data-studio/workbook-preview`：
  - baseline preview 不带 `specimen_states`，只用于 Auto Keep 5 排序与 Advanced 评分表；
  - committed preview 带当前 `specimen_states`，才是 compare/export 的已应用状态来源；手动代表性曲线选择也必须走这同一条状态链，不得另开第二套状态或 endpoint。
- Data Studio workbook 一旦导入，preview / compare / export 只能消费 workbook 内部的曲线与统计数据；`source_files` 只允许做追溯 metadata，禁止静默回源修曲线或补数据。
- Data Studio comparison export 必须复用同一份 committed compare state，一次返回：
  - comparison workbook
  - 每个 included workbook group 一个 filtered standard workbook
  - selected figure outputs
- filtered workbook 必须保持标准 Data Studio sheet 结构、支持再次 import / specimen filter；曲线 sheet 当前保留到小数点后四位，specimen / summary / replicate 数值表保留到小数点后两位。不要在 comparison workbook 上偷偷做第二套数值格式规则。
- sidecar endpoint 必须返回显式 response model，禁止裸 dict。
- 项目文件保存/打开必须经过 sidecar schema 校验迁移层（`/save-project`、`/open-project`）。
- `.sciplotgod` 是 app-level 自包含单文件 bundle，当前固定结构为：
  - `project.json`
  - `sources/plot/primary/<original-filename>` 可选
  - `sources/data_studio/workbooks/<original-filename>` 一个或多个，可选
  - `artifacts/manifest.json`
- Plot 项目恢复必须以 bundle 内嵌 raw source 为真相源；不能依赖原始绝对路径仍然存在。
- Data Studio 项目恢复必须以 bundle 内嵌 workbook 为真相源；`imported_paths` 和 raw file path 只做 provenance，不能参与恢复真相源。

## 桌面运行时约束（macOS）

- 受支持宿主只有 `app/macos`。
- sidecar 策略是 app-managed ownership：
  - 不能只靠端口连通判断可用；
  - `/meta` 或 `/plot-contract` payload 不兼容时必须替换 sidecar；
  - 由 repo `.venv` 启动兼容 sidecar。
- 文件选择、保存、Finder reveal 必须通过明确 runtime 入口，失败需可见报错，禁止静默吞错。
- Plot 文件打开必须同时接受源数据文件和 `.sciplotgod`；选到项目文件时必须恢复保存时的 Plot durable state，并重新走正常 inspect/preview 链路。
- Data Studio 也必须支持打开/保存 `.sciplotgod`；打开项目时按 `selected_workbench` 回到对应工作台，而不是默认落回 Plot。
- Plot `Save Project…` / `Save Project As…` 先挂命令菜单，不新增第二套 toolbar 主入口。
- Data Studio `Save Project…` / `Save Project As…` 同样走命令菜单，不新增第二套 toolbar 主入口。
- toolbar `Help` 是唯一帮助主入口，必须打开 app-level `Quick Help`（按 workbench 提供精简动作提示）；不得恢复各 workbench 长文 `GuideSheet` 或流程说明卡片。
- `PlotSession` / `DataStudioSession` / `ComposerSession` / `CodeConsoleSession` 的异步编排必须复用共享内核（`AsyncLatestTaskCoordinator` / `KeyedAsyncLatestTaskCoordinator`），保持 revision gate + debounce + cancellation + latest-write-wins 语义一致。
- 跨 workbench 的 async 失败处理必须统一把“用户取消 / 生命周期取消”视为控制流，而不是 GUI 错误：
  - 优先复用共享 helper（当前是 `app/macos/Sources/Shared/Utilities/UserCancellation.swift` 的 `isUserCancellationError`）；
  - 不要在单个 session 里重新发明一套 cancellation 文案过滤逻辑。
- Plot / Data Studio 的 template 切换与 reset 语义必须保持：
  - 若当前 figure context 没有显式持久化的 style/theme/palette，则回落到当前 template `default_options` 推荐的 `style_preset + palette_preset + visual_theme_id`；
  - 用户显式切换 style 且未显式改 palette/theme 时，必须同步采用该 style 的 contract 推荐 palette/theme；
  - 用户显式修改 style 后再改 theme/palette，style 必须保持；
  - 用户显式修改 theme 后再改 palette，theme 必须保持；反之亦然；
  - 打开已保存 figure/project 时，持久化值优先，只有缺失或失效时才回退到 template 推荐值。
- 右侧 inspector 统一列宽策略：`inspectorColumnWidth(min: 360, ideal: 400, max: 460)`。
- macOS 导出交互统一以 Data Studio inspector 模式为准：
  - toolbar `Export` 保留为全局主入口；
  - Plot / Composer / Code Console inspector 必须提供 `Actions` 区，主按钮就是 `Export`；
  - `Advanced` 内统一放 `Reveal Output` 和 `Latest Export`，不要再散落第二套导出按钮或状态卡；
  - Plot / Composer / Code Console 的 figure export 必须先选格式（`PDF` / `300 dpi TIFF`），再选目标路径；
  - 单文件导出保留可编辑文件名；多文件导出只选一个 base filename，再追加稳定 suffix；
  - Code Console 的 toolbar/inspector `Export` 只导出 latest run 生成的 PDF figure files，不得退回成 reveal output folder。
- Data Studio import 必须维持单一分阶段 native sheet（wizard）：选择 raw files -> preview/resolve -> create/edit v2 template -> preview normalized output -> save/import；禁止恢复多个串联弹窗，也不要新增独立 Template Manager 作为 v1 入口。
- Data Studio template editor 里 `Curves` 默认是“仅曲线整理”；只有勾选 `Enable Comparison` 才允许 metric 绑定并生成 compare 结构，且勾选后至少要有一个 metric 列（禁用并解释）。
- Data Studio import resolver 的模板默认采用必须由 sidecar 推荐驱动：有推荐才自动预选首项；无推荐必须显式手动选择并给出 disabled/help 解释，不允许静默默认到 tensile。
- Data Studio specimen filter 默认交互必须是 anchored popover，且只保留右侧 `Focused Group` 单一入口；不得恢复左侧重复入口或常驻 split pane。
- Data Studio specimen filter 默认规则是 `Auto Keep 5`：按距离均值最近排序，只保留 5 个合格 specimen；少于 5 个时禁用自动筛选并解释原因。
- `Workbook Groups` 标题栏允许一个全局批量动作 `Auto Keep 5 All`；它直接对当前 session 内所有 eligible workbook group 应用 committed auto-filter 结果，不要再新增第二个批量筛选入口。
- 默认 popover 必须直接展示排序结果和 keep/out cutoff，不要再展示 representative、文件名、workbook 标签等低价值信息。
- specimen 级别的文件名、距离表、手动 inclusion override、手动 representative curve 选择都只能放在 `Advanced` 折叠区；不要把 specimen 细节塞回默认主界面。
- 关键动作必须“禁用并解释”（`disabled + help`），禁止 silent no-op。
- 共享状态文案（`InspectorEmptyState` / `EmptyStateCard` / `ErrorStateCard`）统一保持“状态 + 下一步”的短句，不回退到长段解释文案。
- 状态反馈优先“文档状态”（当前源/模板/最近输出/最近失败），而不是流程阶段术语。
- Plot/Data Studio 的关键编辑必须接入原生 `UndoManager` 撤销/重做语义。
- 共享 inspector 的 `Axis -> Advanced` 是唯一允许放置智能刻度控制（density / edge-label visibility）的入口；不要新增 Data Studio-only 的第二套坐标轴标签 UI。
- Plot `Data Workbook` 是 utility affordance，不是一级工作流阶段：
  - v1 只读，不做 inline cell editing
  - 页签固定为 `Source Data` 和 `Fit`
  - `Fit` 当前支持 `Linear`、`Polynomial 2`、`Polynomial 3`
  - Plot inspector `Advanced Plot` 里的 fit overlay 只开放给 `curve / point_line / scatter`
  - Plot inspector `Advanced Plot` 里的 `extra x axis / extra y axis` 通过 `render_options.extra_x_axis / extra_y_axis` 持久化；当前每张图最多一个额外 X 轴和一个额外 Y 轴，`extra x axis` 只支持 `data_value -> display_value` 换算，`extra y axis` 还支持 `binding_mode=series_assignment` 的 double-Y 系列归属，并和 preview/export/save-open project 保持同一路径
  - Plot inspector `Axis -> Advanced` 里的 `broken axes` 通过 `render_options.x_axis_breaks / y_axis_breaks` 持久化；当前支持 `Compressed` 单图压缩断轴和 `Split` joined multi-panel 断轴，支持多个 break 区间，但只允许在线性轴上启用，不能与 enabled `extra x axis / extra y axis` 共存，并且一次只允许一个轴启用 active split；guide / annotation 也必须复用同一份断轴 panel/坐标映射
  - Plot inspector `Advanced Plot` 里的 `reference guides` 通过 `render_options.reference_guides` 持久化；当前支持多个 `line / region`，可绑定 `x / primary y / secondary y`，并和 preview/export/save-open project 保持同一路径，但不能借此引入第二套 axis/style 常量
  - Plot inspector `Advanced Plot` 里的 `text annotations` 通过 `render_options.text_annotations` 持久化；当前支持普通 note 与 callout connector，并和 preview/export/save-open project 保持同一路径，但不能借此引入第二套坐标/样式常量
  - Plot inspector `Advanced Plot` 里的 `shape annotations` 通过 `render_options.shape_annotations` 持久化；当前支持 `rectangle / ellipse / bracket`，可绑定 `primary y / secondary y`，并复用 broken-axis panel/坐标映射与 preview/export/save-open project 同一路径，但不能借此引入第二套几何/样式常量
- Data Studio `Analysis` 也是 utility affordance，不是一级工作流阶段：
  - 作用域固定为 `Focused Workbook` 和 `Current Figure`
  - 页签固定为 `Source Data` 和 `Fit`
  - `Fit` 当前支持 `Linear`、`Polynomial 2`、`Polynomial 3`
  - `Current Figure` 拟合只开放给 `curve / point_line / scatter`
- macOS GUI smoke / fingerprint 基线必须继续覆盖 imported-state inspector：
  - Plot imported inspector
  - Plot data workbook
  - Data Studio figure inspector
  - 输出继续以 xcresult attachments 为视觉 QA artifact，不要并行维护第二套本地截图链路。

## 绘图与工作流不变量

- 标准模板 `curve / point_line / bar / box / violin / scatter / heatmap` 共用同一物理 axis frame。
- `wide_nmr`、`heatmap` 维持既定特例对齐规则，不得破坏标准模板对齐。
- 共享标签/单位规范化统一走 `src/text_normalization.py`；未知但形如单位的指数写法（例如 `kJ/m2`、`J g-1 K-1`）必须保留 mathtext 上标，前端不得自行兜底格式化。
- `bar` 的 y 轴从 0 起，`box/violin` 不强制从 0 起但下界需可见主刻度。
- categorical 统计图模板保留横轴组名文字，但默认不画 x 轴 tick marks，也不要恢复 x 轴 minor ticks。
- 标准 numeric axis 的 minor ticks 默认保持克制稀疏；不要回到当前这种密集副刻度观感。
- `curve/point_line/scatter` 的 inside legend 不能通过扩张 display bounds 规避。
- `tensile_curve` 默认推荐 `linear` x/y，且 y 轴必须包含 0（保留下方 display padding）。
- Plot canonical local workflow 固定：
  - `Import -> Inspect -> Template -> Refine -> Preflight -> Export`
- Data Studio canonical workflow 固定：
  - `Import -> Group Review -> Compare Preview -> Export / Open in Plot`
- Code Console canonical workflow 固定：
  - `Bind Context -> Inspect Inputs -> Prompt/Code -> Run -> Outputs -> Handoff`

## Composer 约束（v2）

- Composer 项目仅 `version: 2` 合法。
- schema 主体：`layout_grid + regions + panels + texts`。
- drawable 关键字段：`group_id / locked / hidden / crop_rect / region_id / slot_id`。
- 基础网格与 frame 约束保持不变（60x55 基础格，180x165 布局 frame，180x170 画布）。
- graph 允许尺寸仅 `60x55`、`120x55`、`60x110 mm`。
- hidden 对象保留在项目中但预览/导出忽略；locked 对象禁止位置编辑但保留导出。

## 代码设计原则（第一性原理）

- 先收敛“最小必要状态集合”再写代码：
  - 能从单一事实源派生出来的 UI 状态、文案、徽章、按钮禁用态，不要再落第二份状态。
- 同一语义只允许一个事实源：
  - 后端规则只在 Python/contract/schema 一处定义；
  - 前端只做消费与派生展示，不得偷偷重算业务语义。
- 抽象必须服务于“减少重复 + 澄清职责”：
  - 只有当抽象能减少真实重复、缩短调用路径、明确 ownership 时才引入；
  - 为了“将来可能通用”而预埋抽象，一律视为噪音。
- 拒绝屎山增量：
  - 每轮功能改动都要同轮删除死代码、过期 helper、重复分支、无调用旧路径；
  - 不允许把“先放着以后再收拾”作为常态。
- 优先小而清晰的类型化结构：
  - 用明确命名的 payload / presentation model / snapshot 表达语义；
  - 不要用并列 `Bool`、魔法字符串、散落 helper 拼一个隐式状态机。
- 分类优先于堆叠：
  - 当一个文件同时承载 state、async orchestration、presentation copy、view glue 时，要及时分层或提取；
  - 新逻辑默认放回所属层，不要继续把例外堆进调用方。
- 改动完成后必须做一次“瘦身审查”：
  - 问自己：有没有重复状态、重复分支、重复文案派生、无主 helper、不可命名的特殊情况；
  - 如果有，当前轮直接收掉，不把结构债滚到下一轮。

## 修改流程（第一性原则）

1. 先判断是否“契约变更”（模板/默认值/尺寸/palette/style/特殊规则/对齐规则）。
2. 若是契约变更，先改 `src/plot_contract.json`。
3. 运行：
   - `.venv/bin/python scripts/generate_plot_contract_docs.py`
4. 再改 Python/sidecar/macOS 消费层，确保 `/meta` 与 GUI 一致。
5. 代码完成后先清理：
   - `.venv/bin/python scripts/clean_repo.py`
6. 再跑回归，不得跳过 smoke/build/test/check。
   - 推荐直接跑：`.venv/bin/python scripts/blocking_gate.py`
   - 每轮还要补 1 次手工关键流（Plot 导入出图、Data Studio 导入转 Plot、Overlay 拖拽/保存重开一致）
7. 任何影响职责、边界、流程、验证矩阵的改动，必须同轮更新 `AGENTS.md` 与 `README.md`。

## 交接硬要求（每轮必做）

1. 每轮改动完成后，必须同步更新交接台账：
   - `docs/engineering-handoff.md`
2. 台账至少要写清：
   - 日期（绝对日期）
   - 变更范围（模块/接口/数据结构）
   - 用户可见影响（如果无则写“无”）
   - 风险与回滚点
   - 实际回归结果（命令 + 通过/失败）
3. 如果改动涉及架构或运行时策略（例如 sidecar 生命周期、缓存策略、并发语义、默认流程），必须在台账新增一条“决策记录（Decision Record）”，写明：
   - 为什么改（first-principles 动机）
   - 备选方案为何弃用
   - 当前方案边界与失效条件
4. 出现一次“排查超过 15 分钟”的问题，必须把结论沉淀到台账的故障手册区，避免重复踩坑。
5. 若本轮包含性能优化，必须补“性能体感目标 + 保护性测试”，并记录本轮验证结论。

## 交接验收标准

- 新接手开发者在不口头补充背景的情况下，能在 30 分钟内完成：
  - 跑通本地 build/test/smoke
  - 明确唯一受支持入口与工作流
  - 明确可改边界与禁止恢复的 legacy 链路
  - 找到最近两轮改动的风险点和回滚点
- 以上任一项做不到，视为文档未达标，当前轮不可算完成交接。

## 验证命令

- `.venv/bin/python scripts/blocking_gate.py`
- `.venv/bin/python scripts/blocking_gate.py --require-manual --manual-check plot_import_preview_export --manual-check data_studio_import_open_plot --manual-check overlay_drag_save_reopen`
- `.venv/bin/python scripts/clean_repo.py`
- `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`
- `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`
- `.venv/bin/python -m pytest tests`
- `.venv/bin/python scripts/smoke_check.py`
- `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`
- `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`

## 常见坑

- 不要在前端重建评分/推荐逻辑；只消费 sidecar ranked recommendations。
- 不要新增 Data Studio specimen filter 专用 endpoint，也不要在前端按已过滤子集重算 auto recommendation。
- 不要恢复 Data Studio specimen filter 的双入口交互，也不要把默认态重新做回 `Status / Rule / Effect` 卡片堆叠。
- 不要在 sidecar 增加“先兼容旧接口再说”的 fallback。
- 不要把 contract 常量复制到第二份文件。
- 不要绕开 schema 校验层直接读写项目 JSON。
- 不要把 `.sciplotgod` 实现成只记绝对路径的轻量链接文件；它必须嵌入 Plot 当前绑定的原始源文件字节。
- 不要把 legacy style/template alias 当成新的 public product 语义重新暴露出来。
- 不要把 Data Studio import 重新拆回多 sheet 串联弹窗。
- 不要做“按钮可点但 guard-return 无反馈”的 silent no-op 交互。
- 不要把 Plot 子步骤或 Data Studio 子流程重新提升为 app-level 导航。
- 不要引入“保底壳层/历史别名/legacy adapter”。
- 不要在文档里保留已删除目录或接口描述，文档必须与代码同轮一致。
- 不要只改代码不记台账；`docs/engineering-handoff.md` 是持续维护的交接凭证，不可缺席。
