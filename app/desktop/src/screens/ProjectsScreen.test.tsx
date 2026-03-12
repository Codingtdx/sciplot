import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { useComposerStore, useWizardStore, useWorkbenchStore } from "../lib/store";
import { TEST_META } from "../test/fixtures";
import { ProjectsScreen } from "./ProjectsScreen";

vi.mock("../lib/project-io", () => ({
  loadWizardDataFile: vi.fn(),
  loadWizardProjectFile: vi.fn().mockRejectedValue(new Error("project corrupted")),
  loadComposerProjectFile: vi.fn(),
}));

describe("ProjectsScreen", () => {
  beforeEach(() => {
    useWizardStore.getState().reset();
    useComposerStore.getState().reset();
    useWorkbenchStore.setState({
      lastScreen: "wizard",
      pdfImportMode: "graph",
      recentProjects: [
        {
          id: "wizard:project:/tmp/demo.json",
          mode: "wizard",
          kind: "project",
          path: "/tmp/demo.json",
          title: "demo.json",
          detail: "绘图项目",
          updated_at: new Date("2026-03-12T12:00:00Z").toISOString(),
        },
      ],
      settings: { auto_status_poll: true, remember_last_screen: true },
    });
  });

  it("shows restore errors instead of failing silently", async () => {
    render(<ProjectsScreen meta={TEST_META} onNavigate={vi.fn()} />);

    fireEvent.click(screen.getByText("demo.json"));

    await waitFor(() => {
      expect(screen.getByText("project corrupted")).toBeInTheDocument();
    });
  });
});
