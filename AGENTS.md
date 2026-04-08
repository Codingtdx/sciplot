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

## 绘图与工作流不变量

- 标准模板 `curve / point_line / bar / box / violin / scatter / heatmap` 共用同一物理 axis frame。
- `wide_nmr`、`heatmap` 维持既定特例对齐规则，不得破坏标准模板对齐。
- `bar` 的 y 轴从 0 起，`box/violin` 不强制从 0 起但下界需可见主刻度。
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
- 不要在 sidecar 增加“先兼容旧接口再说”的 fallback。
- 不要把 contract 常量复制到第二份文件。
- 不要绕开 schema 校验层直接读写项目 JSON。
- 不要把 Plot 子步骤或 Data Studio 子流程重新提升为 app-level 导航。
- 不要引入“保底壳层/历史别名/legacy adapter”。
- 不要在文档里保留已删除目录或接口描述，文档必须与代码同轮一致。
- 不要只改代码不记台账；`docs/engineering-handoff.md` 是持续维护的交接凭证，不可缺席。
