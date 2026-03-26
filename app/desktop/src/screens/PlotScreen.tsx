import {
  useEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
  type PointerEvent as ReactPointerEvent,
} from "react";
import { useShallow } from "zustand/react/shallow";

import { PreviewPane } from "../components/PreviewPane";
import {
  CompactListRow,
  CompactToolbar,
  InspectorPanel,
  SectionHeader,
  SegmentedControl,
  StepRail,
} from "../components/workbench/V2Primitives";
import { exportRender, inspectFile, openPath } from "../lib/api";
import { applyInspectionToWizard, loadWizardDataFile } from "../lib/project-io";
import { openDialog } from "../lib/tauri-dialog";
import { getSciPlotGodWebviewWindow } from "../lib/tauri-webview";
import { useWizardStore, useWorkbenchStore } from "../lib/store";
import type {
  InputInspection,
  PlotDatasetPreview,
  PlotStage,
  RenderOptionsPayload,
  TemplateName,
  WorkbenchMeta,
  WorkbenchRoute,
  WorkbenchTemplate,
} from "../lib/types";
import {
  compatibleTemplateChoices,
  confirmReplaceWizardSession,
  formatLeaf,
  getErrorMessage,
  getPlotStageLabel,
  plotRoute,
  templateLabel,
  templateMeta,
  toDialogPaths,
} from "../lib/workbench";
import {
  areRenderOptionsEqual,
  selectionFromInspection,
  sanitizeRenderOptions,
  sanitizeTemplateId,
} from "../lib/wizard";
import { useWizardPreflight } from "./wizard/useWizardPreflight";
import { useWizardPreview } from "./wizard/useWizardPreview";

type PlotFlowStage = "import" | "template" | "refine";
type PlotColumnRole = "candidate" | "x" | "y" | "ignore";
type PlotLegendAnchor =
  | "top-left"
  | "top-center"
  | "top-right"
  | "bottom-left"
  | "bottom-center"
  | "bottom-right"
  | "inside-top-left"
  | "inside-top-right";

type PlotDataDraft = {
  datasetId: string;
  headerRowIndex: number;
  columnTitles: string[];
  columnTouched: boolean[];
  columnRoles: PlotColumnRole[];
  rows: string[][];
};

type PlotRefineDraft = {
  title: string;
  subtitle: string;
  xLabel: string;
  yLabel: string;
  legendTitle: string;
  legendAnchor: PlotLegendAnchor;
  legendSnapGrid: boolean;
  showGrid: boolean;
  showLabels: boolean;
  axisRangeX: string;
  axisRangeY: string;
  theme: string;
  fontScale: number;
  lineWidth: number;
  markerSize: number;
  annotation: string;
};

type PlotExportDraft = {
  filename: string;
  outputRoot: string;
  format: "pdf";
};

const FLOW_STEPS: Array<{
  id: PlotFlowStage;
  label: string;
  hint: string;
}> = [
  { id: "import", label: "Import Data", hint: "Upload, inspect, and map fields" },
  { id: "template", label: "Choose Template", hint: "Pick the strongest chart family" },
  { id: "refine", label: "Refine & Export", hint: "Tune the figure and export" },
];

const SUPPORTED_EXTENSIONS = new Set(["csv", "txt", "tsv", "xlsx", "xlsm"]);

const LEGEND_ANCHORS: Array<{ id: PlotLegendAnchor; label: string }> = [
  { id: "top-left", label: "Top left" },
  { id: "top-center", label: "Top center" },
  { id: "top-right", label: "Top right" },
  { id: "bottom-left", label: "Bottom left" },
  { id: "bottom-center", label: "Bottom center" },
  { id: "bottom-right", label: "Bottom right" },
  { id: "inside-top-left", label: "Inside top left" },
  { id: "inside-top-right", label: "Inside top right" },
];

function flowStageForRoute(stage: PlotStage): PlotFlowStage {
  if (stage === "type") {
    return "template";
  }
  if (stage === "tune" || stage === "review" || stage === "export") {
    return "refine";
  }
  return "import";
}

function stageHint(stage: PlotFlowStage) {
  switch (stage) {
    case "template":
      return "Data becomes chart intent.";
    case "refine":
      return "Preview stays alive while you polish and export.";
    case "import":
    default:
      return "Bring data in, map fields, and keep moving.";
  }
}

function cleanCell(value: unknown) {
  if (value == null) {
    return "";
  }
  return String(value);
}

function normalizeDataset(dataset: PlotDatasetPreview): PlotDataDraft {
  const rows = dataset.sample_rows.map((row) => row.map((cell) => cleanCell(cell)));
  const headerRowIndex = 0;
  const headerRow = rows[headerRowIndex] ?? [];
  const numericCandidates = dataset.column_profiles
    .map((profile, index) => ({ profile, index }))
    .filter(({ profile }) => profile.inferred_type === "numeric" || profile.inferred_type === "mixed");
  const firstX = numericCandidates[0]?.index ?? 0;
  const firstY = numericCandidates[1]?.index ?? Math.min(1, dataset.column_profiles.length - 1);
  return {
    datasetId: dataset.dataset_id,
    headerRowIndex,
    columnTitles: dataset.column_profiles.map((profile, index) => headerRow[index] || profile.name),
    columnTouched: dataset.column_profiles.map(() => false),
    columnRoles: dataset.column_profiles.map((_, index) => {
      if (index === firstX) {
        return "x";
      }
      if (index === firstY) {
        return "y";
      }
      return "candidate";
    }),
    rows,
  };
}

function defaultRefineDraft(
  inspection: InputInspection | null,
  template: TemplateName | null,
  dataDraft: PlotDataDraft | null,
  meta: WorkbenchMeta | null,
): PlotRefineDraft {
  const selectedTemplateLabel = templateLabel(meta, template);
  const xLabel = dataDraft?.columnTitles[dataDraft.columnRoles.findIndex((role) => role === "x")] ?? "X";
  const yLabel = dataDraft?.columnTitles[dataDraft.columnRoles.findIndex((role) => role === "y")] ?? "Y";
  return {
    title: selectedTemplateLabel === "-" ? "Plot" : selectedTemplateLabel,
    subtitle: inspection?.recommendation.reason ?? "Refine the figure before export.",
    xLabel,
    yLabel,
    legendTitle: inspection?.model_label ?? "Series",
    legendAnchor: "top-right",
    legendSnapGrid: true,
    showGrid: true,
    showLabels: true,
    axisRangeX: "",
    axisRangeY: "",
    theme: meta?.visual_themes[0]?.id ?? "",
    fontScale: 1,
    lineWidth: 1.4,
    markerSize: 4,
    annotation: "",
  };
}

function defaultExportDraft(inputPath: string, template: TemplateName | null): PlotExportDraft {
  const source = inputPath ? inputPath.replace(/\.[^.]+$/, "") : "plot";
  const suffix = template ? `_${template}` : "";
  return {
    filename: `${formatLeaf(source)}${suffix}`,
    outputRoot: inputPath ? inputPath.replace(/[/\\][^/\\]+$/, "") : "",
    format: "pdf",
  };
}

function supportedFilePath(path: string) {
  const extension = path.split(".").pop()?.toLowerCase() ?? "";
  return SUPPORTED_EXTENSIONS.has(extension);
}

function plotThumbClass(templateId: string) {
  if (templateId.includes("heat")) {
    return "heat";
  }
  if (templateId.includes("scatter") || templateId.includes("bubble")) {
    return "scatter";
  }
  if (templateId.includes("bar") || templateId.includes("box") || templateId.includes("violin") || templateId.includes("hist")) {
    return "bar";
  }
  return "curve";
}

function chartIntentLabel(xType: string | undefined, yType: string | undefined) {
  if (xType === "categorical" && yType === "numeric") {
    return "Comparison first";
  }
  if (xType === "numeric" && yType === "numeric") {
    return "Correlation first";
  }
  if (xType === "numeric" && yType === "categorical") {
    return "Exploration first";
  }
  return "Balanced review";
}

function columnKind(
  dataset: PlotDatasetPreview | null | undefined,
  index: number,
  draft: PlotDataDraft | null,
) {
  if (!dataset || !draft || index < 0) {
    return undefined;
  }
  const value = dataset.column_profiles[index]?.inferred_type ?? "text";
  if (value === "numeric") {
    return "numeric";
  }
  if (value === "mixed") {
    return draft.rows.slice(0, 4).some((row) => row[index] && Number.isFinite(Number(row[index])))
      ? "numeric"
      : "categorical";
  }
  return value === "text" ? "categorical" : undefined;
}

function chartIntentTemplates(
  meta: WorkbenchMeta | null,
  inspection: InputInspection | null,
  draft: PlotDataDraft | null,
  dataset: PlotDatasetPreview | null | undefined,
) {
  const xIndex = draft?.columnRoles.findIndex((role) => role === "x") ?? -1;
  const yIndex = draft?.columnRoles.findIndex((role) => role === "y") ?? -1;
  const xKind = columnKind(dataset, xIndex, draft);
  const yKind = columnKind(dataset, yIndex, draft);
  const choices = compatibleTemplateChoices(meta, inspection?.model);
  const preferredIds: TemplateName[] = [];
  if (xKind === "categorical" && yKind === "numeric") {
    preferredIds.push("bar", "point_line", "curve");
  } else if (xKind === "numeric" && yKind === "numeric") {
    preferredIds.push("scatter", "scatter_fit", "curve");
  } else if (xKind === "numeric" && yKind === "categorical") {
    preferredIds.push("curve", "scatter", "point_line");
  } else {
    preferredIds.push("curve", "point_line", "scatter");
  }
  const ranked = [
    ...preferredIds
      .map((templateId) => choices.find((item) => item.id === templateId))
      .filter((item): item is (typeof choices)[number] => Boolean(item)),
    ...choices.filter((item) => !preferredIds.includes(item.id)).slice(0, 6),
  ];
  return {
    intent: chartIntentLabel(xKind, yKind),
    ranked: ranked.slice(0, 6),
  };
}

function legendAnchorStyle(anchor: PlotLegendAnchor): CSSProperties {
  switch (anchor) {
    case "top-left":
      return { left: 14, top: 14 };
    case "top-center":
      return { left: "50%", top: 14, transform: "translateX(-50%)" };
    case "top-right":
      return { right: 14, top: 14 };
    case "bottom-left":
      return { left: 14, bottom: 14 };
    case "bottom-center":
      return { left: "50%", bottom: 14, transform: "translateX(-50%)" };
    case "bottom-right":
      return { right: 14, bottom: 14 };
    case "inside-top-left":
      return { left: 88, top: 80 };
    case "inside-top-right":
      return { right: 88, top: 80 };
    default:
      return { right: 14, top: 14 };
  }
}

function previewValue(value: unknown) {
  if (value == null || value === "") {
    return "—";
  }
  return String(value);
}

function plotColumnRoleLabel(role: PlotColumnRole) {
  switch (role) {
    case "x":
      return "X field";
    case "y":
      return "Y field";
    case "ignore":
      return "Hidden";
    default:
      return "Candidate";
  }
}

export function PlotScreen({
  meta,
  routeStage = useWizardStore.getState().stage,
  onNavigate = () => {},
}: {
  meta: WorkbenchMeta | null;
  routeStage?: PlotStage;
  onNavigate?(route: WorkbenchRoute): void;
}) {
  const wizard = useWizardStore(
    useShallow((state) => ({
      busy: state.busy,
      error: state.error,
      exportResult: state.exportResult,
      inputPath: state.inputPath,
      inspection: state.inspection,
      options: state.options,
      outputs: state.outputs,
      preflight: state.preflight,
      previewIndex: state.previewIndex,
      previews: state.previews,
      setBusy: state.setBusy,
      setError: state.setError,
      setExportResult: state.setExportResult,
      setInspection: state.setInspection,
      setDataset: state.setDataset,
      setInputPath: state.setInputPath,
      setOptions: state.setOptions,
      setOutputs: state.setOutputs,
      setPreflight: state.setPreflight,
      setPreviewIndex: state.setPreviewIndex,
      setPreviews: state.setPreviews,
      setProjectPath: state.setProjectPath,
      setSheet: state.setSheet,
      setSheetNames: state.setSheetNames,
      setStage: state.setStage,
      setStep: state.setStep,
      setSubmissionReport: state.setSubmissionReport,
      setTemplate: state.setTemplate,
      reset: state.reset,
      sheet: state.sheet,
      sheetNames: state.sheetNames,
      submissionReport: state.submissionReport,
      dataset: state.dataset,
      template: state.template,
    })),
  );
  const rememberProject = useWorkbenchStore((state) => state.rememberProject);
  const recentProjects = useWorkbenchStore((state) => state.recentProjects);
  const [showTemplateGallery, setShowTemplateGallery] = useState(false);
  const [showRecentModal, setShowRecentModal] = useState(false);
  const [showExportModal, setShowExportModal] = useState(false);
  const [dropActive, setDropActive] = useState(false);
  const [dropNotice, setDropNotice] = useState<string | null>(null);
  const [plotDataDraft, setPlotDataDraft] = useState<PlotDataDraft | null>(null);
  const [refineDraft, setRefineDraft] = useState<PlotRefineDraft | null>(null);
  const [exportDraft, setExportDraft] = useState<PlotExportDraft | null>(null);
  const [dragAnchor, setDragAnchor] = useState<PlotLegendAnchor | null>(null);
  const legendDragRef = useRef<{ pointerId: number; startX: number; startY: number } | null>(null);
  const previewShellRef = useRef<HTMLDivElement | null>(null);

  const routeFlowStage = flowStageForRoute(routeStage);
  const hasInput = Boolean(wizard.inputPath);
  const hasTemplate = Boolean(wizard.template);
  const stepItems = useMemo(() => {
    const currentIndex = FLOW_STEPS.findIndex((step) => step.id === routeFlowStage);
    return FLOW_STEPS.map((step, index) => {
      let status: "complete" | "current" | "upcoming" | "disabled" = "upcoming";
      if (!hasInput && index === 0) {
        status = "current";
      } else if (index < currentIndex) {
        status = "complete";
      } else if (index === currentIndex) {
        status = "current";
      }
      return {
        id: step.id,
        label: step.label,
        hint: step.hint,
        status,
        onSelect:
          status === "complete"
            ? () => {
                if (step.id === "import") {
                  onNavigate(plotRoute("import"));
                } else if (step.id === "template") {
                  onNavigate(plotRoute("type"));
                } else {
                  onNavigate(plotRoute("tune"));
                }
              }
            : null,
      };
    });
  }, [hasInput, onNavigate, routeFlowStage]);

  const recommendedSelection = useMemo(
    () => (wizard.inspection ? selectionFromInspection(meta, wizard.inspection) : null),
    [meta, wizard.inspection],
  );
  const recentDataFiles = recentProjects.filter((entry) => entry.mode === "wizard" && entry.kind === "data");
  const stageIntent = chartIntentTemplates(meta, wizard.inspection, plotDataDraft, wizard.dataset);

  const needsPreview =
    hasInput &&
    hasTemplate &&
    routeFlowStage !== "import";
  const needsPreflight =
    hasInput &&
    hasTemplate &&
    routeFlowStage === "refine";

  const {
    busy: previewBusy,
    error: previewError,
  } = useWizardPreview({
    enabled: needsPreview,
    inputPath: wizard.inputPath,
    sheet: wizard.sheet,
    template: wizard.template,
    options: wizard.options,
    onPreviews: wizard.setPreviews,
  });

  const {
    busy: preflightBusy,
    error: preflightRequestError,
  } = useWizardPreflight({
    enabled: needsPreflight,
    inputPath: wizard.inputPath,
    sheet: wizard.sheet,
    template: wizard.template,
    options: wizard.options,
    onPreflight: wizard.setPreflight,
    onSubmissionReport: wizard.setSubmissionReport,
  });

  useEffect(() => {
    wizard.setStage(routeStage);
    wizard.setStep(
      routeStage === "import" || routeStage === "sheet"
        ? "file"
        : routeStage === "type"
          ? "inspect"
          : routeStage === "tune"
            ? "options"
            : routeStage === "review"
              ? "preflight"
              : "export",
    );
  }, [routeStage, wizard.setStage, wizard.setStep]);

  useEffect(() => {
    if (!wizard.inputPath) {
      setPlotDataDraft(null);
      setRefineDraft(null);
      setExportDraft(null);
      return;
    }

    if (wizard.dataset) {
      setPlotDataDraft(normalizeDataset(wizard.dataset));
    }
    if (!refineDraft || !wizard.template) {
      setRefineDraft(defaultRefineDraft(wizard.inspection, wizard.template, plotDataDraft, meta));
    }
    if (!exportDraft) {
      setExportDraft(defaultExportDraft(wizard.inputPath, wizard.template));
    }
  }, [exportDraft, meta, plotDataDraft, refineDraft, wizard.dataset, wizard.inspection, wizard.inputPath, wizard.template]);

  useEffect(() => {
    if (wizard.dataset && wizard.dataset.dataset_id !== plotDataDraft?.datasetId) {
      setPlotDataDraft(normalizeDataset(wizard.dataset));
    }
  }, [plotDataDraft?.datasetId, wizard.dataset]);

  useEffect(() => {
    setShowTemplateGallery(false);
  }, [wizard.template, wizard.inputPath, wizard.sheet]);

  useEffect(() => {
    setShowRecentModal(false);
  }, [wizard.inputPath]);

  useEffect(() => {
    if (!wizard.inspection || !wizard.template) {
      return;
    }
    const nextTemplate = sanitizeTemplateId(meta, wizard.template, recommendedSelection?.template ?? null);
    if (nextTemplate !== wizard.template) {
      wizard.setTemplate(nextTemplate);
    }
    const nextOptions = sanitizeRenderOptions(
      meta,
      nextTemplate,
      wizard.options,
      wizard.inspection.model,
    );
    if (!areRenderOptionsEqual(nextOptions, wizard.options)) {
      wizard.setOptions(nextOptions);
    }
  }, [
    meta,
    recommendedSelection?.template,
    wizard.inspection,
    wizard.options,
    wizard.setOptions,
    wizard.setTemplate,
    wizard.template,
  ]);

  useEffect(() => {
    if (!wizard.inputPath || !wizard.template) {
      setRefineDraft((current) => current);
      return;
    }
    setRefineDraft((current) =>
      current ?? defaultRefineDraft(wizard.inspection, wizard.template, plotDataDraft, meta),
    );
  }, [meta, plotDataDraft, wizard.inspection, wizard.inputPath, wizard.template]);

  useEffect(() => {
    let disposed = false;
    let unlisten: (() => void) | undefined;

    async function handleDroppedPaths(paths: string[]) {
      const cleaned = paths.filter((path) => path && supportedFilePath(path));
      if (cleaned.length === 0) {
        return;
      }
      wizard.setError(null);
      await loadPlotDataPath(cleaned[0], "type");
    }

    async function attach() {
      try {
        const webview = getSciPlotGodWebviewWindow();
        unlisten = await webview.onDragDropEvent((event) => {
          if (disposed) {
            return;
          }
          if (event.payload.type === "enter") {
            setDropActive(true);
            return;
          }
          if (event.payload.type === "leave") {
            setDropActive(false);
            return;
          }
          if (event.payload.type === "drop") {
            setDropActive(false);
            void handleDroppedPaths(event.payload.paths);
          }
        });
      } catch (error) {
        if (!disposed) {
          setDropNotice(getErrorMessage(error));
        }
      }
    }

    void attach();
    return () => {
      disposed = true;
      setDropActive(false);
      void unlisten?.();
    };
  }, [wizard.inputPath]);

  const invalidateRenderState = () => {
    wizard.setPreflight(null);
    wizard.setOutputs([]);
    wizard.setExportResult(null);
    wizard.setSubmissionReport(null);
  };

  const loadPlotDataPath = async (path: string, nextRoute: PlotStage) => {
    if (
      !confirmReplaceWizardSession(
        {
          inputPath: wizard.inputPath,
          inspection: wizard.inspection,
          template: wizard.template,
          outputs: wizard.outputs,
          exportResult: wizard.exportResult,
        },
        formatLeaf(path),
        path,
      )
    ) {
      return null;
    }

    wizard.setBusy(true);
    try {
      const inspected = await loadWizardDataFile(wizard, meta, path);
      const nextTemplate = inspected.inspection.recommendation.template;
      setPlotDataDraft(inspected.dataset ? normalizeDataset(inspected.dataset) : null);
      setRefineDraft(null);
      setExportDraft(defaultExportDraft(inspected.input_path, nextTemplate));
      rememberProject({
        mode: "wizard",
        kind: "data",
        path: inspected.input_path,
        title: formatLeaf(inspected.input_path),
        detail: `Data file · ${inspected.sheet_names.length} sheets · ${templateLabel(meta, nextTemplate)}`,
      });
      onNavigate(plotRoute(nextRoute));
      return inspected;
    } catch (error) {
      wizard.setError(getErrorMessage(error));
      return null;
    } finally {
      wizard.setBusy(false);
    }
  };

  const rerunInspect = async (sheetValue: string | number) => {
    if (!wizard.inputPath) {
      return;
    }
    wizard.setError(null);
    wizard.setBusy(true);
    try {
      const inspected = await inspectFile(wizard.inputPath, sheetValue);
      applyInspectionToWizard(wizard, meta, inspected, { nextStage: inspected.sheet_names.length > 1 ? "sheet" : "type" });
      setPlotDataDraft(inspected.dataset ? normalizeDataset(inspected.dataset) : null);
      invalidateRenderState();
      onNavigate(inspected.sheet_names.length > 1 ? plotRoute("sheet") : plotRoute("type"));
    } catch (error) {
      wizard.setError(getErrorMessage(error));
    } finally {
      wizard.setBusy(false);
    }
  };

  const openDataFile = async () => {
    let path: string | undefined;
    try {
      const selected = await openDialog({
        multiple: false,
        filters: [
          {
            name: "Data",
            extensions: ["csv", "txt", "tsv", "xlsx", "xlsm"],
          },
        ],
      });
      path = toDialogPaths(selected, 1)[0];
    } catch (error) {
      wizard.setError(getErrorMessage(error));
      return;
    }
    if (!path) {
      return;
    }
    wizard.setError(null);
    await loadPlotDataPath(path, "type");
  };

  const openRecentData = async (path: string) => {
    wizard.setError(null);
    await loadPlotDataPath(path, "type");
  };

  const continueFromImport = () => {
    if (!wizard.inputPath || !wizard.inspection) {
      return;
    }
    onNavigate(plotRoute("type"));
  };

  const continueFromTemplate = () => {
    if (!wizard.inputPath || !wizard.template) {
      return;
    }
    onNavigate(plotRoute("tune"));
  };

  const exportOutputPath = useMemo(() => {
    if (!wizard.inputPath || !exportDraft) {
      return "";
    }
    const root = exportDraft.outputRoot || wizard.inputPath.replace(/[/\\][^/\\]+$/, "");
    return root ? `${root.replace(/[/\\]$/, "")}/${exportDraft.filename}` : exportDraft.filename;
  }, [exportDraft, wizard.inputPath]);

  const runExport = async () => {
    if (!wizard.inputPath || !wizard.template) {
      return;
    }
    wizard.setError(null);
    wizard.setBusy(true);
    try {
      const response = await exportRender(
        wizard.inputPath,
        wizard.sheet,
        wizard.template,
        wizard.options,
        exportOutputPath || undefined,
      );
      wizard.setOutputs(response.outputs);
      wizard.setExportResult(response);
      wizard.setSubmissionReport(response.submission_report ?? wizard.submissionReport);
      onNavigate(plotRoute("export"));
      await openPath(response.output_dir);
    } catch (error) {
      wizard.setError(getErrorMessage(error));
    } finally {
      wizard.setBusy(false);
      setShowExportModal(false);
    }
  };

  const updateWizardTemplate = (value: TemplateName) => {
    const nextTemplate = sanitizeTemplateId(meta, value, wizard.inspection?.recommendation.template ?? wizard.template);
    if (!nextTemplate) {
      return;
    }
    invalidateRenderState();
    wizard.setTemplate(nextTemplate);
    wizard.setOptions(sanitizeRenderOptions(meta, nextTemplate, wizard.options, wizard.inspection?.model));
    setRefineDraft(defaultRefineDraft(wizard.inspection, nextTemplate, plotDataDraft, meta));
    setExportDraft((current) =>
      current
        ? {
            ...current,
            filename: `${formatLeaf(wizard.inputPath || "plot").replace(/\.[^.]+$/, "")}_${nextTemplate}`,
          }
        : current,
    );
  };

  const updateColumnRole = (index: number, role: PlotColumnRole) => {
    setPlotDataDraft((current) => {
      if (!current) {
        return current;
      }
      const nextRoles = [...current.columnRoles];
      if (role === "x") {
        nextRoles.fill("candidate");
      }
      if (role === "y") {
        nextRoles.fill("candidate");
      }
      nextRoles[index] = role;
      return { ...current, columnRoles: nextRoles };
    });
  };

  const updateColumnTitle = (index: number, title: string) => {
    setPlotDataDraft((current) => {
      if (!current) {
        return current;
      }
      const nextTitles = [...current.columnTitles];
      const nextTouched = [...current.columnTouched];
      nextTitles[index] = title;
      nextTouched[index] = true;
      return { ...current, columnTitles: nextTitles, columnTouched: nextTouched };
    });
  };

  const updateCellValue = (rowIndex: number, colIndex: number, value: string) => {
    setPlotDataDraft((current) => {
      if (!current) {
        return current;
      }
      const nextRows = current.rows.map((row) => [...row]);
      if (!nextRows[rowIndex]) {
        return current;
      }
      nextRows[rowIndex][colIndex] = value;
      return { ...current, rows: nextRows };
    });
  };

  const updateHeaderRowIndex = (value: number) => {
    setPlotDataDraft((current) => {
      if (!current) {
        return current;
      }
      const nextTitles = [...current.columnTitles];
      const nextTouched = [...current.columnTouched];
      const headerRow = current.rows[value] ?? [];
      current.columnTitles.forEach((_, index) => {
        if (!nextTouched[index]) {
          nextTitles[index] = headerRow[index] ? headerRow[index] : nextTitles[index];
        }
      });
      return { ...current, headerRowIndex: value, columnTitles: nextTitles, columnTouched: nextTouched };
    });
  };

  const updateRefineDraft = (patch: Partial<PlotRefineDraft>) => {
    setRefineDraft((current) => (current ? { ...current, ...patch } : current));
  };

  const selectedXIndex = plotDataDraft?.columnRoles.findIndex((role) => role === "x") ?? -1;
  const selectedYIndex = plotDataDraft?.columnRoles.findIndex((role) => role === "y") ?? -1;
  const selectedXLabel = plotDataDraft && selectedXIndex >= 0 ? plotDataDraft.columnTitles[selectedXIndex] : "X";
  const selectedYLabel = plotDataDraft && selectedYIndex >= 0 ? plotDataDraft.columnTitles[selectedYIndex] : "Y";
  const selectedXKind = columnKind(wizard.dataset, selectedXIndex, plotDataDraft);
  const selectedYKind = columnKind(wizard.dataset, selectedYIndex, plotDataDraft);
  const selectedIntent = chartIntentLabel(selectedXKind, selectedYKind);
  const dataWarnings = [
    ...(wizard.inspection?.warnings ?? []),
    ...(wizard.dataset?.quality_flags?.includes("empty_columns_dropped")
      ? ["Empty columns were dropped from the preview."]
      : []),
    ...(wizard.dataset?.quality_flags?.includes("type_ambiguity")
      ? ["Some columns contain mixed values. Keep an eye on the type badges."]
      : []),
  ];

  const candidateRoleLabels = plotDataDraft
    ? plotDataDraft.columnTitles
        .map((title, index) => ({ title, index, role: plotDataDraft.columnRoles[index] }))
        .filter((item) => item.role === "candidate" || item.role === "x" || item.role === "y" || item.role === "ignore")
    : [];

  const visibleColumns = plotDataDraft?.columnTitles.map((title, index) => ({
    title,
    index,
    role: plotDataDraft.columnRoles[index],
  })) ?? [];

  const visiblePreviewRows = plotDataDraft?.rows.slice(0, 8) ?? [];
  const previewColumns = plotDataDraft?.columnTitles.slice(0, 8) ?? [];
  const templateSections = useMemo(
    () => {
      const recommendations = wizard.inspection?.recommendations ?? [];
      const primary = wizard.inspection?.primary_recommendation?.length
        ? wizard.inspection.primary_recommendation
        : recommendations.slice(0, 2);
      const alternatives = wizard.inspection?.alternative_recommendations?.length
        ? wizard.inspection.alternative_recommendations
        : recommendations.slice(primary.length, primary.length + 4);
      const primaryTemplates = primary
        .map((item) => templateMeta(meta, item.canonical_id ?? item.implementation_id ?? item.template_id) ?? templateMeta(meta, item.template_id))
        .filter((item): item is NonNullable<typeof item> => Boolean(item));
      const alternativeTemplates = alternatives
        .map((item) => templateMeta(meta, item.canonical_id ?? item.implementation_id ?? item.template_id) ?? templateMeta(meta, item.template_id))
        .filter((item): item is NonNullable<typeof item> => Boolean(item));
      return {
        primary: primaryTemplates,
        alternatives: alternativeTemplates,
      };
    },
    [meta, wizard.inspection],
  );

  const galleryGroups = useMemo(() => {
    const groups = new Map<string, WorkbenchTemplate[]>();
    for (const template of meta?.templates ?? []) {
      const category = template.category.replace(/_/g, " ");
      const list = groups.get(category) ?? [];
      list.push(template);
      groups.set(category, list);
    }
    return Array.from(groups.entries()).sort((a, b) => a[0].localeCompare(b[0]));
  }, [meta]);

  const currentPreviewLabel = hasTemplate ? templateLabel(meta, wizard.template) : "Template preview";
  const currentStageTitle =
    routeFlowStage === "import"
      ? "Import data"
      : routeFlowStage === "template"
        ? "Choose template"
        : "Refine and export";

  return (
    <div className={`plot-workspace plot-flow-v3 plot-flow-stage-${routeFlowStage} ${hasInput ? "has-data" : "empty-data"}`}>
      <header className="plot-flow-v3-header">
        <div className="plot-flow-v3-header-copy">
          <span>Plot</span>
          <strong>{currentStageTitle}</strong>
          <p>{stageHint(routeFlowStage)}</p>
        </div>
        <div className="plot-flow-v3-header-actions">
          {routeFlowStage !== "import" && hasInput ? (
            <button className="ghost-button" onClick={() => onNavigate(plotRoute("import"))} type="button">
              Back to import
            </button>
          ) : null}
          {routeFlowStage === "template" && hasTemplate ? (
            <button className="primary-button" onClick={continueFromTemplate} type="button">
              Continue
            </button>
          ) : routeFlowStage === "refine" ? (
            <button className="primary-button" onClick={() => setShowExportModal(true)} type="button">
              Export
            </button>
          ) : (
            <button className="primary-button" disabled={!hasInput} onClick={continueFromImport} type="button">
              Continue
            </button>
          )}
        </div>
      </header>

      <StepRail
        ariaLabel="Plot flow steps"
        steps={stepItems}
      />

      {routeFlowStage === "import" ? (
        <div className={`plot-flow-v3-grid import-grid ${plotDataDraft ? "loaded" : "empty"} ${dropActive ? "drop-active" : ""}`}>
          <section className="plot-flow-v3-main import-main">
            <SectionHeader
              kicker="Stage 1"
              title="Import data"
              description="Upload a file, confirm the sheet, and lightly prep the table before chart selection."
              actions={
                <CompactToolbar label="Import actions">
                  <button className="primary-button" onClick={openDataFile} type="button">
                    Open data
                  </button>
                  <button className="ghost-button" onClick={() => setShowRecentModal(true)} type="button">
                    Open recent
                  </button>
                </CompactToolbar>
              }
            />

            {!hasInput ? (
              <div
                className={`plot-dropzone ${dropActive ? "drag-active" : ""}`}
                onDragOver={(event) => event.preventDefault()}
                onDrop={(event) => {
                  event.preventDefault();
                  const filePaths = Array.from(event.dataTransfer.files ?? [])
                    .map((file) => (file as File & { path?: string }).path ?? "")
                    .filter((path) => supportedFilePath(path));
                  if (filePaths.length > 0) {
                    void loadPlotDataPath(filePaths[0], "type");
                    return;
                  }
                  setDropNotice("Drop a supported data file to import it.");
                }}
                role="button"
                tabIndex={0}
              >
                <div className="plot-dropzone-copy">
                  <strong>Drag a data file here</strong>
                  <p>CSV, TSV, TXT, XLSX, or XLSM. Keep it calm and focused.</p>
                </div>
                <button className="primary-button prominent" onClick={openDataFile} type="button">
                  Upload file
                </button>
                <div className="plot-dropzone-hint">Drop a single workbook or spreadsheet to begin.</div>
              </div>
            ) : (
              <div className="plot-source-stack">
                <article className="plot-file-card">
                  <div className="plot-file-card-head">
                    <div>
                      <span>Attached file</span>
                      <strong title={formatLeaf(wizard.inputPath)}>{formatLeaf(wizard.inputPath)}</strong>
                    </div>
                    <button className="ghost-button" onClick={openDataFile} type="button">
                      Replace
                    </button>
                  </div>
                  <div className="plot-file-card-meta">
                    <span>{wizard.sheetNames.length} sheets</span>
                    <span>{wizard.inspection?.model_label ?? "Inspecting"}</span>
                    <span>{plotDataDraft?.rows.length ?? 0} preview rows</span>
                  </div>
                  {wizard.sheetNames.length > 1 ? (
                    <div className="plot-sheet-strip">
                      {wizard.sheetNames.map((sheetName) => {
                        const active = wizard.sheet === sheetName || (typeof wizard.sheet === "number" && wizard.sheetNames[wizard.sheet] === sheetName);
                        return (
                          <button
                            className={`plot-sheet-chip ${active ? "active" : ""}`}
                            key={sheetName}
                            onClick={() => void rerunInspect(sheetName)}
                            type="button"
                          >
                            {sheetName}
                          </button>
                        );
                      })}
                    </div>
                  ) : null}
                </article>

                {wizard.inspection?.warnings?.length || dataWarnings.length ? (
                  <div className="plot-warning-strip">
                    {[...(wizard.inspection?.warnings ?? []), ...dataWarnings].slice(0, 4).map((warning) => (
                      <span key={warning}>{warning}</span>
                    ))}
                  </div>
                ) : null}
              </div>
            )}

            {plotDataDraft ? (
              <div className="plot-preview-layout">
                <InspectorPanel
                  kicker="Preview"
                  title="Light data prep"
                  extra={
                    <div className="plot-column-summary">
                      <span className="plot-summary-chip x">
                        <strong>X</strong>
                        <span>{selectedXLabel || "X"}</span>
                      </span>
                      <span className="plot-summary-chip y">
                        <strong>Y</strong>
                        <span>{selectedYLabel || "Y"}</span>
                      </span>
                      <span className="plot-summary-meta">{plotDataDraft.rows.length} rows</span>
                    </div>
                  }
                >
                  <div className="plot-column-controls">
                    <label className="plot-control-row">
                      <span>Header row</span>
                      <select
                        value={plotDataDraft.headerRowIndex}
                        onChange={(event) => updateHeaderRowIndex(Number(event.target.value))}
                      >
                        {plotDataDraft.rows.slice(0, 3).map((_, index) => (
                          <option key={index} value={index}>
                            Row {index + 1}
                          </option>
                        ))}
                      </select>
                    </label>
                    <label className="plot-control-row">
                      <span>X column</span>
                      <select
                        value={selectedXIndex >= 0 ? selectedXIndex : ""}
                        onChange={(event) => updateColumnRole(Number(event.target.value), "x")}
                      >
                        <option value="">Choose</option>
                        {visibleColumns.map((column) => (
                          <option key={column.index} value={column.index}>
                            {column.title}
                          </option>
                        ))}
                      </select>
                    </label>
                    <label className="plot-control-row">
                      <span>Y column</span>
                      <select
                        value={selectedYIndex >= 0 ? selectedYIndex : ""}
                        onChange={(event) => updateColumnRole(Number(event.target.value), "y")}
                      >
                        <option value="">Choose</option>
                        {visibleColumns.map((column) => (
                          <option key={column.index} value={column.index}>
                            {column.title}
                          </option>
                        ))}
                      </select>
                    </label>
                  </div>
                  {candidateRoleLabels.length > 0 ? (
                    <div className="plot-candidate-strip">
                      {candidateRoleLabels
                        .filter((item) => item.role !== "ignore")
                        .slice(0, 4)
                        .map((item) => (
                          <button
                            className={`plot-candidate-chip ${item.role === "x" ? "x" : item.role === "y" ? "y" : ""}`}
                            key={`${item.index}-${item.title}`}
                            onClick={() => updateColumnRole(item.index, item.role === "x" ? "y" : "x")}
                            type="button"
                          >
                            {item.title}
                          </button>
                      ))}
                    </div>
                  ) : null}
                  <div className="plot-column-grid">
                    {plotDataDraft.columnTitles.map((title, index) => (
                      <article
                        className={`plot-column-card ${plotDataDraft.columnRoles[index] === "ignore" ? "ignored" : ""} ${index === selectedXIndex || index === selectedYIndex ? "selected" : ""}`}
                        key={`${plotDataDraft.datasetId}-${index}`}
                      >
                        <div className="plot-column-card-head">
                          <div className="plot-column-head-copy">
                            <span className={`plot-column-type ${wizard.dataset?.column_profiles[index]?.inferred_type ?? "text"}`}>
                              {wizard.dataset?.column_profiles[index]?.inferred_type ?? "text"}
                            </span>
                            <span className={`plot-column-role ${plotDataDraft.columnRoles[index]}`}>
                              {plotColumnRoleLabel(plotDataDraft.columnRoles[index])}
                            </span>
                          </div>
                          <div className="plot-column-actions">
                            <button className="ghost-button" onClick={() => updateColumnRole(index, "x")} type="button">
                              X
                            </button>
                            <button className="ghost-button" onClick={() => updateColumnRole(index, "y")} type="button">
                              Y
                            </button>
                            <button className="ghost-button" onClick={() => updateColumnRole(index, "ignore")} type="button">
                              Hide
                            </button>
                          </div>
                        </div>
                        <input
                          className="plot-column-title-input"
                          onChange={(event) => updateColumnTitle(index, event.target.value)}
                          value={title}
                        />
                        <div className="plot-column-meta">
                          <span>{wizard.dataset?.column_profiles[index]?.non_empty_count ?? 0} values</span>
                          <span>{wizard.dataset?.column_profiles[index]?.missing_count ?? 0} missing</span>
                        </div>
                      </article>
                    ))}
                  </div>
                </InspectorPanel>

                <InspectorPanel
                  kicker="Table preview"
                  title="Rows and cells"
                  extra={<span className="plot-preview-note">{stageIntent.intent}</span>}
                >
                  <div className="plot-table-preview">
                    <div className="plot-table-preview-head">
                      <span>#</span>
                      {previewColumns.map((column, index) => (
                        <div
                          className={`plot-table-preview-head-cell ${plotDataDraft.columnRoles[index] === "ignore" ? "muted" : ""}`}
                          key={`${column}-${index}`}
                        >
                          <strong>{column}</strong>
                          <span>
                            {plotColumnRoleLabel(plotDataDraft.columnRoles[index])} · {columnKind(wizard.dataset, index, plotDataDraft) ?? "text"}
                          </span>
                        </div>
                      ))}
                    </div>
                    {visiblePreviewRows.map((row, rowIndex) => (
                      <div className="plot-table-preview-row" key={`row-${rowIndex}`}>
                        <span className="plot-row-index">{rowIndex + 1}</span>
                        {previewColumns.map((_, columnIndex) => (
                          <input
                            className="plot-table-cell"
                            key={`${rowIndex}-${columnIndex}`}
                            onChange={(event) => updateCellValue(rowIndex, columnIndex, event.target.value)}
                            value={previewValue(row[columnIndex])}
                          />
                        ))}
                      </div>
                    ))}
                  </div>
                </InspectorPanel>
              </div>
            ) : null}
          </section>

          <aside className="plot-flow-v3-side">
            <InspectorPanel
              kicker="Workspace"
              title="Current state"
              extra={<span className="plot-stage-pill">{getPlotStageLabel(routeStage)}</span>}
            >
              <div className="plot-state-stack">
                <div className="plot-state-card">
                  <span>Stage</span>
                  <strong>{FLOW_STEPS.find((step) => step.id === routeFlowStage)?.label}</strong>
                  <p>{stageHint(routeFlowStage)}</p>
                </div>
                <div className="plot-state-card">
                  <span>Mapping</span>
                  <strong>{selectedXLabel} / {selectedYLabel}</strong>
                  <p>{selectedIntent}</p>
                </div>
                <div className="plot-state-card">
                  <span>Ready</span>
                  <strong>{hasTemplate ? templateLabel(meta, wizard.template) : "Choose a template"}</strong>
                  <p>{wizard.inspection?.recommendation_summary ?? "The chart scene is waiting for a template choice."}</p>
                </div>
              </div>
            </InspectorPanel>

            {dropNotice ? <div className="warning-card">{dropNotice}</div> : null}
          </aside>
        </div>
      ) : null}

      {routeFlowStage === "template" ? (
        <div className="plot-flow-v3-grid template-grid">
          <section className="plot-flow-v3-main template-main">
            <SectionHeader
              kicker="Stage 2"
              title="Choose template"
              description="Recommended templates appear as visual cards. Select one to update the live preview immediately."
              actions={
                <CompactToolbar label="Template actions">
                  <button className="ghost-button" onClick={() => setShowTemplateGallery(true)} type="button">
                    More chart types
                  </button>
                  <button className="primary-button" disabled={!wizard.template} onClick={continueFromTemplate} type="button">
                    Continue
                  </button>
                </CompactToolbar>
              }
            />

            <div className="plot-template-layout">
              <section className="plot-template-list">
                <div className="plot-template-list-head">
                  <strong>Recommended for {stageIntent.intent.toLowerCase()}</strong>
                  <span>{wizard.inspection?.recommendation_summary ?? "The recommendation is computed from your data and selected mapping."}</span>
                </div>
                <div className="plot-template-card-stack">
                  {templateSections.primary.slice(0, 2).map((template, index) => {
                    const selected = wizard.template === template.id;
                    return (
                      <button
                        className={`plot-template-card ${selected ? "selected" : ""}`}
                        key={template.id}
                        onClick={() => updateWizardTemplate(template.id)}
                        type="button"
                      >
                        <div className={`plot-template-thumb ${plotThumbClass(template.id)}`} aria-hidden="true" />
                        <div className="plot-template-card-copy">
                          <strong>{template.label}</strong>
                          <span>{index === 0 ? "Best fit" : "Close fit"}</span>
                          <p>{template.description}</p>
                        </div>
                      </button>
                    );
                  })}
                </div>

                {templateSections.alternatives.length > 0 ? (
                  <div className="plot-template-alternates">
                    <strong>Alternates</strong>
                    <div className="plot-template-alt-grid">
                      {templateSections.alternatives.slice(0, 4).map((template) => (
                        <button
                          className={`plot-template-card gallery alt ${wizard.template === template.id ? "selected" : ""}`}
                          key={template.id}
                          onClick={() => updateWizardTemplate(template.id)}
                          type="button"
                        >
                          <div className={`plot-template-thumb ${plotThumbClass(template.id)}`} aria-hidden="true" />
                          <div className="plot-template-card-copy">
                            <strong>{template.label}</strong>
                            <span>{template.category.replace(/_/g, " ")}</span>
                            <p>{template.description}</p>
                          </div>
                        </button>
                      ))}
                    </div>
                  </div>
                ) : null}
              </section>

              <section className="plot-template-preview">
                <div className="plot-template-preview-head">
                  <span>{currentPreviewLabel}</span>
                  <strong>{stageIntent.intent}</strong>
                </div>
                <div className="plot-template-preview-shell">
                  <PreviewPane
                    busy={previewBusy}
                    error={previewError}
                    onChangeIndex={wizard.setPreviewIndex}
                    previewIndex={wizard.previewIndex}
                    previews={wizard.previews}
                  />
                </div>
              </section>
            </div>
          </section>
          <aside className="plot-flow-v3-side">
            <InspectorPanel kicker="Guide" title="Template notes">
              <div className="plot-state-stack">
                <div className="plot-state-card">
                  <span>Selected template</span>
                  <strong>{wizard.template ? templateLabel(meta, wizard.template) : "None yet"}</strong>
                  <p>{wizard.template ? "Preview updates automatically." : "Pick a card to continue."}</p>
                </div>
                <div className="plot-state-card">
                  <span>Mapping</span>
                  <strong>{selectedXLabel} / {selectedYLabel}</strong>
                  <p>{wizard.inspection?.recommendation.reason ?? "Data-aware guidance comes from the inspection."}</p>
                </div>
              </div>
            </InspectorPanel>
          </aside>
        </div>
      ) : null}

      {routeFlowStage === "refine" ? (
        <div className="plot-flow-v3-grid refine-grid">
          <section className="plot-flow-v3-main refine-main">
            <SectionHeader
              kicker="Stage 3"
              title="Refine & export"
              description="Keep the preview alive while you polish the final figure and choose an export location."
              actions={
                <CompactToolbar label="Refine actions">
                  <button className="primary-button" onClick={() => setShowExportModal(true)} type="button">
                    Export
                  </button>
                </CompactToolbar>
              }
            />
            <div className="plot-refine-layout">
              <section className="plot-refine-controls">
                <div className="plot-refine-block">
                  <strong>Text</strong>
                  <label className="plot-control-row">
                    <span>Title</span>
                    <input value={refineDraft?.title ?? ""} onChange={(event) => updateRefineDraft({ title: event.target.value })} />
                  </label>
                  <label className="plot-control-row">
                    <span>Subtitle</span>
                    <input value={refineDraft?.subtitle ?? ""} onChange={(event) => updateRefineDraft({ subtitle: event.target.value })} />
                  </label>
                  <label className="plot-control-row">
                    <span>X axis</span>
                    <input value={refineDraft?.xLabel ?? ""} onChange={(event) => updateRefineDraft({ xLabel: event.target.value })} />
                  </label>
                  <label className="plot-control-row">
                    <span>Y axis</span>
                    <input value={refineDraft?.yLabel ?? ""} onChange={(event) => updateRefineDraft({ yLabel: event.target.value })} />
                  </label>
                  <label className="plot-control-row">
                    <span>Legend title</span>
                    <input value={refineDraft?.legendTitle ?? ""} onChange={(event) => updateRefineDraft({ legendTitle: event.target.value })} />
                  </label>
                </div>

                <div className="plot-refine-block">
                  <strong>Legend</strong>
                  <SegmentedControl
                    label="Legend anchor"
                    onChange={(value) => updateRefineDraft({ legendAnchor: value as PlotLegendAnchor })}
                    options={LEGEND_ANCHORS.map((anchor) => ({ id: anchor.id, label: anchor.label }))}
                    value={refineDraft?.legendAnchor ?? "top-right"}
                  />
                  <label className="plot-toggle-row">
                    <input
                      checked={refineDraft?.legendSnapGrid ?? true}
                      onChange={(event) => updateRefineDraft({ legendSnapGrid: event.target.checked })}
                      type="checkbox"
                    />
                    <span>Snap legend to presets</span>
                  </label>
                  <label className="plot-toggle-row">
                    <input
                      checked={refineDraft?.showGrid ?? true}
                      onChange={(event) => updateRefineDraft({ showGrid: event.target.checked })}
                      type="checkbox"
                    />
                    <span>Grid</span>
                  </label>
                  <label className="plot-toggle-row">
                    <input
                      checked={refineDraft?.showLabels ?? true}
                      onChange={(event) => updateRefineDraft({ showLabels: event.target.checked })}
                      type="checkbox"
                    />
                    <span>Labels</span>
                  </label>
                </div>

                <div className="plot-refine-block">
                  <strong>Figure</strong>
                  <label className="plot-control-row">
                    <span>Theme</span>
                    <select value={refineDraft?.theme ?? ""} onChange={(event) => updateRefineDraft({ theme: event.target.value })}>
                      <option value="">Default</option>
                      {(meta?.visual_themes ?? []).map((theme) => (
                        <option key={theme.id} value={theme.id}>{theme.label}</option>
                      ))}
                    </select>
                  </label>
                  <label className="plot-control-row">
                    <span>Font scale</span>
                    <input max="1.4" min="0.8" onChange={(event) => updateRefineDraft({ fontScale: Number(event.target.value) })} step="0.05" type="range" value={refineDraft?.fontScale ?? 1} />
                  </label>
                  <label className="plot-control-row">
                    <span>Marker size</span>
                    <input max="8" min="2" onChange={(event) => updateRefineDraft({ markerSize: Number(event.target.value) })} step="0.5" type="range" value={refineDraft?.markerSize ?? 4} />
                  </label>
                  <label className="plot-control-row">
                    <span>Line thickness</span>
                    <input max="3" min="0.8" onChange={(event) => updateRefineDraft({ lineWidth: Number(event.target.value) })} step="0.1" type="range" value={refineDraft?.lineWidth ?? 1.4} />
                  </label>
                  <label className="plot-control-row">
                    <span>Annotation</span>
                    <textarea value={refineDraft?.annotation ?? ""} onChange={(event) => updateRefineDraft({ annotation: event.target.value })} rows={3} />
                  </label>
                </div>
              </section>

              <section className="plot-refine-preview">
                <div className="plot-refine-preview-shell" ref={previewShellRef}>
                  <div className="plot-refine-preview-draft">
                    <strong>{refineDraft?.title || currentPreviewLabel}</strong>
                    <span>{refineDraft?.subtitle || wizard.inspection?.recommendation.reason || "Ready to refine."}</span>
                  </div>
                  <div
                    className={`plot-refine-legend ${dragAnchor ? "dragging" : ""}`}
                    onPointerDown={(event: ReactPointerEvent<HTMLDivElement>) => {
                      legendDragRef.current = {
                        pointerId: event.pointerId,
                        startX: event.clientX,
                        startY: event.clientY,
                      };
                      setDragAnchor(refineDraft?.legendAnchor ?? "top-right");
                      event.currentTarget.setPointerCapture(event.pointerId);
                    }}
                    onPointerUp={(event) => {
                      const shell = previewShellRef.current?.getBoundingClientRect();
                      if (!shell || !legendDragRef.current) {
                        legendDragRef.current = null;
                        return;
                      }
                      const x = event.clientX - shell.left;
                      const y = event.clientY - shell.top;
                      const horizontal = x < shell.width / 3 ? "left" : x > shell.width * 2 / 3 ? "right" : "center";
                      const vertical = y < shell.height / 3 ? "top" : y > shell.height * 2 / 3 ? "bottom" : "center";
                      const nextAnchor =
                        vertical === "top"
                          ? horizontal === "left"
                            ? "top-left"
                            : horizontal === "right"
                              ? "top-right"
                              : "top-center"
                          : vertical === "bottom"
                            ? horizontal === "left"
                              ? "bottom-left"
                              : horizontal === "right"
                                ? "bottom-right"
                                : "bottom-center"
                            : horizontal === "left"
                              ? "inside-top-left"
                              : "inside-top-right";
                      setDragAnchor(nextAnchor);
                      updateRefineDraft({ legendAnchor: nextAnchor });
                      legendDragRef.current = null;
                    }}
                    style={legendAnchorStyle(refineDraft?.legendAnchor ?? "top-right")}
                  >
                    <strong>{refineDraft?.legendTitle || "Legend"}</strong>
                    <span>Drag to snap</span>
                  </div>
                  <PreviewPane
                    busy={previewBusy || preflightBusy}
                    error={previewError ?? preflightRequestError}
                    onChangeIndex={wizard.setPreviewIndex}
                    previewIndex={wizard.previewIndex}
                    previews={wizard.previews}
                  />
                  <div className="plot-refine-preview-foot">
                    <span>{refineDraft?.xLabel || selectedXLabel}</span>
                    <span>{refineDraft?.yLabel || selectedYLabel}</span>
                    <span>{refineDraft?.legendSnapGrid ? "Snap on" : "Snap off"}</span>
                  </div>
                </div>
              </section>
            </div>
          </section>
          <aside className="plot-flow-v3-side">
            <InspectorPanel kicker="Export" title="Delivery settings">
              <div className="plot-state-stack">
                <div className="plot-state-card">
                  <span>Ready</span>
                  <strong>{wizard.template ? templateLabel(meta, wizard.template) : "Choose a template"}</strong>
                  <p>{wizard.inspection?.recommendation_summary ?? "The figure is ready for refinement."}</p>
                </div>
                <div className="plot-state-card">
                  <span>Export path</span>
                  <strong>{exportOutputPath || "Choose a destination"}</strong>
                  <p>{wizard.exportResult?.output_dir ? "The latest export finished." : "Use the export modal to choose a directory."}</p>
                </div>
              </div>
            </InspectorPanel>
          </aside>
        </div>
      ) : null}

      <footer className="plot-flow-v3-footer">
        <span>{stageHint(routeFlowStage)}</span>
        <div className="plot-flow-v3-footer-actions">
          {routeFlowStage !== "import" ? (
            <button className="ghost-button" onClick={() => onNavigate(plotRoute("import"))} type="button">
              Back
            </button>
          ) : null}
          {routeFlowStage === "template" ? (
            <button className="primary-button" disabled={!wizard.template} onClick={continueFromTemplate} type="button">
              Continue
            </button>
          ) : routeFlowStage === "refine" ? (
            <button className="primary-button" onClick={() => setShowExportModal(true)} type="button">
              Export
            </button>
          ) : (
            <button className="primary-button" disabled={!wizard.inputPath} onClick={continueFromImport} type="button">
              Continue
            </button>
          )}
        </div>
      </footer>

      {showRecentModal ? (
        <div className="plot-modal-backdrop" role="presentation" onClick={() => setShowRecentModal(false)}>
          <div className="plot-modal-card" role="dialog" aria-label="Open recent data" onClick={(event) => event.stopPropagation()}>
            <SectionHeader kicker="Open data" title="Recent files" description="Choose a recent data file to replace the current session." />
            <div className="plot-modal-list">
              {recentDataFiles.length === 0 ? (
                <div className="placeholder-card">No recent data files yet.</div>
              ) : (
                recentDataFiles.map((entry) => (
                  <CompactListRow
                    key={entry.id}
                    onSelect={() => void openRecentData(entry.path)}
                    subtitle={entry.detail}
                    title={entry.title}
                  />
                ))
              )}
            </div>
          </div>
        </div>
      ) : null}

      {showTemplateGallery ? (
        <div className="plot-modal-backdrop" role="presentation" onClick={() => setShowTemplateGallery(false)}>
          <div className="plot-modal-card wide" role="dialog" aria-label="More chart types" onClick={(event) => event.stopPropagation()}>
            <SectionHeader kicker="Gallery" title="More chart types" description="Browse chart families by category. Selecting one updates the preview immediately." />
            <div className="plot-gallery-grid">
              {galleryGroups.map(([category, templates]) => (
                <section className="plot-gallery-group" key={category}>
                  <strong>{category}</strong>
                  <div className="plot-gallery-group-grid">
                    {templates.map((template) => (
                      <button
                        className={`plot-template-card gallery ${wizard.template === template.id ? "selected" : ""}`}
                        key={template.id}
                        onClick={() => {
                          updateWizardTemplate(template.id);
                          setShowTemplateGallery(false);
                        }}
                        type="button"
                      >
                        <div className={`plot-template-thumb ${plotThumbClass(template.id)}`} aria-hidden="true" />
                        <div className="plot-template-card-copy">
                          <strong>{template.label}</strong>
                          <span>{template.default_size}</span>
                          <p>{template.description}</p>
                        </div>
                      </button>
                    ))}
                  </div>
                </section>
              ))}
            </div>
          </div>
        </div>
      ) : null}

      {showExportModal ? (
        <div className="plot-modal-backdrop" role="presentation" onClick={() => setShowExportModal(false)}>
          <div className="plot-modal-card export" role="dialog" aria-label="Export plot" onClick={(event) => event.stopPropagation()}>
            <SectionHeader kicker="Export" title="Choose export destination" description="The bundle defaults to the source folder when possible." />
            <div className="plot-export-form">
              <label className="plot-control-row">
                <span>Bundle name</span>
                <input
                  value={exportDraft?.filename ?? ""}
                  onChange={(event) => setExportDraft((current) => current ? { ...current, filename: event.target.value } : current)}
                />
              </label>
              <label className="plot-control-row">
                <span>Output folder</span>
                <input
                  value={exportDraft?.outputRoot ?? ""}
                  onChange={(event) => setExportDraft((current) => current ? { ...current, outputRoot: event.target.value } : current)}
                />
              </label>
              <div className="plot-export-actions">
                <button
                  className="ghost-button"
                  onClick={async () => {
                    try {
                      const selected = await openDialog({ directory: true, multiple: false, defaultPath: exportDraft?.outputRoot || undefined });
                      const path = toDialogPaths(selected, 1)[0];
                      if (path) {
                        setExportDraft((current) => current ? { ...current, outputRoot: path } : current);
                      }
                    } catch (error) {
                      wizard.setError(getErrorMessage(error));
                    }
                  }}
                  type="button"
                >
                  Choose location
                </button>
                <button className="primary-button" disabled={!wizard.inputPath || !wizard.template} onClick={() => void runExport()} type="button">
                  Export PDF
                </button>
              </div>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}

export const WizardScreen = PlotScreen;
