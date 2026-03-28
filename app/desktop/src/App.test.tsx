import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { App } from "./App";

describe("App shell", () => {
  it("renders the minimal Phase A runtime stub", () => {
    render(<App />);

    expect(screen.getByRole("heading", { name: /Core Runtime Shell/i })).toBeInTheDocument();
    expect(screen.getByText(/render, composer, and tensile backbone active/i)).toBeInTheDocument();
  });
});
