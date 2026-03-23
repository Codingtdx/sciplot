import type { StepFlowItem } from "../../components/StepFlow";
import type {
  DataTemplateFolderResponse,
  InputInspection,
  PlotStage,
  PreflightResult,
  TemplateName,
  WizardStep,
  WorkbenchMeta,
} from "../../lib/types";
import {
  PLOT_STAGE_ORDER,
  PLOT_STAGES,
  formatLeaf,
  templateLabel,
} from "../../lib/workbench";
import { getErrorMessage } from "../../lib/workbench";

export type WizardStatusChip = {
  label: string;
  tone: "accent" | "good" | "warn";
};

export function deriveWizardStep(args: {
  inputPath: string;
  inspectionReady: boolean;
  template: TemplateName | null;
  autoChecking: boolean;
  preflightReady: boolean;
  outputsCount: number;
}): WizardStep {
  if (!args.inputPath) {
    return "file";
  }
  if (args.outputsCount > 0) {
    return "export";
  }
  if (args.autoChecking || args.preflightReady) {
    return "preflight";
  }
  if (args.template) {
    return "options";
  }
  if (args.inspectionReady) {
    return "inspect";
  }
  return "file";
}

export function getWizardStatusChip(args: {
  inputPath: string;
  busy: boolean;
  previewBusy: boolean;
  preflightBusy: boolean;
  previewActivity: "idle" | "scheduled" | "running" | "ready" | "error";
  preflightActivity: "idle" | "scheduled" | "running" | "ready" | "error";
  hasBlockingErrors: boolean;
  outputsCount: number;
  preflightReady: boolean;
  inspectionReady: boolean;
}): WizardStatusChip {
  if (!args.inputPath) {
    return { label: "Waiting for a file", tone: "warn" };
  }
  if (args.busy) {
    return { label: "Loading file", tone: "accent" };
  }
  if (args.previewActivity === "scheduled" || args.preflightActivity === "scheduled") {
    return { label: "Queueing checks", tone: "accent" };
  }
  if (args.previewActivity === "running" && args.preflightActivity === "running") {
    return { label: "Refreshing preview and review", tone: "accent" };
  }
  if (args.previewActivity === "running") {
    return { label: "Refreshing preview", tone: "accent" };
  }
  if (args.preflightActivity === "running") {
    return { label: "Checking export readiness", tone: "accent" };
  }
  if (args.previewBusy || args.preflightBusy) {
    return { label: "Reviewing changes", tone: "accent" };
  }
  if (args.hasBlockingErrors) {
    return { label: "Fix blockers", tone: "warn" };
  }
  if (args.outputsCount > 0) {
    return { label: "Export complete", tone: "good" };
  }
  if (args.preflightReady) {
    return { label: "Ready to export", tone: "good" };
  }
  if (args.inspectionReady) {
    return { label: "Recommendation ready", tone: "accent" };
  }
  return { label: "Waiting for a file", tone: "warn" };
}

export function getExpectedWizardOutputs(
  outputs: string[],
  preflight: PreflightResult | null,
): string[] {
  if (outputs.length > 0) {
    return outputs;
  }
  return (preflight?.output_filenames ?? []).map((filename) => filename);
}

export function getWizardStatusForPlot(args: {
  routeStage: PlotStage;
  busy: boolean;
  previewBusy: boolean;
  preflightBusy: boolean;
  hasBlockingErrors: boolean;
  hasInspection: boolean;
  hasInput: boolean;
  outputsCount: number;
}): WizardStatusChip {
  if (!args.hasInput) {
    return { label: "Waiting for a file", tone: "warn" };
  }
  if (args.busy) {
    return { label: "Loading file", tone: "accent" };
  }
  if (args.preflightBusy) {
    return { label: "Checking readiness", tone: "accent" };
  }
  if (args.previewBusy) {
    return { label: "Refreshing preview", tone: "accent" };
  }
  if (args.outputsCount > 0 && args.routeStage === "export") {
    return { label: "Export complete", tone: "good" };
  }
  if (args.hasBlockingErrors) {
    return { label: "Fix blockers", tone: "warn" };
  }
  if (args.routeStage === "review" && args.hasInspection) {
    return { label: "Reviewing export", tone: "accent" };
  }
  if (args.routeStage === "type" && args.hasInspection) {
    return { label: "Recommendation ready", tone: "good" };
  }
  return { label: "In progress", tone: "accent" };
}

export function buildWizardStepFlowItems(args: {
  routeStage: PlotStage;
  hasInput: boolean;
  hasInspection: boolean;
  hasTemplate: boolean;
  sheetNamesLength: number;
  preflight: PreflightResult | null;
  outputsLength: number;
  onSelectStage(stage: PlotStage): void;
}): StepFlowItem[] {
  const currentIndex = PLOT_STAGE_ORDER.indexOf(args.routeStage);
  return PLOT_STAGES.map((step, index) => {
    const reachable =
      step.id === "import" ||
      (step.id === "sheet" && args.hasInput && args.sheetNamesLength > 1) ||
      (step.id === "type" && args.hasInspection) ||
      (step.id === "tune" && args.hasTemplate) ||
      (step.id === "review" && args.hasTemplate) ||
      (step.id === "export" &&
        args.hasTemplate &&
        (args.routeStage === "export" || args.preflight !== null || args.outputsLength > 0));
    const status =
      step.id === args.routeStage
        ? "current"
        : !reachable
          ? "disabled"
          : index < currentIndex
            ? "complete"
            : "upcoming";
    return {
      ...step,
      status,
      onSelect: status === "complete" ? () => args.onSelectStage(step.id) : null,
    };
  });
}

export function buildWizardSummaryRows(args: {
  inputPath: string;
  sheet: string | number;
  sheetNames: string[];
  inspection: InputInspection | null;
  template: TemplateName | null;
  meta: WorkbenchMeta | null;
}) {
  return [
    {
      label: "File",
      value: args.inputPath ? formatLeaf(args.inputPath) : "No file selected",
    },
    {
      label: "Sheet",
      value:
        typeof args.sheet === "string"
          ? args.sheet
          : args.sheetNames[args.sheet] ?? args.sheetNames[0] ?? "-",
    },
    {
      label: "Model",
      value: args.inspection?.model_label ?? "Waiting for inspect",
    },
    {
      label: "Template",
      value: args.template ? templateLabel(args.meta, args.template) : "Not selected",
    },
  ];
}

export function validateTemplateFolderResponse(response: DataTemplateFolderResponse) {
  if (response.folder_path.trim() === "" || response.folder_name.trim() === "") {
    throw new Error(`Template folder path is invalid: ${response.folder_path || "(empty path)"}`);
  }
  if (response.files.length === 0) {
    throw new Error("Template file generation failed: sidecar returned no workbook files.");
  }
  for (const templateFile of response.files) {
    if (templateFile.filename.trim() === "" || templateFile.file_path.trim() === "") {
      throw new Error(
        `Template file generation failed: ${templateFile.chart_type} is missing its filename or path.`,
      );
    }
  }
}

export function formatTemplateBuildError(error: unknown) {
  const detail = getErrorMessage(error).trim();
  if (detail.includes(" -> http://") || detail.includes(" -> https://") || detail.includes(" -> ")) {
    return detail;
  }
  if (
    detail.startsWith("Template folder path is invalid:")
    || detail.startsWith("Template file generation failed:")
  ) {
    return detail;
  }
  return `Sidecar materialize failed: ${detail}`;
}

export function formatTemplateOpenError(error: unknown) {
  return `Template folder generated, but opening it failed: ${getErrorMessage(error).trim()}`;
}
