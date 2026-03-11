import { useMemo, useRef } from "react";
import { Group, Image, Layer, Rect, Stage, Text, Transformer } from "react-konva";
import useImage from "use-image";

import type { ComposerPanel, ComposerText } from "../lib/types";

const SCALE = 4;
const GRID_MM = 0.5;

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

function PanelNode({
  panel,
  selected,
  imageSrc,
  onSelect,
  onChange,
}: {
  panel: ComposerPanel;
  selected: boolean;
  imageSrc: string | null;
  onSelect(): void;
  onChange(panel: ComposerPanel): void;
}) {
  const [image] = useImage(imageSrc ?? "");
  const groupRef = useRef<any>(null);
  const trRef = useRef<any>(null);

  if (selected && trRef.current && groupRef.current) {
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
          onChange({
            ...panel,
            x_mm: event.target.x() / SCALE,
            y_mm: event.target.y() / SCALE,
          });
        }}
        onTransformEnd={() => {
          const node = groupRef.current;
          const scaleX = node.scaleX();
          const scaleY = node.scaleY();
          node.scaleX(1);
          node.scaleY(1);
          onChange({
            ...panel,
            x_mm: node.x() / SCALE,
            y_mm: node.y() / SCALE,
            w_mm: Math.max(10, panel.w_mm * scaleX),
            h_mm: Math.max(10, panel.h_mm * scaleY),
          });
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
        {panel.label && (
          <Text
            text={panel.label}
            x={10}
            y={8}
            fontStyle="bold"
            fontSize={18}
            fill="#0f172a"
          />
        )}
      </Group>
      {selected && (
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
}) {
  const stageWidth = useMemo(() => widthMm * SCALE, [widthMm]);
  const stageHeight = useMemo(() => heightMm * SCALE, [heightMm]);

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
          {panels.map((panel) => (
            <PanelNode
              key={panel.id}
              imageSrc={thumbnails[panel.id] ?? null}
              panel={panel}
              selected={selectedId === panel.id}
              onSelect={() => onSelect(panel.id)}
              onChange={(updated) => {
                const clamped = {
                  ...updated,
                  x_mm: snapMm(Math.max(0, Math.min(widthMm - updated.w_mm, updated.x_mm))),
                  y_mm: snapMm(Math.max(0, Math.min(heightMm - updated.h_mm, updated.y_mm))),
                  w_mm: snapMm(updated.w_mm),
                  h_mm: snapMm(updated.h_mm),
                };
                const nextPanels = panels.map((item) => (item.id === panel.id ? clamped : item));
                if (panelOverlaps(clamped, nextPanels)) {
                  return;
                }
                onPanelsChange(nextPanels);
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
