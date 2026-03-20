import type { WizardStep } from "../lib/types";
import { STEPS } from "../lib/workbench";

export function StepFlow({ current }: { current: WizardStep }) {
  const currentIndex = STEPS.findIndex((step) => step.id === current);

  return (
    <div className="flow-strip" role="list" aria-label="Plot workflow steps">
      {STEPS.map((step, index) => {
        const status =
          index < currentIndex ? "complete" : index === currentIndex ? "current" : "upcoming";
        return (
          <div
            aria-current={status === "current" ? "step" : undefined}
            className={`flow-step ${status}`}
            key={step.id}
            role="listitem"
            title={step.hint}
          >
            <span className="flow-step-index">{String(index + 1).padStart(2, "0")}</span>
            <strong>{step.label}</strong>
          </div>
        );
      })}
    </div>
  );
}
