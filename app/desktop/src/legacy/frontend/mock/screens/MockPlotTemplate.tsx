import { useState } from "react";

import { mockScatterSeries } from "../data/mockChartData";
import { mockPlotTemplateData } from "../data/mockPlotTemplateData";
import { MockFigureThumbnail, MockLineChart, MockScatterChart } from "../components/MockCharts";

export function MockPlotTemplate() {
  const [previewMode, setPreviewMode] = useState(mockPlotTemplateData.previewModes[0]);

  return (
    <section className="mock-screen">
      <header className="mock-screen-header">
        <div>
          <p className="mock-kicker">Template studio</p>
          <h1 className="mock-screen-title">Recommendation-first selection with a real preview surface.</h1>
          <p className="mock-screen-copy">
            The strongest recommendation leads the left rail, while the preview stage on the right
            remains large enough to judge hierarchy, legend fit, and panel readiness.
          </p>
        </div>
        <div className="mock-header-note">{mockPlotTemplateData.datasetLabel}</div>
      </header>

      <div className="mock-template-layout">
        <aside className="mock-template-rail">
          <article className="mock-panel mock-featured-card">
            <div className="mock-panel-head">
              <div>
                <span className="mock-pill is-accent">{mockPlotTemplateData.featured.fit}</span>
                <h2>{mockPlotTemplateData.featured.label}</h2>
              </div>
              <span className="mock-panel-meta">{mockPlotTemplateData.featured.category}</span>
            </div>

            <div className="mock-featured-card-body">
              <MockFigureThumbnail
                kind={mockPlotTemplateData.featured.thumbnail}
                series={mockPlotTemplateData.preview.series}
                band={mockPlotTemplateData.preview.band}
                className="mock-thumbnail"
              />
              <div className="mock-featured-copy">
                <h3>{mockPlotTemplateData.featured.title}</h3>
                <p>{mockPlotTemplateData.featured.copy}</p>
                <ul className="mock-bullet-list">
                  {mockPlotTemplateData.featured.bullets.map((item) => (
                    <li key={item}>{item}</li>
                  ))}
                </ul>
                <button type="button" className="mock-button is-primary">
                  Use recommended template
                </button>
              </div>
            </div>
          </article>

          <article className="mock-panel">
            <div className="mock-panel-head compact">
              <div>
                <span className="mock-pill">Alternates</span>
                <h2>Other compatible templates</h2>
              </div>
            </div>
            <div className="mock-alternate-list">
              {mockPlotTemplateData.alternates.map((item) => (
                <button key={item.label} type="button" className="mock-alternate-card">
                  <MockFigureThumbnail
                    kind={item.thumbnail}
                    series={mockPlotTemplateData.preview.series}
                    band={mockPlotTemplateData.preview.band}
                    scatterSeries={mockScatterSeries}
                    className="mock-thumbnail is-small"
                  />
                  <span className="mock-alternate-copy">
                    <strong>{item.label}</strong>
                    <small>
                      {item.fit} · {item.category}
                    </small>
                    <span>{item.reason}</span>
                  </span>
                </button>
              ))}
            </div>
          </article>

          <article className="mock-panel">
            <div className="mock-panel-head compact">
              <div>
                <span className="mock-pill">Unavailable</span>
              </div>
            </div>
            <p className="mock-panel-copy">{mockPlotTemplateData.compatibilitySummary}</p>
            <div className="mock-chip-row">
              {mockPlotTemplateData.unavailable.map((item) => (
                <span key={item} className="mock-chip is-muted">
                  {item}
                </span>
              ))}
            </div>
          </article>
        </aside>

        <article className="mock-panel mock-preview-panel">
          <div className="mock-panel-head">
            <div>
              <span className="mock-pill is-accent">{previewMode}</span>
              <h2>{mockPlotTemplateData.preview.title}</h2>
            </div>
            <div className="mock-segmented">
              {mockPlotTemplateData.previewModes.map((item) => (
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

          <div className="mock-preview-stage">
            <div className="mock-figure-paper">
              {previewMode === "Small panel check" ? (
                <MockScatterChart series={mockScatterSeries} />
              ) : (
                <MockLineChart series={mockPlotTemplateData.preview.series} band={mockPlotTemplateData.preview.band} />
              )}
            </div>
          </div>

          <div className="mock-preview-footnotes">
            <p>{mockPlotTemplateData.preview.caption}</p>
            <div className="mock-chip-row">
              {mockPlotTemplateData.preview.insightChips.map((item) => (
                <span key={item} className="mock-chip">
                  {item}
                </span>
              ))}
            </div>
          </div>
        </article>
      </div>
    </section>
  );
}
