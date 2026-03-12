import { render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { useComposerStore, useWorkbenchStore } from "../lib/store";
import { ComposerScreen } from "./ComposerScreen";

vi.mock("@tauri-apps/api/webviewWindow", () => ({
  getCurrentWebviewWindow: () => ({
    onDragDropEvent: vi.fn().mockResolvedValue(() => {}),
  }),
}));

vi.mock("../components/ComposerCanvas", () => ({
  ComposerCanvas: () => <div>Canvas</div>,
}));

vi.mock("../lib/api", async () => {
  const actual = await vi.importActual<typeof import("../lib/api")>("../lib/api");
  return {
    ...actual,
    composePreview: vi.fn().mockRejectedValue(new Error("preview exploded")),
    panelThumbnail: vi.fn(),
  };
});

describe("ComposerScreen", () => {
  beforeEach(() => {
    useComposerStore.getState().reset();
    useWorkbenchStore.setState({
      lastScreen: "wizard",
      pdfImportMode: "graph",
      recentProjects: [],
      settings: { auto_status_poll: true, remember_last_screen: true },
    });
  });

  it("surfaces preview failures to the user", async () => {
    render(<ComposerScreen />);

    await waitFor(() => {
      expect(screen.getByText("preview exploded")).toBeInTheDocument();
    });
  });
});
