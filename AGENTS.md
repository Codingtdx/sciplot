# SciPlot God 开发入口说明

这个仓库已经把绘图规范和 GUI 运行时约束收成同一套事实源。以后不管是人还是 AI 来改，先看这里，再决定动哪一层。

> **Desktop GUI status (2026-04-01):** 当前受支持桌面前端已经切到原生 macOS `app/macos`。app-level product model 仍以 `Plot / Data Studio / Composer / Code Console` 这 4 个保留 workbench 为准；`app/desktop/src/mock/**` 里的当前 mock 仍是受保护的 Plot-only 参考，不代表 whole-app IA，也不要在非 mock-design pass 里改它。

## 项目结构

- `src/`: 绘图内核、数据加载、布局规则、拉伸预处理、拼图后端。
- `src/rendering/`: 绘图服务层；现在按 `inspect / recommendation / preflight / render_curve / render_stats / render_heatmap / render_registry / cache / options / io` 拆开，CLI 和 sidecar 只应该调用 `src/core/application/render.py` 或 `src/rendering/render_service.py`，不要再直连内部 workflow 模块。
- `src/plotting.py`: 现在只是公开 plotting API 的兼容门面；外部兼容调用继续从这里 import，但内部模块不得再从这里拿私有 helper。
- `src/plotting_primitives.py`: 通用 plotting primitives 与共享坐标/刻度/几何 helper；`stats / heatmap / curve support` 都从这里拿共享底座。
- `src/plotting_curve_support.py`: 曲线图族共享 support，承接 `CurveTemplate / shared x layout / stacked layout / edge labels / legend helper` 等曲线专属逻辑。
- `src/plotting_wide_nmr.py`: wide-NMR 专属 support 与 `plot_wide_nmr` 真正实现；不要再把 wide-NMR 特例逻辑塞回 `src/plotting.py`。
- `src/plotting_curves.py`: 曲线图族主流程实现，承接 `plot_curves / plot_scatter / curve template / legend` 等编排逻辑；外部兼容调用仍通过 `src/plotting.py` 暴露。
- `src/plotting_stats.py`: 统计图族实现，承接 `box / bar / violin` 及其共享坐标规则；外部兼容调用仍通过 `src/plotting.py` 暴露。
- `src/plotting_heatmap.py`: 热图实现，承接 heatmap 主图区与 colorbar 布局；外部兼容调用仍通过 `src/plotting.py` 暴露。
- `src/composer.py`: Composer v2 后端公开入口与真相源门面；外部调用继续统一从这里 import。类型与常量在 `src/composer_types.py`，布局/导入/校验在 `src/composer_ops.py`，预览/导出在 `src/composer_render.py`。
- `src/data_studio/`: Data Studio 后端真相源；负责多格式原始文件 intake、模板推荐与持久化、workbook 构建、comparison recipe 生成、session normalize 与 tensile 内置模板族。
- `src/code_console_service.py`: Code Console 后端真相源；负责绑定输入上下文、生成外部 AI prompt/starter code，并运行受控 repo-native Python runner。
- `src/code_console_runtime.py`: Code Console 脚本 helper；runner 内脚本统一从这里读取上下文、加载数据、申请受控输出路径并复用 SciPlot God 风格底座。
- `src/infrastructure/persistence/code_console_runs.py`: Code Console managed run/output 目录与 retention 规则；不要在 sidecar route 里散落手写目录策略。
- `src/infrastructure/persistence/data_studio_imports.py`: Data Studio compare workbook re-import 时的 managed 单组 workbook 恢复目录；comparison workbook 若缺少可用 `source_files`，应先在这里 materialize 可重导入的单组 workbook，再交给 `/data-studio/import-workbook`。
- `make_plot.py`: CLI 兼容入口；现在只负责参数解析、错误出口和调用 `src/rendering/`，不再承载领域逻辑。
- `app/sidecar/server.py`: GUI 唯一后端真相源。`/meta`、`/plot-contract`、预览、导出、拼图、拉伸预处理都从这里走。
- `app/sidecar/schemas.py`: sidecar 请求/响应模型、项目文件 schema 校验与迁移入口；`/save-project`、`/open-project` 统一经过这里。
- `app/sidecar/routes_data_studio.py` + `app/sidecar/schemas_data_studio.py`: Data Studio 的 canonical backend surface；模板列表/创建/重命名/删除、source preview、workbook build/import、workbook preview、comparison context/preview/export、session normalize 全走 `/data-studio/*`。
- `app/sidecar/routes_code_console.py` + `app/sidecar/schemas_code_console.py`: Code Console 的 prompt/context 与 controlled runner surface；当前原生前端统一通过 `/code-console/context`、`/code-console/run` 走这一层。
- `app/macos/`: 当前受支持的原生 macOS 前端；手工 Xcode 工程、SwiftUI app shell、sidecar runtime 与 4 个 workbench 的实现都在这里。
- `app/macos/Sources/App`: SwiftUI `App` root、`NavigationSplitView` shell、toolbar、commands 与 app-level session/runtime 装配。
- `app/macos/Sources/Infrastructure`: `Process + Pipe` sidecar runtime、`URLSession + Codable` client、repo root 定位与 sidecar schema mirror。
- `app/macos/Sources/Features`: `Plot / Data Studio / Composer / Code Console` 各工作台与本地 session state。
- `app/macos/Sources/Shared/UI/StateViews.swift`: 原生 macOS shared inspector primitives 与空态/错误态基础组件；右侧 inspector 的统一列宽、adaptive row、action stack 与 empty-state 应优先从这里复用，不要在各 workbench 里再散写一套 ad hoc `LabeledContent` 和说明文案布局。
- `data_studio_templates/`: Data Studio 模板存储根目录；`builtin/` 放内置模板族，`user/` 放用户保存的结构模板，前后端启动时都要自动加载。
- `app/macos/Tests`: 原生 macOS 测试目标；覆盖 sidecar bootstrap/probe、schema decoding 与工作台状态流。
- `app/desktop/src/`: 旧的 Tauri foundation 代码保留作历史/参考层，不再是受支持的桌面主链路。
- `app/desktop/src/mock/`: 当前受保护的 Plot-only mock 参考；它保留 runnable mount 供后续 mock-design pass 使用，但不代表 app-level IA，也不要在本类 foundation pass 里修改。
- `app/desktop/src/styles.css`: 旧 mock/Tauri 参考样式层；不要把它当成原生 macOS 前端的主题真相源。
- `README.md` + `docs/product-architecture.md`: 当前 whole-app 产品模型、4 个 retained workbench、canonical workflow 与 IA 原则说明；做 mock、shell、路由、文案或导航清理前先看这里。
- `app/desktop/scripts/tauri-smoke.mjs`: 旧 Tauri 宿主 smoke；只在维护受保护 mock 或迁移历史行为时才参考，不是当前桌面主链路验证入口。
- `Launch_Plotter.command`: 桌面端唯一启动器；现在负责构建并打开原生 macOS app，失败时直接报错，不再提供任何 PySide / 终端 fallback。
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
- `inspect-file` / `recommend-render` 的 `inspection` 现在在保持旧 `recommendation` 兼容字段的同时，还会返回 richer ranked `recommendations`（含 `rank / score / reason / suitability_hint / score_gap_to_top`）以及顶层 `recommendation_confidence / recommendation_summary`；Plot 的模板选择层只消费这些后端字段做排序与提示，不要在前端再造一套评分逻辑。
- `export-render` 除了 PDF，还会在输出目录旁写出 preview PNG、normalized options、inspection、preflight、submission report、manifest 这些 bundle 产物；如果 GUI 没传显式 `output_dir`，sidecar 默认写到 app-managed `plot_exports` 目录，只有用户明确选目录时才落到用户指定路径。改导出链路时别漏掉这些伴随文件，也别让桌面端的“打开输出目录”按钮失效。
- 绘图输入解析缓存统一放在 `src/rendering/cache.py`，键是 `(path, sheet, file_mtime_ns)`；如果改了 loader 或预检逻辑，要考虑缓存命中、失效和 clone 语义。
- 如果只是新增某个绘图家族的调用点，优先走 `src/plotting_families/`；`src/plotting.py` 只当公开兼容接口，不当实现文件，也不要再从里面 import 私有 helper。
- 前端打开项目时必须经过运行时校验和归一化，不要再用 TS 强转把不可信 payload 直接吃进去。
- Plot 项目文件和运行时 store 里的渲染选项现在都要保留 `style_preset`；如果改 render options schema，必须同时更新 sidecar schema、桌面运行时 parser、持久化读写和本说明。
- 桌面端当前受支持宿主是 `app/macos` 原生 SwiftUI 应用；文件导入、目录选择、Finder reveal、sidecar 拉起等运行时访问应统一收敛到明确的 Swift runtime 入口，不要在页面里散落调用或静默吞错。
- 原生 macOS runtime 对 sidecar 的策略是“app-managed ownership”：不要再依赖“复用端口上已有 sidecar”来凑兼容。`/meta` 与 `/plot-contract` payload 不可解码或模板集合为空时，必须判定为不兼容并替换为 repo `.venv` 启动的 sidecar。
- `Launch_Plotter.command` 现在代表原生 macOS 主链路，也是唯一受支持的桌面入口；不要再引入 `plot_wizard_gui.py`、`interactive_plot.py` 一类旧 fallback。
- 原生桌面文件对话框优先走 `fileImporter`、`NSOpenPanel`、`NSSavePanel` 这类一方 API；如果 dialog 打不开，必须把错误明确显示到界面上，不能静默失败。
- 原生 macOS 右侧 inspector 现在使用统一的 native column policy：`inspectorColumnWidth(min: 360, ideal: 400, max: 460)`；四个 workbench 的 inspector 都应保持功能优先、短文案、adaptive row 与统一 action stack，不要再在某个模块里单独塞回超长解释文字或私有宽度策略。
- 桌面端当前的 app-level product model 以 `Plot / Data Studio / Composer / Code Console` 这 4 个 retained workbench 为准；`Start / Home / Project / Settings` 只能作为 utility 或受保护 mock 参考，不能再当一级产品区。
- 设计或 mock 规划时要明确区分 canonical internal workflow 和 user-visible UI workflow：detect / normalize / map / validate / handoff / automation 这类系统步骤可以隐藏或并入更大的 work surface，只有用户需要定位、决策、复核、调整、确认、导出或交接时才应暴露成可见步骤。
- 当前受保护 mock 仍展示 `Start -> Plot Import -> Plot Template -> Plot Refine` 这一条 Plot-only 参考流；它服务于后续 mock-design pass，但不是 whole-app IA 真相源，也不要在非 mock pass 里改 `app/desktop/src/mock/**` 与 `app/desktop/src/main.tsx`。
- 桌面端 workspace 默认只保留一个纵向滚动根：`app-main`。除非是明确设计的局部画布/代码横向预览，不要再给页面内部叠第二层默认纵向滚动容器。
- `PreviewPane` 的普通滚轮应继续服务页面滚动；只有 `Ctrl/Cmd + wheel` 才用于缩放，双击回到 reset/fit。不要再让预览面板吞掉默认页面滚动。
- Plot 的 canonical local workflow 是 `Import -> Inspect -> Template -> Refine -> Preflight -> Export`；不要再把旧的 staged 子路由恢复成 app-level 主入口，也不要把 Plot 子步骤重新堆回一级导航。
- `inspect` 仍在导入和切 sheet 后立即执行，但它属于 Plot 的 `Import` 本地阶段；preview、readiness check 与 export 都收敛在 `Refine` 内联完成，不要再改回跨多个 app-level 屏幕的心智模型。
- Plot 的 `Template` 阶段默认只显示当前输入模型兼容的推荐模板，并把其他模板明确标成 disabled 或 unavailable；不要让用户点进一个必报错的模板路径。
- `Data Studio` 是 retained primary workbench；底层仍可保留 tensile 相关 route、schema、fixture 与科学语义，但产品文案、README、IA 和导航不要再把 `Tensile` 当一级产品名。
- `Data Studio` 工作台是 workbook group + compare plotting 工作台：主对象是每个样品组对应的 workbook；parse template 只属于 Import 流程，不是主界面主对象。raw import 时先自动匹配现有模板，只有匹配失败或不确定时才让用户选择或新建解析模板。
- `Data Studio` 原生工作台应与 Plot 对齐成同级壳层：顶部只保留状态和 toolbar Import/Export，左侧是 workbook group rail，中间默认是 current figure preview；当用户打开 specimen filter 时，在 rail 和 preview 之间插入 inline side panel；最右仍是 Plot inspector 主导加少量 Studio-specific 控制。不要再把 template flow/library/status 做成主块，也不要把 review / compare / export 堆成中央长滚动主面。
- `Data Studio` 的左 rail 只承载 workbook group list：display name、replicate 摘要、轻量 warning/ready 状态、include-in-compare 开关与拖拽重排；不要把 raw file list、template library 或解释性文案放回 rail。
- `Data Studio` 的显示语义以 `display_name / include_in_compare / sort_order / focused workbook` 为真相源；display rename 只作用于图例、label 与默认导出命名，不得修改磁盘上的原始文件名、workbook 文件名或 source path。
- `Data Studio` 的 specimen inclusion/exclusion 属于 workbook 级运行时状态，真相源是 session payload 与 sidecar request/response 里的 `specimen_states`；代表曲线、mean/std、replicate compare sheet 与 warning/suggestion 都必须由 `/data-studio/workbook-preview` 和 comparison context/export 链路基于当前 included specimens 回算，前端不得本地重算另一套统计或建议逻辑。
- `Data Studio` 的 specimen filter UI 必须保持 inline side panel：建议结果在打开面板或 specimen 状态变化后自动展示，但绝不自动应用；主 figure preview 在筛选过程中必须保持可见，不要再退回 modal sheet。
- `Data Studio` 的自动 exclusion 建议当前只服务 tensile triad（`Strength / Modulus / Elongation`）这类 specimen compare 清洗；规则不是“挑最接近平均的 5 个”，而是基于当前 included 且 triad-complete 的 specimen 计算三指标 composite z-score，建议排除 `max 1 + min 1` 两个极端样本，典型 7 个样本会留下 5 个用于后续平均值与误差棒。
- `Data Studio` 必须提供正式的 `New Data Studio Session` 语义：清空当前 workbook group list、compare inclusion、display rename、排序与 preview context，但保留 figure type、plot style、canvas/theme/palette 等 figure preferences。`Clear Current Session` 只能作为次级危险动作存在。
- Tensile 现有模板必须继续作为内置模板族工作；默认优先支持并自动匹配现有 tensile raw fixtures，不允许因为 Data Studio 重构而失效。
- Data Studio 的 canonical route surface 是 `/data-studio/templates`、`/data-studio/source-preview`、`/data-studio/build-workbook`、`/data-studio/import-workbook`、`/data-studio/workbook-preview`、`/data-studio/comparison-context`、`/data-studio/comparison-preview`、`/data-studio/comparison-export` 与 `/data-studio/session/normalize`；旧 tensile-specific route 只可作为兼容 seam，不能再主导新前端。
- Data Studio 主 workbench 的 preview 刷新必须走 `/data-studio/comparison-context` + PlotSession 单次 inspect/render；`/data-studio/comparison-preview` 只保留给确实需要 sidecar 直接产出 PDF preview 的场景，不要再让主工作台先渲染一次 PDF 再让 PlotSession 渲染第二次。
- 如果要做面向用户的 mock，Data Studio 的 user-visible workflow 默认优先压缩为 `Import -> Group Review -> Compare Preview -> Export / Open in Plot`；specimen review / 自动 exclusion 建议属于 `Group Review` 内的 inline side panel，不应再拆成新的一级页面；parse template 的自动匹配、候选推荐和新建模板确认都应下沉在 Import sheet 内，不要回到主界面当一级页面。
- Data Studio workbook build 或 comparison context/preview 成功后默认停留在 `Data Studio` 页面；只有显式点击“在绘图中打开”时，才会把整理结果送进 Plot 继续 inspect / preflight / render。
- 最近记录、open/save、managed files 与 runtime cleanup 都属于 utility affordance；不要再把 `Start` 或 `projects/recents` 还原成一级 workspace。
- Plot 导入阶段如需 sidecar materialize `example template folder / blank template folder`，这些 workbook 仍要写到 app-managed stable 目录并按需覆盖刷新；它们只是输入模板与桥接层，不是新的绘图事实源，也不能替代契约、`/meta`、inspect/recommendation 或现有导入责任链。
- `Code Console` 是一级主工作台，不是 utility；前端负责绑定当前 plot session 或直接加载数据文件、继承当前 plot 或 inspect 得出的 size/style/palette 上下文、按需展示 prompt、承接粘贴代码与运行结果，sidecar 负责生成最终 prompt、轻量上下文和受控 runner。
- Code Console 当前的后端真相源就是 `/code-console/context` 与 `/code-console/run`；不要在前端本地重拼 prompt、上下文 JSON、runner 环境变量或 managed output 目录结构。
- `Code Console` 的 prompt、runner、AI bundle 和 data template 都不是新的绘图事实源；不要把 contract 常量、视觉默认值、尺寸规则或 plotting rule 复制进前端，也不要绕过 sidecar 在 GUI 本地重新拼最终 prompt、runner 上下文或模板结构。
- `Code Console` 的主流程是 `Bind Context -> Inspect Inputs -> Prompt/Code -> Run -> Outputs -> Handoff`；默认不要把长 prompt body 常驻铺满页面，也不要把 Console 做成第二套重配置表单。
- `Code Console` runner 只运行 repo-native Python，不是系统 shell：工作目录是 repo root，但预览和导出产物只认受控 `OUTPUT_DIR`，并且要有 timeout、stdout/stderr、exit code、duration、generated files 这些返回字段。runner 的 managed run/output 目录要走 app-managed cache/data 路径并做 retention/cleanup，不能无上限堆积。
- runtime/appearance/managed-file 清理入口如有需要，只能作为 utility surface，用于 reveal/refresh/prune template folders、managed plot exports 和 code-console runs；这类清理只作用于 app-generated artifacts，不能干扰用户显式选择的导出目录。
- `scripts/debug_refresh.py` 的真实数据路径只允许从 `CODEGOD_DEBUG_REFRESH_*` 环境变量注入；不要再把个人机器绝对路径直接提交进仓库。
- Python / Node 开发环境以 `.python-version`、`.nvmrc` 和 `requirements.txt` + `requirements-constraints.txt` 为准；不要再依赖“本机刚好装得上”的浮动版本。
- 当 `Plot` 或 `Composer` 已有当前会话内容时，打开另一份数据文件/项目文件前应先明确提醒“将替换当前会话”；不要静默把当前工作区直接重置掉。
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
- `curve / point_line / scatter` 的 inside legend 只能在当前 axis frame 内择位，不能再为了避让图例去扩张 `x/y` display bounds；`tensile_curve` 这类保留应力语义的小面板多曲线默认优先尝试右下角 legend。
- plain `bar` / plain `box` 是摘要模板：默认不叠 raw replicate points；需要显式样本点覆盖时走 `box_strip`、`point_error`、`lollipop_error` 或 `distribution_compare` 的 `strip_box` 变体。plain `box` 与 `violin_box` 的 box summary 默认禁用 flier glyph，raw-point overlay 不得带黑色描边。
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
- Plot 模板选择层当前使用的兼容模板映射是：
  - `frequency_sweep / temperature_sweep / stress_relaxation -> point_line, curve`
  - `tensile_curve -> curve, point_line, replicate_curves_with_band, stacked_curve, segmented_stacked_curve, scatter, scatter_fit, scatter_with_fit`
  - `curve_table -> curve, point_line, replicate_curves_with_band, stacked_curve, segmented_stacked_curve, scatter, scatter_fit, scatter_with_fit`
  - `replicate_table -> distribution_compare, box_strip, point_error, grouped_bar_error, grouped_bar_compare, histogram_density, box, violin, bar`
  - `heatmap_table -> heatmap, annotated_heatmap`
- 所有识别为 `tensile_curve` 的曲线默认推荐 `linear` x/y 坐标；推荐不应锁死用户选择，若用户显式改为 `log`，则仍按常规正值约束进行预检与渲染。
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
- Native macOS 构建：
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`
- Native macOS 测试：
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`

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
- `xcodebuild ... build`
- 如果改了 `/meta` 或前端选项展示，再跑 `xcodebuild ... test`

改拼图器时，至少回归：

- `pytest`
- `scripts/smoke_check.py` 中的 composer 段
- `ruff check`
- `mypy src/composer.py`
- `xcodebuild ... test`
- 如果改了原生启动链路、窗口配置、sidecar bootstrap 或 Finder/runtime 交互，再跑 `xcodebuild ... build` 与 `xcodebuild ... test`

改拉伸预处理时，至少回归：

- `pytest`
- `scripts/smoke_check.py` 中的 tensile preprocess 段
- `tests/test_sidecar_active_routes.py`
- `xcodebuild ... test` 中覆盖当前 native shell 的用例（如果本轮改了桌面文案、入口或导航假设）
- 确认 tensile built-in template 仍能自动生成 workbook，并且该 workbook 能在 `Data Studio` 工作台显示结果、进入 compare、点击“在绘图中打开”后继续 Plot 的 `inspect / preflight / render`

改 GUI 选项或状态流时，至少回归：

- `xcodebuild ... test`
- `xcodebuild ... build`
- 如果动到 sidecar 交互字段，再补跑 Python smoke

改 `src/rendering/`、`make_plot.py`、sidecar schema 或项目文件读写时，至少回归：

- `ruff check`
- `mypy`
- `pytest`
- `scripts/smoke_check.py`
- 如果 sidecar 返回字段或桌面端载入路径受影响，再跑 `xcodebuild ... test`

## 常见坑

- sidecar 是 GUI 的唯一后端真相源。不要绕过 `/meta` 去本地拼模板列表。
- 不要把“端口能连通”当作 sidecar 可用性的充分条件；`/meta`、`/plot-contract` payload 形状不兼容时必须视为旧 sidecar 并替换。
- Swift sidecar mirror 若使用 `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase`，不要把字段命名成 `*IDs`；统一用 `*Ids` 并补真实 snake_case payload 解码测试，避免 `template_ids` 一类字段被误判为缺失。
- 不要复制模板、尺寸、palette 或默认参数到第二个文件里做“临时常量”。
- 不要把新模板或例外规则偷偷塞进 `plotting.py`、`make_plot.py`、`src/rendering/` 或前端选项，而不回写契约和说明。
- 只要代码改动已经让开发说明中的某一条不再准确，就必须同一轮改 `AGENTS.md`；禁止“代码先合，说明以后再补”。
- 不要在 sidecar 里直接 `return {...}` 一坨裸对象而不经过 response model。
- 不要让 `save/open project` 旁路 `app/sidecar/schemas.py` 的校验/迁移层。
- 不要在前端重新引入“第二套项目文件 schema”或靠 TS 强转跳过运行时校验。
- 不要再按“浏览器宿主也要能跑”的约束设计桌面前端；当前 GUI 的唯一受支持目标宿主是原生 macOS `app/macos`。
- 不要让文件对话框、拖放等桌面能力失败后直接吞掉异常；必须在界面上给出明确错误。
- 不要重新引入 `Launch_Plotter_Legacy.command`、`plot_wizard_gui.py`、`interactive_plot.py` 这类旧入口；当前桌面主链路只保留原生 macOS app。
- 不要让当前受保护 mock 或 Plot-only 参考流反向定义 whole-app IA；app-level retained model 始终是 `Plot / Data Studio / Composer / Code Console`。
- 不要重新把 `Start / Home / Project / Settings` 恢复成一级产品区；这些概念最多只能作为 utility surface 或历史兼容层存在。
- 不要把 Plot 的本地步骤塞回一级导航，也不要把所有 Plot 控件重新堆成一个无层次的大表单；Plot 的 canonical local flow 仍应保持 `Import -> Inspect -> Template -> Refine -> Preflight -> Export`。
- 不要把 detect / normalize / map / preflight / handoff 之类内部系统步骤逐个翻译成 mock 页面；除非用户必须实际操作，否则应并入更大的 decision-oriented work surface。
- 不要把 Data Studio compare 清单做成“必须先保存项目才能继续”的流；它应该是 `Data Studio` 工作台内的运行时工作流增强，并且补录已有 workbook 时不能抢走当前 Plot 主输入。
- 不要把不兼容模板重新放回 `Plot Template` 默认主列表，更不要让 disabled 模板还能被点击。
- 不要让 rheology bundle 的 `curve` 再退回普通 `curve_table` 解析；温度扫描、频率扫描、应力松弛都必须和 `point_line` 走同一套 bundle 预检与渲染入口。
- 不要只靠模板名或人工经验拍脑袋推荐 `log/linear`；要同时看轴标签/单位和实际数据跨度。
- 不要把内部 QA / editorial policy 做成“让用户自己盯着分数改图”的前台功能；默认产品行为应该是软件自己统一出图，必要时只暴露极少数 cleanup 提示。
- 不要把 graph region 的位置真相源拆成两份；region 负责占格，graph panel 的 `x/y/w/h` 只是归一化结果。
- 不要再把 Composer 改回旧的 `3x3 原点吸附 + panels-only` 心智模型；v2 的事实源是 `regions + drawables`。
- 不要让 graph 导入悄悄接受任意尺寸 PDF；不符合 `60x55 / 120x55 / 60x110 mm` 的 PDF 应提示改用 asset 模式。
- 不要在导出里把所有 PDF 先栅格化；graph 和 PDF asset 应尽量保持矢量。
- 改对齐规则时，要同时想到 `single_panel`、`wide_nmr`、`heatmap` 三类约束。
- 改 loader、inspect、preflight 或 render 时，要同时想到 `src/rendering/cache.py` 的缓存失效，不要让旧解析结果穿透到新请求。
- 改拉伸预处理时，不只是看 `.xlsx` 有没有生成，还要看 `Data Studio` 工作台是否正确展示 `preferred_sheet`，以及点击“在绘图中打开”后后续 Plot render 能不能继续。
- `docs/plot_contract.md` 是生成产物；真正要改的是契约 JSON 和生成脚本依赖的数据。
- `scripts/debug_refresh.py` 的真实数据入口只认 `CODEGOD_DEBUG_REFRESH_TENSILE_RAW_DATA`、`CODEGOD_DEBUG_REFRESH_FREQ_SWEEP`、`CODEGOD_DEBUG_REFRESH_TEMP_SWEEP`、`CODEGOD_DEBUG_REFRESH_STRESS_RELAXATION`；不要把个人绝对路径或私有目录结构写回仓库。
- `scripts/clean_repo.py` 默认不应删除当前激活的 `.venv`；如果要清 `app/desktop/node_modules/` 这类旧桌面依赖，必须显式传 `--include-node-modules`，不要把“重装成本高”的依赖目录做成隐式默认删除项。

## 拉伸预处理夹具

- committed raw CSV fixtures 在 `tests/fixtures/tensile_raw/`。
- 这些文件是给 smoke、后续 AI 调试和手动排查用的，不要随手删。
- 如果需要新增拉伸预处理规则，优先补 fixture 和 smoke，再改解析逻辑。
