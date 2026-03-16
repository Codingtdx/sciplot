import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { open, save } from "@tauri-apps/plugin-dialog";

import {
  exportTensileComparison,
  inspectTensileWorkbook,
  preprocessTensileReplicates,
} from "../lib/api";
import { loadWizardDataFile } from "../lib/project-io";
import { useTensileStore, useWizardStore, useWorkbenchStore } from "../lib/store";
import type {
  InspectResponse,
  TensileComparisonExportResponse,
  TensileReplicateResponse,
  TensileWorkbookSummary,
} from "../lib/types";
import { TEST_META } from "../test/fixtures";
import { TensileScreen } from "./TensileScreen";

vi.mock("@tauri-apps/plugin-dialog", () => ({
  open: vi.fn(),
  save: vi.fn(),
}));

vi.mock("../lib/api", async () => {
  const actual = await vi.importActual<typeof import("../lib/api")>("../lib/api");
  return {
    ...actual,
    preprocessTensileReplicates: vi.fn(),
    inspectTensileWorkbook: vi.fn(),
    exportTensileComparison: vi.fn(),
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
    model: "tensile_curve",
    model_label: "拉伸应力-应变曲线",
    recommendation: {
      template: "curve",
      reason: "根据应变/应力标签识别为拉伸曲线。",
      size: "60x55",
      xscale: "linear",
      yscale: "linear",
      reverse_x: false,
    },
    warnings: [],
    signals: [],
  },
};

const TEST_TENSILE_SUMMARY: TensileWorkbookSummary = {
  workbook_path: "/tmp/solid.xlsx",
  label: "solid",
  sheet_names: TEST_PREPROCESS_RESPONSE.sheet_names,
  sample_count: 2,
  representative_filename: "BlendSet_A.csv",
  metrics: [
    { label: "Strength", unit: "MPa", mean: 46.15, std: 1.34 },
    { label: "Modulus", unit: "MPa", mean: 1237.5, std: 38.89 },
    { label: "Elongation", unit: "%", mean: 18.8, std: 2.1 },
  ],
};

const TEST_TENSILE_COMPARE_RESPONSE: TensileComparisonExportResponse = {
  bundle_dir: "/tmp/exports/solid_vs_4-mm_tensile_compare",
  comparison_workbook_path: "/tmp/exports/solid_vs_4-mm_tensile_compare/solid_vs_4-mm_tensile_compare.xlsx",
  labels: ["solid", "4 mm"],
  outputs: [
    "/tmp/exports/solid_vs_4-mm_tensile_compare/representative_curve_compare.pdf",
    "/tmp/exports/solid_vs_4-mm_tensile_compare/strength_box_compare.pdf",
    "/tmp/exports/solid_vs_4-mm_tensile_compare/strength_bar_compare.pdf",
    "/tmp/exports/solid_vs_4-mm_tensile_compare/modulus_box_compare.pdf",
    "/tmp/exports/solid_vs_4-mm_tensile_compare/modulus_bar_compare.pdf",
    "/tmp/exports/solid_vs_4-mm_tensile_compare/elongation_box_compare.pdf",
    "/tmp/exports/solid_vs_4-mm_tensile_compare/elongation_bar_compare.pdf",
  ],
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

describe("TensileScreen", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(open).mockReset();
    vi.mocked(save).mockReset();
    vi.mocked(preprocessTensileReplicates).mockReset();
    vi.mocked(inspectTensileWorkbook).mockReset();
    vi.mocked(exportTensileComparison).mockReset();
    vi.mocked(loadWizardDataFile).mockReset();
    useTensileStore.getState().reset();
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

  it("preprocesses raw tensile CSV files and only opens the wizard after an explicit click", async () => {
    const onNavigate = vi.fn();
    vi.mocked(open).mockResolvedValue([
      "/fixtures/BlendSet_A.csv",
      "/fixtures/BlendSet_B.csv",
      "/fixtures/BlendSet_bad.csv",
    ]);
    vi.mocked(save).mockResolvedValue("/tmp/BlendSet_plot_wizard_template.xlsx");
    vi.mocked(preprocessTensileReplicates).mockResolvedValue(TEST_PREPROCESS_RESPONSE);
    mockWizardReload();

    render(<TensileScreen meta={TEST_META} onNavigate={onNavigate} />);

    fireEvent.click(screen.getByRole("button", { name: "整理 tensile 数据" }));

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

    expect(
      screen.getByText(/已整理 2 个拉伸重复样，代表曲线来自 BlendSet_A.csv/),
    ).toBeInTheDocument();
    expect(loadWizardDataFile).not.toHaveBeenCalled();
    expect(useTensileStore.getState().preprocessResult?.output_path).toBe(
      TEST_PREPROCESS_RESPONSE.output_path,
    );
    expect(useTensileStore.getState().comparisonSources).toHaveLength(1);
    expect(useWorkbenchStore.getState().recentProjects[0]?.path).toBe(
      TEST_PREPROCESS_RESPONSE.output_path,
    );

    fireEvent.click(screen.getAllByRole("button", { name: "在绘图中打开" })[0]!);

    await waitFor(() => {
      expect(loadWizardDataFile).toHaveBeenCalledWith(
        expect.any(Object),
        TEST_META,
        TEST_PREPROCESS_RESPONSE.output_path,
        TEST_PREPROCESS_RESPONSE.preferred_sheet,
        "inspect",
      );
    });

    expect(onNavigate).toHaveBeenCalledWith("wizard");
    expect(useWizardStore.getState().inputPath).toBe(TEST_PREPROCESS_RESPONSE.output_path);
  });

  it("adds existing tensile workbooks to the compare list without replacing the current wizard input", async () => {
    vi.mocked(open).mockResolvedValue(["/tmp/solid.xlsx", "/tmp/4 mm.xlsx"]);
    vi.mocked(inspectTensileWorkbook)
      .mockResolvedValueOnce(TEST_TENSILE_SUMMARY)
      .mockResolvedValueOnce({
        ...TEST_TENSILE_SUMMARY,
        workbook_path: "/tmp/4 mm.xlsx",
        label: "4 mm",
      });

    useWizardStore.setState({
      inputPath: "/tmp/current.xlsx",
      sheet: 0,
      sheetNames: ["Representative_Curve"],
      template: "curve",
      options: {},
    });

    render(<TensileScreen meta={TEST_META} onNavigate={vi.fn()} />);

    fireEvent.click(screen.getByRole("button", { name: "补录已整理 workbook" }));

    await waitFor(() => {
      expect(inspectTensileWorkbook).toHaveBeenCalledTimes(2);
    });

    expect(useWizardStore.getState().inputPath).toBe("/tmp/current.xlsx");
    expect(useTensileStore.getState().comparisonSources.map((item) => item.label)).toEqual([
      "solid",
      "4 mm",
    ]);
  });

  it("exports tensile comparison outputs in the reordered workbook order", async () => {
    vi.mocked(open).mockResolvedValue("/tmp/exports");
    vi.mocked(exportTensileComparison).mockResolvedValue(TEST_TENSILE_COMPARE_RESPONSE);

    useTensileStore.setState({
      preprocessResult: null,
      comparisonSources: [
        TEST_TENSILE_SUMMARY,
        {
          ...TEST_TENSILE_SUMMARY,
          workbook_path: "/tmp/4 mm.xlsx",
          label: "4 mm",
        },
      ],
      comparisonResult: null,
    });

    render(<TensileScreen meta={TEST_META} onNavigate={vi.fn()} />);

    const moveDownButtons = screen.getAllByRole("button", { name: "下移" });
    fireEvent.click(moveDownButtons[0]);
    fireEvent.click(screen.getByRole("button", { name: "生成对比图" }));

    await waitFor(() => {
      expect(exportTensileComparison).toHaveBeenCalledWith(
        ["/tmp/4 mm.xlsx", "/tmp/solid.xlsx"],
        "/tmp/exports",
      );
    });

    expect(screen.getByText(/已为 2 组生成 7 个对比结果/)).toBeInTheDocument();
    expect(useWorkbenchStore.getState().recentProjects[0]?.path).toBe(
      TEST_TENSILE_COMPARE_RESPONSE.comparison_workbook_path,
    );
  });

  it("keeps the compare export button disabled until at least two groups are collected", () => {
    render(<TensileScreen meta={TEST_META} onNavigate={vi.fn()} />);

    expect(screen.getByRole("button", { name: "生成对比图" })).toBeDisabled();
  });
});
