import { exportRender, inspectFile } from "../../lib/api";
import { applyInspectionToWizard, loadWizardDataFile } from "../../lib/project-io";
import type {
  ExportResponse,
  InputInspection,
  PlotStage,
  PreflightResult,
  RecentProjectEntry,
  RenderOptionsPayload,
  SubmissionReport,
  TemplateName,
  WorkbenchMeta,
} from "../../lib/types";
import {
  confirmReplaceWizardSession,
  formatLeaf,
  getErrorMessage,
  templateLabel,
  toDialogPaths,
} from "../../lib/workbench";
import { openDialog } from "../../lib/tauri-dialog";

type WizardStoreForWorkflowActions = Parameters<typeof loadWizardDataFile>[0] & {
  inputPath: string;
  inspection: InputInspection | null;
  template: TemplateName | null;
  outputs: string[];
  exportResult: ExportResponse | null;
  preflight: PreflightResult | null;
  sheet: string | number;
  options: RenderOptionsPayload;
  submissionReport: SubmissionReport | null;
  setOutputs(value: string[]): void;
  setExportResult(value: ExportResponse | null): void;
  setSubmissionReport(value: SubmissionReport | null): void;
};

type Args = {
  wizard: WizardStoreForWorkflowActions;
  meta: WorkbenchMeta | null;
  hasBlockingErrors: boolean;
  rememberProject(entry: Omit<RecentProjectEntry, "id" | "updated_at">): void;
  goToStage(stage: PlotStage): void;
  invalidateRenderState(): void;
  onDialogError(error: unknown): void;
};

export function useWizardWorkflowActions({
  wizard,
  meta,
  hasBlockingErrors,
  rememberProject,
  goToStage,
  invalidateRenderState,
  onDialogError,
}: Args) {
  const openDataFile = async () => {
    let path: string | undefined;
    wizard.setError(null);
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
      onDialogError(error);
      return;
    }
    if (!path) {
      return;
    }
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
      return;
    }

    wizard.setBusy(true);
    try {
      const inspected = await loadWizardDataFile(wizard, meta, path);
      rememberProject({
        mode: "wizard",
        kind: "data",
        path: inspected.input_path,
        title: formatLeaf(inspected.input_path),
        detail: `Data file · ${inspected.sheet_names.length} sheets · ${templateLabel(meta, inspected.inspection.recommendation.template)}`,
      });
      goToStage(inspected.sheet_names.length > 1 ? "sheet" : "type");
    } catch (error) {
      wizard.setError(getErrorMessage(error));
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
      applyInspectionToWizard(wizard, meta, inspected, { nextStage: "type" });
      invalidateRenderState();
      goToStage("type");
    } catch (error) {
      wizard.setError(getErrorMessage(error));
    } finally {
      wizard.setBusy(false);
    }
  };

  const runExport = async () => {
    if (!wizard.inputPath || !wizard.template || !wizard.preflight || hasBlockingErrors) {
      return;
    }

    wizard.setError(null);
    wizard.setBusy(true);
    try {
      const response = await exportRender(
        {
          input_path: wizard.inputPath,
          sheet: wizard.sheet,
          template: wizard.template,
          options: wizard.options,
        },
      );
      wizard.setOutputs(response.outputs);
      wizard.setExportResult(response);
      wizard.setSubmissionReport(response.submission_report ?? wizard.submissionReport);
      goToStage("export");
    } catch (error) {
      wizard.setError(getErrorMessage(error));
    } finally {
      wizard.setBusy(false);
    }
  };

  return {
    openDataFile,
    rerunInspect,
    runExport,
  };
}
