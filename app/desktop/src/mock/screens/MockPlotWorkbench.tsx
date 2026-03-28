import { MockStageNav } from "../components/MockStageNav";
import type { MockPlotStageId, MockRoute } from "../data/mockNavigationData";
import { MockPlotImport } from "./MockPlotImport";
import { MockPlotRefine } from "./MockPlotRefine";
import { MockPlotTemplate } from "./MockPlotTemplate";

type MockPlotWorkbenchProps = {
  stage: MockPlotStageId;
};

function getRoute(stage: MockPlotStageId): MockRoute {
  return { workbench: "plot", stage };
}

export function MockPlotWorkbench({ stage }: MockPlotWorkbenchProps) {
  return (
    <section className="mock-screen mock-workbench mock-workbench--plot">
      <MockStageNav currentRoute={getRoute(stage)} />
      {stage === "import" ? <MockPlotImport /> : null}
      {stage === "template" ? <MockPlotTemplate /> : null}
      {stage === "refine" ? <MockPlotRefine /> : null}
    </section>
  );
}
