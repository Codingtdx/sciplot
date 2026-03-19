import type { PreflightResult, TemplateName, WizardStep } from "../../lib/types";

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
