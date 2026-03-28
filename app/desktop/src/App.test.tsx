import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { App } from "./App";

describe("App shell", () => {
  it("renders the minimal Phase A runtime stub", () => {
    render(<App />);

    expect(screen.getByRole("heading", { name: /Core Workbench Foundation/i })).toBeInTheDocument();
    expect(screen.getByText(/four retained workbenches/i)).toBeInTheDocument();
    expect(screen.getByText(/Start, Project, and Settings are utility concerns/i)).toBeInTheDocument();
  });
});
