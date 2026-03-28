import {
  mockRefineExportFormats,
  mockRefineHeader,
  mockRefineInspectorSections,
  mockRefineSeries,
  type MockSeries,
} from "../data/mockPlotRefineData";

const STAGE_WIDTH = 760;
const STAGE_HEIGHT = 430;
const STAGE_MARGIN = { top: 36, right: 30, bottom: 58, left: 72 };
const MIN_X = 0.1;
const MAX_X = 100;
const MIN_Y = 0;
const MAX_Y = 5.5;
const X_TICKS = [0.1, 1, 10, 100];
const Y_TICKS = [0, 1, 2, 3, 4, 5];
const PREVIEW_TOOL_ACTIONS = ["Fit", "100%", "Guides"];

function scaleX(value: number) {
  const innerWidth = STAGE_WIDTH - STAGE_MARGIN.left - STAGE_MARGIN.right;
  const logMin = Math.log10(MIN_X);
  const logMax = Math.log10(MAX_X);
  const ratio = (Math.log10(value) - logMin) / (logMax - logMin);
  return STAGE_MARGIN.left + ratio * innerWidth;
}

function scaleY(value: number) {
  const innerHeight = STAGE_HEIGHT - STAGE_MARGIN.top - STAGE_MARGIN.bottom;
  const ratio = (value - MIN_Y) / (MAX_Y - MIN_Y);
  return STAGE_HEIGHT - STAGE_MARGIN.bottom - ratio * innerHeight;
}

function buildPolyline(series: MockSeries) {
  return series.points
    .map((point) => `${scaleX(point.x).toFixed(1)},${scaleY(point.y).toFixed(1)}`)
    .join(" ");
}

function RefineChart() {
  return (
    <svg
      className="mock-refine__chart-svg"
      viewBox={`0 0 ${STAGE_WIDTH} ${STAGE_HEIGHT}`}
      role="img"
      aria-label="Figure preview showing storage and loss modulus across frequency"
    >
      <rect
        x="0"
        y="0"
        width={STAGE_WIDTH}
        height={STAGE_HEIGHT}
        rx="28"
        className="mock-refine__stage-bg"
      />

      {Y_TICKS.map((tick) => (
        <line
          key={`y-grid-${tick}`}
          x1={STAGE_MARGIN.left}
          y1={scaleY(tick)}
          x2={STAGE_WIDTH - STAGE_MARGIN.right}
          y2={scaleY(tick)}
          className="mock-refine__grid-line"
        />
      ))}

      {X_TICKS.map((tick) => (
        <line
          key={`x-grid-${tick}`}
          x1={scaleX(tick)}
          y1={STAGE_MARGIN.top}
          x2={scaleX(tick)}
          y2={STAGE_HEIGHT - STAGE_MARGIN.bottom}
          className="mock-refine__grid-line"
        />
      ))}

      <line
        x1={STAGE_MARGIN.left}
        y1={STAGE_MARGIN.top}
        x2={STAGE_MARGIN.left}
        y2={STAGE_HEIGHT - STAGE_MARGIN.bottom}
        className="mock-refine__axis"
      />
      <line
        x1={STAGE_MARGIN.left}
        y1={STAGE_HEIGHT - STAGE_MARGIN.bottom}
        x2={STAGE_WIDTH - STAGE_MARGIN.right}
        y2={STAGE_HEIGHT - STAGE_MARGIN.bottom}
        className="mock-refine__axis"
      />

      {mockRefineSeries.map((series) => (
        <g key={series.id}>
          <polyline
            points={buildPolyline(series)}
            fill="none"
            stroke={series.color}
            strokeWidth="4"
            strokeLinejoin="round"
            strokeLinecap="round"
          />
          {series.points.map((point) => (
            <circle
              key={`${series.id}-${point.x}`}
              cx={scaleX(point.x)}
              cy={scaleY(point.y)}
              r="5"
              fill={series.color}
              stroke="rgba(255,255,255,0.92)"
              strokeWidth="2"
            />
          ))}
        </g>
      ))}

      {Y_TICKS.map((tick) => (
        <text
          key={`y-label-${tick}`}
          x={STAGE_MARGIN.left - 16}
          y={scaleY(tick) + 5}
          className="mock-refine__tick"
          textAnchor="end"
        >
          {tick}
        </text>
      ))}

      {X_TICKS.map((tick) => (
        <text
          key={`x-label-${tick}`}
          x={scaleX(tick)}
          y={STAGE_HEIGHT - STAGE_MARGIN.bottom + 28}
          className="mock-refine__tick"
          textAnchor="middle"
        >
          {tick}
        </text>
      ))}

      <text
        x={STAGE_WIDTH / 2}
        y={STAGE_HEIGHT - 12}
        className="mock-refine__axis-label"
        textAnchor="middle"
      >
        Frequency (Hz)
      </text>
      <text
        x="20"
        y={STAGE_HEIGHT / 2}
        className="mock-refine__axis-label"
        textAnchor="middle"
        transform={`rotate(-90 20 ${STAGE_HEIGHT / 2})`}
      >
        Modulus (MPa)
      </text>

      <g transform="translate(520 46)">
        <rect
          x="0"
          y="0"
          width="186"
          height="74"
          rx="20"
          className="mock-refine__legend-bg"
        />
        {mockRefineSeries.map((series, index) => (
          <g key={series.id} transform={`translate(18 ${24 + index * 24})`}>
            <circle cx="0" cy="0" r="5" fill={series.color} />
            <text x="14" y="5" className="mock-refine__legend-text">
              {series.label}
            </text>
          </g>
        ))}
      </g>

      <g transform="translate(82 54)">
        <rect
          x="0"
          y="0"
          width="230"
          height="52"
          rx="18"
          className="mock-refine__annotation-bg"
        />
        <text x="18" y="22" className="mock-refine__annotation-title">
          Analytical note
        </text>
        <text x="18" y="38" className="mock-refine__annotation-copy">
          Aging shifts G&apos; upward across the full sweep.
        </text>
      </g>
    </svg>
  );
}

export function MockPlotRefine() {
  return (
    <section className="mock-screen mock-refine">
      <div className="mock-panel mock-refine__intro">
        <div>
          <p className="mock-panel__eyebrow">Figure workspace</p>
          <h2>{mockRefineHeader.figureName}</h2>
          <p>{mockRefineHeader.datasetName}</p>
        </div>
        <div className="mock-refine__intro-meta">
          <span className="mock-chip mock-chip--accent">{mockRefineHeader.status}</span>
          <span className="mock-chip">{mockRefineHeader.lastUpdated}</span>
        </div>
      </div>

      <div className="mock-refine__layout">
        <div className="mock-refine__stage-column">
          <div className="mock-panel mock-refine__stage">
            <div className="mock-panel__header">
              <div>
                <p className="mock-panel__eyebrow">Preview stage</p>
                <h3>Publication-ready figure preview</h3>
              </div>
              <div className="mock-chip-row">
                <span className="mock-chip">120 x 55 mm</span>
                <span className="mock-chip">log x</span>
                <span className="mock-chip">2 series</span>
              </div>
            </div>
            <div className="mock-refine__preview-toolbar">
              <div className="mock-refine__toolbar-actions">
                {PREVIEW_TOOL_ACTIONS.map((action, index) => (
                  <button
                    key={action}
                    className={`mock-refine__toolbar-button${
                      index === 0 ? " is-active" : ""
                    }`}
                    type="button"
                  >
                    {action}
                  </button>
                ))}
              </div>
              <div className="mock-refine__toolbar-meta">
                <span>Axis frame locked</span>
                <span>Legend inline</span>
              </div>
            </div>
            <RefineChart />
            <div className="mock-refine__stage-export">
              <div className="mock-refine__export-copy">
                <p className="mock-panel__eyebrow">Export</p>
                <h3>Keep export attached to the active figure</h3>
                <div className="mock-refine__filename">freq_sweep_dual_modulus_curve</div>
              </div>
              <div className="mock-refine__export-controls">
                <div className="mock-chip-row">
                  {mockRefineExportFormats.map((format, index) => (
                    <span
                      key={format}
                      className={`mock-chip${
                        index === 0 ? " mock-chip--accent" : " mock-chip--subtle"
                      }`}
                    >
                      {format}
                    </span>
                  ))}
                </div>
                <button className="mock-button mock-button--primary" type="button">
                  Export Figure Bundle
                </button>
              </div>
            </div>
          </div>
        </div>

        <div className="mock-panel mock-refine__inspector">
          <div className="mock-panel__header">
            <div>
              <p className="mock-panel__eyebrow">Inspector</p>
              <h3>Compact figure controls</h3>
            </div>
          </div>
          <div className="mock-refine__inspector-sections">
            {mockRefineInspectorSections.map((section) => (
              <section key={section.title} className="mock-refine__inspector-section">
                <p className="mock-panel__eyebrow">{section.title}</p>
                <div className="mock-refine__inspector-items">
                  {section.items.map((item) => (
                    <div key={item.label} className="mock-refine__inspector-item">
                      <span>{item.label}</span>
                      <strong>{item.value}</strong>
                    </div>
                  ))}
                </div>
              </section>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
