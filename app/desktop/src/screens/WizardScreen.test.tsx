import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { open, save } from "@tauri-apps/plugin-dialog";

import {
  preflightRender,
  preprocessTensileReplicates,
  renderPreview,
} from "../lib/api";
import { loadWizardDataFile } from "../lib/project-io";
import { useWizardStore, useWorkbenchStore } from "../lib/store";
import type { InspectResponse, TensileReplicateResponse } from "../lib/types";
import { TEST_META } from "../test/fixtures";
import { WizardScreen } from "./WizardScreen";

vi.mock("@tauri-apps/plugin-dialog", () => ({
  open: vi.fn(),
  save: vi.fn(),
}));

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
    preprocessTensileReplicates: vi.fn(),
    renderPreview: vi.fn().mockResolvedValue({
      template: "curve",
      sheet: "Representative_Curve",
      previews: [],
    }),
  };
});

vi.mock("../lib/project-io", async () => {
  const actual = await vi.importActual<typeof import("../lib/project-io")>("../lib/project-io");
  return {
    ...actual,
    loadWizardDataFile: vi.fn(),
  };
});

const TEST_PREPROCESS_RESPONSE: TensileReplicateResponse = {
  output_path: "/tmp/BlendSet_plot_wizard_template.xlsx",
  group_name: "BlendSet",
  preferred_sheet: "Representative_Curve",
  sheet_names: [
    "Representative_Curve",
    "All_Curves",
    "Summary",
    "All_Specimens",
    "Strength_Replicates",
    "Modulus_Replicates",
    "Elongation_Replicates",
  ],
  sample_count: 2,
  representative_filename: "BlendSet_A.csv",
  metrics: [
    { label: "Strength", unit: "MPa", mean: 46.15, std: 1.34 },
    { label: "Modulus", unit: "MPa", mean: 1237.5, std: 38.89 },
  ],
  warnings: ["已跳过 BlendSet_bad.csv: 没有找到结果表格 2 中的应力-应变曲线。"],
};

const TEST_INSPECT_RESPONSE: InspectResponse = {
  input_path: TEST_PREPROCESS_RESPONSE.output_path,
  sheet: TEST_PREPROCESS_RESPONSE.preferred_sheet,
  sheet_names: TEST_PREPROCESS_RESPONSE.sheet_names,
  inspection: {
    model: "curve_table",
    model_label: "曲线表",
    recommendation: {
      template: "curve",
      reason: "识别到普通成对曲线表，默认推荐普通曲线图。",
      size: "60x55",
      xscale: "linear",
      yscale: "linear",
      reverse_x: false,
    },
    warnings: [],
    signals: ["检测到标准成对曲线表。"],
  },
};

function mockWizardReload() {
  vi
    .mocked(loadWizardDataFile)
    .mockImplementationOnce(async (wizard: Parameters<typeof loadWizardDataFile>[0]) => {
      wizard.reset();
      wizard.setInputPath(TEST_INSPECT_RESPONSE.input_path);
      wizard.setSheet(TEST_INSPECT_RESPONSE.sheet);
      wizard.setSheetNames(TEST_INSPECT_RESPONSE.sheet_names);
      wizard.setInspection(TEST_INSPECT_RESPONSE.inspection);
      wizard.setTemplate(TEST_INSPECT_RESPONSE.inspection.recommendation.template);
      wizard.setOptions({
        size: TEST_INSPECT_RESPONSE.inspection.recommendation.size,
        xscale: TEST_INSPECT_RESPONSE.inspection.recommendation.xscale,
        yscale: TEST_INSPECT_RESPONSE.inspection.recommendation.yscale,
        reverse_x: TEST_INSPECT_RESPONSE.inspection.recommendation.reverse_x,
      });
      wizard.setStep("inspect");
      return TEST_INSPECT_RESPONSE;
    });
}

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
    vi.mocked(save).mockReset();
    vi.mocked(preflightRender).mockReset();
    vi.mocked(preprocessTensileReplicates).mockReset();
    vi.mocked(loadWizardDataFile).mockReset();
    vi.mocked(renderPreview).mockReset();
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
        model_label: "应力松弛导出表",
        recommendation: {
          template: "point_line",
          reason: "识别到应力松弛的 4 列一组导出表。",
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

    expect(getTemplateButton("点线")).toBeInTheDocument();
    expect(getTemplateButton("曲线")).toBeInTheDocument();
    expect(queryTemplateButton("热图")).not.toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "更多图型" }));

    const heatmapButton = getTemplateButton("热图");
    expect(heatmapButton).toBeDisabled();
    expect(screen.getByText("当前输入是流变导出表，先用点线或曲线。")).toBeInTheDocument();
  });

  it("renders options from sidecar meta without local hardcoded lists", () => {
    useWizardStore.setState({
      template: "heatmap",
      options: {},
    });

    render(<WizardScreen meta={TEST_META} />);

    expect(screen.getByText("显示 colorbar")).toBeInTheDocument();
    expect(screen.getByDisplayValue("Colorblind Safe")).toBeInTheDocument();
  });

  it("cleans heatmap-only options when switching back to a compatible curve template", () => {
    useWizardStore.setState({
      inputPath: "/tmp/curve.csv",
      sheet: 0,
      template: "heatmap",
      inspection: {
        model: "curve_table",
        model_label: "曲线表",
        recommendation: {
          template: "curve",
          reason: "识别到普通成对曲线表。",
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

    fireEvent.click(getTemplateButton("曲线"));

    expect(useWizardStore.getState().template).toBe("curve");
    expect(useWizardStore.getState().options).toEqual({
      size: "60x55",
      xscale: "linear",
      yscale: "linear",
      reverse_x: false,
      palette_preset: "colorblind_safe",
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
        model_label: "曲线表",
        recommendation: {
          template: "curve",
          reason: "识别到普通成对曲线表。",
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
        model_label: "应力松弛导出表",
        recommendation: {
          template: "point_line",
          reason: "识别到应力松弛的 4 列一组导出表。",
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

    const exportButton = screen.getByRole("button", { name: "导出 PDF" });
    expect(exportButton).toBeDisabled();

    fireEvent.click(screen.getByRole("button", { name: "恢复推荐" }));

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
    expect(screen.getByRole("button", { name: "导出 PDF" })).toBeEnabled();
  });

  it("preprocesses raw tensile CSV files, reloads the workbook, and records the project", async () => {
    vi.mocked(open).mockResolvedValue([
      "/fixtures/BlendSet_A.csv",
      "/fixtures/BlendSet_B.csv",
      "/fixtures/BlendSet_bad.csv",
    ]);
    vi.mocked(save).mockResolvedValue("/tmp/BlendSet_plot_wizard_template.xlsx");
    vi.mocked(preprocessTensileReplicates).mockResolvedValue(TEST_PREPROCESS_RESPONSE);
    mockWizardReload();

    render(<WizardScreen meta={TEST_META} />);

    fireEvent.click(screen.getByText("整理拉伸重复 CSV"));

    await waitFor(() => {
      expect(preprocessTensileReplicates).toHaveBeenCalledWith(
        [
          "/fixtures/BlendSet_A.csv",
          "/fixtures/BlendSet_B.csv",
          "/fixtures/BlendSet_bad.csv",
        ],
        "/tmp/BlendSet_plot_wizard_template.xlsx",
        "BlendSet",
      );
    });

    await waitFor(() => {
      expect(loadWizardDataFile).toHaveBeenCalledWith(
        expect.any(Object),
        TEST_META,
        TEST_PREPROCESS_RESPONSE.output_path,
        TEST_PREPROCESS_RESPONSE.preferred_sheet,
        "inspect",
      );
      expect(renderPreview).toHaveBeenCalled();
    });

    expect(
      screen.getByText(/已整理 2 个拉伸重复样，代表曲线来自 BlendSet_A.csv/),
    ).toBeInTheDocument();
    expect(screen.getAllByText("Representative_Curve").length).toBeGreaterThan(0);
    expect(screen.getByText("Strength")).toBeInTheDocument();
    expect(screen.getByText("展开查看被跳过的文件")).toBeInTheDocument();
    expect(screen.getByText(/已跳过 BlendSet_bad.csv/)).toBeInTheDocument();

    expect(useWizardStore.getState().inputPath).toBe(TEST_PREPROCESS_RESPONSE.output_path);
    expect(useWizardStore.getState().template).toBe("curve");
    expect(useWorkbenchStore.getState().recentProjects[0]?.path).toBe(
      TEST_PREPROCESS_RESPONSE.output_path,
    );
  });

  it("shows a visible error when the desktop file dialog is unavailable", async () => {
    vi.mocked(open).mockRejectedValue(new Error("dialog unavailable"));

    render(<WizardScreen meta={TEST_META} />);

    fireEvent.click(screen.getByRole("button", { name: "选择数据" }));

    await waitFor(() => {
      expect(
        screen.getByText("无法打开文件选择窗口：dialog unavailable"),
      ).toBeInTheDocument();
    });
  });

  it("clears prior preprocess success when a later preprocess attempt fails", async () => {
    vi.mocked(open)
      .mockResolvedValueOnce([
        "/fixtures/BlendSet_A.csv",
        "/fixtures/BlendSet_B.csv",
        "/fixtures/BlendSet_bad.csv",
      ])
      .mockResolvedValueOnce([
        "/fixtures/BlendSet_A.csv",
        "/fixtures/BlendSet_bad.csv",
      ]);
    vi.mocked(save)
      .mockResolvedValueOnce("/tmp/BlendSet_plot_wizard_template.xlsx")
      .mockResolvedValueOnce("/tmp/BlendSet_retry.xlsx");
    vi.mocked(preprocessTensileReplicates)
      .mockResolvedValueOnce(TEST_PREPROCESS_RESPONSE)
      .mockRejectedValueOnce(new Error("csv exploded"));
    mockWizardReload();

    render(<WizardScreen meta={TEST_META} />);

    fireEvent.click(screen.getByText("整理拉伸重复 CSV"));

    await waitFor(() => {
      expect(
        screen.getByText(/已整理 2 个拉伸重复样，代表曲线来自 BlendSet_A.csv/),
      ).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText("整理拉伸重复 CSV"));

    await waitFor(() => {
      expect(screen.getByText("csv exploded")).toBeInTheDocument();
    });

    expect(
      screen.queryByText(/已整理 2 个拉伸重复样，代表曲线来自 BlendSet_A.csv/),
    ).not.toBeInTheDocument();
  });
});
