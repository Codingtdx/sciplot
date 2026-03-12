import { render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it } from "vitest";

import { useWizardStore, useWorkbenchStore } from "../lib/store";
import { TEST_META } from "../test/fixtures";
import { WizardScreen } from "./WizardScreen";

describe("WizardScreen", () => {
  beforeEach(() => {
    useWizardStore.getState().reset();
    useWorkbenchStore.setState({
      lastScreen: "wizard",
      pdfImportMode: "graph",
      recentProjects: [],
      settings: { auto_status_poll: true, remember_last_screen: true },
    });
  });

  it("renders template choices from sidecar meta", () => {
    useWizardStore.setState({
      step: "template",
      template: "curve",
    });

    render(<WizardScreen meta={TEST_META} />);

    expect(screen.getByText("曲线")).toBeInTheDocument();
    expect(screen.getByText("热图")).toBeInTheDocument();
  });

  it("renders options from sidecar meta without local hardcoded lists", () => {
    useWizardStore.setState({
      step: "options",
      template: "heatmap",
      options: {},
    });

    render(<WizardScreen meta={TEST_META} />);

    expect(screen.getByText("显示 colorbar")).toBeInTheDocument();
    expect(screen.getByDisplayValue("Colorblind Safe")).toBeInTheDocument();
  });
});
