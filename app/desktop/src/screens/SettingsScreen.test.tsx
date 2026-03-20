import { fireEvent, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it } from "vitest";

import { useComposerStore, useWorkbenchStore, useWizardStore } from "../lib/store";
import { TEST_CONTRACT, TEST_META } from "../test/fixtures";
import { SettingsScreen } from "./SettingsScreen";

describe("SettingsScreen", () => {
  beforeEach(() => {
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
});
