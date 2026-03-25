import { renderHook, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { panelThumbnail } from "../../lib/api";
import type { ComposerPanel } from "../../lib/types";
import { usePanelThumbnails } from "./usePanelThumbnails";

vi.mock("../../lib/api", async () => {
  const actual = await vi.importActual<typeof import("../../lib/api")>("../../lib/api");
  return {
    ...actual,
    panelThumbnail: vi.fn(),
  };
});

const PANEL_BASE: Omit<ComposerPanel, "id"> = {
  file_path: "/tmp/figure.pdf",
  page_index: 0,
  x_mm: 0,
  y_mm: 0,
  w_mm: 60,
  h_mm: 55,
  kind: "graph",
  z_index: 1,
  crop_rect: { x: 0, y: 0, width: 1, height: 1 },
};

describe("usePanelThumbnails", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("deduplicates in-flight thumbnail requests for identical panel sources", async () => {
    vi.mocked(panelThumbnail).mockResolvedValue("thumb-1");
    const panels: ComposerPanel[] = [
      { ...PANEL_BASE, id: "panel-a" },
      { ...PANEL_BASE, id: "panel-b" },
    ];

    const { result } = renderHook(() => usePanelThumbnails(panels));
    await waitFor(() => expect(result.current["panel-a"]).toBe("thumb-1"));
    expect(result.current["panel-b"]).toBe("thumb-1");
    expect(panelThumbnail).toHaveBeenCalledTimes(1);
  });

  it("reuses cached thumbnails for newly added panels with the same source key", async () => {
    vi.mocked(panelThumbnail).mockResolvedValue("thumb-cached");
    const initialPanels: ComposerPanel[] = [
      { ...PANEL_BASE, id: "panel-a" },
    ];
    const { result, rerender } = renderHook(
      ({ panels }) => usePanelThumbnails(panels),
      { initialProps: { panels: initialPanels } },
    );

    await waitFor(() => expect(result.current["panel-a"]).toBe("thumb-cached"));
    expect(panelThumbnail).toHaveBeenCalledTimes(1);

    rerender({
      panels: [
        ...initialPanels,
        { ...PANEL_BASE, id: "panel-b" },
      ],
    });

    await waitFor(() => expect(result.current["panel-b"]).toBe("thumb-cached"));
    expect(panelThumbnail).toHaveBeenCalledTimes(1);
  });
});
