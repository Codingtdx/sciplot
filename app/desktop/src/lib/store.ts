import { create } from "zustand";
import { createJSONStorage, persist } from "zustand/middleware";

import type {
  ComposerPanel,
  ComposerProject,
  ComposerText,
  InputInspection,
  PalettePreset,
  PdfImportMode,
  PreflightResult,
  PreviewItem,
  RecentProjectEntry,
  RenderOptionsPayload,
  TensileComparisonExportResponse,
  TensileComparisonSource,
  TensileReplicateResponse,
  TemplateName,
  WizardStep,
  WorkbenchScreen,
  WorkbenchSettings,
} from "./types";
import { EMPTY_COMPOSER_PROJECT, normalizeComposerProject } from "./composer";
import {
  moveTensileComparisonSource as moveTensileComparisonSourceList,
  normalizeTensileComparisonSources,
  upsertTensileComparisonSource,
} from "./tensile-comparison";

type WizardState = {
  inputPath: string;
  sheet: string | number;
  sheetNames: string[];
  inspection: InputInspection | null;
  template: TemplateName | null;
  options: RenderOptionsPayload;
  preflight: PreflightResult | null;
  previews: PreviewItem[];
  previewIndex: number;
  outputs: string[];
  step: WizardStep;
  sidecarReady: boolean;
  busy: boolean;
  error: string | null;
  setSidecarReady(value: boolean): void;
  setInputPath(value: string): void;
  setSheet(value: string | number): void;
  setSheetNames(value: string[]): void;
  setInspection(value: InputInspection | null): void;
  setTemplate(value: TemplateName | null): void;
  setOptions(value: RenderOptionsPayload): void;
  setPreflight(value: PreflightResult | null): void;
  setPreviews(value: PreviewItem[]): void;
  setPreviewIndex(value: number): void;
  setOutputs(value: string[]): void;
  setStep(value: WizardStep): void;
  setBusy(value: boolean): void;
  setError(value: string | null): void;
  reset(): void;
};

type TensileState = {
  preprocessResult: TensileReplicateResponse | null;
  comparisonSources: TensileComparisonSource[];
  comparisonResult: TensileComparisonExportResponse | null;
  setPreprocessResult(value: TensileReplicateResponse | null): void;
  addComparisonSource(value: TensileComparisonSource): void;
  removeComparisonSource(workbookPath: string): void;
  moveComparisonSource(workbookPath: string, offset: -1 | 1): void;
  clearComparisonSources(): void;
  setComparisonResult(value: TensileComparisonExportResponse | null): void;
  reset(): void;
};

type ComposerState = {
  project: ComposerProject;
  previewPng: string | null;
  validationError: string | null;
  selectedId: string | null;
  palettePreset: PalettePreset;
  setProject(project: ComposerProject): void;
  updatePanels(panels: ComposerPanel[]): void;
  updateTexts(texts: ComposerText[]): void;
  setPreview(png: string | null, validationError: string | null): void;
  setSelectedId(value: string | null): void;
  setPalettePreset(value: PalettePreset): void;
  reset(): void;
};

type WorkbenchState = {
  lastScreen: WorkbenchScreen;
  pdfImportMode: PdfImportMode;
  recentProjects: RecentProjectEntry[];
  settings: WorkbenchSettings;
  setLastScreen(value: WorkbenchScreen): void;
  setPdfImportMode(value: PdfImportMode): void;
  rememberProject(entry: Omit<RecentProjectEntry, "id" | "updated_at">): void;
  clearRecentProjects(): void;
  updateSettings(value: Partial<WorkbenchSettings>): void;
};

const storage = createJSONStorage(() => localStorage);

const defaultOptions: RenderOptionsPayload = {};

const emptyProject: ComposerProject = {
  ...EMPTY_COMPOSER_PROJECT,
  layout_grid: { ...EMPTY_COMPOSER_PROJECT.layout_grid },
  regions: [],
  panels: [],
  texts: [],
};

const defaultWorkbenchSettings: WorkbenchSettings = {
  auto_status_poll: true,
  remember_last_screen: true,
  theme_preference: "system",
};

export const useWizardStore = create<WizardState>()(
  persist(
    (set) => ({
      inputPath: "",
      sheet: 0,
      sheetNames: [],
      inspection: null,
      template: null,
      options: { ...defaultOptions },
      preflight: null,
      previews: [],
      previewIndex: 0,
      outputs: [],
      step: "file",
      sidecarReady: false,
      busy: false,
      error: null,
      setSidecarReady: (value) => set({ sidecarReady: value }),
      setInputPath: (value) => set({ inputPath: value }),
      setSheet: (value) => set({ sheet: value }),
      setSheetNames: (value) => set({ sheetNames: value }),
      setInspection: (value) => set({ inspection: value }),
      setTemplate: (value) => set({ template: value }),
      setOptions: (value) => set({ options: { ...value } }),
      setPreflight: (value) => set({ preflight: value }),
      setPreviews: (value) => set({ previews: value, previewIndex: 0 }),
      setPreviewIndex: (value) => set({ previewIndex: value }),
      setOutputs: (value) => set({ outputs: value }),
      setStep: (value) => set({ step: value }),
      setBusy: (value) => set({ busy: value }),
      setError: (value) => set({ error: value }),
      reset: () =>
        set({
          inputPath: "",
          sheet: 0,
          sheetNames: [],
          inspection: null,
          template: null,
          options: { ...defaultOptions },
          preflight: null,
          previews: [],
          previewIndex: 0,
          outputs: [],
          step: "file",
          busy: false,
          error: null,
        }),
    }),
    {
      name: "codegod-wizard-store",
      storage,
      partialize: (state) => ({
        inputPath: state.inputPath,
        sheet: state.sheet,
        sheetNames: state.sheetNames,
        inspection: state.inspection,
        template: state.template,
        options: state.options,
        preflight: state.preflight,
        outputs: state.outputs,
        step: state.step,
      }),
    },
  ),
);

export const useTensileStore = create<TensileState>()(
  persist(
    (set) => ({
      preprocessResult: null,
      comparisonSources: [],
      comparisonResult: null,
      setPreprocessResult: (value) => set({ preprocessResult: value }),
      addComparisonSource: (value) =>
        set((state) => ({
          comparisonSources: upsertTensileComparisonSource(state.comparisonSources, value),
          comparisonResult: null,
        })),
      removeComparisonSource: (workbookPath) =>
        set((state) => ({
          comparisonSources: normalizeTensileComparisonSources(
            state.comparisonSources.filter((item) => item.workbook_path !== workbookPath),
          ),
          comparisonResult: null,
        })),
      moveComparisonSource: (workbookPath, offset) =>
        set((state) => ({
          comparisonSources: moveTensileComparisonSourceList(
            state.comparisonSources,
            workbookPath,
            offset,
          ),
          comparisonResult: null,
        })),
      clearComparisonSources: () =>
        set({
          comparisonSources: [],
          comparisonResult: null,
        }),
      setComparisonResult: (value) => set({ comparisonResult: value }),
      reset: () =>
        set({
          preprocessResult: null,
          comparisonSources: [],
          comparisonResult: null,
        }),
    }),
    {
      name: "codegod-tensile-store",
      storage,
      partialize: (state) => ({
        preprocessResult: state.preprocessResult,
        comparisonSources: state.comparisonSources,
        comparisonResult: state.comparisonResult,
      }),
    },
  ),
);

export const useComposerStore = create<ComposerState>()(
  persist(
    (set) => ({
      project: { ...emptyProject, panels: [], texts: [] },
      previewPng: null,
      validationError: null,
      selectedId: null,
      palettePreset: "colorblind_safe",
      setProject: (project) => set({ project }),
      updatePanels: (panels) => set((state) => ({ project: { ...state.project, panels } })),
      updateTexts: (texts) => set((state) => ({ project: { ...state.project, texts } })),
      setPreview: (png, validationError) => set({ previewPng: png, validationError }),
      setSelectedId: (value) => set({ selectedId: value }),
      setPalettePreset: (value) => set({ palettePreset: value }),
      reset: () =>
        set({
          project: { ...emptyProject, panels: [], texts: [] },
          previewPng: null,
          validationError: null,
          selectedId: null,
          palettePreset: "colorblind_safe",
        }),
    }),
    {
      name: "codegod-composer-store",
      storage,
      version: 2,
      migrate: (persistedState) => {
        const state = persistedState as Partial<ComposerState> | undefined;
        return {
          project: state?.project
            ? normalizeComposerProject(state.project as ComposerProject)
            : { ...emptyProject, layout_grid: { ...emptyProject.layout_grid }, regions: [], panels: [], texts: [] },
          palettePreset: typeof state?.palettePreset === "string" ? state.palettePreset : "colorblind_safe",
        };
      },
      partialize: (state) => ({
        project: state.project,
        palettePreset: state.palettePreset,
      }),
    },
  ),
);

export const useWorkbenchStore = create<WorkbenchState>()(
  persist(
    (set) => ({
      lastScreen: "wizard",
      pdfImportMode: "graph",
      recentProjects: [],
      settings: { ...defaultWorkbenchSettings },
      setLastScreen: (value) => set({ lastScreen: value }),
      setPdfImportMode: (value) => set({ pdfImportMode: value }),
      rememberProject: (entry) =>
        set((state) => {
          const nextEntry: RecentProjectEntry = {
            ...entry,
            id: `${entry.mode}:${entry.kind}:${entry.path}`,
            updated_at: new Date().toISOString(),
          };
          const deduped = state.recentProjects.filter(
            (item) => item.id !== nextEntry.id,
          );
          return {
            recentProjects: [nextEntry, ...deduped].slice(0, 10),
          };
        }),
      clearRecentProjects: () => set({ recentProjects: [] }),
      updateSettings: (value) =>
        set((state) => ({
          settings: {
            ...state.settings,
            ...value,
          },
        })),
    }),
    {
      name: "codegod-workbench-store",
      storage,
      merge: (persistedState, currentState) => {
        const persisted = persistedState as Partial<WorkbenchState> | undefined;
        return {
          ...currentState,
          ...persisted,
          settings: {
            ...defaultWorkbenchSettings,
            ...(persisted?.settings ?? {}),
          },
        };
      },
    },
  ),
);
