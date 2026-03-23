import { loadWizardDataFile } from "../../lib/project-io";
import type {
  InputInspection,
  PlotStage,
  TemplateName,
  WorkbenchMeta,
} from "../../lib/types";
import {
  confirmReplaceWizardSession,
  formatLeaf,
  getErrorMessage,
} from "../../lib/workbench";

type WizardStoreForRecentData = Parameters<typeof loadWizardDataFile>[0] & {
  inputPath: string;
  inspection: InputInspection | null;
  template: TemplateName | null;
  outputs: string[];
  exportResult: { output_dir?: string | null } | null;
  setBusy(value: boolean): void;
  setError(value: string | null): void;
};

type Args = {
  wizard: WizardStoreForRecentData;
  meta: WorkbenchMeta | null;
  goToStage(stage: PlotStage): void;
};

export function useWizardRecentDataAction({ wizard, meta, goToStage }: Args) {
  const reopenRecentData = async (path: string) => {
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
    wizard.setError(null);
    try {
      const inspected = await loadWizardDataFile(wizard, meta, path);
      goToStage(inspected.sheet_names.length > 1 ? "sheet" : "type");
    } catch (error) {
      wizard.setError(getErrorMessage(error));
    } finally {
      wizard.setBusy(false);
    }
  };

  return { reopenRecentData };
}
