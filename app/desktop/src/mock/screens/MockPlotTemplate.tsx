import { useState, type ReactNode } from "react";

import {
  mockTemplateHeader,
  mockTemplateOptions,
  type MockTemplateOption,
} from "../data/mockPlotTemplateData";

type PreviewTone = "primary" | "secondary" | "accent";

function renderFigureFrame(
  width: number,
  height: number,
  innerWidth: number,
  innerHeight: number,
  children: ReactNode,
  large = false,
) {
  const left = large ? 56 : 38;
  const top = large ? 26 : 18;
  const plotWidth = innerWidth;
  const plotHeight = innerHeight;
  const right = left + plotWidth;
  const bottom = top + plotHeight;
  const xTicks = large ? ["0.1", "1", "10", "100"] : ["0.1", "1", "10"];
  const yTicks = large ? ["0", "2", "4", "6"] : ["0", "2", "4"];

  return (
    <svg
      className={`mock-template-svg${large ? " mock-template-svg--large" : ""}`}
      viewBox={`0 0 ${width} ${height}`}
      aria-hidden="true"
    >
      <rect
        x="0.5"
        y="0.5"
        width={width - 1}
        height={height - 1}
        rx={large ? 10 : 8}
        className="mock-template-svg__surface"
      />
      <rect
        x={left}
        y={top}
        width={plotWidth}
        height={plotHeight}
        className="mock-template-svg__plot-frame"
      />
      {[0.25, 0.5, 0.75].map((ratio) => (
        <line
          key={`grid-y-${ratio}`}
          x1={left}
          y1={top + plotHeight * ratio}
          x2={right}
          y2={top + plotHeight * ratio}
          className="mock-template-svg__grid-line"
        />
      ))}
      {[0.2, 0.45, 0.7].map((ratio) => (
        <line
          key={`grid-x-${ratio}`}
          x1={left + plotWidth * ratio}
          y1={top}
          x2={left + plotWidth * ratio}
          y2={bottom}
          className="mock-template-svg__grid-line"
        />
      ))}
      <line
        x1={left}
        y1={bottom}
        x2={right}
        y2={bottom}
        className="mock-template-svg__axis"
      />
      <line
        x1={left}
        y1={top}
        x2={left}
        y2={bottom}
        className="mock-template-svg__axis"
      />
      {xTicks.map((tick, index) => {
        const x = left + (plotWidth / (xTicks.length - 1)) * index;
        return (
          <g key={`xtick-${tick}`}>
            <line
              x1={x}
              y1={bottom}
              x2={x}
              y2={bottom + 4}
              className="mock-template-svg__axis"
            />
            <text x={x} y={bottom + (large ? 22 : 16)} className="mock-template-svg__tick">
              {tick}
            </text>
          </g>
        );
      })}
      {yTicks.map((tick, index) => {
        const y = bottom - (plotHeight / (yTicks.length - 1)) * index;
        return (
          <g key={`ytick-${tick}`}>
            <line
              x1={left - 4}
              y1={y}
              x2={left}
              y2={y}
              className="mock-template-svg__axis"
            />
            <text
              x={left - (large ? 10 : 8)}
              y={y + 4}
              className="mock-template-svg__tick mock-template-svg__tick--y"
            >
              {tick}
            </text>
          </g>
        );
      })}
      <text
        x={(left + right) / 2}
        y={height - (large ? 10 : 8)}
        className="mock-template-svg__label"
      >
        Frequency (Hz)
      </text>
      <text
        x={large ? 18 : 12}
        y={top + plotHeight / 2}
        className="mock-template-svg__label"
        transform={`rotate(-90 ${large ? 18 : 12} ${top + plotHeight / 2})`}
      >
        Modulus (MPa)
      </text>
      {children}
    </svg>
  );
}

function renderTemplateThumbnail(
  templateId: string,
  tone: PreviewTone = "primary",
) {
  const lineClass =
    tone === "accent"
      ? "mock-template-svg__line--accent"
      : tone === "secondary"
        ? "mock-template-svg__line--secondary"
        : "mock-template-svg__line";

  switch (templateId) {
    case "point-line-comparison":
      return (
        renderFigureFrame(
          240,
          160,
          174,
          102,
          <>
            <path
              d="M46 106 L76 94 L104 82 L132 66 L164 52 L202 40"
              className={lineClass}
            />
            {[46, 76, 104, 132, 164, 202].map((x, index) => (
              <circle
                key={`${templateId}-${x}`}
                cx={x}
                cy={[106, 94, 82, 66, 52, 40][index]}
                r="3.8"
                className="mock-template-svg__dot"
              />
            ))}
          </>,
        )
      );
    case "band-summary":
      return (
        renderFigureFrame(
          240,
          160,
          174,
          102,
          <>
            <path
              d="M46 110 C76 92 106 82 134 72 C162 62 184 54 202 44 L202 66 C182 76 160 86 132 96 C104 106 78 118 46 126 Z"
              className="mock-template-svg__band"
            />
            <path
              d="M46 118 C76 98 106 86 134 76 C162 66 184 56 202 48"
              className={lineClass}
            />
          </>,
        )
      );
    case "scatter-sweep":
      return (
        renderFigureFrame(
          240,
          160,
          174,
          102,
          <>
            {[48, 70, 88, 116, 132, 158, 184, 202].map((x, index) => (
              <circle
                key={`${templateId}-${x}`}
                cx={x}
                cy={[106, 94, 100, 84, 72, 62, 54, 42][index]}
                r="4.3"
                className={
                  index % 2 === 0
                    ? "mock-template-svg__dot"
                    : "mock-template-svg__dot mock-template-svg__dot--secondary"
                }
              />
            ))}
          </>,
        )
      );
    case "twin-modulus-curve":
    default:
      return (
        renderFigureFrame(
          240,
          160,
          174,
          102,
          <>
            <path
              d="M46 104 C74 98 100 88 126 68 C152 50 176 42 202 34"
              className={lineClass}
            />
            <path
              d="M46 118 C76 112 102 104 128 92 C154 82 180 74 202 68"
              className="mock-template-svg__line--secondary"
            />
          </>,
        )
      );
  }
}

function renderPreviewFigure(template: MockTemplateOption) {
  switch (template.id) {
    case "point-line-comparison":
      return renderFigureFrame(
        520,
        340,
        416,
        228,
        <>
          <path
            d="M72 236 L132 210 L186 188 L248 152 L318 126 L440 92"
            className="mock-template-svg__line--accent"
          />
          {[72, 132, 186, 248, 318, 440].map((x, index) => (
            <circle
              key={`${template.id}-preview-${x}`}
              cx={x}
              cy={[236, 210, 188, 152, 126, 92][index]}
              r="5"
              className="mock-template-svg__dot"
            />
          ))}
        </>,
        true,
      );
    case "band-summary":
      return renderFigureFrame(
        520,
        340,
        416,
        228,
        <>
          <path
            d="M72 250 C144 206 220 176 292 152 C344 134 390 112 440 92 L440 130 C392 148 344 170 288 188 C212 212 144 236 72 272 Z"
            className="mock-template-svg__band"
          />
          <path
            d="M72 260 C144 216 220 186 292 164 C344 146 390 122 440 102"
            className="mock-template-svg__line"
          />
        </>,
        true,
      );
    case "scatter-sweep":
      return renderFigureFrame(
        520,
        340,
        416,
        228,
        <>
          {[84, 118, 156, 194, 238, 286, 334, 386, 436].map((x, index) => (
            <circle
              key={`${template.id}-preview-${x}`}
              cx={x}
              cy={[244, 226, 232, 198, 184, 162, 142, 128, 104][index]}
              r="5.2"
              className={
                index % 2 === 0
                  ? "mock-template-svg__dot"
                  : "mock-template-svg__dot mock-template-svg__dot--secondary"
              }
            />
          ))}
        </>,
        true,
      );
    case "twin-modulus-curve":
    default:
      return renderFigureFrame(
        520,
        340,
        416,
        228,
        <>
          <path
            d="M72 236 C146 220 202 194 258 150 C314 108 372 84 440 72"
            className="mock-template-svg__line"
          />
          <path
            d="M72 270 C142 258 200 242 258 218 C314 194 372 176 440 158"
            className="mock-template-svg__line--secondary"
          />
          <g className="mock-template-svg__legend">
            <rect x="334" y="32" width="116" height="54" rx="8" />
            <circle cx="354" cy="52" r="4.5" className="mock-template-svg__dot" />
            <text x="366" y="56" className="mock-template-svg__tick">
              Storage modulus
            </text>
            <circle
              cx="354"
              cy="70"
              r="4.5"
              className="mock-template-svg__dot mock-template-svg__dot--secondary"
            />
            <text x="366" y="74" className="mock-template-svg__tick">
              Loss modulus
            </text>
          </g>
        </>,
        true,
      );
  }
}

function renderPreview(template: MockTemplateOption) {
  return (
    <div className="mock-template__preview-stage">
      {renderPreviewFigure(template)}
      <div className="mock-template__preview-caption">
        <div>
          <h3>{template.name}</h3>
        </div>
        <span className="mock-template__preview-confidence">{template.confidence}</span>
      </div>
      <div className="mock-template__metrics">
        {template.metrics.slice(0, 3).map((metric) => (
          <div key={metric.label} className="mock-template__metric">
            <span>{metric.label}</span>
            <strong>{metric.value}</strong>
          </div>
        ))}
      </div>
    </div>
  );
}

export function MockPlotTemplate() {
  const [selectedId, setSelectedId] = useState<string>(mockTemplateOptions[0].id);

  const selectedTemplate =
    mockTemplateOptions.find((template) => template.id === selectedId) ??
    mockTemplateOptions[0];
  const [recommendedTemplate, ...alternateTemplates] = mockTemplateOptions;

  return (
    <section className="mock-screen mock-template">
      <div className="mock-template__layout">
        <div className="mock-template__selection-column">
          <div className="mock-panel mock-template__dataset-bar">
            <div className="mock-panel__header">
              <div>
                <h3>{mockTemplateHeader.datasetName}</h3>
              </div>
              <span className="mock-template__intro-meta">{mockTemplateHeader.sheetName}</span>
            </div>
          </div>

          <button
            className={`mock-panel mock-template__recommended${
              selectedTemplate.id === recommendedTemplate.id ? " is-active" : ""
            }`}
            type="button"
            onClick={() => setSelectedId(recommendedTemplate.id)}
          >
            <div className="mock-panel__header">
              <div>
                <h3>{recommendedTemplate.name}</h3>
              </div>
              <span className="mock-template__alternate-meta">{recommendedTemplate.confidence}</span>
            </div>
            <div className="mock-template__recommended-body">
              {renderTemplateThumbnail(recommendedTemplate.id)}
              <div className="mock-template__recommended-copy">
                <strong>{recommendedTemplate.badge}</strong>
              </div>
            </div>
          </button>

          <div className="mock-panel mock-template__alternates">
            <div className="mock-panel__header">
              <div>
                <h3>Alternates</h3>
              </div>
            </div>
            <div className="mock-template__alternate-list">
              {alternateTemplates.map((template) => (
                <button
                  key={template.id}
                  className={`mock-template__alternate${
                    selectedTemplate.id === template.id ? " is-active" : ""
                  }`}
                  type="button"
                  onClick={() => setSelectedId(template.id)}
                >
                  <div className="mock-template__alternate-thumb">
                    {renderTemplateThumbnail(template.id, "secondary")}
                  </div>
                  <div className="mock-template__alternate-copy">
                    <strong>{template.name}</strong>
                  </div>
                  <span className="mock-template__alternate-meta">{template.confidence}</span>
                </button>
              ))}
            </div>
          </div>
        </div>

        <div className="mock-panel mock-template__preview-column">
          {renderPreview(selectedTemplate)}
          <a className="mock-button mock-button--primary" href="#/plot/refine">
            Continue with Selected Template
          </a>
        </div>
      </div>
    </section>
  );
}
