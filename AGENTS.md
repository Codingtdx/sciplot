# CodeGod 开发入口说明

这个仓库已经把绘图规范和 GUI 运行时约束收成同一套事实源。以后不管是人还是 AI 来改，先看这里，再决定动哪一层。

## 项目结构

- `src/`: 绘图内核、数据加载、布局规则、拉伸预处理、拼图后端。
- `make_plot.py`: CLI 入口，同时承载识别、推荐、预检、渲染主流程。
- `app/sidecar/server.py`: GUI 唯一后端真相源。`/meta`、`/plot-contract`、预览、导出、拼图、拉伸预处理都从这里走。
- `app/desktop/src/`: 4.x GUI。屏幕按 `wizard / composer / projects / settings` 分层，尽量不要再把事实源硬编码回前端。
- `scripts/smoke_check.py`: Python 回归主入口，会检查绘图、拼图、拉伸预处理，并写出 `figures/debug_outputs/smoke_report.json`。
- `docs/plot_contract.md`: 从契约生成的人类可读绘图说明，不要手改。

## 唯一事实源

- `src/plot_contract.json` 是绘图契约唯一事实源。
- `src/plot_contract.py` 负责 typed loader；Python 绘图逻辑、sidecar `/meta`、`/plot-contract`、smoke 校验都要读这一份。
- GUI 只能消费 sidecar 返回的模板、尺寸、palette、默认值和标签，不要在前端再维护一套本地常量。
- 任何新增图模板、修改模板行为、增加特殊布局规则、调整模板默认值、允许尺寸、palette/style 选项、对齐规则或特例行为的改动，都视为“契约变更”。
- 契约变更必须先更新 `src/plot_contract.json`，再重生成 `docs/plot_contract.md`，最后再改 Python、sidecar、desktop 实现；禁止只改绘图代码逻辑而不更新契约与说明。

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

## 验证命令

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

- `scripts/smoke_check.py`
- `app/desktop npm run build`
- 如果改了 `/meta` 或前端选项展示，再跑 `app/desktop npm test`

改拼图器时，至少回归：

- `scripts/smoke_check.py` 中的 composer 段
- `app/desktop npm test`
- `app/desktop/src-tauri cargo check`

改拉伸预处理时，至少回归：

- `scripts/smoke_check.py` 中的 tensile preprocess 段
- `app/desktop/src/screens/WizardScreen.test.tsx`
- 确认生成的 workbook 能被 wizard 自动载入并继续 `inspect / preflight / render`

改 GUI 选项或状态流时，至少回归：

- `app/desktop npm test`
- `app/desktop npm run build`
- 如果动到 sidecar 交互字段，再补跑 Python smoke

## 常见坑

- sidecar 是 GUI 的唯一后端真相源。不要绕过 `/meta` 去本地拼模板列表。
- 不要复制模板、尺寸、palette 或默认参数到第二个文件里做“临时常量”。
- 不要把新模板或例外规则偷偷塞进 `plotting.py`、`make_plot.py` 或前端选项，而不回写契约和说明。
- 改对齐规则时，要同时想到 `single_panel`、`wide_nmr`、`heatmap` 三类约束。
- 改拉伸预处理时，不只是看 `.xlsx` 有没有生成，还要看 wizard 是否会自动载入 `preferred_sheet`，以及后续 render 能不能继续。
- `docs/plot_contract.md` 是生成产物；真正要改的是契约 JSON 和生成脚本依赖的数据。

## 拉伸预处理夹具

- committed raw CSV fixtures 在 `tests/fixtures/tensile_raw/`。
- 这些文件是给 smoke、后续 AI 调试和手动排查用的，不要随手删。
- 如果需要新增拉伸预处理规则，优先补 fixture 和 smoke，再改解析逻辑。
