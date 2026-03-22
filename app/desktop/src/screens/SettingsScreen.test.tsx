import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const apiMocks = vi.hoisted(() => ({
  cleanupManagedStorage: vi.fn(),
  getManagedStorage: vi.fn(),
  healthcheck: vi.fn(),
  openPath: vi.fn(),
}));

vi.mock("../lib/api", async () => {
  const actual = await vi.importActual<typeof import("../lib/api")>("../lib/api");
  return {
    ...actual,
    cleanupManagedStorage: apiMocks.cleanupManagedStorage,
    getManagedStorage: apiMocks.getManagedStorage,
    healthcheck: apiMocks.healthcheck,
    openPath: apiMocks.openPath,
  };
});

import {
  useComposerStore,
  useWorkbenchStore,
  useWizardStore,
} from "../lib/store";
import { TEST_CONTRACT, TEST_META } from "../test/fixtures";
import { SettingsScreen } from "./SettingsScreen";

function makeManagedStorageSnapshot() {
  return {
    root_path: "/tmp/sciplot-god",
    data_root: "/tmp/sciplot-god/data",
    cache_root: "/tmp/sciplot-god/cache",
    example_templates_path: "/tmp/sciplot-god/data/templates/folders/example",
    blank_templates_path: "/tmp/sciplot-god/data/templates/folders/blank",
    single_example_templates_path: "/tmp/sciplot-god/data/templates/single/example",
    single_blank_templates_path: "/tmp/sciplot-god/data/templates/single/blank",
    plot_exports_path: "/tmp/sciplot-god/data/plot_exports",
    code_console_runs_path: "/tmp/sciplot-god/cache/code_console/runs",
    example_template_file_count: 4,
    blank_template_file_count: 4,
    single_template_file_count: 2,
    plot_export_dir_count: 3,
    code_console_run_dir_count: 2,
  };
}

describe("SettingsScreen", () => {
  beforeEach(() => {
    apiMocks.cleanupManagedStorage.mockReset();
    apiMocks.getManagedStorage.mockReset();
    apiMocks.healthcheck.mockReset();
    apiMocks.openPath.mockReset();
    useWizardStore.getState().reset();
    useComposerStore.getState().reset();
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

  it("shows contract-backed frame information", () => {
    render(<SettingsScreen contract={TEST_CONTRACT} meta={TEST_META} />);

    expect(screen.getByText("60 x 55 mm")).toBeInTheDocument();
    expect(screen.getByText("2 contract-backed validation rule(s).")).toBeInTheDocument();
  });

  it("persists the selected theme preset and removes internal guide copy", () => {
    render(<SettingsScreen contract={TEST_CONTRACT} meta={TEST_META} />);

    fireEvent.click(screen.getByRole("button", { name: /Nocturne Glass/i }));

    expect(useWorkbenchStore.getState().settings.appearance_mode).toBe("dark");
    expect(useWorkbenchStore.getState().settings.theme_preset_id).toBe("nocturne-glass");
    expect(screen.queryByText("Current principles")).not.toBeInTheDocument();
  });

  it("reveals and prunes app-managed files when the sidecar is ready", async () => {
    const snapshot = makeManagedStorageSnapshot();
    apiMocks.getManagedStorage.mockResolvedValue(snapshot);
    apiMocks.cleanupManagedStorage.mockResolvedValue({
      ...snapshot,
      strategy: "stale",
      removed_files: 3,
      removed_directories: 1,
    });
    useWizardStore.getState().setSidecarReady(true);

    render(<SettingsScreen contract={TEST_CONTRACT} meta={TEST_META} />);

    await waitFor(() =>
      expect(apiMocks.getManagedStorage).toHaveBeenCalledTimes(1),
    );

    expect(screen.getByRole("button", { name: "Open app data" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Open exports" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Open run cache" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Prune stale" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Clean app files" })).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Open exports" }));
    expect(apiMocks.openPath).toHaveBeenCalledWith("/tmp/sciplot-god/data/plot_exports");

    fireEvent.click(screen.getByRole("button", { name: "Prune stale" }));

    await waitFor(() =>
      expect(apiMocks.cleanupManagedStorage).toHaveBeenCalledWith({ strategy: "stale" }),
    );
    expect(
      screen.getByText("Pruned 3 file(s) and 1 folder(s) from managed storage."),
    ).toBeInTheDocument();
  });
});
