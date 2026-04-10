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
  - `/preprocess-tensile-replicates`
  - `/inspect-tensile-workbook`
  - `/export-tensile-comparison`
- inspection 旧兼容字段已删除：`inspection.recommendation`

## 唯一事实源

- 绘图契约唯一事实源：`src/plot_contract.json`
- typed loader：`src/plot_contract.py`
- sidecar `/meta`、`/plot-contract`、渲染/预检/smoke 一律消费同一份契约。
- GUI 不得维护模板、尺寸、palette/style、本地默认值的第二套常量。
- public `style_preset` 目前只允许一个值：`nature`。
- 旧 style id（`default`、`lab_default`、`science_editorial`、`jacs_analytical`、`advanced_materials_spacious`）只能在入口兼容层被接受，并且必须立刻归一化成 `nature`，不能再向外发射。
- public template surface 只能暴露显式模板；`scatter_with_fit`、`replicate_curves_with_band`、`grouped_bar_compare`、`distribution_compare` 都只能作为入口兼容 id，不能再出现在 `/meta`、`/plot-contract`、recommendation、Data Studio recipe/export、macOS gallery 或持久化状态里。
- `distribution_compare` 只能在兼容迁移层被解析为显式模板：优先按当前数据解析成 `violin` / `box_strip` / `box`，拿不到源数据时保守回退到 `box`。

## Sidecar 与前端边界

- Plot 检查与推荐统一走 `POST /inspect-file`。
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
- Data Studio comparison export 必须复用同一份 committed compare state，一次返回：
  - comparison workbook
  - 每个 included workbook group 一个 filtered standard workbook
  - selected figure outputs
- filtered workbook 必须保持标准 Data Studio sheet 结构、支持再次 import / specimen filter，并且数值导出当前统一保留到小数点后两位；不要在 comparison workbook 上偷偷做第二套数值格式规则。
- sidecar endpoint 必须返回显式 response model，禁止裸 dict。
- 项目文件保存/打开必须经过 sidecar schema 校验迁移层（`/save-project`、`/open-project`）。

## 桌面运行时约束（macOS）

- 受支持宿主只有 `app/macos`。
- sidecar 策略是 app-managed ownership：
  - 不能只靠端口连通判断可用；
  - `/meta` 或 `/plot-contract` payload 不兼容时必须替换 sidecar；
  - 由 repo `.venv` 启动兼容 sidecar。
- 文件选择、保存、Finder reveal 必须通过明确 runtime 入口，失败需可见报错，禁止静默吞错。
- `PlotSession` / `DataStudioSession` / `ComposerSession` / `CodeConsoleSession` 的异步编排必须复用共享内核（`AsyncLatestTaskCoordinator` / `KeyedAsyncLatestTaskCoordinator`），保持 revision gate + debounce + cancellation + latest-write-wins 语义一致。
- 右侧 inspector 统一列宽策略：`inspectorColumnWidth(min: 360, ideal: 400, max: 460)`。
- Data Studio import 必须维持单一分阶段 native sheet（wizard），禁止恢复多个串联弹窗。
- Data Studio specimen filter 默认交互必须是 anchored popover，且只保留右侧 `Focused Group` 单一入口；不得恢复左侧重复入口或常驻 split pane。
- Data Studio specimen filter 默认规则是 `Auto Keep 5`：按距离均值最近排序，只保留 5 个合格 specimen；少于 5 个时禁用自动筛选并解释原因。
- `Workbook Groups` 标题栏允许一个全局批量动作 `Auto Keep 5 All`；它直接对当前 session 内所有 eligible workbook group 应用 committed auto-filter 结果，不要再新增第二个批量筛选入口。
- 默认 popover 必须直接展示排序结果和 keep/out cutoff，不要再展示 representative、文件名、workbook 标签等低价值信息。
- specimen 级别的文件名、距离表、手动 inclusion override、手动 representative curve 选择都只能放在 `Advanced` 折叠区；不要把 specimen 细节塞回默认主界面。
- 关键动作必须“禁用并解释”（`disabled + help`），禁止 silent no-op。
- 状态反馈优先“文档状态”（当前源/模板/最近输出/最近失败），而不是流程阶段术语。
- Plot/Data Studio 的关键编辑必须接入原生 `UndoManager` 撤销/重做语义。
- 共享 inspector 的 `Axis -> Advanced` 是唯一允许放置智能刻度控制（density / edge-label visibility）的入口；不要新增 Data Studio-only 的第二套坐标轴标签 UI。

## 绘图与工作流不变量

- 标准模板 `curve / point_line / bar / box / violin / scatter / heatmap` 共用同一物理 axis frame。
- `wide_nmr`、`heatmap` 维持既定特例对齐规则，不得破坏标准模板对齐。
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
- 不要把 legacy style/template alias 当成新的 public product 语义重新暴露出来。
- 不要把 Data Studio import 重新拆回多 sheet 串联弹窗。
- 不要做“按钮可点但 guard-return 无反馈”的 silent no-op 交互。
- 不要把 Plot 子步骤或 Data Studio 子流程重新提升为 app-level 导航。
- 不要引入“保底壳层/历史别名/legacy adapter”。
- 不要在文档里保留已删除目录或接口描述，文档必须与代码同轮一致。
- 不要只改代码不记台账；`docs/engineering-handoff.md` 是持续维护的交接凭证，不可缺席。
