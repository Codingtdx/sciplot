import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { open } from "@tauri-apps/plugin-dialog";

import {
  exportRender,
  materializeDataTemplateFolder,
  openPath,
  preflightRender,
  renderPreview,
} from "../lib/api";
import { loadWizardDataFile } from "../lib/project-io";
import { useWizardStore, useWorkbenchStore } from "../lib/store";
import type { InspectResponse, PlotStage } from "../lib/types";
import { TEST_META } from "../test/fixtures";
import { WizardScreen } from "./WizardScreen";

vi.mock("@tauri-apps/plugin-dialog", () => ({
  open: vi.fn(),
}));

vi.mock("../lib/project-io", async () => {
  const actual = await vi.importActual<typeof import("../lib/project-io")>("../lib/project-io");
  return {
    ...actual,
    loadWizardDataFile: vi.fn(),
  };
});

vi.mock("../lib/api", async () => {
  const actual = await vi.importActual<typeof import("../lib/api")>("../lib/api");
  return {
    ...actual,
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
    renderPreview: vi.fn().mockResolvedValue({
      template: "curve",
      sheet: 0,
      previews: [],
    }),
    exportRender: vi.fn().mockResolvedValue({
      outputs: ["/tmp/exports/curve.pdf"],
      output_dir: "/tmp/exports",
      preview_outputs: ["/tmp/exports/curve.preview.png"],
      artifact_paths: [
        "/tmp/exports/codegod_normalized_options.json",
        "/tmp/exports/codegod_manifest.json",
      ],
      manifest_path: "/tmp/exports/codegod_manifest.json",
      submission_report: {
        context: "export",
        readiness: "ready",
        summary: "Export is submission-ready under the current contract and style preset.",
        output_count: 1,
        output_filenames: ["curve.pdf"],
        blockers: [],
        checks: [],
      },
    }),
    openPath: vi.fn().mockResolvedValue({
      output_path: "/tmp/exports",
    }),
    materializeDataTemplateFolder: vi.fn(),
  };
});

const TEST_INSPECT_RESPONSE: InspectResponse = {
  input_path: "/tmp/curve.csv",
  sheet: 0,
  sheet_names: ["Sheet1"],
  inspection: {
    model: "curve_table",
    model_label: "Paired curve table (curve_table)",
    recommendation: {
      template: "curve",
      reason:
        "Detected a standard paired curve table, so a basic curve plot is recommended by default.",
      size: "60x55",
      xscale: "linear",
      yscale: "linear",
      reverse_x: false,
    },
    warnings: [],
    signals: ["Detected a standard paired curve table."],
  },
};

function getTemplateButton(label: string) {
  const button = screen
    .getAllByRole("button")
    .find((candidate) => candidate.querySelector("strong")?.textContent === label);
  expect(button).toBeTruthy();
  return button as HTMLButtonElement;
}

function renderStage(stage: PlotStage, onNavigate = vi.fn()) {
  render(<WizardScreen meta={TEST_META} onNavigate={onNavigate} routeStage={stage} />);
  return onNavigate;
}

describe("WizardScreen", () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(open).mockReset();
    vi.mocked(preflightRender).mockReset();
    vi.mocked(renderPreview).mockReset();
    vi.mocked(exportRender).mockReset();
    vi.mocked(openPath).mockReset();
    vi.mocked(materializeDataTemplateFolder).mockReset();
    vi.mocked(loadWizardDataFile).mockReset();
    vi.mocked(preflightRender).mockResolvedValue({
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
    });
    vi.mocked(renderPreview).mockResolvedValue({
      template: "curve",
      sheet: 0,
      previews: [],
    });
    vi.mocked(exportRender).mockResolvedValue({
      outputs: ["/tmp/exports/curve.pdf"],
      output_dir: "/tmp/exports",
      preview_outputs: ["/tmp/exports/curve.preview.png"],
      artifact_paths: [
        "/tmp/exports/codegod_normalized_options.json",
        "/tmp/exports/codegod_manifest.json",
      ],
      manifest_path: "/tmp/exports/codegod_manifest.json",
      submission_report: {
        context: "export",
        readiness: "ready",
        summary: "Export is submission-ready under the current contract and style preset.",
        output_count: 1,
        output_filenames: ["curve.pdf"],
        blockers: [],
        checks: [],
      },
    });
    vi.mocked(openPath).mockResolvedValue({
      output_path: "/tmp/exports",
    });
    vi.mocked(materializeDataTemplateFolder).mockResolvedValue({
      variant: "blank",
      folder_path: "/tmp/templates/codegod-blank-template-folder-demo",
      folder_name: "codegod-blank-template-folder-demo",
      chart_types: ["curve", "scatter", "bar", "boxplot", "heatmap"],
      files: [
        {
          chart_type: "curve",
          label: "Curve",
          template_id: "curve",
          filename: "curve_blank.xlsx",
          file_path: "/tmp/templates/codegod-blank-template-folder-demo/curve_blank.xlsx",
          input_model: "curve_table",
          source_template_id: "curve_table",
          format_summary: "Paired x/y columns with units and sample headers.",
        },
        {
          chart_type: "boxplot",
          label: "Boxplot",
          template_id: "box",
          filename: "boxplot_blank.xlsx",
          file_path: "/tmp/templates/codegod-blank-template-folder-demo/boxplot_blank.xlsx",
          input_model: "replicate_table",
          source_template_id: "replicate_table",
          format_summary: "Replicate columns with shared value labels and units.",
        },
      ],
    });
    vi.mocked(loadWizardDataFile).mockResolvedValue(TEST_INSPECT_RESPONSE);
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
  });

  it("shows the staged import surface by default", () => {
    renderStage("import");

    expect(screen.getByText("Import a data file")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Open data" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Open example folder" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Open blank folder" })).toBeInTheDocument();
    expect(screen.getByText("Recent data")).toBeInTheDocument();
  });

  it("builds and opens a blank template folder directly from the import stage", async () => {
    renderStage("import");

    fireEvent.click(screen.getByRole("button", { name: "Open blank folder" }));

    await waitFor(() => expect(materializeDataTemplateFolder).toHaveBeenCalledTimes(1));
    expect(materializeDataTemplateFolder).toHaveBeenCalledWith({
      variant: "blank",
    });
    expect(openPath).toHaveBeenCalledWith("/tmp/templates/codegod-blank-template-folder-demo");
    expect(screen.getByText("codegod-blank-template-folder-demo")).toBeInTheDocument();
    expect(
      screen.getByText("/tmp/templates/codegod-blank-template-folder-demo"),
    ).toBeInTheDocument();
    expect(screen.getByText("2 template files ready")).toBeInTheDocument();
    expect(screen.getByText("curve_blank.xlsx")).toBeInTheDocument();
    expect(screen.getByText("boxplot_blank.xlsx")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Open folder again" }));
    await waitFor(() =>
      expect(openPath).toHaveBeenCalledWith("/tmp/templates/codegod-blank-template-folder-demo"),
    );
    expect(loadWizardDataFile).not.toHaveBeenCalled();
  });

  it("shows loading immediately while the template folder is being materialized", async () => {
    let resolveFolder:
      | ((value: Awaited<ReturnType<typeof materializeDataTemplateFolder>>) => void)
      | undefined;
    vi.mocked(materializeDataTemplateFolder).mockImplementation(
      () =>
        new Promise<Awaited<ReturnType<typeof materializeDataTemplateFolder>>>((resolve) => {
          resolveFolder = resolve;
        }),
    );

    renderStage("import");

    fireEvent.click(screen.getByRole("button", { name: "Open example folder" }));

    expect(screen.getAllByRole("button", { name: "Refreshing…" })).toHaveLength(2);

    await act(async () => {
      resolveFolder?.({
        variant: "example",
        folder_path: "/tmp/templates/codegod-example-template-folder-demo",
        folder_name: "codegod-example-template-folder-demo",
        chart_types: ["curve", "boxplot"],
        files: [
          {
            chart_type: "curve",
            label: "Curve",
            template_id: "curve",
            filename: "curve_example.xlsx",
            file_path: "/tmp/templates/codegod-example-template-folder-demo/curve_example.xlsx",
            input_model: "curve_table",
            source_template_id: "curve_table",
            format_summary: "Paired x/y columns with units and sample headers.",
          },
          {
            chart_type: "boxplot",
            label: "Boxplot",
            template_id: "box",
            filename: "boxplot_example.xlsx",
            file_path: "/tmp/templates/codegod-example-template-folder-demo/boxplot_example.xlsx",
            input_model: "replicate_table",
            source_template_id: "replicate_table",
            format_summary: "Replicate columns with shared value labels and units.",
          },
        ],
      });
    });

    await waitFor(() =>
      expect(screen.getByText("codegod-example-template-folder-demo")).toBeInTheDocument(),
    );
  });

  it("keeps the success state when opening the generated template folder fails", async () => {
    vi.mocked(openPath).mockRejectedValueOnce(new Error("Not Found"));

    renderStage("import");

    fireEvent.click(screen.getByRole("button", { name: "Open blank folder" }));

    await waitFor(() =>
      expect(screen.getByText("codegod-blank-template-folder-demo")).toBeInTheDocument(),
    );
    expect(screen.getByText("curve_blank.xlsx")).toBeInTheDocument();
    expect(
      screen.getByText("Template folder generated, but opening it failed: Not Found"),
    ).toBeInTheDocument();
  });

  it("shows a build error without leaving a stale success state when materialize fails", async () => {
    vi.mocked(materializeDataTemplateFolder).mockRejectedValueOnce(new Error("Not Found"));

    renderStage("import");

    fireEvent.click(screen.getByRole("button", { name: "Open blank folder" }));

    await waitFor(() =>
      expect(screen.getByText("Sidecar materialize failed: Not Found")).toBeInTheDocument(),
    );
    expect(screen.queryByText("codegod-blank-template-folder-demo")).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Open folder again" })).not.toBeInTheDocument();
  });

  it("shows a sheet selector stage for multi-sheet inputs", () => {
    useWizardStore.setState({
      inputPath: "/tmp/curve.xlsx",
      sheet: 0,
      sheetNames: ["Sheet1", "Sheet2"],
      inspection: TEST_INSPECT_RESPONSE.inspection,
      template: "curve",
      stage: "sheet",
      step: "sheet",
    });

    renderStage("sheet");

    expect(screen.getByText("Select the workbook tab")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Sheet1/i })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Sheet2/i })).toBeInTheDocument();
  });

  it("lets completed steps navigate backward without wiping the current session", () => {
    const onNavigate = vi.fn();
    useWizardStore.setState({
      inputPath: "/tmp/curve.csv",
      sheet: 0,
      sheetNames: ["Sheet1"],
      inspection: TEST_INSPECT_RESPONSE.inspection,
      template: "curve",
      options: {
        size: "60x55",
        xscale: "linear",
        yscale: "linear",
        reverse_x: false,
        style_preset: "default",
        palette_preset: "colorblind_safe",
      },
      preflight: {
        template: "curve",
        warnings: [],
        errors: [],
        output_filenames: ["curve.pdf"],
      },
      stage: "review",
      step: "preflight",
    });

    const { rerender } = render(
      <WizardScreen meta={TEST_META} onNavigate={onNavigate} routeStage="review" />,
    );

    const tuneStep = screen.getByRole("button", { name: "Plot step Tune" });
    const reviewStep = screen.getByRole("button", { name: "Plot step Review" });
    const exportStep = screen.getByRole("button", { name: "Plot step Export" });

    expect(tuneStep).toBeEnabled();
    expect(reviewStep).toHaveAttribute("aria-current", "step");
    expect(exportStep).toBeDisabled();

    fireEvent.click(tuneStep);

    expect(onNavigate).toHaveBeenCalledWith("/plot/tune");
    expect(useWizardStore.getState().inputPath).toBe("/tmp/curve.csv");
    expect(useWizardStore.getState().sheet).toBe(0);
    expect(useWizardStore.getState().template).toBe("curve");
    expect(useWizardStore.getState().options).toMatchObject({
      size: "60x55",
      xscale: "linear",
      yscale: "linear",
      reverse_x: false,
      style_preset: "default",
      palette_preset: "colorblind_safe",
    });

    rerender(<WizardScreen meta={TEST_META} onNavigate={onNavigate} routeStage="tune" />);

    expect(useWizardStore.getState().stage).toBe("tune");
  });

  it("shows only compatible templates first and disables incompatible ones behind more types", () => {
    useWizardStore.setState({
      inputPath: "/tmp/relaxation.xlsx",
      sheet: 0,
      sheetNames: ["Sheet1"],
      template: "point_line",
      inspection: {
        model: "stress_relaxation",
        model_label: "Stress relaxation export table",
        recommendation: {
          template: "point_line",
          reason: "Detected a stress relaxation export table with 4 columns per bundle.",
          size: "60x55",
          xscale: "log",
          yscale: "linear",
          reverse_x: false,
        },
        warnings: [],
        signals: [],
      },
      options: {
        size: "60x55",
        xscale: "log",
        yscale: "linear",
        reverse_x: false,
      },
      stage: "type",
      step: "inspect",
    });

    renderStage("type");

    expect(getTemplateButton("Point line")).toBeInTheDocument();
    expect(getTemplateButton("Curve")).toBeInTheDocument();
    expect(screen.queryByText("Heatmap")).not.toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "More types" }));

    const heatmapButton = getTemplateButton("Heatmap");
    expect(heatmapButton).toBeDisabled();
    expect(
      screen.getByText(
        "This input is a rheology export bundle. Start with point-line or curve.",
      ),
    ).toBeInTheDocument();
  });

  it("refreshes preview in tune stage and only runs preflight once review opens", async () => {
    vi.useFakeTimers();
    useWizardStore.setState({
      inputPath: "/tmp/curve.csv",
      sheet: 0,
      sidecarReady: true,
      sheetNames: ["Sheet1"],
      template: "curve",
      inspection: TEST_INSPECT_RESPONSE.inspection,
      options: {
        size: "60x55",
        xscale: "linear",
        yscale: "linear",
        reverse_x: false,
        style_preset: "default",
        palette_preset: "colorblind_safe",
      },
      stage: "tune",
      step: "options",
    });

    const { rerender } = render(
      <WizardScreen meta={TEST_META} onNavigate={vi.fn()} routeStage="tune" />,
    );

    await act(async () => {
      vi.advanceTimersByTime(250);
    });

    expect(renderPreview).toHaveBeenCalledTimes(1);
    expect(preflightRender).not.toHaveBeenCalled();

    fireEvent.change(screen.getByDisplayValue("Default"), {
      target: { value: "nature" },
    });
    expect(useWizardStore.getState().options.style_preset).toBe("nature");

    rerender(<WizardScreen meta={TEST_META} onNavigate={vi.fn()} routeStage="review" />);

    await act(async () => {
      vi.advanceTimersByTime(250);
    });

    expect(preflightRender).toHaveBeenCalledTimes(1);
  });

  it("locks tensile curve scales to linear in the tune stage", async () => {
    useWizardStore.setState({
      inputPath: "/tmp/tensile_curve.csv",
      sheet: 0,
      sheetNames: ["Sheet1"],
      template: "curve",
      inspection: {
        model: "tensile_curve",
        model_label: "Tensile stress-strain curve (tensile_curve)",
        recommendation: {
          template: "curve",
          reason: "The strain / elongation x-axis and stress y-axis suggest a tensile curve.",
          size: "60x55",
          xscale: "linear",
          yscale: "linear",
          reverse_x: false,
        },
        warnings: [],
        signals: [],
      },
      options: {
        size: "60x55",
        xscale: "log",
        yscale: "log",
        reverse_x: false,
      },
      stage: "tune",
      step: "options",
    });

    renderStage("tune");

    await waitFor(() => {
      expect(useWizardStore.getState().options.xscale).toBe("linear");
      expect(useWizardStore.getState().options.yscale).toBe("linear");
    });

    expect(screen.queryByRole("option", { name: "log" })).not.toBeInTheDocument();
    expect(screen.getByText("Tensile curves keep linear x/y scales.")).toBeInTheDocument();
  });

  it("prompts before replacing the current plot session when opening another data file", async () => {
    useWizardStore.setState({
      inputPath: "/tmp/current.csv",
      sheet: 0,
      sheetNames: ["Sheet1"],
      template: "curve",
      inspection: TEST_INSPECT_RESPONSE.inspection,
      outputs: ["/tmp/exports/current.pdf"],
      exportResult: {
        outputs: ["/tmp/exports/current.pdf"],
        output_dir: "/tmp/exports",
        preview_outputs: [],
        artifact_paths: [],
        manifest_path: null,
      },
      stage: "import",
      step: "file",
    });
    vi.mocked(open).mockResolvedValue("/tmp/new-data.xlsx");
    const confirmSpy = vi.spyOn(window, "confirm").mockReturnValue(false);

    renderStage("import");

    fireEvent.click(screen.getByRole("button", { name: "Open data" }));

    await waitFor(() => {
      expect(confirmSpy).toHaveBeenCalledWith(
        expect.stringContaining("replace the current Plot session"),
      );
    });
    expect(loadWizardDataFile).not.toHaveBeenCalled();

    confirmSpy.mockRestore();
  });

  it("reopens recent data from import stage and routes to sheet when inspect finds multiple sheets", async () => {
    const onNavigate = vi.fn();
    const confirmSpy = vi.spyOn(window, "confirm").mockReturnValue(true);
    useWorkbenchStore.setState({
      recentProjects: [
        {
          id: "recent-wizard-data-1",
          mode: "wizard",
          kind: "data",
          path: "/tmp/recent-curve.xlsx",
          title: "recent-curve.xlsx",
          detail: "Data file · 2 sheets · Curve",
          updated_at: "2026-03-24T00:00:00.000Z",
        },
      ],
    });
    vi.mocked(loadWizardDataFile).mockResolvedValue({
      ...TEST_INSPECT_RESPONSE,
      input_path: "/tmp/recent-curve.xlsx",
      sheet_names: ["Sheet1", "Sheet2"],
    });

    renderStage("import", onNavigate);

    fireEvent.click(screen.getByRole("button", { name: /recent-curve\.xlsx/i }));

    await waitFor(() => {
      expect(loadWizardDataFile).toHaveBeenCalledWith(
        expect.any(Object),
        TEST_META,
        "/tmp/recent-curve.xlsx",
      );
    });
    expect(onNavigate).toHaveBeenCalledWith("/plot/sheet");
    expect(confirmSpy).toHaveBeenCalledWith(
      expect.stringContaining("replace the current Plot session"),
    );

    confirmSpy.mockRestore();
  });

  it("exports from review and opens the output folder in export stage", async () => {
    const onNavigate = vi.fn();
    useWizardStore.setState({
      inputPath: "/tmp/curve.csv",
      sheet: 0,
      sidecarReady: true,
      sheetNames: ["Sheet1"],
      template: "curve",
      inspection: TEST_INSPECT_RESPONSE.inspection,
      options: {
        size: "60x55",
        xscale: "linear",
        yscale: "linear",
        reverse_x: false,
        style_preset: "default",
      },
      preflight: {
        template: "curve",
        warnings: [],
        errors: [],
        output_filenames: ["curve.pdf"],
      },
      stage: "review",
      step: "preflight",
    });

    const { rerender } = render(
      <WizardScreen meta={TEST_META} onNavigate={onNavigate} routeStage="review" />,
    );

    await waitFor(() => {
      expect(screen.getByRole("button", { name: "Export bundle" })).toBeEnabled();
    });

    fireEvent.click(screen.getByRole("button", { name: "Export bundle" }));

    await waitFor(() => {
      expect(exportRender).toHaveBeenCalledTimes(1);
    });

    expect(onNavigate).toHaveBeenCalledWith("/plot/export");

    rerender(<WizardScreen meta={TEST_META} onNavigate={vi.fn()} routeStage="export" />);

    expect(screen.getByRole("button", { name: "Open output folder" })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Open output folder" }));

    await waitFor(() => {
      expect(openPath).toHaveBeenCalledWith("/tmp/exports");
    });
  });
});
