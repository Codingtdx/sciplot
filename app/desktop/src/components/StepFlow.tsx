import type { WizardStep } from "../lib/types";
import { STEPS } from "../lib/workbench";

export function StepFlow({ current }: { current: WizardStep }) {
  const currentIndex = STEPS.findIndex((step) => step.id === current);

  return (
    <div className="flow-strip">
      {STEPS.map((step, index) => {
        const status =
          index < currentIndex ? "complete" : index === currentIndex ? "current" : "upcoming";
        return (
          <div className={`flow-step ${status}`} key={step.id}>
            <span className="flow-step-index">{String(index + 1).padStart(2, "0")}</span>
            <div className="flow-step-body">
              <strong>{step.label}</strong>
              <span>{step.hint}</span>
            </div>
          </div>
        );
      })}
    </div>
  );
}
