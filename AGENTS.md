# CodeGod 开发入口说明

这个仓库已经把绘图规范和 GUI 运行时约束收成同一套事实源。以后不管是人还是 AI 来改，先看这里，再决定动哪一层。

## 项目结构

- `src/`: 绘图内核、数据加载、布局规则、拉伸预处理、拼图后端。
- `src/rendering/`: 绘图服务层；现在按 `inspect / recommendation / preflight / render / cache / options / io` 拆开，CLI 和 sidecar 都只应该调用这一层。
- `src/plotting.py`: 仍保留核心绘图实现；如果只是复用绘图家族入口，优先从 `src/plotting_families/` 进入，不要继续把新调用点直接绑死到这个大文件。
- `src/composer.py`: Composer v2 后端真相源；维护 `layout_grid / regions / slot / z_index / crop_rect / hidden`、拼图预览和可编辑 PDF 导出。
- `make_plot.py`: CLI 兼容入口；现在只负责参数解析、错误出口和调用 `src/rendering/`，不再承载领域逻辑。
- `app/sidecar/server.py`: GUI 唯一后端真相源。`/meta`、`/plot-contract`、预览、导出、拼图、拉伸预处理都从这里走。
- `app/sidecar/schemas.py`: sidecar 请求/响应模型、项目文件 schema 校验与迁移入口；`/save-project`、`/open-project` 统一经过这里。
- `app/desktop/src/`: 4.x GUI。屏幕按 `wizard / composer / projects / settings` 分层，尽量不要再把事实源硬编码回前端。
- `scripts/smoke_check.py`: Python 回归主入口，会检查绘图、拼图、拉伸预处理，并写出 `figures/debug_outputs/smoke_report.json`。
- `pyproject.toml`: Python 工具配置入口；`pytest / ruff / mypy / coverage` 都从这里读配置。
- `.pre-commit-config.yaml`: 本地提交前的轻量门禁。
- `docs/plot_contract.md`: 从契约生成的人类可读绘图说明，不要手改。

## 唯一事实源

- `src/plot_contract.json` 是绘图契约唯一事实源。
- `src/plot_contract.py` 负责 typed loader；Python 绘图逻辑、sidecar `/meta`、`/plot-contract`、smoke 校验都要读这一份。
- GUI 只能消费 sidecar 返回的模板、尺寸、palette、默认值和标签，不要在前端再维护一套本地常量。
- 项目文件的唯一合法入口是 sidecar 的校验/迁移层：保存走 `/save-project`，打开走 `/open-project`；不要在前端或脚本里直接信任任意 JSON payload。
- 任何新增图模板、修改模板行为、增加特殊布局规则、调整模板默认值、允许尺寸、palette/style 选项、对齐规则或特例行为的改动，都视为“契约变更”。
- 契约变更必须先更新 `src/plot_contract.json`，再重生成 `docs/plot_contract.md`，最后再改 Python、sidecar、desktop 实现；禁止只改绘图代码逻辑而不更新契约与说明。

## 内部边界

- CLI、GUI、旧脚本都可以继续 import `make_plot.py`，但新增逻辑必须写进 `src/rendering/`，不要再把识别、预检或渲染逻辑回填进 CLI 壳。
- sidecar endpoint 必须声明显式响应模型；不要再返回“随手拼的 dict”。
- 绘图输入解析缓存统一放在 `src/rendering/cache.py`，键是 `(path, sheet, file_mtime_ns)`；如果改了 loader 或预检逻辑，要考虑缓存命中、失效和 clone 语义。
- 如果只是新增某个绘图家族的调用点，优先走 `src/plotting_families/`，把 `src/plotting.py` 当实现文件，不当接口文件。
- 前端打开项目时必须经过运行时校验和归一化，不要再用 `as WizardProject` / `as ComposerProject` 这类强转把不可信 payload 直接吃进去。
- Composer 项目现在只有 `version: 2` 合法；保存和打开都必须走 `layout_grid + regions + panels + texts` 结构，不再兼容旧的 `panels-only` v1。
- Composer drawable 的运行时字段除了几何和层级外，还包括 `locked / hidden / crop_rect / region_id / slot_id`；如果改了拼图项目 schema，必须同时更新 sidecar schema、前端运行时校验和本说明。

## 拼图器约束

- Composer 基础格固定为 `60 x 55 mm`，布局 frame 固定为 `180 x 165 mm`，画布仍是 `180 x 170 mm`。
- `graph` 只指 CodeGod 标准图 PDF 的 graph 导入模式；允许的 graph 物理尺寸只有 `60x55`、`120x55`、`60x110 mm`。
- graph 几何必须由 `graph region` 推导，不能在前端或 sidecar 手动把 graph 改成脱格尺寸。
- `60x110` graph region 默认自带 `structure slot`；slot 内的自由素材和文字要能跟随该 region 一起移动。
- `free region` 只表示合并后的占格区域，不直接导出；真正导出的仍是 `panel / text` 这些 drawable。
- 自由素材和文字允许覆盖 graph；要防的是 region 占格冲突，不是所有 drawable 一律禁止 overlap。
- 所有非破坏性裁边都走 drawable 上的 `crop_rect`；不要修改源 PDF 或源图片文件。
- drawable 的 `hidden` 表示“仍留在项目里，但预览和导出都忽略”；不要把隐藏当删除，也不要让导出偷偷带上隐藏对象。
- 文字对象和自由素材都允许 `locked`；锁定后不能继续拖拽，但仍应保留在图层列表、项目文件和导出里。
- Composer 导出必须保持单页 PDF，并优先保证 Illustrator 继续选中 `graph / asset / text / 结构式覆盖物` 这一层级。

## 绘图不变量

- 标准单图模板 `curve / point_line / bar / box / violin / scatter / heatmap` 必须共用同一套物理 axis frame。
- `wide_nmr` 是特例：只要求左、右、底对齐；顶部保留结构式区域；总高度保持双高。
- `heatmap` 也是特例：主热图区必须和标准单图同 frame；顶部水平 colorbar 不能挤压主图区，也不能出画布。
- 日常渲染会直接吃契约；完整“画完再审”的重校验只在 smoke / 查 bug 时跑。

## 修改流程

1. 先判断本次改动是否属于“契约变更”；新增模板、模板行为变化、特殊布局、默认参数、允许尺寸、palette/style 选项、对齐规则、特例规则都算契约变更。
2. 如果是契约变更，先改 `src/plot_contract.json`。
3. 契约变更后，立即更新文档：
   - `.venv/bin/python scripts/generate_plot_contract_docs.py`
4. 再同步改 Python、sidecar、desktop 实现，并确认 sidecar `/meta` 与 GUI 选项一致。
5. 最后跑对应回归，不要跳过 smoke、build、test、check。
6. 任何改动只要影响开发说明、运行约束、目录职责、验证命令、接口边界或项目工作流，必须在同一轮同步更新本说明；不要把文档更新留到“之后再补”。

## 验证命令

- Python 静态检查：
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`
- Python 类型检查：
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`
- Python 单测：
  - `.venv/bin/python -m pytest tests`
- Python 全量回归：
  - `.venv/bin/python scripts/smoke_check.py`
- GUI 组件测试：
  - `cd app/desktop && npm test`
- GUI 构建：
  - `cd app/desktop && npm run build`
- Tauri 编译检查：
  - `cd app/desktop/src-tauri && cargo check`

## 变更清单

新增模板或特殊规则时，必须完成：

- `src/plot_contract.json` 已更新。
- `docs/plot_contract.md` 已重生成。
- sidecar `/meta` 与 GUI 选项保持一致。
- `scripts/smoke_check.py` 至少覆盖一张真实输出。
- 如果是特殊布局，还要补对应的对齐或边界断言。

改绘图契约或布局时，至少回归：

- `ruff check`
- `pytest`
- `scripts/smoke_check.py`
- `app/desktop npm run build`
- 如果改了 `/meta` 或前端选项展示，再跑 `app/desktop npm test`

改拼图器时，至少回归：

- `pytest`
- `scripts/smoke_check.py` 中的 composer 段
- `ruff check`
- `mypy src/composer.py`
- `app/desktop npm test`
- `app/desktop npm run build`
- `app/desktop/src-tauri cargo check`

改拉伸预处理时，至少回归：

- `pytest`
- `scripts/smoke_check.py` 中的 tensile preprocess 段
- `app/desktop/src/screens/WizardScreen.test.tsx`
- 确认生成的 workbook 能被 wizard 自动载入并继续 `inspect / preflight / render`

改 GUI 选项或状态流时，至少回归：

- `app/desktop npm test`
- `app/desktop npm run build`
- 如果动到 sidecar 交互字段，再补跑 Python smoke

改 `src/rendering/`、`make_plot.py`、sidecar schema 或项目文件读写时，至少回归：

- `ruff check`
- `mypy`
- `pytest`
- `scripts/smoke_check.py`
- 如果 sidecar 返回字段或桌面端载入路径受影响，再跑 `app/desktop npm test`

## 常见坑

- sidecar 是 GUI 的唯一后端真相源。不要绕过 `/meta` 去本地拼模板列表。
- 不要复制模板、尺寸、palette 或默认参数到第二个文件里做“临时常量”。
- 不要把新模板或例外规则偷偷塞进 `plotting.py`、`make_plot.py`、`src/rendering/` 或前端选项，而不回写契约和说明。
- 只要代码改动已经让开发说明中的某一条不再准确，就必须同一轮改 `AGENTS.md`；禁止“代码先合，说明以后再补”。
- 不要在 sidecar 里直接 `return {...}` 一坨裸对象而不经过 response model。
- 不要让 `save/open project` 旁路 `app/sidecar/schemas.py` 的校验/迁移层。
- 不要在前端重新引入“第二套项目文件 schema”或靠 TS 强转跳过运行时校验。
- 不要把 graph region 的位置真相源拆成两份；region 负责占格，graph panel 的 `x/y/w/h` 只是归一化结果。
- 不要再把 Composer 改回旧的 `3x3 原点吸附 + panels-only` 心智模型；v2 的事实源是 `regions + drawables`。
- 不要让 graph 导入悄悄接受任意尺寸 PDF；不符合 `60x55 / 120x55 / 60x110 mm` 的 PDF 应提示改用 asset 模式。
- 不要在导出里把所有 PDF 先栅格化；graph 和 PDF asset 应尽量保持矢量。
- 改对齐规则时，要同时想到 `single_panel`、`wide_nmr`、`heatmap` 三类约束。
- 改 loader、inspect、preflight 或 render 时，要同时想到 `src/rendering/cache.py` 的缓存失效，不要让旧解析结果穿透到新请求。
- 改拉伸预处理时，不只是看 `.xlsx` 有没有生成，还要看 wizard 是否会自动载入 `preferred_sheet`，以及后续 render 能不能继续。
- `docs/plot_contract.md` 是生成产物；真正要改的是契约 JSON 和生成脚本依赖的数据。

## 拉伸预处理夹具

- committed raw CSV fixtures 在 `tests/fixtures/tensile_raw/`。
- 这些文件是给 smoke、后续 AI 调试和手动排查用的，不要随手删。
- 如果需要新增拉伸预处理规则，优先补 fixture 和 smoke，再改解析逻辑。
