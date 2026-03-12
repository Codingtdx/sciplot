import { useMemo, useRef } from "react";
import { Group, Image, Layer, Rect, Stage, Text, Transformer } from "react-konva";
import useImage from "use-image";

import type { ComposerPanel, ComposerText } from "../lib/types";

const SCALE = 4;
const GRID_MM = 0.5;
const GRID_COLUMNS = 3;
const GRID_ROWS = 3;
const CELL_WIDTH_MM = 60;

function snapMm(value: number): number {
  return Math.round(value / GRID_MM) * GRID_MM;
}

function panelOverlaps(panel: ComposerPanel, others: ComposerPanel[]) {
  return others.some((other) => {
    if (other.id === panel.id) {
      return false;
    }
    return !(
      panel.x_mm + panel.w_mm <= other.x_mm ||
      other.x_mm + other.w_mm <= panel.x_mm ||
      panel.y_mm + panel.h_mm <= other.y_mm ||
      other.y_mm + other.h_mm <= panel.y_mm
    );
  });
}

function cellHeightMm(heightMm: number) {
  return heightMm / GRID_ROWS;
}

function clampPanelToCanvas(panel: ComposerPanel, widthMm: number, heightMm: number): ComposerPanel {
  return {
    ...panel,
    x_mm: Math.max(0, Math.min(widthMm - panel.w_mm, panel.x_mm)),
    y_mm: Math.max(0, Math.min(heightMm - panel.h_mm, panel.y_mm)),
  };
}

function snapGraphPanel(panel: ComposerPanel, widthMm: number, heightMm: number): ComposerPanel {
  const rowHeight = cellHeightMm(heightMm);
  const column = Math.max(0, Math.min(GRID_COLUMNS - 1, Math.round(panel.x_mm / CELL_WIDTH_MM)));
  const row = Math.max(0, Math.min(GRID_ROWS - 1, Math.round(panel.y_mm / rowHeight)));
  return clampPanelToCanvas(
    {
      ...panel,
      x_mm: column * CELL_WIDTH_MM,
      y_mm: row * rowHeight,
    },
    widthMm,
    heightMm,
  );
}

function resolveAutoLabels(panels: ComposerPanel[], enabled: boolean) {
  if (!enabled) {
    return Object.fromEntries(panels.map((panel) => [panel.id, panel.label ?? ""]));
  }
  const ordered = [...panels].sort((a, b) => {
    if (Math.abs(a.y_mm - b.y_mm) > 0.25) {
      return a.y_mm - b.y_mm;
    }
    if (Math.abs(a.x_mm - b.x_mm) > 0.25) {
      return a.x_mm - b.x_mm;
    }
    return a.id.localeCompare(b.id);
  });
  return Object.fromEntries(
    ordered.map((panel, index) => [panel.id, String.fromCharCode("a".charCodeAt(0) + index)]),
  );
}

function PanelNode({
  panel,
  selected,
  displayLabel,
  imageSrc,
  onSelect,
  onChange,
}: {
  panel: ComposerPanel;
  selected: boolean;
  displayLabel: string;
  imageSrc: string | null;
  onSelect(): void;
  onChange(panel: ComposerPanel): boolean;
}) {
  const [image] = useImage(imageSrc ?? "");
  const groupRef = useRef<any>(null);
  const trRef = useRef<any>(null);

  if (panel.kind === "asset" && selected && trRef.current && groupRef.current) {
    trRef.current.nodes([groupRef.current]);
    trRef.current.getLayer()?.batchDraw();
  }

  return (
    <>
      <Group
        ref={groupRef}
        x={panel.x_mm * SCALE}
        y={panel.y_mm * SCALE}
        draggable={!panel.locked}
        onClick={onSelect}
        onTap={onSelect}
        onDragEnd={(event) => {
          const accepted = onChange({
            ...panel,
            x_mm: event.target.x() / SCALE,
            y_mm: event.target.y() / SCALE,
          });
          if (!accepted) {
            event.target.position({ x: panel.x_mm * SCALE, y: panel.y_mm * SCALE });
            event.target.getLayer()?.batchDraw();
          }
        }}
        onTransformEnd={() => {
          if (panel.kind !== "asset") {
            return;
          }
          const node = groupRef.current;
          const scaleX = node.scaleX();
          const scaleY = node.scaleY();
          node.scaleX(1);
          node.scaleY(1);
          const accepted = onChange({
            ...panel,
            x_mm: node.x() / SCALE,
            y_mm: node.y() / SCALE,
            w_mm: Math.max(10, panel.w_mm * scaleX),
            h_mm: Math.max(10, panel.h_mm * scaleY),
          });
          if (!accepted) {
            node.x(panel.x_mm * SCALE);
            node.y(panel.y_mm * SCALE);
            node.width(panel.w_mm * SCALE);
            node.height(panel.h_mm * SCALE);
            node.getLayer()?.batchDraw();
          }
        }}
      >
        <Rect
          x={0}
          y={0}
          width={panel.w_mm * SCALE}
          height={panel.h_mm * SCALE}
          fill="#ffffff"
          stroke={selected ? "#2563eb" : "#d5dce7"}
          strokeWidth={selected ? 2 : 1}
          cornerRadius={8}
        />
        {image && (
          <Image
            image={image}
            x={0}
            y={0}
            width={panel.w_mm * SCALE}
            height={panel.h_mm * SCALE}
            cornerRadius={8}
          />
        )}
        {displayLabel && (
          <Text
            text={displayLabel}
            x={10}
            y={8}
            fontStyle="bold"
            fontSize={18}
            fill="#0f172a"
          />
        )}
      </Group>
      {panel.kind === "asset" && selected && (
        <Transformer
          ref={trRef}
          rotateEnabled={false}
          flipEnabled={false}
          keepRatio={false}
          boundBoxFunc={(_, newBox) => {
            if (newBox.width < 60 || newBox.height < 60) {
              return _;
            }
            return newBox;
          }}
        />
      )}
    </>
  );
}

export function ComposerCanvas({
  widthMm,
  heightMm,
  panels,
  texts,
  selectedId,
  thumbnails,
  onSelect,
  onPanelsChange,
  onTextsChange,
  autoLabels,
}: {
  widthMm: number;
  heightMm: number;
  panels: ComposerPanel[];
  texts: ComposerText[];
  selectedId: string | null;
  thumbnails: Record<string, string>;
  onSelect(id: string | null): void;
  onPanelsChange(next: ComposerPanel[]): void;
  onTextsChange(next: ComposerText[]): void;
  autoLabels: boolean;
}) {
  const stageWidth = useMemo(() => widthMm * SCALE, [widthMm]);
  const stageHeight = useMemo(() => heightMm * SCALE, [heightMm]);
  const labels = useMemo(() => resolveAutoLabels(panels, autoLabels), [panels, autoLabels]);
  const rowHeight = useMemo(() => cellHeightMm(heightMm), [heightMm]);

  return (
    <div className="composer-stage-shell">
      <Stage
        width={stageWidth}
        height={stageHeight}
        className="composer-stage"
        onMouseDown={(event) => {
          if (event.target === event.target.getStage()) {
            onSelect(null);
          }
        }}
      >
        <Layer>
          <Rect
            x={0}
            y={0}
            width={stageWidth}
            height={stageHeight}
            fill="#ffffff"
            stroke="#d6deea"
            strokeWidth={1}
            cornerRadius={10}
          />
          {Array.from({ length: GRID_COLUMNS - 1 }, (_, index) => (
            <Rect
              key={`grid-v-${index}`}
              x={(index + 1) * CELL_WIDTH_MM * SCALE}
              y={0}
              width={1}
              height={stageHeight}
              fill="#edf2f7"
            />
          ))}
          {Array.from({ length: GRID_ROWS - 1 }, (_, index) => (
            <Rect
              key={`grid-h-${index}`}
              x={0}
              y={(index + 1) * rowHeight * SCALE}
              width={stageWidth}
              height={1}
              fill="#edf2f7"
            />
          ))}
          {panels.map((panel) => (
            <PanelNode
              key={panel.id}
              displayLabel={labels[panel.id] ?? ""}
              imageSrc={thumbnails[panel.id] ?? null}
              panel={panel}
              selected={selectedId === panel.id}
              onSelect={() => onSelect(panel.id)}
              onChange={(updated) => {
                const clamped =
                  panel.kind === "graph"
                    ? snapGraphPanel(updated, widthMm, heightMm)
                    : clampPanelToCanvas(
                        {
                          ...updated,
                          x_mm: snapMm(updated.x_mm),
                          y_mm: snapMm(updated.y_mm),
                          w_mm: snapMm(updated.w_mm),
                          h_mm: snapMm(updated.h_mm),
                        },
                        widthMm,
                        heightMm,
                      );
                const nextPanels = panels.map((item) => (item.id === panel.id ? clamped : item));
                if (panelOverlaps(clamped, nextPanels)) {
                  return false;
                }
                onPanelsChange(nextPanels);
                return true;
              }}
            />
          ))}
          {texts.map((text) => (
            <Text
              key={text.id}
              draggable
              text={text.text}
              x={text.x_mm * SCALE}
              y={text.y_mm * SCALE}
              fontSize={text.font_size_pt * 1.4}
              fill={selectedId === text.id ? "#1d4ed8" : "#0f172a"}
              fontStyle="bold"
              onClick={() => onSelect(text.id)}
              onTap={() => onSelect(text.id)}
              onDragEnd={(event) => {
                const nextTexts = texts.map((item) =>
                  item.id === text.id
                    ? {
                        ...item,
                        x_mm: snapMm(event.target.x() / SCALE),
                        y_mm: snapMm(event.target.y() / SCALE),
                      }
                    : item,
                );
                onTextsChange(nextTexts);
              }}
            />
          ))}
        </Layer>
      </Stage>
    </div>
  );
}
