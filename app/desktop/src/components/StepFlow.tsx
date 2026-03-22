import type { PlotStage } from "../lib/types";

type StepStatus = "complete" | "current" | "upcoming" | "disabled";

export type StepFlowItem = {
  id: PlotStage;
  label: string;
  hint: string;
  status: StepStatus;
  onSelect?: (() => void) | null;
};

export function StepFlow({ steps }: { steps: StepFlowItem[] }) {
  return (
    <div className="flow-strip" role="list" aria-label="Plot workflow steps">
      {steps.map((step, index) => {
        const interactive = step.status === "complete" && typeof step.onSelect === "function";
        const handleSelect = interactive ? (step.onSelect as () => void) : undefined;
        return (
          <div key={step.id} role="listitem">
            <button
              aria-current={step.status === "current" ? "step" : undefined}
              aria-label={`Plot step ${step.label}`}
              className={`flow-step ${step.status}`}
              disabled={!interactive}
              onClick={handleSelect}
              title={step.hint}
              type="button"
            >
              <span className="flow-step-index">{String(index + 1).padStart(2, "0")}</span>
              <div className="flow-step-copy">
                <strong>{step.label}</strong>
                <span className="flow-step-hint">{step.hint}</span>
              </div>
            </button>
          </div>
        );
      })}
    </div>
  );
}
