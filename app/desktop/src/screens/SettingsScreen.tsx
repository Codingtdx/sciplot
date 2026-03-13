import { healthcheck } from "../lib/api";
import { useComposerStore, useWizardStore, useWorkbenchStore } from "../lib/store";
import type { PlotContract, WorkbenchMeta } from "../lib/types";
import { useState } from "react";

export function SettingsScreen({
  meta,
  contract,
}: {
  meta: WorkbenchMeta | null;
  contract: PlotContract | null;
}) {
  const sidecarReady = useWizardStore((state) => state.sidecarReady);
  const setSidecarReady = useWizardStore((state) => state.setSidecarReady);
  const resetWizard = useWizardStore((state) => state.reset);
  const resetComposer = useComposerStore((state) => state.reset);
  const composerProject = useComposerStore((state) => state.project);
  const pdfImportMode = useWorkbenchStore((state) => state.pdfImportMode);
  const recentProjects = useWorkbenchStore((state) => state.recentProjects);
  const settings = useWorkbenchStore((state) => state.settings);
  const updateSettings = useWorkbenchStore((state) => state.updateSettings);
  const clearRecentProjects = useWorkbenchStore((state) => state.clearRecentProjects);
  const [checking, setChecking] = useState(false);
  const [maintenanceNotice, setMaintenanceNotice] = useState<string | null>(null);

  const refreshSidecar = async () => {
    setChecking(true);
    try {
      setSidecarReady(await healthcheck());
    } finally {
      setChecking(false);
    }
  };

  const runMaintenance = (action: "wizard" | "composer" | "recent" | "all") => {
    if (action === "wizard" || action === "all") {
      resetWizard();
    }
    if (action === "composer" || action === "all") {
      resetComposer();
    }
    if (action === "recent" || action === "all") {
      clearRecentProjects();
    }

    const labels = {
      wizard: "已重置绘图精灵现场。",
      composer: "已重置拼图器现场。",
      recent: "已清空最近项目记录。",
      all: "已重置工作台现场并清空最近记录。",
    } as const;

    setMaintenanceNotice(labels[action]);
  };

  const validationRuleCount = contract ? Object.keys(contract.validation_rules).length : 0;

  return (
    <div className="desk-layout">
      <section className="desk-main">
        <div className="summary-grid">
          <article className="work-card section-card">
            <div className="section-head">
              <div>
                <div className="card-kicker">运行状态</div>
                <h2>{sidecarReady ? "Python sidecar 已连通" : "Python sidecar 暂未连通"}</h2>
                <p>绘图精灵的识别、预检和渲染都依赖 sidecar，这里给一个明确的健康状态反馈。</p>
              </div>
            </div>
            <div className="step-actions">
              <button
                className="primary-button"
                disabled={checking}
                onClick={() => void refreshSidecar()}
                type="button"
              >
                {checking ? "检查中…" : "重新检查"}
              </button>
            </div>
          </article>

          <article className="work-card section-card">
            <div className="section-head">
              <div>
                <div className="card-kicker">画布约定</div>
                <h2>
                  {composerProject.canvas_width_mm} x {composerProject.canvas_height_mm} mm
                </h2>
                <p>当前拼图器遵循 3x3 网格和 0.5 mm 步进，这是 5.0 版桌面工作台的默认结构。</p>
              </div>
            </div>
          </article>

          <article className="work-card section-card">
            <div className="section-head">
              <div>
                <div className="card-kicker">绘图契约</div>
                <h2>
                  {meta?.global_frame.panel_width_mm ?? 60} x {meta?.global_frame.panel_height_mm ?? 55} mm 标准轴框
                </h2>
                <p>当前前后端都引用同一份绘图契约；这里显示标准单图 frame 和规则总数。</p>
              </div>
            </div>
            <div className="context-list">
              <div className="context-row">
                <span>左 / 右</span>
                <strong>
                  {meta?.global_frame.left_margin_mm ?? 14} / {meta?.global_frame.right_margin_mm ?? 4.5} mm
                </strong>
              </div>
              <div className="context-row">
                <span>下 / 上</span>
                <strong>
                  {meta?.global_frame.bottom_margin_mm ?? 11} / {meta?.global_frame.top_margin_mm ?? 5.5} mm
                </strong>
              </div>
              <div className="context-row">
                <span>校验规则</span>
                <strong>{validationRuleCount}</strong>
              </div>
            </div>
          </article>

          <article className="work-card section-card">
            <div className="section-head">
              <div>
                <div className="card-kicker">工作台偏好</div>
                <h2>把少量真正有用的偏好保存下来</h2>
                <p>这里不堆很多伪配置，只保留会明显影响工作体验的开关。</p>
              </div>
            </div>

            <div className="inspector-stack">
              <label className="toggle-field">
                <input
                  checked={settings.auto_status_poll}
                  onChange={(event) =>
                    updateSettings({ auto_status_poll: event.target.checked })
                  }
                  type="checkbox"
                />
                <span>自动轮询 sidecar 状态</span>
              </label>

              <label className="toggle-field">
                <input
                  checked={settings.remember_last_screen}
                  onChange={(event) =>
                    updateSettings({ remember_last_screen: event.target.checked })
                  }
                  type="checkbox"
                />
                <span>记住上次打开的工作台页面</span>
              </label>
            </div>
          </article>

          <article className="work-card section-card">
            <div className="section-head">
              <div>
                <div className="card-kicker">维护动作</div>
                <h2>需要时快速清理现场</h2>
                <p>重置当前工作状态，而不是去手动找缓存或改配置文件。</p>
              </div>
            </div>

            {maintenanceNotice && <div className="success-card">{maintenanceNotice}</div>}

            <div className="step-actions">
              <button className="ghost-button" onClick={() => runMaintenance("wizard")} type="button">
                重置绘图精灵
              </button>
              <button className="ghost-button" onClick={() => runMaintenance("composer")} type="button">
                重置拼图器
              </button>
              <button className="ghost-button" onClick={() => runMaintenance("recent")} type="button">
                清空最近记录
              </button>
              <button className="ghost-button danger-button" onClick={() => runMaintenance("all")} type="button">
                全部重置
              </button>
            </div>
          </article>
        </div>
      </section>

      <aside className="desk-context">
        <article className="context-card">
          <div className="context-card-head">
            <div>
              <h3>当前状态</h3>
              <p>把真实运行状态和当前偏好总结出来，避免设置页变成一堆无意义开关。</p>
            </div>
          </div>
          <div className="context-list">
            <div className="context-row">
              <span>最近记录</span>
              <strong>{recentProjects.length}</strong>
            </div>
            <div className="context-row">
              <span>PDF 导入模式</span>
              <strong>{pdfImportMode === "graph" ? "作为图" : "作为素材"}</strong>
            </div>
            <div className="context-row">
              <span>自动轮询</span>
              <strong>{settings.auto_status_poll ? "开启" : "关闭"}</strong>
            </div>
            <div className="context-row">
              <span>记住页面</span>
              <strong>{settings.remember_last_screen ? "开启" : "关闭"}</strong>
            </div>
          </div>
        </article>

        <article className="context-card">
          <div className="context-card-head">
            <div>
              <h3>当前原则</h3>
              <p>设置页继续遵守你定的方向: 桌面工作台，不是 Web 后台表单墙。</p>
            </div>
          </div>
          <ul className="bullet-list">
            <li>左侧保持轻导航，不承担主要操作。</li>
            <li>绘图精灵按单步卡片流推进。</li>
            <li>拼图器把对象属性、图层和对齐信息收在右侧。</li>
            <li>最近项目和偏好都会在本地持久化保存。</li>
          </ul>
        </article>
      </aside>
    </div>
  );
}
