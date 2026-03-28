import { render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { App } from "./App";
import { TEST_META } from "./test/fixtures";

const fetchMock = vi.fn<typeof fetch>();

describe("App shell", () => {
  beforeEach(() => {
    vi.stubGlobal("fetch", fetchMock);
    fetchMock.mockReset();
    fetchMock.mockResolvedValue(
      new Response(JSON.stringify(TEST_META), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    );
    window.history.replaceState({}, "", "/");
  });

  it("renders the rebuilt shell and primary plot flow", async () => {
    render(<App />);

    await waitFor(() => {
      expect(screen.getByText("Launch directly into a plotting session.")).toBeInTheDocument();
    });

    expect(screen.getByRole("button", { name: /Start/i })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Plot Import/i })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Plot Template/i })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Plot Refine/i })).toBeInTheDocument();
    expect(screen.getByText(/single plot-first desktop path/i)).toBeInTheDocument();
  });
});
