import { useState } from "react";

import { AppIcon } from "../../components/AppIcon";
import { mockPlotRefineData } from "../data/mockPlotRefineData";
import { MockFigureThumbnail, MockLineChart } from "../components/MockCharts";

export function MockPlotRefine() {
  const [previewMode, setPreviewMode] = useState(mockPlotRefineData.previewModes[0]);

  return (
    <section className="mock-screen">
      <header className="mock-screen-header">
        <div>
          <p className="mock-kicker">Figure lab</p>
          <h1 className="mock-screen-title">Preview-dominant chart workspace with an attached export bar.</h1>
          <p className="mock-screen-copy">
            The preview now owns the screen. Inspector controls stay compact, and export remains
            visually attached to the figure workflow instead of floating off as a separate page.
          </p>
        </div>
        <div className="mock-header-note">{mockPlotRefineData.datasetSummary}</div>
      </header>

      <div className="mock-refine-layout">
        <article className="mock-panel mock-refine-preview-panel">
          <div className="mock-preview-toolbar">
            <div>
              <span className="mock-pill is-accent">{mockPlotRefineData.templateLabel}</span>
              <h2>{mockPlotRefineData.figureLabel}</h2>
            </div>
            <div className="mock-segmented">
              {mockPlotRefineData.previewModes.map((item) => (
                <button
                  key={item}
                  type="button"
                  className={item === previewMode ? "is-active" : ""}
                  onClick={() => setPreviewMode(item)}
                >
                  {item}
                </button>
              ))}
            </div>
          </div>

          <div className="mock-figure-workspace">
            <div className="mock-figure-paper is-large">
              <MockLineChart series={mockPlotRefineData.preview.series} band={mockPlotRefineData.preview.band} />
            </div>

            <div className="mock-filmstrip">
              {mockPlotRefineData.filmstrip.map((item) => (
                <button key={item.label} type="button" className="mock-filmstrip-item">
                  <MockFigureThumbnail
                    kind={item.mode}
                    series={mockPlotRefineData.preview.series}
                    band={mockPlotRefineData.preview.band}
                    className="mock-thumbnail is-tiny"
                  />
                  <span>{item.label}</span>
                </button>
              ))}
            </div>
          </div>

          <footer className="mock-export-bar">
            <div className="mock-export-copy">
              <p className="mock-kicker">Export bundle</p>
              <strong>{mockPlotRefineData.exportSummary.preset}</strong>
              <span>{mockPlotRefineData.exportSummary.outputPath}</span>
              <small>{mockPlotRefineData.exportSummary.bundleNote}</small>
            </div>
            <div className="mock-export-actions">
              <button type="button" className="mock-button">
                <AppIcon name="check" />
                Readiness check
              </button>
              <button type="button" className="mock-button is-primary">
                <AppIcon name="export" />
                Export bundle
              </button>
            </div>
          </footer>
        </article>

        <aside className="mock-panel mock-refine-rail">
          <div className="mock-panel-head compact">
            <div>
              <span className="mock-pill">Inspector</span>
              <h2>Compact figure settings</h2>
            </div>
          </div>

          <div className="mock-inspector-section">
            <span className="mock-sidebar-label">Figure defaults</span>
            <dl className="mock-role-list">
              <div>
                <dt>Size</dt>
                <dd>{mockPlotRefineData.inspector.size}</dd>
              </div>
              <div>
                <dt>Style</dt>
                <dd>{mockPlotRefineData.inspector.style}</dd>
              </div>
              <div>
                <dt>Palette</dt>
                <dd>{mockPlotRefineData.inspector.palette}</dd>
              </div>
            </dl>
          </div>

          <div className="mock-inspector-section">
            <span className="mock-sidebar-label">Axes and legend</span>
            <div className="mock-control-stack">
              <label>
                <span>X scale</span>
                <select defaultValue={mockPlotRefineData.inspector.xScale}>
                  <option>Linear</option>
                  <option>Log</option>
                </select>
              </label>
              <label>
                <span>Y scale</span>
                <select defaultValue={mockPlotRefineData.inspector.yScale}>
                  <option>Linear</option>
                  <option>Log</option>
                </select>
              </label>
              <label>
                <span>Markers</span>
                <select defaultValue={mockPlotRefineData.inspector.markerMode}>
                  <option>Every point</option>
                  <option>Every other point</option>
                  <option>Hidden</option>
                </select>
              </label>
              <label>
                <span>Legend</span>
                <select defaultValue={mockPlotRefineData.inspector.legendPlacement}>
                  <option>Upper right</option>
                  <option>Lower left</option>
                  <option>Outside</option>
                </select>
              </label>
            </div>
          </div>

          <div className="mock-inspector-section">
            <span className="mock-sidebar-label">Readiness</span>
            <ul className="mock-bullet-list">
              {mockPlotRefineData.readinessChecks.map((item) => (
                <li key={item}>{item}</li>
              ))}
            </ul>
          </div>

          <div className="mock-inspector-note">
            <p>{mockPlotRefineData.preview.note}</p>
          </div>
        </aside>
      </div>
    </section>
  );
}
