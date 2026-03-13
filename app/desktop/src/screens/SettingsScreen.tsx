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
      all: "已重置当前页面状态并清空最近记录。",
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
                <p>绘图识别、预览和导出都依赖 sidecar，这里可以随时重新检查。</p>
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
                <div className="card-kicker">默认拼图画布</div>
                <h2>
                  {composerProject.canvas_width_mm} x {composerProject.canvas_height_mm} mm
                </h2>
                <p>当前项目会使用这套画布尺寸和网格步进来排版。</p>
              </div>
            </div>
          </article>

          <article className="work-card section-card">
            <div className="section-head">
              <div>
                <div className="card-kicker">默认绘图区</div>
                <h2>
                  {meta?.global_frame.panel_width_mm ?? 60} x {meta?.global_frame.panel_height_mm ?? 55} mm 标准轴框
                </h2>
                <p>这里显示当前单图的默认绘图区尺寸和边距。</p>
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
                <div className="card-kicker">显示与偏好</div>
                <h2>主题和常用设置</h2>
                <p>这些设置会保存在本地，并在下次打开时继续使用。</p>
              </div>
            </div>

            <div className="inspector-stack">
              <label>
                <span className="field-label">主题</span>
                <select
                  className="field"
                  onChange={(event) =>
                    updateSettings({
                      theme_preference:
                        event.target.value === "light" || event.target.value === "dark"
                          ? event.target.value
                          : "system",
                    })
                  }
                  value={settings.theme_preference}
                >
                  <option value="system">跟随系统</option>
                  <option value="light">浅色</option>
                  <option value="dark">深色</option>
                </select>
              </label>

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
                <span>记住上次打开的页面</span>
              </label>
            </div>
          </article>

          <article className="work-card section-card">
            <div className="section-head">
              <div>
                <div className="card-kicker">维护动作</div>
                <h2>清理当前工作现场</h2>
                <p>需要时可以重置绘图、拼图或最近项目记录。</p>
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
              <h3>当前设置</h3>
              <p>这里汇总当前保存的主题和常用偏好。</p>
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
              <span>主题</span>
              <strong>
                {settings.theme_preference === "system"
                  ? "跟随系统"
                  : settings.theme_preference === "light"
                    ? "浅色"
                    : "深色"}
              </strong>
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
      </aside>
    </div>
  );
}
