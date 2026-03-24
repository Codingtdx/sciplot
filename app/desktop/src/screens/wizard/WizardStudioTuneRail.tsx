import type {
  RenderOptionsPayload,
  TemplateName,
  WorkbenchMeta,
  WorkbenchPalette,
  WorkbenchStyle,
  WorkbenchTemplate,
} from "../../lib/types";
import { CompactToolbar } from "../../components/workbench/V2Primitives";
import { WizardOptionsSection } from "./WizardOptionsSection";

type Props = {
  meta: WorkbenchMeta | null;
  template: TemplateName | null;
  currentTemplate: WorkbenchTemplate | null;
  options: RenderOptionsPayload;
  paletteOptions: WorkbenchPalette[];
  sizeOptions: Array<{ id: string; label: string }>;
  styleOptions: WorkbenchStyle[];
  tensileCurveMode: boolean;
  hasTemplate: boolean;
  onUpdateOptions(value: Partial<RenderOptionsPayload>): void;
  onBackToType(): void;
  onContinueToReview(): void;
};

export function WizardStudioTuneRail({
  meta,
  template,
  currentTemplate,
  options,
  paletteOptions,
  sizeOptions,
  styleOptions,
  tensileCurveMode,
  hasTemplate,
  onUpdateOptions,
  onBackToType,
  onContinueToReview,
}: Props) {
  return (
    <>
      <WizardOptionsSection
        currentTemplate={currentTemplate}
        meta={meta}
        onUpdateOptions={onUpdateOptions}
        options={options}
        paletteOptions={paletteOptions}
        sizeOptions={sizeOptions}
        styleOptions={styleOptions}
        template={template}
        tensileCurveMode={tensileCurveMode}
      />

      <CompactToolbar label="Tune stage actions">
        <button className="ghost-button" onClick={onBackToType} type="button">
          Back to type
        </button>
        <button
          className="primary-button"
          disabled={!hasTemplate}
          onClick={onContinueToReview}
          type="button"
        >
          Continue to review
        </button>
      </CompactToolbar>
    </>
  );
}
