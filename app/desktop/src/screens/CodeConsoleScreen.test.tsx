import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const apiMocks = vi.hoisted(() => ({
  generateCodeConsole: vi.fn(),
  inspectFile: vi.fn(),
  openPath: vi.fn(),
  runCodeConsole: vi.fn(),
}));

const dialogMocks = vi.hoisted(() => ({
  openDialog: vi.fn(),
}));

const writeText = vi.fn().mockResolvedValue(undefined);

vi.mock("../lib/api", () => ({
  generateCodeConsole: apiMocks.generateCodeConsole,
  inspectFile: apiMocks.inspectFile,
  openPath: apiMocks.openPath,
  runCodeConsole: apiMocks.runCodeConsole,
}));

vi.mock("../lib/tauri-dialog", () => ({
  openDialog: dialogMocks.openDialog,
}));

import { useWizardStore } from "../lib/store";
import type { InspectResponse } from "../lib/types";
import { TEST_CONTRACT, TEST_META } from "../test/fixtures";
import { CodeConsoleScreen } from "./CodeConsoleScreen";

function makeInspectionResponse(inputPath: string): InspectResponse {
  return {
    input_path: inputPath,
    sheet: "Sheet1",
    sheet_names: ["Sheet1"],
    inspection: {
      model: "curve_table",
      model_label: "Curve table",
      recommendation: {
        template: "curve",
        reason: "Default curve.",
        size: "60x55",
        xscale: "linear",
        yscale: "linear",
        reverse_x: false,
        style_preset: "default",
        palette_preset: "colorblind_safe",
      },
      warnings: [],
      signals: ["Detected paired x/y columns."],
    },
  };
}

function makeGenerateResponse(promptText = "repo-native incremental prompt") {
  return {
    bundle_version: 1,
    generated_at: "2026-03-21T12:00:00Z",
    contract: {
      version: 1,
      sha256: "a".repeat(64),
      default_style: "default",
      default_palette: "colorblind_safe",
    },
    session: {
      session_id: "session_demo",
      session_source: "wizard",
      input_path: "/tmp/session_curve_prompt.csv",
      input_display_path: "session_curve_prompt.csv",
      input_filename: "session_curve_prompt.csv",
      sheet: "Sheet1",
      sheet_names: ["Sheet1"],
      template: "point_line",
      size_label: "120 x 55 mm",
      size_id: "120x55",
      style_preset: "nature",
      palette_preset: "colorblind_safe",
      xscale: "log",
      yscale: "linear",
      reverse_x: true,
      baseline: "linear_endpoints",
      show_colorbar: false,
      intent: "custom_plot",
      target_path: "src/rendering/custom_point_line_helper.py",
    },
    defaults_panel: {
      locked_by_contract: [],
      user_selectable: [],
      derived_from_session: [],
    },
    truth_sources: [
      {
        id: "plot_contract",
        label: "Plot contract",
        path: "src/plot_contract.json",
        display_path: "src/plot_contract.json",
        kind: "contract",
        available: true,
        reason: "Canonical contract.",
      },
    ],
    data_context: {
      available: true,
      model: "curve_table",
      model_label: "Curve table",
      raw_row_count: 10,
      raw_column_count: 4,
      column_names: ["Time", "Stress"],
      normalized_columns: ["sample", "x", "y"],
      column_summaries: [],
      sample_rows: [],
      normalized_preview_rows: [],
      missing_summary: { empty_cells: 0, rows: 10, columns: 4 },
      inspection: { warnings: [], signals: ["Detected paired x/y columns."] },
      recommendation: {
        template: "point_line",
        reason: "Markers help here.",
        size: "120x55",
        style_preset: "nature",
        palette_preset: "colorblind_safe",
      },
      interpreted_summary: { roles: { x: "Time", y: "Stress" } },
      full_data_rows: 10,
      full_data_columns: 3,
    },
    prompt_text: promptText,
    scaffold_text: "unused scaffold",
    lightweight_bundle: {
      text: "lightweight context",
      includes_data_context: true,
      includes_inspection_summary: true,
      includes_project_context: false,
      includes_full_data: false,
    },
  };
}

function bindPlotContext(inputPath = "/tmp/session_curve_prompt.csv") {
  act(() => {
    useWizardStore.getState().setSidecarReady(true);
    useWizardStore.getState().setInputPath(inputPath);
    useWizardStore.getState().setSheet("Sheet1");
    useWizardStore.getState().setSheetNames(["Sheet1"]);
    useWizardStore.getState().setInspection({
      model: "curve_table",
      model_label: "Curve table",
      recommendation: {
        template: "point_line",
        reason: "Markers help here.",
        size: "120x55",
        xscale: "log",
        yscale: "linear",
        reverse_x: true,
        style_preset: "nature",
        palette_preset: "colorblind_safe",
      },
      warnings: [],
      signals: ["Detected paired x/y columns."],
    });
    useWizardStore.getState().setTemplate("point_line");
    useWizardStore.getState().setOptions({
      size: "120x55",
      xscale: "log",
      yscale: "linear",
      reverse_x: true,
      baseline: "linear_endpoints",
      style_preset: "nature",
      palette_preset: "colorblind_safe",
    });
  });
}

describe("CodeConsoleScreen", () => {
  beforeEach(() => {
    useWizardStore.getState().reset();
    useWizardStore.getState().setSidecarReady(true);
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: {
        writeText,
      },
    });
  });

  afterEach(() => {
    apiMocks.generateCodeConsole.mockReset();
    apiMocks.inspectFile.mockReset();
    apiMocks.openPath.mockReset();
    apiMocks.runCodeConsole.mockReset();
    dialogMocks.openDialog.mockReset();
    writeText.mockClear();
  });

  it("binds data directly inside Code Console and keeps the prompt idle until requested", async () => {
    dialogMocks.openDialog.mockResolvedValue("/tmp/local_curve.csv");
    apiMocks.inspectFile.mockResolvedValue(makeInspectionResponse("/tmp/local_curve.csv"));

    render(<CodeConsoleScreen contract={TEST_CONTRACT} meta={TEST_META} />);

    expect(screen.getByRole("button", { name: "Use Plot data" })).toBeDisabled();
    expect(apiMocks.generateCodeConsole).not.toHaveBeenCalled();

    fireEvent.click(screen.getByRole("button", { name: "Open data" }));

    await waitFor(() =>
      expect(apiMocks.inspectFile).toHaveBeenCalledWith("/tmp/local_curve.csv", 0),
    );

    expect(screen.getByText("local_curve.csv")).toBeInTheDocument();
    expect(screen.getByText("Loaded here")).toBeInTheDocument();
    expect(screen.getByText("Curve table")).toBeInTheDocument();
    expect(screen.getByText("60 x 55 mm / Default / Colorblind Safe")).toBeInTheDocument();
    expect(apiMocks.generateCodeConsole).not.toHaveBeenCalled();
  });

  it("copies the prompt from the current Plot context on demand and keeps it hidden by default", async () => {
    bindPlotContext();
    apiMocks.generateCodeConsole.mockResolvedValue(makeGenerateResponse());

    render(<CodeConsoleScreen contract={TEST_CONTRACT} meta={TEST_META} />);

    expect(apiMocks.generateCodeConsole).not.toHaveBeenCalled();
    expect(screen.queryByLabelText("Generated AI prompt")).not.toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Copy prompt" }));

    await waitFor(() =>
      expect(apiMocks.generateCodeConsole).toHaveBeenCalledTimes(1),
    );
    expect(apiMocks.generateCodeConsole.mock.calls[0]?.[0]).toMatchObject({
      intent: "custom_plot",
      brief: "",
      base_template: "point_line",
      input_path: "/tmp/session_curve_prompt.csv",
      sheet: "Sheet1",
      include_data_context: true,
      include_inspection_summary: true,
      include_project_context: false,
      options: {
        size: "120x55",
        xscale: "log",
        yscale: "linear",
        reverse_x: true,
        baseline: "linear_endpoints",
        style_preset: "nature",
        palette_preset: "colorblind_safe",
      },
    });
    expect(writeText).toHaveBeenCalledWith("repo-native incremental prompt");

    fireEvent.click(screen.getByRole("button", { name: "Show prompt" }));

    await waitFor(() =>
      expect(screen.getByLabelText("Generated AI prompt")).toHaveTextContent(
        "repo-native incremental prompt",
      ),
    );
    expect(apiMocks.generateCodeConsole).toHaveBeenCalledTimes(1);
  });

  it("runs pasted repo-native Python and surfaces managed outputs", async () => {
    bindPlotContext("/tmp/session_curve_run.csv");
    act(() => {
      useWizardStore.getState().setProjectPath("/tmp/current.plotproject.json");
    });

    apiMocks.runCodeConsole.mockResolvedValue({
      generated_at: "2026-03-21T12:03:00Z",
      output_dir: "/tmp/code-console/session_demo",
      stdout: "render ok",
      stderr: "",
      exit_code: 0,
      timed_out: false,
      duration_ms: 321,
      generated_files: [
        {
          path: "/tmp/code-console/session_demo/outputs/custom_curve.pdf",
          filename: "custom_curve.pdf",
          kind: "pdf",
        },
      ],
      previews: [
        {
          filename: "custom_curve.preview.png",
          png_base64: "aGVsbG8=",
          qa: null,
        },
      ],
    });

    render(<CodeConsoleScreen contract={TEST_CONTRACT} meta={TEST_META} />);

    fireEvent.change(screen.getByLabelText("Code console runner input"), {
      target: { value: "print('render ok')" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Run" }));

    await waitFor(() => expect(apiMocks.runCodeConsole).toHaveBeenCalledTimes(1));
    expect(apiMocks.runCodeConsole.mock.calls[0]?.[0]).toMatchObject({
      code: "print('render ok')",
      base_template: "point_line",
      input_path: "/tmp/session_curve_run.csv",
      sheet: "Sheet1",
      project_path: "/tmp/current.plotproject.json",
      include_project_context: true,
      options: {
        size: "120x55",
        xscale: "log",
        yscale: "linear",
        reverse_x: true,
        baseline: "linear_endpoints",
        style_preset: "nature",
        palette_preset: "colorblind_safe",
      },
    });

    expect(screen.getByText("render ok")).toBeInTheDocument();
    expect(screen.getByText("custom_curve.pdf")).toBeInTheDocument();
    expect(screen.getByText(/exit 0 · 321 ms · 1 file/)).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Open output folder" }));
    await waitFor(() =>
      expect(apiMocks.openPath).toHaveBeenCalledWith("/tmp/code-console/session_demo"),
    );
  });
});
