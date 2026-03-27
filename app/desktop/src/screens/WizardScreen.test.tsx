import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { open } from "@tauri-apps/plugin-dialog";

import { inspectFile } from "../lib/api";
import { useWizardStore, useWorkbenchStore } from "../lib/store";
import type { InspectResponse, PlotDatasetPreview, PlotStage } from "../lib/types";
import { TEST_META } from "../test/fixtures";
import { WizardScreen } from "./WizardScreen";

vi.mock("@tauri-apps/plugin-dialog", () => ({
  open: vi.fn(),
}));

vi.mock("../components/PreviewPane", () => ({
  PreviewPane: ({
    previews,
    previewIndex,
  }: {
    previews: Array<{ filename: string }>;
    previewIndex: number;
  }) => (
    <div data-testid="preview-pane">
      {previews[previewIndex]?.filename ?? "empty"}
    </div>
  ),
}));

vi.mock("../lib/api", async () => {
  const actual = await vi.importActual<typeof import("../lib/api")>("../lib/api");
  return {
    ...actual,
    inspectFile: vi.fn(),
    renderPreview: vi.fn().mockResolvedValue({
      template: "curve",
      sheet: 0,
      previews: [
        {
          filename: "curve.png",
          png_base64:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO3+o1kAAAAASUVORK5CYII=",
        },
      ],
    }),
    preflightRender: vi.fn().mockResolvedValue({
      input_path: "/tmp/curve.csv",
      sheet: 0,
      template: "curve",
      options: {},
      preflight: {
        template: "curve",
        warnings: [],
        errors: [],
        output_filenames: ["curve.pdf"],
      },
    }),
    exportRender: vi.fn().mockResolvedValue({
      outputs: ["/tmp/exports/curve.pdf"],
      output_dir: "/tmp/exports",
      preview_outputs: ["/tmp/exports/curve.preview.png"],
      artifact_paths: ["/tmp/exports/codegod_manifest.json"],
      manifest_path: "/tmp/exports/codegod_manifest.json",
      submission_report: {
        context: "export",
        readiness: "ready",
        summary: "Export is submission-ready.",
        output_count: 1,
        output_filenames: ["curve.pdf"],
        blockers: [],
        checks: [],
      },
    }),
  };
});

vi.mock("./wizard/useWizardPreview", () => ({
  useWizardPreview: () => ({
    busy: false,
    error: null,
    activity: "idle",
  }),
}));

vi.mock("./wizard/useWizardPreflight", () => ({
  useWizardPreflight: () => ({
    busy: false,
    error: null,
    activity: "idle",
  }),
}));

const TEST_DATASET: PlotDatasetPreview = {
  dataset_id: "dataset_123",
  model: "curve_table",
  raw_rows: 4,
  raw_cols: 3,
  column_profiles: [
    {
      name: "Time",
      header_preview: ["Time", "s", null],
      inferred_type: "numeric",
      non_empty_count: 4,
      missing_count: 0,
      min_value: 0,
      max_value: 3,
    },
    {
      name: "Stress",
      header_preview: ["Stress", "MPa", null],
      inferred_type: "numeric",
      non_empty_count: 4,
      missing_count: 0,
      min_value: 10,
      max_value: 16,
    },
    {
      name: "Group",
      header_preview: ["Group", null, null],
      inferred_type: "text",
      non_empty_count: 4,
      missing_count: 0,
    },
  ],
  candidate_roles: {
    x: ["Time"],
    y: ["Stress"],
    z: [],
    group: ["Group"],
    sample: [],
    value: [],
    metric: [],
    label: [],
    series: [],
  },
  data_shapes: ["curve_like"],
  semantic_signals: ["paired x/y table"],
  quality_flags: [],
  sample_rows: [
    [0, 10, "A"],
    [1, 12, "A"],
    [2, 14, "B"],
    [3, 16, "B"],
  ],
};

const TEST_INSPECTION: InspectResponse = {
  input_path: "/tmp/curve.csv",
  sheet: 0,
  sheet_names: ["Sheet1"],
  inspection: {
    model: "curve_table",
    model_label: "Paired curve table (curve_table)",
    recommendation: {
      template: "curve",
      reason: "Detected a standard paired curve table, so a basic curve plot is recommended by default.",
      size: "60x55",
      xscale: "linear",
      yscale: "linear",
      reverse_x: false,
    },
    recommendations: [
      {
        template_id: "curve",
        canonical_id: "curve",
        role: "canonical",
        lifecycle_policy: "canonical",
        implementation_id: "curve",
        score: 92.2,
        rank: 1,
        reason: "Best match for a paired curve table.",
        suitability_hint: "Fastest path to a clean line chart.",
        score_gap_to_top: 0,
        why_hard_match: ["Curve tables map cleanly to line charts."],
        why_soft_prior: ["Minimal controls keep the scene lightweight."],
        inferred_mapping: { x: "Time", y: "Stress" },
        optional_enhancements: ["Use point_line for visible markers."],
        preview_config_summary: { size: "60x55" },
      },
      {
        template_id: "point_line",
        canonical_id: "point_line",
        role: "canonical",
        lifecycle_policy: "canonical",
        implementation_id: "point_line",
        score: 88.1,
        rank: 2,
        reason: "Marker-forward alternative.",
        suitability_hint: "Good when the user wants a slightly more explicit series view.",
        score_gap_to_top: 4.1,
        why_hard_match: ["Compatible with paired x/y data."],
        why_soft_prior: ["Markers can improve readability for sparse series."],
        inferred_mapping: { x: "Time", y: "Stress" },
        optional_enhancements: ["Reduce marker size for dense data."],
        preview_config_summary: { size: "60x55" },
      },
    ],
    primary_recommendation: [
      {
        template_id: "curve",
        canonical_id: "curve",
        role: "canonical",
        lifecycle_policy: "canonical",
        implementation_id: "curve",
        score: 92.2,
        rank: 1,
        reason: "Best match for a paired curve table.",
        suitability_hint: "Fastest path to a clean line chart.",
        score_gap_to_top: 0,
        why_hard_match: ["Curve tables map cleanly to line charts."],
        why_soft_prior: ["Minimal controls keep the scene lightweight."],
        inferred_mapping: { x: "Time", y: "Stress" },
        optional_enhancements: ["Use point_line for visible markers."],
        preview_config_summary: { size: "60x55" },
      },
    ],
    alternative_recommendations: [
      {
        template_id: "point_line",
        canonical_id: "point_line",
        role: "canonical",
        lifecycle_policy: "canonical",
        implementation_id: "point_line",
        score: 88.1,
        rank: 2,
        reason: "Marker-forward alternative.",
        suitability_hint: "Good when the user wants a slightly more explicit series view.",
        score_gap_to_top: 4.1,
        why_hard_match: ["Compatible with paired x/y data."],
        why_soft_prior: ["Markers can improve readability for sparse series."],
        inferred_mapping: { x: "Time", y: "Stress" },
        optional_enhancements: ["Reduce marker size for dense data."],
        preview_config_summary: { size: "60x55" },
      },
    ],
    warnings: [],
    signals: ["Detected a standard paired curve table."],
  },
  dataset: TEST_DATASET,
};

function resetState() {
  useWizardStore.getState().reset();
  useWorkbenchStore.setState({
    lastRoute: "/",
    pdfImportMode: "graph",
    recentProjects: [],
    settings: {
      auto_status_poll: true,
      remember_last_screen: true,
      appearance_mode: "system",
      theme_preset_id: "paper-lab",
    },
  });
}

function renderStage(stage: PlotStage, onNavigate = vi.fn()) {
  render(<WizardScreen meta={TEST_META} onNavigate={onNavigate} routeStage={stage} />);
  return onNavigate;
}

describe("WizardScreen", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(open).mockReset();
    vi.mocked(inspectFile).mockReset();
    resetState();

    vi.mocked(inspectFile).mockResolvedValue(TEST_INSPECTION);
  });

  afterEach(() => {
    cleanup();
    vi.useRealTimers();
  });

  it("opens as a single clean three-stage Plot scene", () => {
    renderStage("import");

    expect(screen.getByText("Drag a data file here")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Upload file" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Browse files" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Open recent" })).toBeInTheDocument();
    expect(screen.queryByText("Current dataset")).not.toBeInTheDocument();
    expect(screen.queryByText("Choose Template")).not.toBeInTheDocument();
    expect(screen.queryByText("Refine & Export")).not.toBeInTheDocument();
  });

  it("imports a file and transitions into the template stage", async () => {
    vi.mocked(open).mockResolvedValue("/tmp/curve.csv");
    const onNavigate = vi.fn();

    renderStage("import", onNavigate);
    fireEvent.click(screen.getByRole("button", { name: "Browse files" }));

    await waitFor(() => expect(onNavigate).toHaveBeenCalledWith("/plot/type"));
    expect(screen.getByText("Current dataset")).toBeInTheDocument();
    expect(screen.getByText("curve.csv")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Sheet1" })).toBeInTheDocument();
    expect(screen.getByText("Rows and cells")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Continue" })).toBeInTheDocument();
  });

});
