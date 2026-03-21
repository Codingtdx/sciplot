import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const apiMocks = vi.hoisted(() => ({
  exportCodeConsoleBundle: vi.fn(),
  generateCodeConsole: vi.fn(),
  openPath: vi.fn(),
}));
const dialogMocks = vi.hoisted(() => ({
  openDialog: vi.fn(),
}));
const writeText = vi.fn().mockResolvedValue(undefined);

vi.mock("../lib/api", () => ({
  exportCodeConsoleBundle: apiMocks.exportCodeConsoleBundle,
  generateCodeConsole: apiMocks.generateCodeConsole,
  openPath: apiMocks.openPath,
}));

vi.mock("../lib/tauri-dialog", () => ({
  openDialog: dialogMocks.openDialog,
}));

import { useCodeConsoleStore, useWizardStore } from "../lib/store";
import { TEST_CONTRACT, TEST_META } from "../test/fixtures";
import { CodeConsoleScreen } from "./CodeConsoleScreen";

describe("CodeConsoleScreen", () => {
  beforeEach(() => {
    useCodeConsoleStore.getState().reset();
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
    apiMocks.exportCodeConsoleBundle.mockReset();
    apiMocks.openPath.mockReset();
    dialogMocks.openDialog.mockReset();
    writeText.mockClear();
  });

  it("backs the generate request with the current plot session and renders sidecar output", async () => {
    act(() => {
      useWizardStore.getState().setInputPath("/tmp/session_curve.csv");
      useWizardStore.getState().setSheet("Sheet1");
      useWizardStore.getState().setInspection({
        model: "curve_table",
        model_label: "Curve table",
        recommendation: {
          template: "point_line",
          reason: "Markers help here.",
          size: "120x55",
          style_preset: "nature",
          palette_preset: "colorblind_safe",
        },
        warnings: [],
        signals: ["Detected paired x/y columns."],
      });
      useWizardStore.getState().setTemplate("point_line");
      useWizardStore.getState().setOptions({
        size: "120x55",
        style_preset: "nature",
        palette_preset: "colorblind_safe",
      });
    });

    apiMocks.generateCodeConsole.mockResolvedValue({
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
        input_path: "/tmp/session_curve.csv",
        input_display_path: "session_curve.csv",
        input_filename: "session_curve.csv",
        sheet: "Sheet1",
        sheet_names: ["Sheet1"],
        template: "point_line",
        size_label: "120 x 55 mm",
        size_id: "120x55",
        style_preset: "nature",
        palette_preset: "colorblind_safe",
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
        interpreted_summary: {},
        full_data_rows: 10,
        full_data_columns: 3,
      },
      prompt_text: "repo-native prompt",
      scaffold_text: "repo-native scaffold",
      lightweight_bundle: {
        text: "lightweight context",
        includes_data_context: true,
        includes_inspection_summary: true,
        includes_project_context: false,
        includes_full_data: false,
      },
    });

    render(<CodeConsoleScreen contract={TEST_CONTRACT} meta={TEST_META} />);

    fireEvent.change(screen.getByLabelText("Code console brief"), {
      target: { value: "做一个 repo-native 的 broken axis point-line 图。" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Generate AI bridge" }));

    await waitFor(() => expect(apiMocks.generateCodeConsole).toHaveBeenCalledTimes(1));
    expect(apiMocks.generateCodeConsole.mock.calls[0]?.[0]).toMatchObject({
      base_template: "point_line",
      size: "120x55",
      style_preset: "nature",
      palette_preset: "colorblind_safe",
      input_path: "/tmp/session_curve.csv",
      sheet: "Sheet1",
      include_data_context: true,
      include_inspection_summary: true,
    });
    expect(screen.getByLabelText("Generated AI prompt")).toHaveTextContent("repo-native prompt");
    expect(screen.getByLabelText("Generated Python scaffold")).toHaveTextContent(
      "repo-native scaffold",
    );
  });

  it("keeps full-data export opt-in and disables data context toggles when no data is bound", async () => {
    dialogMocks.openDialog.mockResolvedValue("/tmp/ai-bundle");
    apiMocks.exportCodeConsoleBundle.mockResolvedValue({
      bundle_dir: "/tmp/ai-bundle/bundle",
      zip_path: "/tmp/ai-bundle/bundle.zip",
      manifest_path: "/tmp/ai-bundle/bundle/manifest.json",
      exported_files: [],
      includes_full_data: true,
      truth_sources: [],
    });

    render(<CodeConsoleScreen contract={TEST_CONTRACT} meta={TEST_META} />);

    expect(screen.getByText(/No current data file is bound to Plot/i)).toBeInTheDocument();
    expect(screen.getByRole("checkbox", { name: /Attach current data context/i })).toBeDisabled();

    act(() => {
      useWizardStore.getState().setInputPath("/tmp/session_curve.csv");
      useWizardStore.getState().setSheet(0);
      useWizardStore.getState().setProjectPath("/tmp/session.plotproject.json");
    });

    fireEvent.click(screen.getByRole("checkbox", { name: /Opt in to full-data export/i }));
    fireEvent.click(screen.getByRole("checkbox", { name: /Attach current project context/i }));
    fireEvent.click(screen.getByRole("button", { name: "Export full-data bundle" }));

    await waitFor(() => expect(apiMocks.exportCodeConsoleBundle).toHaveBeenCalledTimes(1));
    expect(apiMocks.exportCodeConsoleBundle.mock.calls[0]?.[0]).toMatchObject({
      include_full_data: true,
      project_path: "/tmp/session.plotproject.json",
      include_project_context: true,
      output_dir: "/tmp/ai-bundle",
    });
  });
});
