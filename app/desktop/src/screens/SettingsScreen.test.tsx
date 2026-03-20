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
        theme_preference: "system",
      },
    });
  });

  it("shows contract-backed frame information", () => {
    render(<SettingsScreen contract={TEST_CONTRACT} meta={TEST_META} />);

    expect(screen.getByText("60 x 55 mm standard frame")).toBeInTheDocument();
    expect(screen.getByText("2")).toBeInTheDocument();
  });

  it("persists the selected theme preference and removes internal guide copy", () => {
    render(<SettingsScreen contract={TEST_CONTRACT} meta={TEST_META} />);

    fireEvent.change(screen.getByLabelText("Theme"), {
      target: { value: "light" },
    });

    expect(useWorkbenchStore.getState().settings.theme_preference).toBe("light");
    expect(screen.queryByText("Current principles")).not.toBeInTheDocument();
  });
});
