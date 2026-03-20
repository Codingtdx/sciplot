import { act, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { open, save } from "@tauri-apps/plugin-dialog";

import { EMPTY_COMPOSER_PROJECT } from "../lib/composer";
import { composePreviewWithOptions, importComposerPanels } from "../lib/api";
import { loadComposerProjectFile } from "../lib/project-io";
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

vi.mock("@tauri-apps/plugin-dialog", () => ({
  open: vi.fn(),
  save: vi.fn(),
}));

vi.mock("../components/ComposerCanvas", () => ({
  ComposerCanvas: (props: {
    onObjectSelection(ids: string[], additive?: boolean): void;
    onDuplicateDrawableStart(id: string): string | null;
  }) => (
    <div>
      Canvas
      <button
        onClick={() => props.onObjectSelection(["asset-1", "asset-2"], false)}
        type="button"
      >
        Mock Marquee Select
      </button>
      <button
        onClick={() => props.onDuplicateDrawableStart("asset-2")}
        type="button"
      >
        Mock Alt Duplicate
      </button>
    </div>
  ),
}));

vi.mock("../lib/api", async () => {
  const actual = await vi.importActual<typeof import("../lib/api")>("../lib/api");
  return {
    ...actual,
    composePreviewWithOptions: vi.fn().mockRejectedValue(new Error("preview exploded")),
    importComposerPanels: vi.fn(),
    panelThumbnail: vi.fn().mockResolvedValue(""),
  };
});

vi.mock("../lib/project-io", () => ({
  loadComposerProjectFile: vi.fn(),
}));

function seedComposerProject() {
  useComposerStore.getState().setProject({
    ...EMPTY_COMPOSER_PROJECT,
    regions: [
      {
        id: "region-1",
        kind: "free",
        col: 0,
        row: 0,
        col_span: 1,
        row_span: 1,
        label: null,
        locked: false,
        slot_kind: null,
      },
    ],
    panels: [
      {
        id: "asset-1",
        file_path: "/tmp/asset-1.png",
        page_index: 0,
        x_mm: 10,
        y_mm: 20,
        w_mm: 24,
        h_mm: 12,
        locked: false,
        label: null,
        kind: "asset",
        z_index: 0,
        region_id: "region-1",
        slot_id: null,
        crop_rect: { x: 0, y: 0, width: 1, height: 1 },
      },
      {
        id: "asset-2",
        file_path: "/tmp/asset-2.png",
        page_index: 0,
        x_mm: 40,
        y_mm: 36,
        w_mm: 18,
        h_mm: 12,
        locked: false,
        label: null,
        kind: "asset",
        z_index: 1,
        region_id: null,
        slot_id: null,
        crop_rect: { x: 0, y: 0, width: 1, height: 1 },
      },
    ],
  });
}

describe("ComposerScreen", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    dragDropHandler = null;
    useComposerStore.getState().reset();
    useWorkbenchStore.setState({
      lastRoute: "/",
      pdfImportMode: "graph",
      recentProjects: [],
      settings: {
        auto_status_poll: true,
        remember_last_screen: true,
        theme_preference: "system",
      },
    });
    vi.mocked(open).mockReset();
    vi.mocked(save).mockReset();
    vi.mocked(loadComposerProjectFile).mockReset();
    vi.mocked(loadComposerProjectFile).mockResolvedValue(EMPTY_COMPOSER_PROJECT);
  });

  it("surfaces preview failures to the user", async () => {
    render(<ComposerScreen />);

    await waitFor(() => {
      expect(screen.getByText("preview exploded")).toBeInTheDocument();
    });
  });

  it("prompts before replacing the current composer layout when opening a project", async () => {
    seedComposerProject();
    vi.mocked(open).mockResolvedValue("/tmp/layout.plotproject.json");
    const confirmSpy = vi.spyOn(window, "confirm").mockReturnValue(false);

    render(<ComposerScreen />);

    fireEvent.click(screen.getByRole("button", { name: "Open project" }));

    await waitFor(() => {
      expect(confirmSpy).toHaveBeenCalledWith(
        expect.stringContaining("replace the current Composer layout"),
      );
    });
    expect(loadComposerProjectFile).not.toHaveBeenCalled();

    confirmSpy.mockRestore();
  });

  it("applies preview cleanup suggestions to the project", async () => {
    vi.mocked(composePreviewWithOptions).mockResolvedValue({
      valid: true,
      validation_error: null,
      png_base64: "",
      qa: {
        score: 82,
        grade: "solid",
        issues: [],
        autofixes_applied: [],
      },
      suggested_project_patch: [
        {
          kind: "text",
          id: "text-1",
          patch: { x_mm: 120, y_mm: 24 },
        },
      ],
    });
    useComposerStore.getState().setProject({
      ...EMPTY_COMPOSER_PROJECT,
      texts: [
        {
          id: "text-1",
          text: "Hello",
          x_mm: 178,
          y_mm: 10,
          font_size_pt: 8,
          align: "left",
          z_index: 0,
        },
      ],
    });

    render(<ComposerScreen />);

    await waitFor(() => {
      expect(
        screen.getByRole("button", { name: "Apply cleanup suggestions" }),
      ).toBeInTheDocument();
    });

    fireEvent.click(screen.getByRole("button", { name: "Apply cleanup suggestions" }));

    await waitFor(() => {
      expect(useComposerStore.getState().project.texts[0]).toMatchObject({
        x_mm: 120,
        y_mm: 24,
      });
    });

    expect(screen.getByText("Applied layout cleanup suggestions.")).toBeInTheDocument();
  });

  it("surfaces desktop dialog failures to the user", async () => {
    vi.mocked(open).mockRejectedValue(new Error("dialog unavailable"));

    render(<ComposerScreen />);

    fireEvent.click(screen.getByRole("button", { name: "Import graph" }));

    await waitFor(() => {
      expect(
        screen.getByText("Could not open the file picker: dialog unavailable"),
      ).toBeInTheDocument();
    });
  });

  it("imports dropped pdfs and rasters while skipping unsupported files", async () => {
    vi.mocked(importComposerPanels)
      .mockResolvedValueOnce({
        ...EMPTY_COMPOSER_PROJECT,
        regions: [
          {
            id: "region-1",
            kind: "graph",
            col: 0,
            row: 0,
            col_span: 1,
            row_span: 1,
            label: null,
            locked: false,
            slot_kind: null,
          },
        ],
        panels: [
          {
            id: "panel-1",
            file_path: "/tmp/figure.pdf",
            page_index: 0,
            x_mm: 0,
            y_mm: 2.5,
            w_mm: 60,
            h_mm: 55,
            kind: "graph",
            z_index: 0,
            region_id: "region-1",
            slot_id: null,
            crop_rect: { x: 0, y: 0, width: 1, height: 1 },
          },
        ],
      })
      .mockResolvedValueOnce({
        ...EMPTY_COMPOSER_PROJECT,
        regions: [
          {
            id: "region-1",
            kind: "graph",
            col: 0,
            row: 0,
            col_span: 1,
            row_span: 1,
            label: null,
            locked: false,
            slot_kind: null,
          },
        ],
        panels: [
          {
            id: "panel-1",
            file_path: "/tmp/figure.pdf",
            page_index: 0,
            x_mm: 0,
            y_mm: 2.5,
            w_mm: 60,
            h_mm: 55,
            kind: "graph",
            z_index: 0,
            region_id: "region-1",
            slot_id: null,
            crop_rect: { x: 0, y: 0, width: 1, height: 1 },
          },
          {
            id: "asset-1",
            file_path: "/tmp/asset.png",
            page_index: 0,
            x_mm: 64,
            y_mm: 20,
            w_mm: 48,
            h_mm: 36,
            kind: "asset",
            z_index: 1,
            region_id: null,
            slot_id: null,
            crop_rect: { x: 0, y: 0, width: 1, height: 1 },
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
        expect.objectContaining({ panels: [], regions: [] }),
        ["/tmp/figure.pdf"],
        "graph",
      );
      expect(importComposerPanels).toHaveBeenNthCalledWith(
        2,
        expect.objectContaining({
          panels: [expect.objectContaining({ file_path: "/tmp/figure.pdf" })],
          regions: [expect.objectContaining({ id: "region-1" })],
        }),
        ["/tmp/asset.png"],
        "asset",
      );
    });

    expect(screen.getByText(/Skipped unsupported files: notes\.txt/)).toBeInTheDocument();
    expect(useComposerStore.getState().project.panels).toHaveLength(2);
    expect(useComposerStore.getState().project.regions).toHaveLength(1);
  });

  it("supports multi-select alignment from the layer list", async () => {
    seedComposerProject();

    render(<ComposerScreen />);

    fireEvent.click(screen.getByRole("button", { name: "Mock Marquee Select" }));
    fireEvent.click(screen.getByRole("button", { name: "Left" }));

    await waitFor(() => {
      const project = useComposerStore.getState().project;
      expect(project.panels.find((panel) => panel.id === "asset-1")?.x_mm).toBe(10);
      expect(project.panels.find((panel) => panel.id === "asset-2")?.x_mm).toBe(10);
    });
  });

  it("groups the selected objects and reselects the whole group from one member", async () => {
    seedComposerProject();

    render(<ComposerScreen />);

    fireEvent.click(screen.getByRole("button", { name: "Mock Marquee Select" }));
    fireEvent.click(screen.getByRole("button", { name: "Group" }));

    await waitFor(() => {
      const project = useComposerStore.getState().project;
      expect(project.panels.find((panel) => panel.id === "asset-1")?.group_id).toBeTruthy();
      expect(project.panels.find((panel) => panel.id === "asset-2")?.group_id).toBeTruthy();
    });

    fireEvent.click(screen.getByRole("tab", { name: "Layers" }));
    fireEvent.click(screen.getByRole("button", { name: /asset-1\.png/i }));
    fireEvent.click(screen.getByRole("tab", { name: "Inspect" }));

    await waitFor(() => {
      const tile = screen.getByText("Selected").closest(".stat-tile");
      expect(tile).not.toBeNull();
      expect(within(tile as HTMLElement).getByText("2")).toBeInTheDocument();
    });
  });

  it("ungroups the selected objects", async () => {
    seedComposerProject();

    render(<ComposerScreen />);

    fireEvent.click(screen.getByRole("button", { name: "Mock Marquee Select" }));
    fireEvent.click(screen.getByRole("button", { name: "Group" }));

    await waitFor(() => {
      expect(useComposerStore.getState().project.panels.find((panel) => panel.id === "asset-1")?.group_id).toBeTruthy();
    });

    fireEvent.click(screen.getByRole("button", { name: "Ungroup" }));

    await waitFor(() => {
      const project = useComposerStore.getState().project;
      expect(project.panels.find((panel) => panel.id === "asset-1")?.group_id).toBeNull();
      expect(project.panels.find((panel) => panel.id === "asset-2")?.group_id).toBeNull();
    });
  });

  it("supports marquee-driven multi-select from the canvas", async () => {
    seedComposerProject();

    render(<ComposerScreen />);

    fireEvent.click(screen.getByRole("button", { name: "Mock Marquee Select" }));

    await waitFor(() => {
      const tile = screen.getByText("Selected").closest(".stat-tile");
      expect(tile).not.toBeNull();
      expect(within(tile as HTMLElement).getByText("2")).toBeInTheDocument();
    });
  });

  it("supports ctrl-click additive selection from the layer list", async () => {
    seedComposerProject();

    render(<ComposerScreen />);

    fireEvent.click(screen.getByRole("tab", { name: "Layers" }));
    fireEvent.click(screen.getByRole("button", { name: /asset-1\.png/i }), { ctrlKey: true });
    fireEvent.click(screen.getByRole("button", { name: /asset-2\.png/i }), { ctrlKey: true });
    fireEvent.click(screen.getByRole("tab", { name: "Inspect" }));

    await waitFor(() => {
      const tile = screen.getByText("Selected").closest(".stat-tile");
      expect(tile).not.toBeNull();
      expect(within(tile as HTMLElement).getByText("2")).toBeInTheDocument();
    });
  });

  it("locks and unlocks selected drawables from the layer actions", async () => {
    seedComposerProject();

    render(<ComposerScreen />);

    fireEvent.click(screen.getByRole("button", { name: "Mock Marquee Select" }));
    fireEvent.click(screen.getByRole("tab", { name: "Layers" }));
    fireEvent.click(screen.getByRole("button", { name: "Lock selected" }));

    await waitFor(() => {
      const project = useComposerStore.getState().project;
      expect(project.panels.find((panel) => panel.id === "asset-1")?.locked).toBe(true);
      expect(project.panels.find((panel) => panel.id === "asset-2")?.locked).toBe(true);
    });

    fireEvent.click(screen.getByRole("button", { name: "Unlock selected" }));

    await waitFor(() => {
      const project = useComposerStore.getState().project;
      expect(project.panels.find((panel) => panel.id === "asset-1")?.locked).toBe(false);
      expect(project.panels.find((panel) => panel.id === "asset-2")?.locked).toBe(false);
    });
  });

  it("hides and shows selected drawables from the layer actions", async () => {
    seedComposerProject();

    render(<ComposerScreen />);

    fireEvent.click(screen.getByRole("button", { name: "Mock Marquee Select" }));
    fireEvent.click(screen.getByRole("tab", { name: "Layers" }));
    fireEvent.click(screen.getByRole("button", { name: "Hide selected" }));

    await waitFor(() => {
      const project = useComposerStore.getState().project;
      expect(project.panels.find((panel) => panel.id === "asset-1")?.hidden).toBe(true);
      expect(project.panels.find((panel) => panel.id === "asset-2")?.hidden).toBe(true);
    });

    fireEvent.click(screen.getByRole("button", { name: "Show selected" }));

    await waitFor(() => {
      const project = useComposerStore.getState().project;
      expect(project.panels.find((panel) => panel.id === "asset-1")?.hidden).toBe(false);
      expect(project.panels.find((panel) => panel.id === "asset-2")?.hidden).toBe(false);
    });
  });

  it("nudges the selected asset with arrow keys", async () => {
    seedComposerProject();

    render(<ComposerScreen />);

    fireEvent.click(screen.getByRole("tab", { name: "Layers" }));
    fireEvent.click(screen.getByRole("button", { name: /asset-1\.png/i }));
    fireEvent.keyDown(window, { key: "ArrowRight" });

    await waitFor(() => {
      const project = useComposerStore.getState().project;
      expect(project.panels.find((panel) => panel.id === "asset-1")?.x_mm).toBe(10.5);
      expect(project.panels.find((panel) => panel.id === "asset-1")?.y_mm).toBe(20);
    });
  });

  it("does not move or resize a locked asset through keyboard and binding actions", async () => {
    seedComposerProject();
    useComposerStore.getState().setProject({
      ...useComposerStore.getState().project,
      panels: useComposerStore
        .getState()
        .project.panels.map((panel) =>
          panel.id === "asset-1" ? { ...panel, locked: true } : panel,
        ),
    });

    render(<ComposerScreen />);

    fireEvent.click(screen.getByRole("tab", { name: "Layers" }));
    fireEvent.click(screen.getByRole("button", { name: /asset-1\.png/i }));
    fireEvent.keyDown(window, { key: "ArrowRight" });
    fireEvent.click(screen.getByRole("button", { name: "Fit to binding" }));

    await waitFor(() => {
      const project = useComposerStore.getState().project;
      expect(project.panels.find((panel) => panel.id === "asset-1")).toMatchObject({
        x_mm: 10,
        y_mm: 20,
        w_mm: 24,
        h_mm: 12,
        locked: true,
      });
    });
  });

  it("snaps a bound asset to the bottom of its region", async () => {
    seedComposerProject();

    render(<ComposerScreen />);

    fireEvent.click(screen.getByRole("tab", { name: "Layers" }));
    fireEvent.click(screen.getByRole("button", { name: /asset-1\.png/i }));
    fireEvent.click(screen.getByRole("button", { name: "Bottom" }));

    await waitFor(() => {
      const project = useComposerStore.getState().project;
      expect(project.panels.find((panel) => panel.id === "asset-1")?.y_mm).toBe(45.5);
      expect(project.panels.find((panel) => panel.id === "asset-1")?.x_mm).toBe(10);
    });
  });

  it("duplicates the selected object with the repeat action", async () => {
    seedComposerProject();

    render(<ComposerScreen />);

    fireEvent.click(screen.getByRole("tab", { name: "Layers" }));
    fireEvent.click(screen.getByRole("button", { name: /asset-2\.png/i }));
    fireEvent.click(screen.getByRole("button", { name: "Duplicate" }));

    await waitFor(() => {
      const project = useComposerStore.getState().project;
      expect(project.panels).toHaveLength(3);
      expect(project.panels.find((panel) => panel.id === "asset-3")).toMatchObject({
        x_mm: 44,
        y_mm: 40,
        file_path: "/tmp/asset-2.png",
      });
    });
  });

  it("copies and pastes the selected object with keyboard shortcuts", async () => {
    seedComposerProject();

    render(<ComposerScreen />);

    fireEvent.click(screen.getByRole("tab", { name: "Layers" }));
    fireEvent.click(screen.getByRole("button", { name: /asset-2\.png/i }));
    fireEvent.keyDown(window, { key: "c", ctrlKey: true });
    fireEvent.keyDown(window, { key: "v", ctrlKey: true });

    await waitFor(() => {
      const project = useComposerStore.getState().project;
      expect(project.panels).toHaveLength(3);
      expect(project.panels.find((panel) => panel.id === "asset-3")).toMatchObject({
        x_mm: 44,
        y_mm: 40,
      });
    });

    expect(screen.getByText("Pasted a duplicated selection.")).toBeInTheDocument();
  });

  it("snaps a bound asset to the left edge of its region", async () => {
    seedComposerProject();

    render(<ComposerScreen />);

    fireEvent.click(screen.getByRole("tab", { name: "Layers" }));
    fireEvent.click(screen.getByRole("button", { name: /asset-1\.png/i }));
    fireEvent.click(screen.getByRole("button", { name: "Left" }));

    await waitFor(() => {
      const project = useComposerStore.getState().project;
      expect(project.panels.find((panel) => panel.id === "asset-1")?.x_mm).toBe(0);
      expect(project.panels.find((panel) => panel.id === "asset-1")?.y_mm).toBe(20);
    });
  });

  it("duplicates a drawable at the same position for alt-drag copy", async () => {
    seedComposerProject();

    render(<ComposerScreen />);

    fireEvent.click(screen.getByRole("button", { name: "Mock Alt Duplicate" }));

    await waitFor(() => {
      const project = useComposerStore.getState().project;
      expect(project.panels).toHaveLength(3);
      expect(project.panels.find((panel) => panel.id === "asset-3")).toMatchObject({
        x_mm: 40,
        y_mm: 36,
        file_path: "/tmp/asset-2.png",
      });
    });
  });

  it("can hide the selected asset from preview/export", async () => {
    seedComposerProject();

    render(<ComposerScreen />);

    fireEvent.click(screen.getByRole("tab", { name: "Layers" }));
    fireEvent.click(screen.getByRole("button", { name: /asset-2\.png/i }));
    fireEvent.click(screen.getByLabelText("Hide object"));

    await waitFor(() => {
      const project = useComposerStore.getState().project;
      expect(project.panels.find((panel) => panel.id === "asset-2")?.hidden).toBe(true);
    });
  });
});
