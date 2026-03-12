import { render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it } from "vitest";

import { useComposerStore, useWorkbenchStore, useWizardStore } from "../lib/store";
import { TEST_CONTRACT, TEST_META } from "../test/fixtures";
import { SettingsScreen } from "./SettingsScreen";

describe("SettingsScreen", () => {
  beforeEach(() => {
    useWizardStore.getState().reset();
    useComposerStore.getState().reset();
    useWorkbenchStore.setState({
      lastScreen: "wizard",
      pdfImportMode: "graph",
      recentProjects: [],
      settings: { auto_status_poll: true, remember_last_screen: true },
    });
  });

  it("shows contract-backed frame information", () => {
    render(<SettingsScreen contract={TEST_CONTRACT} meta={TEST_META} />);

    expect(screen.getByText("60 x 55 mm 标准轴框")).toBeInTheDocument();
    expect(screen.getByText("2")).toBeInTheDocument();
  });
});
