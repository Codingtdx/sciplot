import type {
  DataTemplateFolderResponse,
  PlotStage,
  PreflightResult,
} from "../../lib/types";
import { getErrorMessage } from "../../lib/workbench";

export type WizardStatusChip = {
  label: string;
  tone: "accent" | "good" | "warn";
};

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
