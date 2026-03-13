import { useState } from "react";

import { loadComposerProjectFile, loadWizardDataFile, loadWizardProjectFile } from "../lib/project-io";
import { useComposerStore, useWizardStore, useWorkbenchStore } from "../lib/store";
import type { RecentProjectEntry, WorkbenchMeta } from "../lib/types";
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
              <div className="card-kicker">最近</div>
              <h2>最近打开的输入与排版</h2>
              <p>单图流程默认直接处理数据文件；只有拼图器才需要显式保存项目。</p>
            </div>
          </div>
        </article>

        <article className="work-card section-card">
          <div className="section-head">
            <div>
              <div className="card-kicker">记录</div>
              <h2>最近工作入口</h2>
              <p>这里会记住最近打开的数据文件和拼图文件，点一下就能回去继续。</p>
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
                还没有最近记录。先打开一份数据文件，或者在拼图器里载入一次排版文件，这里就会开始积累。
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
              <h3>当前会话</h3>
            </div>
          </div>
          <div className="context-list">
            <div className="context-row">
              <span>绘图文件</span>
              <strong>{wizard.inputPath ? formatLeaf(wizard.inputPath) : "未加载"}</strong>
            </div>
            <div className="context-row">
              <span>最近记录</span>
              <strong>{recentProjects.length}</strong>
            </div>
            <div className="context-row">
              <span>绘图步骤</span>
              <strong>{getWizardStepLabel(wizard.step)}</strong>
            </div>
            <div className="context-row">
              <span>拼图对象</span>
              <strong>{composer.project.panels.length + composer.project.texts.length}</strong>
            </div>
          </div>
          <div className="step-actions compact-actions">
            <button className="primary-button" onClick={() => onNavigate("wizard")} type="button">
              回到绘图
            </button>
            <button className="ghost-button" onClick={() => onNavigate("composer")} type="button">
              回到拼图
            </button>
          </div>
        </article>

        {wizard.outputs.length > 0 && (
          <article className="context-card">
            <div className="context-card-head">
              <div>
                <h3>最近导出</h3>
              </div>
            </div>
            <div className="context-list">
              <div className="context-row">
                <span>输出数</span>
                <strong>{wizard.outputs.length}</strong>
              </div>
              <div className="context-row">
                <span>最新结果</span>
                <strong>{formatLeaf(wizard.outputs[wizard.outputs.length - 1] ?? "-")}</strong>
              </div>
            </div>
          </article>
        )}
      </aside>
    </div>
  );
}
