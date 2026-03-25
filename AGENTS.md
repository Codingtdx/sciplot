# SciPlot God 开发入口说明

这个仓库已经把绘图规范和 GUI 运行时约束收成同一套事实源。以后不管是人还是 AI 来改，先看这里，再决定动哪一层。

## 项目结构

- `src/`: 绘图内核、数据加载、布局规则、拉伸预处理、拼图后端。
- `src/rendering/`: 绘图服务层；现在按 `inspect / recommendation / preflight / render / cache / options / io` 拆开，CLI 和 sidecar 都只应该调用这一层。
- `src/plotting.py`: 仍保留核心绘图实现与公开绘图门面；如果只是复用绘图家族入口，优先从 `src/plotting_families/` 进入，不要继续把新调用点直接绑死到这个大文件。
- `src/plotting_curves.py`: 曲线图族主流程实现，承接 `plot_curves / plot_scatter / curve template / legend` 等编排逻辑；外部兼容调用仍通过 `src/plotting.py` 暴露。
- `src/plotting_stats.py`: 统计图族实现，承接 `box / bar / violin` 及其共享坐标规则；外部兼容调用仍通过 `src/plotting.py` 暴露。
- `src/plotting_heatmap.py`: 热图实现，承接 heatmap 主图区与 colorbar 布局；外部兼容调用仍通过 `src/plotting.py` 暴露。
- `src/composer.py`: Composer v2 后端公开入口与真相源门面；外部调用继续统一从这里 import。类型与常量在 `src/composer_types.py`，布局/导入/校验在 `src/composer_ops.py`，预览/导出在 `src/composer_render.py`。
- `make_plot.py`: CLI 兼容入口；现在只负责参数解析、错误出口和调用 `src/rendering/`，不再承载领域逻辑。
- `app/sidecar/server.py`: GUI 唯一后端真相源。`/meta`、`/plot-contract`、预览、导出、拼图、拉伸预处理都从这里走。
- `app/sidecar/schemas.py`: sidecar 请求/响应模型、项目文件 schema 校验与迁移入口；`/save-project`、`/open-project` 统一经过这里。
- `app/desktop/src/`: 4.x GUI，仅支持 Tauri 桌面宿主。屏幕按 `launchpad / tensile / wizard / composer / code-console / settings` 分层，尽量不要再把事实源硬编码回前端。
- `app/desktop/src/screens/composer/`: Composer 屏专属 hooks、面板组件和选择态/快捷键等 UI 行为模块；优先在这里继续拆分，不要再把导入、inspect、layers、快捷键逻辑重新堆回单个 `ComposerScreen.tsx`。
- `app/desktop/src/screens/wizard/`: Wizard 屏专属 hooks、section 组件和流程辅助函数；保持 `WizardScreen.tsx` 只做状态编排，不要再把 detect/templates/options/preflight 整段 UI 塞回主屏文件。
- `app/desktop/src/styles/`: 桌面端按功能拆分的样式分片；`shell / components / responsive` 承接共享外壳、通用控件和断点规则，`wizard / composer` 这类页面专属规则优先放到对应 CSS 分片中。
- `app/desktop/scripts/tauri-smoke.mjs`: 更接近真实桌面宿主的 Tauri 启动 smoke；会复用或拉起本地 Vite、真实 sidecar，并确认原生 `sciplot-god-desktop` 进程已起来。
- `Launch_Plotter.command`: 桌面端唯一启动器；只负责拉起当前 Tauri 开发宿主，失败时直接报错，不再提供任何 PySide / 终端 fallback。
- `scripts/smoke_check.py`: Python 回归主入口，会检查绘图、拼图、拉伸预处理，并写出 `figures/debug_outputs/smoke_report.json`；如果需要保留本轮 smoke 的输入/输出产物供人工审图，可设置 `CODEGOD_SMOKE_CAPTURE_DIR=/绝对路径`。
- `scripts/debug_refresh.py`: 人工审图刷新脚本；始终重刷 review fixtures，真实数据输入统一走 `CODEGOD_DEBUG_REFRESH_TENSILE_RAW_DATA`、`CODEGOD_DEBUG_REFRESH_FREQ_SWEEP`、`CODEGOD_DEBUG_REFRESH_TEMP_SWEEP`、`CODEGOD_DEBUG_REFRESH_STRESS_RELAXATION`。
- `scripts/clean_repo.py`: 仓库级清理入口；默认清掉缓存、`.DS_Store`、临时目录、桌面构建产物和 `.venv-*` 这类备份环境，只有显式传 `--include-node-modules` 才会进一步删掉桌面端依赖目录。
- `pyproject.toml`: Python 工具配置入口；`pytest / ruff / mypy / coverage` 都从这里读配置。
- `requirements.txt` + `requirements-constraints.txt`: Python 顶层依赖与版本约束；统一用 `pip install -r requirements.txt` 安装，约束文件会自动生效。
- `.python-version` / `.nvmrc`: 开发态固定语言版本；当前分别锁定 `Python 3.14.3` 与 `Node 20`。
- `.ignore` / `.vscode/settings.json`: 搜索与 TODO 视图噪音排除入口；lockfile、缓存和构建产物默认不应再参与待办扫描。
- `.pre-commit-config.yaml`: 本地提交前的轻量门禁。
- `docs/plot_contract.md`: 从契约生成的人类可读绘图说明，不要手改。

## 唯一事实源

- `src/plot_contract.json` 是绘图契约唯一事实源。
- 契约里的 `qa_profiles` 不是给终端用户看的评分表，而是内部 editorial policy / autofix 的唯一策略源；small panel legend、heatmap top strip、stat spacing、Composer cleanup patch 都应从这里读门槛。
- `src/plot_contract.py` 负责 typed loader；Python 绘图逻辑、sidecar `/meta`、`/plot-contract`、smoke 校验都要读这一份。
- GUI 只能消费 sidecar 返回的模板、尺寸、palette、默认值和标签，不要在前端再维护一套本地常量。
- 单图渲染选项里的 `style_preset` 现在和 `palette_preset` 一样属于契约字段；可选投稿风格只认契约里的 `available_styles`，不要再引入第二套 `journal_target` 或前端私有风格枚举。
- 项目文件的唯一合法入口是 sidecar 的校验/迁移层：保存走 `/save-project`，打开走 `/open-project`；不要在前端或脚本里直接信任任意 JSON payload。
- 任何新增图模板、修改模板行为、增加特殊布局规则、调整模板默认值、允许尺寸、palette/style 选项、对齐规则或特例行为的改动，都视为“契约变更”。
- 契约变更必须先更新 `src/plot_contract.json`，再重生成 `docs/plot_contract.md`，最后再改 Python、sidecar、desktop 实现；禁止只改绘图代码逻辑而不更新契约与说明。

## 内部边界

- CLI、GUI、脚本都可以继续 import `make_plot.py`，但新增逻辑必须写进 `src/rendering/`，不要再把识别、预检或渲染逻辑回填进 CLI 壳。
- sidecar endpoint 必须声明显式响应模型；不要再返回“随手拼的 dict”。
- `preflight-render`、`render-preview`、`export-render`、`compose-preview` 现在都会返回统一的 `submission_report`；它是投稿检查摘要，不是新的 blocker 通道。真正阻止导出的一律仍走 preflight / Composer overlap 校验。
- `inspect-file` / `recommend-render` 的 `inspection` 现在在保持旧 `recommendation` 兼容字段的同时，还会返回 richer ranked `recommendations`（含 `rank / score / reason / suitability_hint / score_gap_to_top`）以及顶层 `recommendation_confidence / recommendation_summary`；`wizard` 的 `/plot/type` 只消费这些后端字段做排序与提示，不要在前端再造一套评分逻辑。
- `export-render` 除了 PDF，还会在输出目录旁写出 preview PNG、normalized options、inspection、preflight、submission report、manifest 这些 bundle 产物；如果 GUI 没传显式 `output_dir`，sidecar 默认写到 app-managed `plot_exports` 目录，只有用户明确选目录时才落到用户指定路径。改导出链路时别漏掉这些伴随文件，也别让桌面端的“打开输出目录”按钮失效。
- 绘图输入解析缓存统一放在 `src/rendering/cache.py`，键是 `(path, sheet, file_mtime_ns)`；如果改了 loader 或预检逻辑，要考虑缓存命中、失效和 clone 语义。
- 如果只是新增某个绘图家族的调用点，优先走 `src/plotting_families/`，把 `src/plotting.py` 当实现文件，不当接口文件。
- 前端打开项目时必须经过运行时校验和归一化，不要再用 `as WizardProject` / `as ComposerProject` 这类强转把不可信 payload 直接吃进去。
- Wizard 项目文件和运行时 store 里的渲染选项现在都要保留 `style_preset`；如果改 render options schema，必须同时更新 sidecar schema、桌面运行时 parser、持久化读写和本说明。
- 桌面端现在只支持 Tauri 宿主；文件对话框、拖放事件等桌面运行时访问统一走 `app/desktop/src/lib/tauri-dialog.ts`、`app/desktop/src/lib/tauri-webview.ts` 这类入口，不要在页面里散落调用。
- `Launch_Plotter.command` 只代表当前 Tauri 主链路，也是唯一受支持的桌面入口；不要再引入 `plot_wizard_gui.py`、`interactive_plot.py` 一类旧 fallback。
- 文件对话框依赖 `app/desktop/src-tauri/capabilities/` 里的 capability 配置；如果 dialog 打不开，必须把错误明确显示到界面上，不能静默失败。
- 桌面端现在默认先进入 `Launchpad`，再进入 `plot / tensile / composer / code-console / settings` 这些专属 workspace；不要再把全局信息架构改回“常驻后台侧栏 + 一个大工作区”。
- 桌面端 workspace 默认只保留一个纵向滚动根：`app-main`。除非是明确设计的局部画布/代码横向预览，不要再给页面内部叠第二层默认纵向滚动容器。
- `PreviewPane` 的普通滚轮应继续服务页面滚动；只有 `Ctrl/Cmd + wheel` 才用于缩放，双击回到 reset/fit。不要再让预览面板吞掉默认页面滚动。
- 单图 `wizard` 流程默认是 staged workspace：`import -> sheet(按需) -> type -> tune -> review -> export`；不要把“保存/打开项目文件”重新堆成单图主入口，需要显式项目文件的主要仍是 `composer`。
- `wizard` 的 `inspect` 仍在导入和切 sheet 后立即执行；`render-preview` 只在 `type / tune / review / export` 阶段活跃，`preflight` 只在 `review` 阶段活跃；不要再改回“单屏自动把所有检查全跑完”的心智模型。
- `wizard` 的模板区默认只显示当前输入模型兼容的模板，其他模板只能放在“更多图型”里并以 disabled 方式展示；不要再让用户点进一个必报错的模板路径。
- 拉伸整理和拉伸对比现在收敛到独立 `tensile` 工作台；`wizard` 只保留通用单图绘图流，不再承载 tensile preprocess / compare UI。
- `tensile` 工作台支持整理 raw tensile CSV、补录任意组数的已整理 workbook，并一键导出代表曲线 + Strength/Modulus/Elongation 的箱线图与柱状图；compare 清单只保存在 tensile 运行时 store，不写进项目文件 schema。
- tensile preprocess 成功后默认停留在 `tensile` 页面，不再自动抢占 `wizard`；只有显式点击“在绘图中打开”时，才会把整理结果送进 `wizard` 继续 inspect / preflight / render。
- 最近记录现在由 `Launchpad` 直接承接，不再保留独立 `projects/recents` workspace；如果只是做一张图，优先记住最近数据文件，不要强迫用户先保存 wizard 项目。
- `wizard` 导入阶段现在可以一键触发 sidecar materialize `example template folder / blank template folder`；这些 workbook 要写到 app-managed stable 目录并按需覆盖刷新，不能再每次动作都散落新的 temp folder。这些模板和 folder 只是输入模板、格式引导与桥接层，不是新的绘图事实源，也不能替代契约、`/meta`、inspect/recommendation 或现有导入责任链。
- `code-console` 工作台现在收敛为“数据绑定/inspect + chart type 选择 + prompt 复制器 + repo-native Python runner”：前端负责绑定当前 plot session 或直接加载数据文件、继承当前 plot 或 inspect 得出的 size/style/palette 上下文、按需展示 prompt、承接粘贴代码与运行结果，sidecar 负责生成最终 prompt、轻量上下文和受控 runner。
- `code-console` 的 prompt、runner、AI bundle 和 data template 都不是新的绘图事实源；不要把 contract 常量、视觉默认值、尺寸规则或 plotting rule 复制进前端，也不要绕过 sidecar 在 GUI 本地重新拼最终 prompt、runner 上下文或模板结构。
- `code-console` 的主流程是 `Load data or reuse Plot data -> inspect -> choose chart type -> Copy prompt -> Ask external AI -> Paste code -> Run`；默认不要把长 prompt body 常驻铺满页面，也不要把 Console 做成第二套重配置表单。
- `code-console` runner 只运行 repo-native Python，不是系统 shell：工作目录是 repo root，但预览和导出产物只认受控 `OUTPUT_DIR`，并且要有 timeout、stdout/stderr、exit code、duration、generated files 这些返回字段。runner 的 managed run/output 目录要走 app-managed cache/data 路径并做 retention/cleanup，不能无上限堆积。
- `settings` 现在应提供轻量的 app-managed 文件入口和清理入口，用于 reveal/refresh/prune template folders、managed plot exports 和 code-console runs；这类清理只作用于 app-generated artifacts，不能干扰用户显式选择的导出目录。
- `scripts/debug_refresh.py` 的真实数据路径只允许从 `CODEGOD_DEBUG_REFRESH_*` 环境变量注入；不要再把个人机器绝对路径直接提交进仓库。
- Python / Node 开发环境以 `.python-version`、`.nvmrc` 和 `requirements.txt` + `requirements-constraints.txt` 为准；不要再依赖“本机刚好装得上”的浮动版本。
- 当 `wizard` 或 `composer` 已有当前会话内容时，打开另一份数据文件/项目文件前应先明确提醒“将替换当前会话”；不要静默把当前工作区直接重置掉。
- Composer 项目现在只有 `version: 2` 合法；保存和打开都必须走 `layout_grid + regions + panels + texts` 结构，不再兼容旧的 `panels-only` v1。
- Composer drawable 的运行时字段除了几何和层级外，还包括 `group_id / locked / hidden / crop_rect / region_id / slot_id`；如果改了拼图项目 schema，必须同时更新 sidecar schema、前端运行时校验和本说明。

## 拼图器约束

- Composer 基础格固定为 `60 x 55 mm`，布局 frame 固定为 `180 x 165 mm`，画布仍是 `180 x 170 mm`。
- `graph` 只指 SciPlot God 标准图 PDF 的 graph 导入模式；允许的 graph 物理尺寸只有 `60x55`、`120x55`、`60x110 mm`。
- graph 几何必须由 `graph region` 推导，不能在前端或 sidecar 手动把 graph 改成脱格尺寸。
- `60x110` graph region 默认自带 `structure slot`；slot 内的自由素材和文字要能跟随该 region 一起移动。
- `free region` 只表示合并后的占格区域，不直接导出；真正导出的仍是 `panel / text` 这些 drawable。
- 自由素材和文字允许覆盖 graph；要防的是 region 占格冲突，不是所有 drawable 一律禁止 overlap。
- 所有非破坏性裁边都走 drawable 上的 `crop_rect`；不要修改源 PDF 或源图片文件。
- drawable 的 `hidden` 表示“仍留在项目里，但预览、导出、画布框选和智能吸附都忽略”；不要把隐藏当删除，也不要让导出偷偷带上隐藏对象。
- 文字对象和自由素材都允许 `locked`；graph 还要同时尊重 region 锁。锁定后不能继续拖拽，也不能再被方向键、贴边/居中、适配绑定区这类位置编辑改动，但仍应保留在图层列表、项目文件和导出里。
- `group_id` 只用于自由 drawable 的成组选择、整组拖拽、复制/粘贴和重复；不要把 graph region 的占格语义混进 group 里。
- Composer 导出必须保持单页 PDF，并优先保证 Illustrator 继续选中 `graph / asset / text / 结构式覆盖物` 这一层级。
- 导出 PDF 里的每个可见 graph / asset / text 都应挂到稳定命名的 OCG 图层；改导出时别把这层命名语义丢掉，也别把 hidden 对象导成可见图层。

## 绘图不变量

- 标准单图模板 `curve / point_line / bar / box / violin / scatter / heatmap` 必须共用同一套物理 axis frame。
- editorial autofix 只能优化 axis frame 内部纪律，不能改 shared axis frame 的物理锚点；`60x55` 小图彼此左右上下坐标轴必须对齐，两张 `60x55` 并排后的最左/最右边界也必须与 `120x55` 中图对齐。
- 标准单轴图 `curve / point_line / scatter / bar / box / violin` 现在统一采用两层坐标边界：
  - `labeled bounds` 负责显示整洁端点数字
  - `display bounds` 负责实际绘图区留白
- 标准线性轴默认使用 `1/2/5 * 10^n` 的 nice 包络，再做 `5%` 对称无标签 outer padding；x/y 两轴都要按同一套规则处理。
- `bar` 是例外：`y` 轴必须从 `0` 起画，底部不留 display padding；`box / violin` 不强制从 `0` 起，但自动下界必须显示成可见主刻度。
- `wide_nmr` 是特例：只要求左、右、底对齐；顶部保留结构式区域；总高度保持双高。
- `heatmap` 也是特例：主热图区必须和标准单图同 frame；顶部水平 colorbar 不能挤压主图区，也不能出画布。
- 输入识别先看表结构，再看轴标签/单位，最后才看数值跨度：
  - 先分清 `curve_table / replicate_table / heatmap xyz_long_table / rheology bundle`。
  - 曲线类再根据 `Chemical shift / ppm / Wavenumber / 2theta / Heat flow / Time / σ/σ₀` 这些标签和单位判断推荐图型。
  - `xscale / yscale` 默认值要参考正值数据跨越的数量级；横纵轴变化幅度不够时保留 `linear`，跨越多个数量级时再改成 `log`。
- stress relaxation 这类 4 列一组导出表不是普通 `curve_table`；`point_line` 和 `curve` 都应走专用 rheology loader 读取 `σ/σ₀`，不要再让 `curve` 误走成对列解析。
- `frequency_sweep / temperature_sweep / stress_relaxation` 这三类 rheology bundle 上，`curve` 和 `point_line` 必须共享同一套 bundle loader 和指标拆分，只允许在“是否显示 markers”上分叉：
  - `frequency_sweep curve` 导出 `freq_*_curve.pdf`
  - `temperature_sweep curve` 导出 `temp_*_curve.pdf`
  - `stress_relaxation curve` 导出 `stress_relaxation_sigma_over_sigma0_curve.pdf`
- `wizard` 前端当前使用的兼容模板映射是：
  - `frequency_sweep / temperature_sweep / stress_relaxation -> point_line, curve`
  - `tensile_curve -> curve, point_line, stacked_curve, segmented_stacked_curve, scatter`
  - `curve_table -> curve, point_line, stacked_curve, segmented_stacked_curve, scatter`
  - `replicate_table -> bar, box, violin`
  - `heatmap_table -> heatmap`
- 所有识别为 `tensile_curve` 的曲线都必须固定使用 `linear` x/y 坐标；不允许在推荐、预检或渲染阶段退回 `log`。
- `tensile_curve` 的 `y` 轴必须始终包含并显示 `0`，但 display bounds 仍要在 `0` 下方留出无标签留白；不要再把 tensile 曲线直接贴在横轴上。
- 标准 `log` 轴允许 display bounds 超过最后一个标签，但标签只显示 decade 主刻度；不要把 `2×10^n`、`5×10^n` 直接当成主标签端点。
- 日常渲染会直接吃契约；完整“画完再审”的重校验只在 smoke / 查 bug 时跑。
- 日常 UI 不展示面向用户的 QA scorecard；QA 主要用于 render-time 候选布局选择、静默 autofix、smoke 报告和可选调试输出。

## 修改流程

1. 先判断本次改动是否属于“契约变更”；新增模板、模板行为变化、特殊布局、默认参数、允许尺寸、palette/style 选项、对齐规则、特例规则都算契约变更。
2. 如果是契约变更，先改 `src/plot_contract.json`。
3. 契约变更后，立即更新文档：
   - `.venv/bin/python scripts/generate_plot_contract_docs.py`
4. 再同步改 Python、sidecar、desktop 实现，并确认 sidecar `/meta` 与 GUI 选项一致。
5. 代码改动完成后，先运行 `.venv/bin/python scripts/clean_repo.py` 清理缓存、`.DS_Store`、临时目录、桌面构建产物和 `.venv-*` 备份环境；只有明确接受重装成本时，才额外显式传 `--include-node-modules`。
6. 再跑对应回归，不要跳过 smoke、build、test、check。
7. 任何改动只要影响开发说明、运行约束、目录职责、验证命令、接口边界或项目工作流，必须在同一轮同步更新本说明；不要把文档更新留到“之后再补”。

## 验证命令

- 开发缓存清理：
  - `.venv/bin/python scripts/clean_repo.py`
- 开发缓存清理预演：
  - `.venv/bin/python scripts/clean_repo.py --dry-run`
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
- GUI Tauri 启动 smoke：
  - `cd app/desktop && npm run test:e2e:tauri-smoke`
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
- 如果改了 Tauri 启动链路、窗口配置、wrapper 与真实宿主交互或桌面打包入口，再跑 `app/desktop npm run test:e2e:tauri-smoke`
- `app/desktop npm run build`
- `app/desktop/src-tauri cargo check`

改拉伸预处理时，至少回归：

- `pytest`
- `scripts/smoke_check.py` 中的 tensile preprocess 段
- `app/desktop/src/screens/TensileScreen.test.tsx`
- `app/desktop/src/screens/WizardScreen.test.tsx`
- 确认生成的 workbook 能在 tensile 工作台显示整理结果，并且点击“在绘图中打开”后可继续 `inspect / preflight / render`

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
- 不要再按“浏览器宿主也要能跑”的约束设计桌面前端；当前 GUI 的唯一目标宿主是 Tauri。
- 不要让文件对话框、拖放等桌面能力失败后直接吞掉异常；必须在界面上给出明确错误。
- 不要重新引入 `Launch_Plotter_Legacy.command`、`plot_wizard_gui.py`、`interactive_plot.py` 这类旧入口；当前桌面主链路只保留 Tauri。
- 不要把 wizard 再改回“先保存项目再继续”或“所有内容都堆在一屏里”的心智模型；单图流程默认应该保持 `Launchpad -> staged plot workspace`。
- 不要把 tensile compare 清单做成“必须先保存项目才能继续”的流；它应该是 `tensile` 工作台内的运行时工作流增强，并且补录已有 workbook 时不能抢走当前 `wizard` 主输入。
- 不要把不兼容模板重新放回 wizard 默认主列表，更不要让 disabled 模板还能被点击。
- 不要让 rheology bundle 的 `curve` 再退回普通 `curve_table` 解析；温度扫描、频率扫描、应力松弛都必须和 `point_line` 走同一套 bundle 预检与渲染入口。
- 不要只靠模板名或人工经验拍脑袋推荐 `log/linear`；要同时看轴标签/单位和实际数据跨度。
- 不要把内部 QA / editorial policy 做成“让用户自己盯着分数改图”的前台功能；默认产品行为应该是软件自己统一出图，必要时只暴露极少数 cleanup 提示。
- 不要把 graph region 的位置真相源拆成两份；region 负责占格，graph panel 的 `x/y/w/h` 只是归一化结果。
- 不要再把 Composer 改回旧的 `3x3 原点吸附 + panels-only` 心智模型；v2 的事实源是 `regions + drawables`。
- 不要让 graph 导入悄悄接受任意尺寸 PDF；不符合 `60x55 / 120x55 / 60x110 mm` 的 PDF 应提示改用 asset 模式。
- 不要在导出里把所有 PDF 先栅格化；graph 和 PDF asset 应尽量保持矢量。
- 改对齐规则时，要同时想到 `single_panel`、`wide_nmr`、`heatmap` 三类约束。
- 改 loader、inspect、preflight 或 render 时，要同时想到 `src/rendering/cache.py` 的缓存失效，不要让旧解析结果穿透到新请求。
- 改拉伸预处理时，不只是看 `.xlsx` 有没有生成，还要看 tensile 工作台是否正确展示 `preferred_sheet`，以及点击“在绘图中打开”后后续 render 能不能继续。
- `docs/plot_contract.md` 是生成产物；真正要改的是契约 JSON 和生成脚本依赖的数据。
- `scripts/debug_refresh.py` 的真实数据入口只认 `CODEGOD_DEBUG_REFRESH_TENSILE_RAW_DATA`、`CODEGOD_DEBUG_REFRESH_FREQ_SWEEP`、`CODEGOD_DEBUG_REFRESH_TEMP_SWEEP`、`CODEGOD_DEBUG_REFRESH_STRESS_RELAXATION`；不要把个人绝对路径或私有目录结构写回仓库。
- `scripts/clean_repo.py` 默认不应删除当前激活的 `.venv`；如果要清 `app/desktop/node_modules/`，必须显式传 `--include-node-modules`，不要把“重装成本高”的依赖目录做成隐式默认删除项。

## 拉伸预处理夹具

- committed raw CSV fixtures 在 `tests/fixtures/tensile_raw/`。
- 这些文件是给 smoke、后续 AI 调试和手动排查用的，不要随手删。
- 如果需要新增拉伸预处理规则，优先补 fixture 和 smoke，再改解析逻辑。
