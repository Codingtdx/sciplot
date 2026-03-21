import { act, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { getPlotContract, getWorkbenchMeta, healthcheck } from "./lib/api";
import {
  useCodeConsoleStore,
  useComposerStore,
  useTensileStore,
  useWizardStore,
  useWorkbenchStore,
} from "./lib/store";
import { TEST_CONTRACT, TEST_META } from "./test/fixtures";
import App from "./App";

vi.mock("./screens/LaunchpadScreen", () => ({
  LaunchpadScreen: () => <div>Launchpad Stub</div>,
}));

vi.mock("./screens/TensileScreen", () => ({
  TensileScreen: () => <div>Tensile Stub</div>,
}));

vi.mock("./screens/WizardScreen", () => ({
  WizardScreen: () => <div>Wizard Stub</div>,
}));

vi.mock("./screens/ComposerScreen", () => ({
  ComposerScreen: () => <div>Composer Stub</div>,
}));

vi.mock("./screens/CodeConsoleScreen", () => ({
  CodeConsoleScreen: () => <div>Code Console Stub</div>,
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
    window.history.replaceState(window.history.state, "", "/");
    useTensileStore.getState().reset();
    useWizardStore.getState().reset();
    useComposerStore.getState().reset();
    useCodeConsoleStore.getState().reset();
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
    vi.mocked(healthcheck).mockResolvedValueOnce(false).mockResolvedValueOnce(true);

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

  it("applies the resolved system theme to the document root", async () => {
    Object.defineProperty(window, "matchMedia", {
      writable: true,
      configurable: true,
      value: vi.fn().mockImplementation((query: string) => ({
        matches: true,
        media: query,
        onchange: null,
        addEventListener: vi.fn(),
        removeEventListener: vi.fn(),
        addListener: vi.fn(),
        removeListener: vi.fn(),
        dispatchEvent: vi.fn(),
      })),
    });
    vi.mocked(getWorkbenchMeta).mockResolvedValue(TEST_META);
    vi.mocked(getPlotContract).mockResolvedValue(TEST_CONTRACT);
    vi.mocked(healthcheck).mockResolvedValue(true);

    render(<App />);

    await act(async () => {
      await Promise.resolve();
      await Promise.resolve();
    });

    expect(document.documentElement.dataset.theme).toBe("dark");
  });

  it("opens on launchpad and no longer renders the old navigation rail", async () => {
    vi.mocked(getWorkbenchMeta).mockResolvedValue(TEST_META);
    vi.mocked(getPlotContract).mockResolvedValue(TEST_CONTRACT);
    vi.mocked(healthcheck).mockResolvedValue(true);

    render(<App />);

    await act(async () => {
      await Promise.resolve();
      await Promise.resolve();
    });

    expect(screen.getByText("Launchpad Stub")).toBeInTheDocument();
    expect(document.querySelector(".nav-rail")).toBeNull();
  });

  it("lets the Start button return to launchpad from Plot without bouncing back", async () => {
    window.history.replaceState(window.history.state, "", "/plot/type");
    vi.mocked(getWorkbenchMeta).mockResolvedValue(TEST_META);
    vi.mocked(getPlotContract).mockResolvedValue(TEST_CONTRACT);
    vi.mocked(healthcheck).mockResolvedValue(true);

    render(<App />);

    await act(async () => {
      await Promise.resolve();
      await Promise.resolve();
    });

    expect(screen.getByText("Wizard Stub")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: /start/i }));

    await act(async () => {
      await Promise.resolve();
      await Promise.resolve();
    });

    expect(screen.getByText("Launchpad Stub")).toBeInTheDocument();
    expect(window.location.pathname).toBe("/");
  });

  it("navigates to the code console workspace from the sidebar", async () => {
    vi.mocked(getWorkbenchMeta).mockResolvedValue(TEST_META);
    vi.mocked(getPlotContract).mockResolvedValue(TEST_CONTRACT);
    vi.mocked(healthcheck).mockResolvedValue(true);

    render(<App />);

    await act(async () => {
      await Promise.resolve();
      await Promise.resolve();
    });

    fireEvent.click(screen.getByRole("button", { name: /code console/i }));

    await act(async () => {
      await Promise.resolve();
      await Promise.resolve();
    });

    expect(screen.getByText("Code Console Stub")).toBeInTheDocument();
    expect(window.location.pathname).toBe("/code-console");
  });
});
