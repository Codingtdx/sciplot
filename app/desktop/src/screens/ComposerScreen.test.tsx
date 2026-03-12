import { act, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { importComposerPanels } from "../lib/api";
import { useComposerStore, useWorkbenchStore } from "../lib/store";
import { ComposerScreen } from "./ComposerScreen";

let dragDropHandler:
  | ((event: { payload: { type: string; paths: string[] } }) => void)
  | null = null;

vi.mock("@tauri-apps/api/webviewWindow", () => ({
  getCurrentWebviewWindow: () => ({
    onDragDropEvent: vi.fn().mockImplementation(async (handler) => {
      dragDropHandler = handler;
      return () => {};
    }),
  }),
}));

vi.mock("../components/ComposerCanvas", () => ({
  ComposerCanvas: () => <div>Canvas</div>,
}));

vi.mock("../lib/api", async () => {
  const actual = await vi.importActual<typeof import("../lib/api")>("../lib/api");
  return {
    ...actual,
    composePreviewWithOptions: vi.fn().mockRejectedValue(new Error("preview exploded")),
    importComposerPanels: vi.fn(),
    panelThumbnail: vi.fn(),
  };
});

describe("ComposerScreen", () => {
  beforeEach(() => {
    dragDropHandler = null;
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

  it("imports dropped pdfs and rasters while skipping unsupported files", async () => {
    vi.mocked(importComposerPanels)
      .mockResolvedValueOnce({
        panels: [
          {
            id: "panel-1",
            file_path: "/tmp/figure.pdf",
            page_index: 0,
            x_mm: 0,
            y_mm: 0,
            w_mm: 60,
            h_mm: 40,
            kind: "graph",
          },
        ],
      })
      .mockResolvedValueOnce({
        panels: [
          {
            id: "panel-1",
            file_path: "/tmp/figure.pdf",
            page_index: 0,
            x_mm: 0,
            y_mm: 0,
            w_mm: 60,
            h_mm: 40,
            kind: "graph",
          },
          {
            id: "panel-2",
            file_path: "/tmp/asset.png",
            page_index: 0,
            x_mm: 64,
            y_mm: 0,
            w_mm: 48,
            h_mm: 36,
            kind: "asset",
          },
        ],
      });

    render(<ComposerScreen />);

    await waitFor(() => {
      expect(dragDropHandler).not.toBeNull();
    });

    await act(async () => {
      dragDropHandler?.({
        payload: {
          type: "drop",
          paths: ["/tmp/figure.pdf", "/tmp/asset.png", "/tmp/notes.txt"],
        },
      });
      await Promise.resolve();
    });

    await waitFor(() => {
      expect(importComposerPanels).toHaveBeenNthCalledWith(
        1,
        expect.objectContaining({ panels: [] }),
        ["/tmp/figure.pdf"],
        "graph",
      );
      expect(importComposerPanels).toHaveBeenNthCalledWith(
        2,
        expect.objectContaining({
          panels: [expect.objectContaining({ file_path: "/tmp/figure.pdf" })],
        }),
        ["/tmp/asset.png"],
        "asset",
      );
    });

    expect(screen.getByText(/已跳过不支持的文件: notes.txt/)).toBeInTheDocument();
    expect(useComposerStore.getState().project.panels).toHaveLength(2);
  });
});
