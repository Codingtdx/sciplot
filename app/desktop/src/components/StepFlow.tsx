import type { PlotStage } from "../lib/types";
import { StepRail } from "./workbench/V2Primitives";

type StepStatus = "complete" | "current" | "upcoming" | "disabled";

export type StepFlowItem = {
  id: PlotStage;
  label: string;
  hint: string;
  status: StepStatus;
  onSelect?: (() => void) | null;
};

export function StepFlow({ steps }: { steps: StepFlowItem[] }) {
  return <StepRail ariaLabel="Plot workflow steps" steps={steps} />;
}
