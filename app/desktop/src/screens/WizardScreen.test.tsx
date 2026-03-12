import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { open, save } from "@tauri-apps/plugin-dialog";

import { preprocessTensileReplicates, renderPreview } from "../lib/api";
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
    .mockImplementationOnce(async (wizard: ReturnType<typeof useWizardStore.getState>) => {
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

describe("WizardScreen", () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(open).mockReset();
    vi.mocked(save).mockReset();
    vi.mocked(preprocessTensileReplicates).mockReset();
    vi.mocked(loadWizardDataFile).mockReset();
    vi.mocked(renderPreview).mockReset();
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
      settings: { auto_status_poll: true, remember_last_screen: true },
    });
  });

  it("renders template choices from sidecar meta", () => {
    useWizardStore.setState({
      step: "template",
      template: "curve",
    });

    render(<WizardScreen meta={TEST_META} />);

    expect(screen.getByText("曲线")).toBeInTheDocument();
    expect(screen.getByText("热图")).toBeInTheDocument();
  });

  it("renders options from sidecar meta without local hardcoded lists", () => {
    useWizardStore.setState({
      step: "options",
      template: "heatmap",
      options: {},
    });

    render(<WizardScreen meta={TEST_META} />);

    expect(screen.getByText("显示 colorbar")).toBeInTheDocument();
    expect(screen.getByDisplayValue("Colorblind Safe")).toBeInTheDocument();
  });

  it("cleans heatmap-only options when switching back to a curve template", () => {
    useWizardStore.setState({
      step: "template",
      template: "heatmap",
      options: {
        size: "60x55",
        show_colorbar: true,
        palette_preset: "colorblind_safe",
      },
    });

    render(<WizardScreen meta={TEST_META} />);

    fireEvent.click(screen.getByRole("button", { name: /曲线/ }));

    expect(useWizardStore.getState().template).toBe("curve");
    expect(useWizardStore.getState().options).toEqual({
      size: "60x55",
      xscale: "linear",
      yscale: "linear",
      reverse_x: false,
      palette_preset: "colorblind_safe",
    });
  });

  it("keeps only the latest preview response when options change quickly", async () => {
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
      step: "options",
      template: "curve",
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
    expect(useWizardStore.getState().step).toBe("inspect");
    expect(useWorkbenchStore.getState().recentProjects[0]?.path).toBe(
      TEST_PREPROCESS_RESPONSE.output_path,
    );
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

    await act(async () => {
      useWizardStore.getState().setStep("file");
    });
    await waitFor(() => {
      expect(screen.getByText("整理拉伸重复 CSV")).toBeInTheDocument();
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
