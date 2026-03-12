import { useState } from "react";

import { loadComposerProjectFile, loadWizardDataFile, loadWizardProjectFile } from "../lib/project-io";
import { useComposerStore, useWizardStore, useWorkbenchStore } from "../lib/store";
import type { RecentProjectEntry, WorkbenchMeta, WorkbenchScreen } from "../lib/types";
import {
  AppMode,
  formatLeaf,
  formatRecentTimestamp,
  getErrorMessage,
  getWizardStepLabel,
  templateLabel,
} from "../lib/workbench";

export function ProjectsScreen({
  meta,
  onNavigate,
}: {
  meta: WorkbenchMeta | null;
  onNavigate(mode: AppMode): void;
}) {
  const wizard = useWizardStore();
  const composer = useComposerStore();
  const recentProjects = useWorkbenchStore((state) => state.recentProjects);
  const rememberProject = useWorkbenchStore((state) => state.rememberProject);
  const [activeRecentId, setActiveRecentId] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [noticeTone, setNoticeTone] = useState<"success" | "warning">("success");

  const reopenRecent = async (entry: RecentProjectEntry) => {
    setActiveRecentId(entry.id);
    setNotice(null);

    try {
      if (entry.mode === "wizard" && entry.kind === "data") {
        const inspected = await loadWizardDataFile(
          useWizardStore.getState(),
          meta,
          entry.path,
        );
        rememberProject({
          mode: "wizard",
          kind: "data",
          path: inspected.input_path,
          title: formatLeaf(inspected.input_path),
          detail: `数据文件 · ${inspected.sheet_names.length} sheet · ${templateLabel(meta, inspected.inspection.recommendation.template)}`,
        });
        setNoticeTone("success");
        setNotice(`已恢复数据文件：${formatLeaf(inspected.input_path)}`);
        onNavigate("wizard");
        return;
      }

      if (entry.mode === "wizard") {
        const payload = await loadWizardProjectFile(
          useWizardStore.getState(),
          meta,
          entry.path,
        );
        rememberProject({
          mode: "wizard",
          kind: "project",
          path: entry.path,
          title: formatLeaf(entry.path),
          detail: `绘图项目 · ${formatLeaf(payload.wizard.input_path)} · ${payload.wizard.outputs.length} 个结果`,
        });
        setNoticeTone("success");
        setNotice(`已恢复绘图项目：${formatLeaf(entry.path)}`);
        onNavigate("wizard");
        return;
      }

      const project = await loadComposerProjectFile(useComposerStore.getState(), entry.path);
      rememberProject({
        mode: "composer",
        kind: "project",
        path: entry.path,
        title: formatLeaf(entry.path),
        detail: `拼图项目 · ${project.panels.length} 个 panel / ${project.texts.length} 段文字`,
      });
      setNoticeTone("success");
      setNotice(`已恢复拼图项目：${formatLeaf(entry.path)}`);
      onNavigate("composer");
    } catch (error) {
      setNoticeTone("warning");
      setNotice(getErrorMessage(error));
    } finally {
      setActiveRecentId(null);
    }
  };

  return (
    <div className="desk-layout">
      <section className="desk-main">
        <article className="work-card hero-card">
          <div className="section-head hero-head">
            <div>
              <div className="card-kicker">Project Overview</div>
              <h2>把两个核心工作流都收进一个项目视角</h2>
              <p>先看到当前会话里已经做到哪一步，再决定回哪一个工作台继续推进。</p>
            </div>
          </div>
        </article>

        <div className="summary-grid">
          <article className="work-card section-card">
            <div className="section-head">
              <div>
                <div className="card-kicker">绘图精灵</div>
                <h2>{wizard.inputPath ? formatLeaf(wizard.inputPath) : "还没有加载数据"}</h2>
                <p>当前步骤是 {getWizardStepLabel(wizard.step)}，导出文件数为 {wizard.outputs.length}。</p>
              </div>
            </div>
            <div className="step-actions">
              <button className="primary-button" onClick={() => onNavigate("wizard")} type="button">
                回到绘图精灵
              </button>
            </div>
          </article>

          <article className="work-card section-card">
            <div className="section-head">
              <div>
                <div className="card-kicker">拼图器</div>
                <h2>
                  {composer.project.panels.length} 个 panel / {composer.project.texts.length} 段文字
                </h2>
                <p>
                  当前画布 {composer.project.canvas_width_mm} x {composer.project.canvas_height_mm} mm，
                  自动编号 {composer.project.auto_labels ? "已开启" : "已关闭"}。
                </p>
              </div>
            </div>
            <div className="step-actions">
              <button className="primary-button" onClick={() => onNavigate("composer")} type="button">
                回到拼图器
              </button>
            </div>
          </article>
        </div>

        <article className="work-card section-card">
          <div className="section-head">
            <div>
              <div className="card-kicker">最近项目与输入</div>
              <h2>从最近一次工作现场继续</h2>
              <p>打开过的数据文件、保存过的项目和最近恢复过的工作，都会在这里形成可回跳的入口。</p>
            </div>
          </div>

          {notice && (
            <div className={noticeTone === "success" ? "success-card" : "warning-card"}>
              {notice}
            </div>
          )}

          <div className="layer-list">
            {recentProjects.length === 0 && (
              <div className="placeholder-card">
                还没有最近记录。先在绘图精灵或拼图器里打开/保存一次项目，这里就会开始积累。
              </div>
            )}

            {recentProjects.map((entry) => (
              <button
                className="layer-item recent-item"
                disabled={activeRecentId === entry.id}
                key={entry.id}
                onClick={() => void reopenRecent(entry)}
                type="button"
              >
                <strong>{entry.title}</strong>
                <span>{entry.detail}</span>
                <span className="recent-meta">
                  {entry.mode === "wizard" ? "绘图精灵" : "拼图器"} ·{" "}
                  {entry.kind === "data" ? "数据文件" : "项目文件"} · {formatRecentTimestamp(entry.updated_at)}
                </span>
              </button>
            ))}
          </div>
        </article>
      </section>

      <aside className="desk-context">
        <article className="context-card">
          <div className="context-card-head">
            <div>
              <h3>4.x 项目观</h3>
              <p>项目页现在已经不只是说明页，而是承担“最近项目恢复”和“双工作流切换”的入口。</p>
            </div>
          </div>
          <div className="context-list">
            <div className="context-row">
              <span>最近记录</span>
              <strong>{recentProjects.length}</strong>
            </div>
            <div className="context-row">
              <span>绘图结果</span>
              <strong>{wizard.outputs.length}</strong>
            </div>
            <div className="context-row">
              <span>拼图图层</span>
              <strong>{composer.project.panels.length}</strong>
            </div>
          </div>
        </article>

        <article className="context-card">
          <div className="context-card-head">
            <div>
              <h3>使用方式</h3>
              <p>让项目页做“恢复现场”的事，而不是重新造一套笨重的资源管理器。</p>
            </div>
          </div>
          <ul className="bullet-list">
            <li>单图出图继续走绘图精灵。</li>
            <li>拼版和画布编辑继续走拼图器。</li>
            <li>最近记录优先服务于快速回到上一次工作现场。</li>
          </ul>
        </article>
      </aside>
    </div>
  );
}
