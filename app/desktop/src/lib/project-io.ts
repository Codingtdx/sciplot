import { inspectFile, openProject } from "./api";
import { extractComposerProject, normalizeComposerProject } from "./composer";
import { extractWizardProject } from "./projects";
import type {
  ComposerProject,
  InspectResponse,
  InputInspection,
  RenderOptionsPayload,
  TemplateName,
  WizardProject,
  WizardStep,
  WorkbenchMeta,
} from "./types";
import { selectionFromInspection } from "./wizard";

type WizardStoreSnapshot = {
  busy: boolean;
  reset(): void;
  setBusy(value: boolean): void;
  setError(value: string | null): void;
  setInputPath(value: string): void;
  setInspection(value: InputInspection | null): void;
  setOptions(value: RenderOptionsPayload): void;
  setOutputs(value: string[]): void;
  setSheet(value: string | number): void;
  setSheetNames(value: string[]): void;
  setStep(value: WizardStep): void;
  setTemplate(value: TemplateName | null): void;
};

type ComposerStoreSnapshot = {
  setProject(project: ComposerProject): void;
  setSelectedId(value: string | null): void;
};

export function applyInspectionToWizard(
  wizard: WizardStoreSnapshot,
  meta: WorkbenchMeta | null,
  inspected: InspectResponse,
  overrides?: {
    template?: TemplateName | null;
    options?: RenderOptionsPayload;
    nextStep?: WizardStep;
  },
) {
  const selection = selectionFromInspection(meta, inspected.inspection, {
    template: overrides?.template,
    options: overrides?.options,
  });
  wizard.setInputPath(inspected.input_path);
  wizard.setSheet(inspected.sheet);
  wizard.setSheetNames(inspected.sheet_names);
  wizard.setInspection(inspected.inspection);
  wizard.setTemplate(selection.template);
  wizard.setOptions(selection.options);
  wizard.setStep(
    overrides?.nextStep ?? (inspected.sheet_names.length > 1 ? "sheet" : "inspect"),
  );
}

export async function loadWizardDataFile(
  wizard: WizardStoreSnapshot,
  meta: WorkbenchMeta | null,
  filePath: string,
  initialSheet: string | number = 0,
  nextStep?: WizardStep,
): Promise<InspectResponse> {
  const keepBusy = wizard.busy;
  wizard.reset();
  wizard.setBusy(keepBusy);
  wizard.setError(null);
  wizard.setInputPath(filePath);
  wizard.setStep("file");

  const inspected = await inspectFile(filePath, initialSheet);
  applyInspectionToWizard(wizard, meta, inspected, { nextStep });
  return inspected;
}

export async function loadWizardProjectFile(
  wizard: WizardStoreSnapshot,
  meta: WorkbenchMeta | null,
  projectPath: string,
): Promise<WizardProject> {
  const keepBusy = wizard.busy;
  wizard.reset();
  wizard.setBusy(keepBusy);
  wizard.setError(null);

  const payload = extractWizardProject(await openProject(projectPath));

  const { input_path, options, outputs, sheet, template } = payload.wizard;
  const inspected = await inspectFile(input_path, sheet);
  applyInspectionToWizard(wizard, meta, inspected, {
    template: template ?? inspected.inspection.recommendation.template,
    options,
  });
  wizard.setOutputs(outputs ?? []);
  wizard.setStep(outputs && outputs.length > 0 ? "export" : "options");
  return payload;
}

export async function loadComposerProjectFile(
  composer: ComposerStoreSnapshot,
  projectPath: string,
): Promise<ComposerProject> {
  const payload = await openProject(projectPath);
  const project = extractComposerProject(payload);
  const normalized = normalizeComposerProject(project);
  composer.setProject(normalized);
  composer.setSelectedId(null);
  return normalized;
}
