import { useEffect } from "react";

import type { PlotStage } from "../../lib/types";
import { wizardStepForStage } from "../../lib/workbench";

type Args = {
  routeStage: PlotStage;
  stage: PlotStage;
  inputPath: string;
  sheetNamesLength: number;
  inspection: object | null;
  template: string | null;
  outputsLength: number;
  exportResult: object | null;
  setStage(value: PlotStage): void;
  setStep(value: ReturnType<typeof wizardStepForStage>): void;
  goToStage(stage: PlotStage): void;
};

export function useWizardStageRouting({
  routeStage,
  stage,
  inputPath,
  sheetNamesLength,
  inspection,
  template,
  outputsLength,
  exportResult,
  setStage,
  setStep,
  goToStage,
}: Args) {
  useEffect(() => {
    if (stage !== routeStage) {
      setStage(routeStage);
      setStep(wizardStepForStage(routeStage));
    }
  }, [routeStage, setStage, setStep, stage]);

  useEffect(() => {
    if (!inputPath && routeStage !== "import") {
      goToStage("import");
      return;
    }
    if (inputPath && sheetNamesLength <= 1 && routeStage === "sheet") {
      goToStage("type");
      return;
    }
    if (!inspection && (routeStage === "type" || routeStage === "tune" || routeStage === "review")) {
      goToStage("import");
      return;
    }
    if (!template && (routeStage === "tune" || routeStage === "review")) {
      goToStage("type");
      return;
    }
    if (routeStage === "export" && outputsLength === 0 && !exportResult) {
      goToStage("review");
    }
  }, [
    routeStage,
    exportResult,
    inputPath,
    inspection,
    outputsLength,
    sheetNamesLength,
    template,
  ]);
}
