import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { open } from "@tauri-apps/plugin-dialog";

import { preflightRender, renderPreview } from "../lib/api";
import { useWizardStore, useWorkbenchStore } from "../lib/store";
import type { InspectResponse } from "../lib/types";
import { TEST_META } from "../test/fixtures";
import { WizardScreen } from "./WizardScreen";

vi.mock("@tauri-apps/plugin-dialog", () => ({
  open: vi.fn(),
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
    renderPreview: vi.fn().mockResolvedValue({
      template: "curve",
      sheet: "Representative_Curve",
      previews: [],
    }),
  };
});

const TEST_INSPECT_RESPONSE: InspectResponse = {
  input_path: "/tmp/curve.csv",
  sheet: 0,
  sheet_names: ["Sheet1"],
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

  it("locks tensile curve scales to linear when the inspection model is tensile_curve", async () => {
    useWizardStore.setState({
      inputPath: "/tmp/tensile_curve.csv",
      sheet: 0,
      sheetNames: ["Sheet1"],
      template: "curve",
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
    expect(screen.getByText("当前输入识别为拉伸应力-应变曲线，x/y 坐标轴固定使用 linear。")).toBeInTheDocument();
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
});
