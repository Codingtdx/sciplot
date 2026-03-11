import { create } from "zustand";

import type {
  ComposerPanel,
  ComposerProject,
  ComposerText,
  InputInspection,
  PalettePreset,
  PreflightResult,
  PreviewItem,
  RenderOptionsPayload,
  TemplateName,
  WizardStep,
} from "./types";

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
  setOptions(value: Partial<RenderOptionsPayload>): void;
  setPreflight(value: PreflightResult | null): void;
  setPreviews(value: PreviewItem[]): void;
  setPreviewIndex(value: number): void;
  setOutputs(value: string[]): void;
  setStep(value: WizardStep): void;
  setBusy(value: boolean): void;
  setError(value: string | null): void;
  reset(): void;
};

const defaultOptions: RenderOptionsPayload = {
  size: "60x55",
  xscale: "linear",
  yscale: "linear",
  reverse_x: false,
  baseline: "none",
  show_colorbar: true,
  palette_preset: "colorblind_safe",
  use_sidecar: null,
};

export const useWizardStore = create<WizardState>((set) => ({
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
  setOptions: (value) => set((state) => ({ options: { ...state.options, ...value } })),
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
}));

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

const emptyProject: ComposerProject = {
  version: 1,
  mode: "composer",
  canvas_width_mm: 180,
  canvas_height_mm: 170,
  grid_mm: 0.5,
  panels: [],
  texts: [],
  auto_labels: true,
};

export const useComposerStore = create<ComposerState>((set) => ({
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
    }),
}));
