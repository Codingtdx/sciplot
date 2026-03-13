import { useMemo, useRef, useState } from "react";
import {
  Group,
  Image,
  Layer,
  Line,
  Rect,
  Stage,
  Text,
  Transformer,
} from "react-konva";
import useImage from "use-image";

import {
  cellRect,
  drawableIdsInRect,
  findRegion,
  moveRegion,
  orderDrawables,
  regionAtCell,
  regionRect,
  regionSlotRect,
  resolveSelectedPanelLabel,
  selectedRegionIdsForObjects,
  textRect,
} from "../lib/composer";
import type { ComposerPanel, ComposerProject, ComposerText } from "../lib/types";

const SCALE = 4;
const GRID_MM = 0.5;
const SNAP_THRESHOLD_MM = 1.8;

type GuideLine = {
  orientation: "vertical" | "horizontal";
  valueMm: number;
};

function nodeOrAncestorHasName(target: any, name: string) {
  return Boolean(target?.hasName?.(name) || target?.findAncestor?.(`.${name}`, true));
}

function snapMm(value: number): number {
  return Math.round(value / GRID_MM) * GRID_MM;
}

function textBounds(text: ComposerText) {
  return textRect(text);
}

function clampRect(
  rect: { x_mm: number; y_mm: number; w_mm: number; h_mm: number },
  project: ComposerProject,
) {
  return {
    ...rect,
    x_mm: Math.max(0, Math.min(project.canvas_width_mm - rect.w_mm, rect.x_mm)),
    y_mm: Math.max(0, Math.min(project.canvas_height_mm - rect.h_mm, rect.y_mm)),
  };
}

function candidateGuides(project: ComposerProject, movingId: string) {
  const vertical = new Set<number>([
    0,
    project.canvas_width_mm / 2,
    project.canvas_width_mm,
    project.layout_grid.frame_x_mm,
    project.layout_grid.frame_x_mm + project.layout_grid.frame_width_mm / 2,
    project.layout_grid.frame_x_mm + project.layout_grid.frame_width_mm,
  ]);
  const horizontal = new Set<number>([
    0,
    project.canvas_height_mm / 2,
    project.canvas_height_mm,
    project.layout_grid.frame_y_mm,
    project.layout_grid.frame_y_mm + project.layout_grid.frame_height_mm / 2,
    project.layout_grid.frame_y_mm + project.layout_grid.frame_height_mm,
  ]);

  project.regions.forEach((region) => {
    const rect = regionRect(project, region);
    vertical.add(rect.x_mm);
    vertical.add(rect.x_mm + rect.w_mm / 2);
    vertical.add(rect.x_mm + rect.w_mm);
    horizontal.add(rect.y_mm);
    horizontal.add(rect.y_mm + rect.h_mm / 2);
    horizontal.add(rect.y_mm + rect.h_mm);
    const slot = regionSlotRect(project, region);
    if (slot) {
      vertical.add(slot.x_mm);
      vertical.add(slot.x_mm + slot.w_mm / 2);
      vertical.add(slot.x_mm + slot.w_mm);
      horizontal.add(slot.y_mm);
      horizontal.add(slot.y_mm + slot.h_mm / 2);
      horizontal.add(slot.y_mm + slot.h_mm);
    }
  });

  project.panels
    .filter((panel) => panel.id !== movingId)
    .forEach((panel) => {
      vertical.add(panel.x_mm);
      vertical.add(panel.x_mm + panel.w_mm / 2);
      vertical.add(panel.x_mm + panel.w_mm);
      horizontal.add(panel.y_mm);
      horizontal.add(panel.y_mm + panel.h_mm / 2);
      horizontal.add(panel.y_mm + panel.h_mm);
    });

  project.texts
    .filter((text) => text.id !== movingId)
    .forEach((text) => {
      const bounds = textBounds(text);
      vertical.add(bounds.x_mm);
      vertical.add(bounds.x_mm + bounds.w_mm / 2);
      vertical.add(bounds.x_mm + bounds.w_mm);
      horizontal.add(bounds.y_mm);
      horizontal.add(bounds.y_mm + bounds.h_mm / 2);
      horizontal.add(bounds.y_mm + bounds.h_mm);
    });

  return { vertical, horizontal };
}

function snapRectWithGuides(
  project: ComposerProject,
  movingId: string,
  rect: { x_mm: number; y_mm: number; w_mm: number; h_mm: number },
) {
  const { vertical, horizontal } = candidateGuides(project, movingId);
  const rectXs = [rect.x_mm, rect.x_mm + rect.w_mm / 2, rect.x_mm + rect.w_mm];
  const rectYs = [rect.y_mm, rect.y_mm + rect.h_mm / 2, rect.y_mm + rect.h_mm];

  let bestX = { delta: Number.POSITIVE_INFINITY, value: rect.x_mm, guide: null as GuideLine | null };
  for (const guide of vertical) {
    for (const edge of rectXs) {
      const delta = guide - edge;
      if (Math.abs(delta) < Math.abs(bestX.delta) && Math.abs(delta) <= SNAP_THRESHOLD_MM) {
        bestX = { delta, value: rect.x_mm + delta, guide: { orientation: "vertical", valueMm: guide } };
      }
    }
  }

  let bestY = { delta: Number.POSITIVE_INFINITY, value: rect.y_mm, guide: null as GuideLine | null };
  for (const guide of horizontal) {
    for (const edge of rectYs) {
      const delta = guide - edge;
      if (Math.abs(delta) < Math.abs(bestY.delta) && Math.abs(delta) <= SNAP_THRESHOLD_MM) {
        bestY = { delta, value: rect.y_mm + delta, guide: { orientation: "horizontal", valueMm: guide } };
      }
    }
  }

  const snapped = clampRect(
    {
      ...rect,
      x_mm: bestX.guide ? bestX.value : snapMm(rect.x_mm),
      y_mm: bestY.guide ? bestY.value : snapMm(rect.y_mm),
    },
    project,
  );

  return {
    rect: snapped,
    guides: [bestX.guide, bestY.guide].filter(Boolean) as GuideLine[],
  };
}

function imageCropForPanel(
  panel: ComposerPanel,
  image: HTMLImageElement | undefined,
) {
  if (!image) {
    return undefined;
  }
  return {
    x: panel.crop_rect.x * image.width,
    y: panel.crop_rect.y * image.height,
    width: panel.crop_rect.width * image.width,
    height: panel.crop_rect.height * image.height,
  };
}

function PanelNode({
  panel,
  project,
  selected,
  transformEnabled,
  displayLabel,
  imageSrc,
  onSelect,
  onDuplicateDragStart,
  consumeSuppressedClick,
  onProjectChange,
  onGuidesChange,
}: {
  panel: ComposerPanel;
  project: ComposerProject;
  selected: boolean;
  transformEnabled: boolean;
  displayLabel: string;
  imageSrc: string | null;
  onSelect(additive: boolean): void;
  onDuplicateDragStart(id: string): string | null;
  consumeSuppressedClick(): boolean;
  onProjectChange(project: ComposerProject): void;
  onGuidesChange(guides: GuideLine[]): void;
}) {
  const [image] = useImage(imageSrc ?? "");
  const groupRef = useRef<any>(null);
  const trRef = useRef<any>(null);
  const activeDragPanelIdRef = useRef(panel.id);

  if (panel.kind === "asset" && transformEnabled && trRef.current && groupRef.current) {
    trRef.current.nodes([groupRef.current]);
    trRef.current.getLayer()?.batchDraw();
  }

  const slotRegion = panel.region_id ? findRegion(project, panel.region_id) : null;

  return (
    <>
      <Group
        name="composer-drawable"
        ref={groupRef}
        x={panel.x_mm * SCALE}
        y={panel.y_mm * SCALE}
        draggable={!panel.locked}
        onClick={(event) => {
          if (consumeSuppressedClick()) {
            return;
          }
          onSelect(Boolean(event.evt.shiftKey || event.evt.metaKey));
        }}
        onTap={() => {
          if (consumeSuppressedClick()) {
            return;
          }
          onSelect(false);
        }}
        onDragStart={(event) => {
          activeDragPanelIdRef.current = panel.id;
          if (panel.kind !== "asset" || !event.evt.altKey) {
            return;
          }
          const duplicateId = onDuplicateDragStart(panel.id);
          if (duplicateId) {
            activeDragPanelIdRef.current = duplicateId;
          }
        }}
        onDragMove={(event) => {
          const activePanelId =
            project.panels.find((item) => item.id === activeDragPanelIdRef.current) != null
              ? activeDragPanelIdRef.current
              : panel.id;
          if (panel.kind === "graph") {
            return;
          }
          const rect = snapRectWithGuides(project, activePanelId, {
            x_mm: event.target.x() / SCALE,
            y_mm: event.target.y() / SCALE,
            w_mm: panel.w_mm,
            h_mm: panel.h_mm,
          });
          event.target.position({ x: rect.rect.x_mm * SCALE, y: rect.rect.y_mm * SCALE });
          onGuidesChange(rect.guides);
        }}
        onDragEnd={(event) => {
          const activePanelId =
            project.panels.find((item) => item.id === activeDragPanelIdRef.current) != null
              ? activeDragPanelIdRef.current
              : panel.id;
          if (panel.kind === "graph") {
            const region = panel.region_id ? findRegion(project, panel.region_id) : null;
            if (!region) {
              event.target.position({ x: panel.x_mm * SCALE, y: panel.y_mm * SCALE });
              activeDragPanelIdRef.current = panel.id;
              return;
            }
            const col = Math.max(
              0,
              Math.min(
                project.layout_grid.columns - region.col_span,
                Math.round((event.target.x() / SCALE - project.layout_grid.frame_x_mm) / project.layout_grid.cell_width_mm),
              ),
            );
            const row = Math.max(
              0,
              Math.min(
                project.layout_grid.rows - region.row_span,
                Math.round((event.target.y() / SCALE - project.layout_grid.frame_y_mm) / project.layout_grid.cell_height_mm),
              ),
            );
            onProjectChange(moveRegion(project, region.id, col, row));
            event.target.position({ x: panel.x_mm * SCALE, y: panel.y_mm * SCALE });
            onGuidesChange([]);
            activeDragPanelIdRef.current = panel.id;
            return;
          }

          const snapped = snapRectWithGuides(project, activePanelId, {
            x_mm: event.target.x() / SCALE,
            y_mm: event.target.y() / SCALE,
            w_mm: panel.w_mm,
            h_mm: panel.h_mm,
          });
          onProjectChange({
            ...project,
            panels: project.panels.map((item) =>
              item.id === activePanelId
                ? {
                    ...item,
                    ...snapped.rect,
                  }
                : item,
            ),
          });
          onGuidesChange([]);
          activeDragPanelIdRef.current = panel.id;
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
          onProjectChange({
            ...project,
            panels: project.panels.map((item) =>
              item.id === panel.id
                ? clampRect(
                    {
                      ...item,
                      x_mm: snapMm(node.x() / SCALE),
                      y_mm: snapMm(node.y() / SCALE),
                      w_mm: Math.max(10, snapMm(panel.w_mm * scaleX)),
                      h_mm: Math.max(10, snapMm(panel.h_mm * scaleY)),
                    },
                    project,
                  )
                : item,
            ) as ComposerProject["panels"],
          });
        }}
      >
        <Rect
          x={0}
          y={0}
          width={panel.w_mm * SCALE}
          height={panel.h_mm * SCALE}
          fill="#ffffff"
          stroke={selected ? "#2563eb" : panel.kind === "graph" ? "#9fb6d6" : "#d5dce7"}
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
            crop={imageCropForPanel(panel, image)}
            cornerRadius={8}
          />
        )}
        {displayLabel && panel.kind === "graph" && (
          <Text
            text={displayLabel}
            x={10}
            y={8}
            fontStyle="bold"
            fontSize={18}
            fill="#0f172a"
          />
        )}
        {slotRegion?.slot_kind === "structure" && panel.kind === "graph" && (
          (() => {
            const slot = regionSlotRect(project, slotRegion);
            if (!slot) {
              return null;
            }
            return (
              <Rect
                x={0}
                y={0}
                width={slot.w_mm * SCALE}
                height={slot.h_mm * SCALE}
                dash={[8, 6]}
                stroke="#f59e0b"
                strokeWidth={1}
              />
            );
          })()
        )}
      </Group>
      {panel.kind === "asset" && transformEnabled && (
        <Transformer
          ref={trRef}
          rotateEnabled={false}
          flipEnabled={false}
          keepRatio={false}
          boundBoxFunc={(oldBox, newBox) => {
            if (newBox.width < 60 || newBox.height < 60) {
              return oldBox;
            }
            return newBox;
          }}
        />
      )}
    </>
  );
}

export function ComposerCanvas({
  project,
  selectedId,
  selectedObjectIds,
  selectedCells,
  highlightRegionIds,
  thumbnails,
  onSelect,
  onObjectSelection,
  onDuplicateDrawableStart,
  onProjectChange,
  onSelectedCellsChange,
}: {
  project: ComposerProject;
  selectedId: string | null;
  selectedObjectIds: string[];
  selectedCells: Array<{ col: number; row: number }>;
  highlightRegionIds: string[];
  thumbnails: Record<string, string>;
  onSelect(id: string | null, additive?: boolean): void;
  onObjectSelection(ids: string[], additive?: boolean): void;
  onDuplicateDrawableStart(id: string): string | null;
  onProjectChange(project: ComposerProject): void;
  onSelectedCellsChange(cells: Array<{ col: number; row: number }>): void;
}) {
  const stageRef = useRef<any>(null);
  const stageWidth = useMemo(() => project.canvas_width_mm * SCALE, [project.canvas_width_mm]);
  const stageHeight = useMemo(() => project.canvas_height_mm * SCALE, [project.canvas_height_mm]);
  const [guides, setGuides] = useState<GuideLine[]>([]);
  const [marqueeRect, setMarqueeRect] = useState<{
    x: number;
    y: number;
    width: number;
    height: number;
  } | null>(null);
  const marqueeStartRef = useRef<{ x: number; y: number; additive: boolean } | null>(null);
  const suppressClickRef = useRef(false);
  const activeTextDragIdRef = useRef<string | null>(null);
  const highlightIds = useMemo(
    () => new Set([...highlightRegionIds, ...selectedRegionIdsForObjects(project, selectedObjectIds)]),
    [highlightRegionIds, project, selectedObjectIds],
  );
  const labels = useMemo(
    () =>
      Object.fromEntries(
        project.panels
          .filter((panel) => panel.kind === "graph")
          .map((panel) => [panel.id, resolveSelectedPanelLabel(project, panel)]),
      ),
    [project],
  );

  const orderedDrawables = useMemo(
    () =>
      orderDrawables(project)
        .map((item) =>
          item.type === "panel"
            ? { type: "panel" as const, item: project.panels.find((panel) => panel.id === item.id)! }
            : { type: "text" as const, item: project.texts.find((text) => text.id === item.id)! },
        )
        .filter(
          (entry) =>
            Boolean(entry.item) &&
            !("hidden" in entry.item && Boolean(entry.item.hidden)),
        ),
    [project],
  );

  const consumeSuppressedClick = () => {
    if (!suppressClickRef.current) {
      return false;
    }
    suppressClickRef.current = false;
    return true;
  };

  return (
    <div className="composer-stage-shell">
      <Stage
        ref={stageRef}
        width={stageWidth}
        height={stageHeight}
        className="composer-stage"
        onMouseDownCapture={(event: any) => {
          const target = event.target;
          if (
            nodeOrAncestorHasName(target, "composer-drawable") ||
            nodeOrAncestorHasName(target, "composer-region")
          ) {
            return;
          }
          const pointer = stageRef.current?.getPointerPosition();
          if (!pointer) {
            return;
          }
          marqueeStartRef.current = {
            x: pointer.x,
            y: pointer.y,
            additive: Boolean(event.evt.shiftKey || event.evt.metaKey),
          };
          setMarqueeRect({
            x: pointer.x,
            y: pointer.y,
            width: 0,
            height: 0,
          });
        }}
        onMouseMoveCapture={() => {
          const start = marqueeStartRef.current;
          const pointer = stageRef.current?.getPointerPosition();
          if (!start || !pointer) {
            return;
          }
          setMarqueeRect({
            x: Math.min(start.x, pointer.x),
            y: Math.min(start.y, pointer.y),
            width: Math.abs(pointer.x - start.x),
            height: Math.abs(pointer.y - start.y),
          });
        }}
        onMouseUpCapture={() => {
          const start = marqueeStartRef.current;
          if (!start) {
            return;
          }
          const nextRect = marqueeRect;
          marqueeStartRef.current = null;
          if (!nextRect) {
            return;
          }
          setMarqueeRect(null);
          setGuides([]);
          if (nextRect.width < 6 && nextRect.height < 6) {
            return;
          }
          suppressClickRef.current = true;
          onObjectSelection(
            drawableIdsInRect(project, {
              x_mm: nextRect.x / SCALE,
              y_mm: nextRect.y / SCALE,
              w_mm: nextRect.width / SCALE,
              h_mm: nextRect.height / SCALE,
            }),
            start.additive,
          );
          onSelectedCellsChange([]);
        }}
        onMouseDown={(event) => {
          if (event.target === event.target.getStage()) {
            onSelect(null, false);
            setGuides([]);
          }
        }}
      >
        <Layer>
          <Rect
            name="composer-surface"
            x={0}
            y={0}
            width={stageWidth}
            height={stageHeight}
            fill="#ffffff"
            stroke="#d6deea"
            strokeWidth={1}
            cornerRadius={10}
          />
          <Rect
            x={project.layout_grid.frame_x_mm * SCALE}
            y={project.layout_grid.frame_y_mm * SCALE}
            width={project.layout_grid.frame_width_mm * SCALE}
            height={project.layout_grid.frame_height_mm * SCALE}
            fill="#fbfdff"
            stroke="#cbd9ec"
            strokeWidth={1}
          />
          {Array.from({ length: project.layout_grid.columns }).map((_, col) =>
            Array.from({ length: project.layout_grid.rows }).map((__, row) => {
              const rect = cellRect(project, col, row);
              const selected = selectedCells.some((cell) => cell.col === col && cell.row === row);
              return (
                <Rect
                  name="composer-cell"
                  key={`cell-${col}-${row}`}
                  x={rect.x_mm * SCALE}
                  y={rect.y_mm * SCALE}
                  width={rect.w_mm * SCALE}
                  height={rect.h_mm * SCALE}
                  fill={selected ? "#dbeafe" : "rgba(0,0,0,0)"}
                  stroke="#edf2f7"
                  strokeWidth={1}
                  onClick={(event) => {
                    if (suppressClickRef.current) {
                      suppressClickRef.current = false;
                      return;
                    }
                    const region = regionAtCell(project, col, row);
                    if (region) {
                      onSelect(region.id, false);
                      onSelectedCellsChange([]);
                      return;
                    }
                    const nextCells = event.evt.shiftKey
                      ? [...selectedCells, { col, row }]
                      : [{ col, row }];
                    onSelectedCellsChange(nextCells);
                  }}
                />
              );
            }),
          )}

          {project.regions.map((region) => {
            const rect = regionRect(project, region);
            const slot = regionSlotRect(project, region);
            const selected = selectedId === region.id;
            const highlighted = highlightIds.has(region.id);
            return (
              <Group
                key={region.id}
                name="composer-region"
                x={rect.x_mm * SCALE}
                y={rect.y_mm * SCALE}
                draggable={region.kind === "free" && !region.locked}
                onClick={() => {
                  if (suppressClickRef.current) {
                    suppressClickRef.current = false;
                    return;
                  }
                  onSelect(region.id, false);
                  onSelectedCellsChange([]);
                }}
                onDragEnd={(event) => {
                  if (region.kind !== "free") {
                    return;
                  }
                  const col = Math.max(
                    0,
                    Math.min(
                      project.layout_grid.columns - region.col_span,
                      Math.round((event.target.x() / SCALE - project.layout_grid.frame_x_mm) / project.layout_grid.cell_width_mm),
                    ),
                  );
                  const row = Math.max(
                    0,
                    Math.min(
                      project.layout_grid.rows - region.row_span,
                      Math.round((event.target.y() / SCALE - project.layout_grid.frame_y_mm) / project.layout_grid.cell_height_mm),
                    ),
                  );
                  onProjectChange(moveRegion(project, region.id, col, row));
                }}
              >
                <Rect
                  x={0}
                  y={0}
                  width={rect.w_mm * SCALE}
                  height={rect.h_mm * SCALE}
                  fill={region.kind === "free" ? "rgba(14,165,233,0.06)" : "rgba(148,163,184,0.05)"}
                  stroke={selected ? "#2563eb" : region.kind === "free" ? "#7dd3fc" : "#bfd0e8"}
                  strokeWidth={selected ? 2 : 1}
                  dash={region.kind === "free" ? [8, 6] : undefined}
                />
                {highlighted && (
                  <>
                    <Line
                      points={[
                        (rect.w_mm / 2) * SCALE,
                        0,
                        (rect.w_mm / 2) * SCALE,
                        rect.h_mm * SCALE,
                      ]}
                      stroke={selected ? "#2563eb" : "#60a5fa"}
                      strokeWidth={1}
                      dash={[6, 6]}
                    />
                    <Line
                      points={[
                        0,
                        (rect.h_mm / 2) * SCALE,
                        rect.w_mm * SCALE,
                        (rect.h_mm / 2) * SCALE,
                      ]}
                      stroke={selected ? "#2563eb" : "#60a5fa"}
                      strokeWidth={1}
                      dash={[6, 6]}
                    />
                  </>
                )}
                {slot && (
                  <>
                    <Rect
                      x={0}
                      y={0}
                      width={slot.w_mm * SCALE}
                      height={slot.h_mm * SCALE}
                      stroke="#f59e0b"
                      strokeWidth={1}
                      dash={[8, 6]}
                    />
                    {highlighted && (
                      <>
                        <Line
                          points={[
                            (slot.w_mm / 2) * SCALE,
                            0,
                            (slot.w_mm / 2) * SCALE,
                            slot.h_mm * SCALE,
                          ]}
                          stroke="#f59e0b"
                          strokeWidth={1}
                          dash={[6, 6]}
                        />
                        <Line
                          points={[
                            0,
                            (slot.h_mm / 2) * SCALE,
                            slot.w_mm * SCALE,
                            (slot.h_mm / 2) * SCALE,
                          ]}
                          stroke="#f59e0b"
                          strokeWidth={1}
                          dash={[6, 6]}
                        />
                      </>
                    )}
                  </>
                )}
              </Group>
            );
          })}

          {orderedDrawables.map((entry) =>
            entry.type === "panel" ? (
              <PanelNode
                key={entry.item.id}
                displayLabel={labels[entry.item.id] ?? ""}
                imageSrc={thumbnails[entry.item.id] ?? null}
                panel={entry.item}
                project={project}
                selected={selectedObjectIds.includes(entry.item.id)}
                transformEnabled={selectedObjectIds.length === 1 && selectedObjectIds[0] === entry.item.id}
                onGuidesChange={setGuides}
                onProjectChange={(next) => onProjectChange(next)}
                onDuplicateDragStart={onDuplicateDrawableStart}
                consumeSuppressedClick={consumeSuppressedClick}
                onSelect={(additive) => {
                  onSelect(entry.item.id, additive);
                  onSelectedCellsChange([]);
                }}
              />
            ) : (
              <Text
                key={entry.item.id}
                name="composer-drawable"
                draggable={!entry.item.locked}
                text={entry.item.text}
                x={textBounds(entry.item).x_mm * SCALE}
                y={textBounds(entry.item).y_mm * SCALE}
                fontSize={entry.item.font_size_pt * 1.4}
                fill={selectedObjectIds.includes(entry.item.id) ? "#1d4ed8" : "#0f172a"}
                fontStyle="bold"
                onClick={(event) => {
                  if (consumeSuppressedClick()) {
                    return;
                  }
                  onSelect(entry.item.id, Boolean(event.evt.shiftKey || event.evt.metaKey));
                  onSelectedCellsChange([]);
                }}
                onTap={() => {
                  if (consumeSuppressedClick()) {
                    return;
                  }
                  onSelect(entry.item.id, false);
                  onSelectedCellsChange([]);
                }}
                onDragStart={(event) => {
                  activeTextDragIdRef.current = entry.item.id;
                  if (!event.evt.altKey) {
                    return;
                  }
                  const duplicateId = onDuplicateDrawableStart(entry.item.id);
                  if (duplicateId) {
                    activeTextDragIdRef.current = duplicateId;
                  }
                }}
                onDragMove={(event) => {
                  const activeTextId =
                    project.texts.find((item) => item.id === activeTextDragIdRef.current) != null
                      ? (activeTextDragIdRef.current ?? entry.item.id)
                      : entry.item.id;
                  const bounds = textBounds({
                    ...entry.item,
                    x_mm: event.target.x() / SCALE,
                    y_mm: event.target.y() / SCALE,
                  });
                  const snapped = snapRectWithGuides(project, activeTextId, bounds);
                  event.target.position({ x: snapped.rect.x_mm * SCALE, y: snapped.rect.y_mm * SCALE });
                  setGuides(snapped.guides);
                }}
                onDragEnd={(event) => {
                  const activeTextId =
                    project.texts.find((item) => item.id === activeTextDragIdRef.current) != null
                      ? (activeTextDragIdRef.current ?? entry.item.id)
                      : entry.item.id;
                  const bounds = textBounds({
                    ...entry.item,
                    x_mm: event.target.x() / SCALE,
                    y_mm: event.target.y() / SCALE,
                  });
                  const snapped = snapRectWithGuides(project, activeTextId, bounds);
                  onProjectChange({
                    ...project,
                    texts: project.texts.map((item) =>
                      item.id === activeTextId
                        ? {
                            ...item,
                            x_mm: snapped.rect.x_mm,
                            y_mm: snapped.rect.y_mm,
                          }
                        : item,
                    ),
                  });
                  setGuides([]);
                  activeTextDragIdRef.current = null;
                }}
              />
            ),
          )}

          {marqueeRect && (marqueeRect.width >= 1 || marqueeRect.height >= 1) && (
            <Rect
              x={marqueeRect.x}
              y={marqueeRect.y}
              width={marqueeRect.width}
              height={marqueeRect.height}
              fill="rgba(37,99,235,0.08)"
              stroke="#2563eb"
              strokeWidth={1}
              dash={[8, 4]}
              listening={false}
            />
          )}

          {guides.map((guide) =>
            guide.orientation === "vertical" ? (
              <Line
                key={`guide-v-${guide.valueMm}`}
                points={[guide.valueMm * SCALE, 0, guide.valueMm * SCALE, stageHeight]}
                stroke="#0ea5e9"
                strokeWidth={1}
                dash={[6, 6]}
              />
            ) : (
              <Line
                key={`guide-h-${guide.valueMm}`}
                points={[0, guide.valueMm * SCALE, stageWidth, guide.valueMm * SCALE]}
                stroke="#0ea5e9"
                strokeWidth={1}
                dash={[6, 6]}
              />
            ),
          )}
        </Layer>
      </Stage>
    </div>
  );
}
