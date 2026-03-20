import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { open } from "@tauri-apps/plugin-dialog";

import { exportRender, openPath, preflightRender, renderPreview } from "../lib/api";
import { loadWizardDataFile } from "../lib/project-io";
import { useWizardStore, useWorkbenchStore } from "../lib/store";
import type { InspectResponse } from "../lib/types";
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
      sheet: "Representative_Curve",
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
      reason: "Detected a standard paired curve table, so a basic curve plot is recommended by default.",
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

function queryTemplateButton(label: string) {
  return (
    screen
      .queryAllByRole("button")
      .find((candidate) => candidate.querySelector("strong")?.textContent === label) ?? null
  );
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
      sheet: "Representative_Curve",
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
    vi.mocked(loadWizardDataFile).mockResolvedValue(TEST_INSPECT_RESPONSE);
    useWizardStore.getState().reset();
    useWorkbenchStore.setState({
      lastScreen: "wizard",
      pdfImportMode: "graph",
      recentProjects: [],
      settings: {
        auto_status_poll: true,
        remember_last_screen: true,
        theme_preference: "system",
      },
    });
  });

  it("shows only compatible templates by default and disables incompatible ones under more templates", () => {
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
    });

    render(<WizardScreen meta={TEST_META} />);

    expect(getTemplateButton("Point line")).toBeInTheDocument();
    expect(getTemplateButton("Curve")).toBeInTheDocument();
    expect(queryTemplateButton("Heatmap")).not.toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "More types" }));

    const heatmapButton = getTemplateButton("Heatmap");
    expect(heatmapButton).toBeDisabled();
    expect(screen.getByText("This input is a rheology export bundle. Start with point-line or curve.")).toBeInTheDocument();
  });

  it("renders options from sidecar meta without local hardcoded lists", () => {
    useWizardStore.setState({
      template: "heatmap",
      options: {},
    });

    render(<WizardScreen meta={TEST_META} />);

    expect(screen.getByText("Show color bar")).toBeInTheDocument();
    expect(screen.getByDisplayValue("Default")).toBeInTheDocument();
    expect(screen.getByDisplayValue("Colorblind Safe")).toBeInTheDocument();
  });

  it("prompts before replacing the current plotting session when opening another data file", async () => {
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
    });
    vi.mocked(open).mockResolvedValue("/tmp/new-data.xlsx");
    const confirmSpy = vi.spyOn(window, "confirm").mockReturnValue(false);

    render(<WizardScreen meta={TEST_META} />);

    fireEvent.click(screen.getByRole("button", { name: "Open data" }));

    await waitFor(() => {
      expect(confirmSpy).toHaveBeenCalledWith(
        expect.stringContaining("replace the current Plot Builder session"),
      );
    });
    expect(loadWizardDataFile).not.toHaveBeenCalled();

    confirmSpy.mockRestore();
  });

  it("cleans heatmap-only options when switching back to a compatible curve template", () => {
    useWizardStore.setState({
      inputPath: "/tmp/curve.csv",
      sheet: 0,
      template: "heatmap",
      inspection: {
        model: "curve_table",
        model_label: "Paired curve table (curve_table)",
        recommendation: {
          template: "curve",
          reason: "Detected a standard paired curve table.",
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
        show_colorbar: true,
        palette_preset: "colorblind_safe",
      },
    });

    render(<WizardScreen meta={TEST_META} />);

    fireEvent.click(getTemplateButton("Curve"));

    expect(useWizardStore.getState().template).toBe("curve");
    expect(useWizardStore.getState().options).toEqual({
      size: "60x55",
      xscale: "linear",
      yscale: "linear",
      reverse_x: false,
      style_preset: "default",
      palette_preset: "colorblind_safe",
    });
  });

  it("locks tensile curve scales to linear when the inspection model is tensile_curve", async () => {
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
    });

    render(<WizardScreen meta={TEST_META} />);

    await waitFor(() => {
      expect(useWizardStore.getState().options.xscale).toBe("linear");
      expect(useWizardStore.getState().options.yscale).toBe("linear");
    });

    expect(screen.queryByRole("option", { name: "log" })).not.toBeInTheDocument();
    expect(screen.getByText("Tensile curves keep linear x/y scales.")).toBeInTheDocument();
  });

  it("lets the user switch the public submission style from wizard options", () => {
    useWizardStore.setState({
      template: "curve",
      options: {
        size: "60x55",
        xscale: "linear",
        yscale: "linear",
        reverse_x: false,
        style_preset: "default",
        palette_preset: "colorblind_safe",
      },
    });

    render(<WizardScreen meta={TEST_META} />);

    fireEvent.change(screen.getByDisplayValue("Default"), {
      target: { value: "nature" },
    });

    expect(useWizardStore.getState().options.style_preset).toBe("nature");
    expect(screen.getAllByText("Nature").length).toBeGreaterThan(0);
  });

  it("shows the export bundle controls and opens the output folder after export", async () => {
    useWizardStore.setState({
      inputPath: "/tmp/curve.csv",
      sheet: 0,
      sidecarReady: true,
      template: "curve",
      inspection: TEST_INSPECT_RESPONSE.inspection,
      options: {
        size: "60x55",
        xscale: "linear",
        yscale: "linear",
        reverse_x: false,
        style_preset: "default",
      },
    });

    render(<WizardScreen meta={TEST_META} />);

    await waitFor(() => {
      expect(screen.getByRole("button", { name: "Export submission bundle" })).toBeEnabled();
    });

    fireEvent.click(screen.getByRole("button", { name: "Export submission bundle" }));

    await waitFor(() => {
      expect(exportRender).toHaveBeenCalledTimes(1);
    });

    expect(screen.getByRole("button", { name: "Open output folder" })).toBeInTheDocument();
    expect(screen.getByText("Manifest: codegod_manifest.json")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Open output folder" }));

    await waitFor(() => {
      expect(openPath).toHaveBeenCalledWith("/tmp/exports");
    });
  });

  it("automatically refreshes preview and preflight when options change quickly", async () => {
    vi.useFakeTimers();
    let resolveFirst:
      | ((value: {
          template: string;
          sheet: string | number;
          previews: Array<{ filename: string; png_base64: string }>;
        }) => void)
      | undefined;
    let resolveSecond:
      | ((value: {
          template: string;
          sheet: string | number;
          previews: Array<{ filename: string; png_base64: string }>;
        }) => void)
      | undefined;

    vi.mocked(renderPreview)
      .mockImplementationOnce(
        () =>
          new Promise((resolve) => {
            resolveFirst = resolve;
          }),
      )
      .mockImplementationOnce(
        () =>
          new Promise((resolve) => {
            resolveSecond = resolve;
          }),
      );

    useWizardStore.setState({
      inputPath: "/tmp/curve.csv",
      sheet: 0,
      sidecarReady: true,
      template: "curve",
      inspection: {
        model: "curve_table",
        model_label: "Paired curve table (curve_table)",
        recommendation: {
          template: "curve",
          reason: "Detected a standard paired curve table.",
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
        xscale: "linear",
        yscale: "linear",
        reverse_x: false,
      },
    });

    render(<WizardScreen meta={TEST_META} />);

    await act(async () => {
      vi.advanceTimersByTime(250);
    });
    expect(renderPreview).toHaveBeenCalledTimes(1);
    expect(preflightRender).toHaveBeenCalledTimes(1);

    await act(async () => {
      useWizardStore.getState().setOptions({
        size: "60x55",
        xscale: "log",
        yscale: "linear",
        reverse_x: false,
      });
    });

    await act(async () => {
      vi.advanceTimersByTime(250);
    });
    expect(renderPreview).toHaveBeenCalledTimes(2);
    expect(preflightRender).toHaveBeenCalledTimes(2);

    await act(async () => {
      resolveFirst?.({
        template: "curve",
        sheet: 0,
        previews: [{ filename: "old.pdf", png_base64: "old" }],
      });
      await Promise.resolve();
    });

    expect(useWizardStore.getState().previews).toEqual([]);

    await act(async () => {
      resolveSecond?.({
        template: "curve",
        sheet: 0,
        previews: [{ filename: "new.pdf", png_base64: "new" }],
      });
      await Promise.resolve();
    });

    expect(useWizardStore.getState().previews[0]?.filename).toBe("new.pdf");
  });

  it("restores the recommended template and scales, and re-enables export after blocking errors clear", async () => {
    vi.useFakeTimers();
    vi.mocked(preflightRender).mockImplementation(async (_path, _sheet, template, options) => {
      if (template === "curve") {
        return {
          input_path: "/tmp/relaxation.xlsx",
          sheet: 0,
          template,
          options,
          preflight: {
            template,
            warnings: [],
            errors: ["curve blocked"],
            output_filenames: [],
          },
        };
      }
      return {
        input_path: "/tmp/relaxation.xlsx",
        sheet: 0,
        template,
        options,
        preflight: {
          template,
          warnings: [],
          errors: [],
          output_filenames: ["stress_relaxation_sigma_over_sigma0.pdf"],
        },
      };
    });

    useWizardStore.setState({
      inputPath: "/tmp/relaxation.xlsx",
      sheet: 0,
      sidecarReady: true,
      template: "curve",
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
        xscale: "linear",
        yscale: "linear",
        reverse_x: false,
      },
    });

    render(<WizardScreen meta={TEST_META} />);

    await act(async () => {
      vi.advanceTimersByTime(250);
    });

    const exportButton = screen.getByRole("button", { name: "Export submission bundle" });
    expect(exportButton).toBeDisabled();

    fireEvent.click(screen.getByRole("button", { name: "Use recommendation" }));

    await act(async () => {
      vi.advanceTimersByTime(250);
    });

    expect(useWizardStore.getState().template).toBe("point_line");
    expect(useWizardStore.getState().options).toEqual(
      expect.objectContaining({
        size: "60x55",
        xscale: "log",
        yscale: "linear",
        reverse_x: false,
      }),
    );
    expect(preflightRender).toHaveBeenLastCalledWith(
      "/tmp/relaxation.xlsx",
      0,
      "point_line",
      expect.objectContaining({
        xscale: "log",
        yscale: "linear",
      }),
      expect.any(Object),
    );
    expect(screen.getByRole("button", { name: "Export submission bundle" })).toBeEnabled();
  });

  it("shows a visible error when the desktop file dialog is unavailable", async () => {
    vi.mocked(open).mockRejectedValue(new Error("dialog unavailable"));

    render(<WizardScreen meta={TEST_META} />);

    fireEvent.click(screen.getByRole("button", { name: "Open data" }));

    await waitFor(() => {
      expect(
        screen.getByText("Could not open the file picker: dialog unavailable"),
      ).toBeInTheDocument();
    });
  });
});
