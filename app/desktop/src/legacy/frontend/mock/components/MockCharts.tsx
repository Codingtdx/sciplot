import type { CSSProperties } from "react";

import type { MockBand, MockLineSeries, MockPoint, MockScatterSeries } from "../data/mockChartData";

type ChartKind = "point-line" | "curve" | "band" | "scatter";

function extent(points: MockPoint[]) {
  return points.reduce(
    (acc, point) => ({
      minX: Math.min(acc.minX, point.x),
      maxX: Math.max(acc.maxX, point.x),
      minY: Math.min(acc.minY, point.y),
      maxY: Math.max(acc.maxY, point.y),
    }),
    {
      minX: Number.POSITIVE_INFINITY,
      maxX: Number.NEGATIVE_INFINITY,
      minY: Number.POSITIVE_INFINITY,
      maxY: Number.NEGATIVE_INFINITY,
    },
  );
}

function scalePoint(
  point: MockPoint,
  bounds: { minX: number; maxX: number; minY: number; maxY: number },
  width: number,
  height: number,
  padding: { top: number; right: number; bottom: number; left: number },
) {
  const usableWidth = width - padding.left - padding.right;
  const usableHeight = height - padding.top - padding.bottom;
  const x = padding.left + ((point.x - bounds.minX) / (bounds.maxX - bounds.minX || 1)) * usableWidth;
  const y = height - padding.bottom - ((point.y - bounds.minY) / (bounds.maxY - bounds.minY || 1)) * usableHeight;
  return { x, y };
}

function linePath(
  points: MockPoint[],
  bounds: { minX: number; maxX: number; minY: number; maxY: number },
  width: number,
  height: number,
  padding: { top: number; right: number; bottom: number; left: number },
) {
  return points
    .map((point, index) => {
      const scaled = scalePoint(point, bounds, width, height, padding);
      return `${index === 0 ? "M" : "L"} ${scaled.x.toFixed(2)} ${scaled.y.toFixed(2)}`;
    })
    .join(" ");
}

function bandPath(
  band: MockBand,
  bounds: { minX: number; maxX: number; minY: number; maxY: number },
  width: number,
  height: number,
  padding: { top: number; right: number; bottom: number; left: number },
) {
  const upper = band.upper
    .map((point, index) => {
      const scaled = scalePoint(point, bounds, width, height, padding);
      return `${index === 0 ? "M" : "L"} ${scaled.x.toFixed(2)} ${scaled.y.toFixed(2)}`;
    })
    .join(" ");
  const lower = [...band.lower]
    .reverse()
    .map((point) => {
      const scaled = scalePoint(point, bounds, width, height, padding);
      return `L ${scaled.x.toFixed(2)} ${scaled.y.toFixed(2)}`;
    })
    .join(" ");
  return `${upper} ${lower} Z`;
}

function chartBounds(series: MockLineSeries[], band?: MockBand) {
  const allPoints = series.flatMap((item) => item.points);
  const summary = extent(allPoints);
  if (!band) {
    return summary;
  }
  const bandSummary = extent([...band.lower, ...band.upper]);
  return {
    minX: Math.min(summary.minX, bandSummary.minX),
    maxX: Math.max(summary.maxX, bandSummary.maxX),
    minY: Math.min(summary.minY, bandSummary.minY),
    maxY: Math.max(summary.maxY, bandSummary.maxY),
  };
}

function scatterBounds(series: MockScatterSeries[]) {
  const allPoints = series.flatMap((item) => [...item.points, ...item.trend]);
  return extent(allPoints);
}

export function MockFigureThumbnail({
  kind,
  series,
  band,
  scatterSeries,
  className,
  style,
}: {
  kind: ChartKind;
  series?: MockLineSeries[];
  band?: MockBand;
  scatterSeries?: MockScatterSeries[];
  className?: string;
  style?: CSSProperties;
}) {
  if (kind === "scatter") {
    return (
      <div className={className} style={style}>
        <MockScatterChart series={scatterSeries ?? []} compact />
      </div>
    );
  }

  return (
    <div className={className} style={style}>
      <MockLineChart
        series={series ?? []}
        band={kind === "band" ? band : undefined}
        compact
        showMarkers={kind === "point-line" || kind === "band"}
        showLegend={false}
      />
    </div>
  );
}

export function MockLineChart({
  series,
  band,
  compact = false,
  showLegend = true,
  showMarkers = true,
}: {
  series: MockLineSeries[];
  band?: MockBand;
  compact?: boolean;
  showLegend?: boolean;
  showMarkers?: boolean;
}) {
  const width = compact ? 360 : 900;
  const height = compact ? 220 : 600;
  const padding = compact
    ? { top: 24, right: 22, bottom: 28, left: 38 }
    : { top: 42, right: 38, bottom: 54, left: 74 };
  const bounds = chartBounds(series, band);
  const gridLines = compact ? 4 : 5;
  const ticks = Array.from({ length: gridLines }, (_, index) => index);

  return (
    <svg className="mock-chart-svg" viewBox={`0 0 ${width} ${height}`} role="img" aria-label="Mock line chart">
      <rect x="0" y="0" width={width} height={height} rx={compact ? 22 : 30} fill="#ffffff" />
      {ticks.map((tick) => {
        const ratio = tick / (gridLines - 1 || 1);
        const y = padding.top + ratio * (height - padding.top - padding.bottom);
        return (
          <line
            key={`h-${tick}`}
            x1={padding.left}
            y1={y}
            x2={width - padding.right}
            y2={y}
            stroke="rgba(150, 168, 198, 0.24)"
            strokeWidth="1"
          />
        );
      })}
      {ticks.map((tick) => {
        const ratio = tick / (gridLines - 1 || 1);
        const x = padding.left + ratio * (width - padding.left - padding.right);
        return (
          <line
            key={`v-${tick}`}
            x1={x}
            y1={padding.top}
            x2={x}
            y2={height - padding.bottom}
            stroke="rgba(150, 168, 198, 0.16)"
            strokeWidth="1"
          />
        );
      })}
      <line
        x1={padding.left}
        y1={height - padding.bottom}
        x2={width - padding.right}
        y2={height - padding.bottom}
        stroke="#2c3552"
        strokeWidth={compact ? 1.4 : 1.8}
      />
      <line
        x1={padding.left}
        y1={padding.top}
        x2={padding.left}
        y2={height - padding.bottom}
        stroke="#2c3552"
        strokeWidth={compact ? 1.4 : 1.8}
      />
      {band ? <path d={bandPath(band, bounds, width, height, padding)} fill={band.color} /> : null}
      {series.map((item) => (
        <g key={item.label}>
          <path
            d={linePath(item.points, bounds, width, height, padding)}
            fill="none"
            stroke={item.color}
            strokeWidth={compact ? 3 : 4}
            strokeDasharray={item.dashed ? "10 8" : undefined}
            strokeLinecap="round"
            strokeLinejoin="round"
          />
          {showMarkers && (item.markers ?? !compact)
            ? item.points.map((point, index) => {
                const scaled = scalePoint(point, bounds, width, height, padding);
                return (
                  <circle
                    key={`${item.label}-${index}`}
                    cx={scaled.x}
                    cy={scaled.y}
                    r={compact ? 3.6 : 5.3}
                    fill="#ffffff"
                    stroke={item.color}
                    strokeWidth={compact ? 1.8 : 2.4}
                  />
                );
              })
            : null}
        </g>
      ))}
      {!compact ? (
        <>
          <text x={width / 2} y={height - 16} textAnchor="middle" className="mock-chart-label">
            Frequency (Hz)
          </text>
          <text
            x={18}
            y={height / 2}
            textAnchor="middle"
            transform={`rotate(-90 18 ${height / 2})`}
            className="mock-chart-label"
          >
            Storage modulus (Pa)
          </text>
          <text x={padding.left} y={26} className="mock-chart-caption">
            Frequency sweep comparison
          </text>
        </>
      ) : null}
      {showLegend && !compact ? (
        <g transform={`translate(${width - 240}, 34)`}>
          <rect
            x="0"
            y="0"
            width="204"
            height="102"
            rx="18"
            fill="rgba(248, 251, 255, 0.96)"
            stroke="rgba(170, 184, 210, 0.45)"
          />
          {series.map((item, index) => (
            <g key={item.label} transform={`translate(18 ${24 + index * 26})`}>
              <line
                x1="0"
                y1="0"
                x2="24"
                y2="0"
                stroke={item.color}
                strokeWidth="4"
                strokeDasharray={item.dashed ? "8 6" : undefined}
                strokeLinecap="round"
              />
              <circle cx="12" cy="0" r="4.2" fill="#ffffff" stroke={item.color} strokeWidth="2" />
              <text x="34" y="5" className="mock-chart-legend">
                {item.label}
              </text>
            </g>
          ))}
        </g>
      ) : null}
    </svg>
  );
}

export function MockScatterChart({
  series,
  compact = false,
}: {
  series: MockScatterSeries[];
  compact?: boolean;
}) {
  const width = compact ? 360 : 900;
  const height = compact ? 220 : 600;
  const padding = compact
    ? { top: 24, right: 22, bottom: 28, left: 38 }
    : { top: 42, right: 38, bottom: 54, left: 74 };
  const bounds = scatterBounds(series);
  const ticks = compact ? 4 : 5;

  return (
    <svg className="mock-chart-svg" viewBox={`0 0 ${width} ${height}`} role="img" aria-label="Mock scatter chart">
      <rect x="0" y="0" width={width} height={height} rx={compact ? 22 : 30} fill="#ffffff" />
      {Array.from({ length: ticks }, (_, index) => {
        const ratio = index / (ticks - 1 || 1);
        const y = padding.top + ratio * (height - padding.top - padding.bottom);
        const x = padding.left + ratio * (width - padding.left - padding.right);
        return (
          <g key={index}>
            <line x1={padding.left} y1={y} x2={width - padding.right} y2={y} stroke="rgba(150, 168, 198, 0.22)" />
            <line x1={x} y1={padding.top} x2={x} y2={height - padding.bottom} stroke="rgba(150, 168, 198, 0.16)" />
          </g>
        );
      })}
      <line x1={padding.left} y1={height - padding.bottom} x2={width - padding.right} y2={height - padding.bottom} stroke="#2c3552" strokeWidth={compact ? 1.4 : 1.8} />
      <line x1={padding.left} y1={padding.top} x2={padding.left} y2={height - padding.bottom} stroke="#2c3552" strokeWidth={compact ? 1.4 : 1.8} />
      {series.map((item) => (
        <g key={item.label}>
          <path
            d={linePath(item.trend, bounds, width, height, padding)}
            fill="none"
            stroke={item.color}
            strokeWidth={compact ? 2.8 : 3.6}
            strokeDasharray="9 7"
            strokeLinecap="round"
          />
          {item.points.map((point, index) => {
            const scaled = scalePoint(point, bounds, width, height, padding);
            return (
              <circle
                key={`${item.label}-${index}`}
                cx={scaled.x}
                cy={scaled.y}
                r={compact ? 4.2 : 5.6}
                fill={`${item.color}22`}
                stroke={item.color}
                strokeWidth={compact ? 1.8 : 2.2}
              />
            );
          })}
        </g>
      ))}
    </svg>
  );
}
