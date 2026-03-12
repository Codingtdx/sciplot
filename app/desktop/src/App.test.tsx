import { act, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { getPlotContract, getWorkbenchMeta, healthcheck } from "./lib/api";
import { useComposerStore, useWizardStore, useWorkbenchStore } from "./lib/store";
import { TEST_CONTRACT, TEST_META } from "./test/fixtures";
import App from "./App";

vi.mock("./screens/WizardScreen", () => ({
  WizardScreen: () => <div>Wizard Stub</div>,
}));

vi.mock("./screens/ComposerScreen", () => ({
  ComposerScreen: () => <div>Composer Stub</div>,
}));

vi.mock("./screens/ProjectsScreen", () => ({
  ProjectsScreen: () => <div>Projects Stub</div>,
}));

vi.mock("./screens/SettingsScreen", () => ({
  SettingsScreen: () => <div>Settings Stub</div>,
}));

vi.mock("./lib/api", async () => {
  const actual = await vi.importActual<typeof import("./lib/api")>("./lib/api");
  return {
    ...actual,
    getWorkbenchMeta: vi.fn(),
    getPlotContract: vi.fn(),
    healthcheck: vi.fn(),
  };
});

describe("App", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    useWizardStore.getState().reset();
    useComposerStore.getState().reset();
    useWorkbenchStore.setState({
      lastScreen: "wizard",
      pdfImportMode: "graph",
      recentProjects: [],
      settings: { auto_status_poll: true, remember_last_screen: true },
    });
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("reloads meta and contract after the sidecar comes online later", async () => {
    vi.mocked(getWorkbenchMeta)
      .mockRejectedValueOnce(new Error("sidecar offline"))
      .mockResolvedValue(TEST_META);
    vi.mocked(getPlotContract)
      .mockRejectedValueOnce(new Error("sidecar offline"))
      .mockResolvedValue(TEST_CONTRACT);
    vi.mocked(healthcheck)
      .mockResolvedValueOnce(false)
      .mockResolvedValueOnce(true);

    render(<App />);

    await act(async () => {
      await Promise.resolve();
      await Promise.resolve();
    });
    expect(screen.getByText("sidecar offline")).toBeInTheDocument();
    expect(screen.getByText("Sidecar Offline")).toBeInTheDocument();

    await act(async () => {
      vi.advanceTimersByTime(6000);
      await Promise.resolve();
      await Promise.resolve();
    });

    expect(screen.getByText("Sidecar Online")).toBeInTheDocument();
    expect(screen.queryByText("sidecar offline")).not.toBeInTheDocument();

    expect(getWorkbenchMeta).toHaveBeenCalledTimes(2);
    expect(getPlotContract).toHaveBeenCalledTimes(2);
  });
});
