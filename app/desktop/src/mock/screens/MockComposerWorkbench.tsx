import {
  mockComposerAssets,
  mockComposerExportBundle,
  mockComposerHeader,
  mockComposerLayers,
} from "../data/mockComposerData";
import type { MockComposerStageId } from "../data/mockNavigationData";

type MockComposerWorkbenchProps = {
  stage: MockComposerStageId;
};

const COMPOSER_ADD_ACTIONS = ["Add graph", "Add asset", "Add label"];
const COMPOSER_ORDER_ACTIONS = ["Forward", "Back", "To front", "To back"];

export function MockComposerWorkbench({ stage }: MockComposerWorkbenchProps) {
  const railTitle = stage === "assets" ? "Assets" : stage === "export" ? "Export" : "Review";
  const sharedActions = (
    <div className="mock-composer__asset-actions" aria-label="Composer add actions">
      {COMPOSER_ADD_ACTIONS.map((action) => (
        <button key={action} className="mock-button" type="button">
          {action}
        </button>
      ))}
    </div>
  );
  const railBody =
    stage === "assets" ? (
      <>
        {sharedActions}
        <div className="mock-composer__asset-list">
          {mockComposerAssets.map((asset) => (
            <div key={asset.name} className="mock-composer__asset-item">
              <strong>{asset.name}</strong>
              <span>{asset.meta}</span>
            </div>
          ))}
        </div>
      </>
    ) : stage === "export" ? (
      <>
        {sharedActions}
        <div className="mock-composer__export-list">
          {mockComposerExportBundle.map((item) => (
            <div key={item} className="mock-composer__export-item">
              {item}
            </div>
          ))}
          <button className="mock-button mock-button--primary" type="button">
            Export PDF
          </button>
        </div>
      </>
    ) : (
      <>
        {sharedActions}
        <div className="mock-composer__order-actions" aria-label="Composer layer order">
          {COMPOSER_ORDER_ACTIONS.map((action) => (
            <button key={action} className="mock-button" type="button">
              {action}
            </button>
          ))}
        </div>
        <div className="mock-composer__layer-list">
          {mockComposerLayers.map((layer) => (
            <div key={layer} className="mock-composer__layer-item">
              {layer}
            </div>
          ))}
        </div>
      </>
    );

  return (
    <section className="mock-screen mock-workbench mock-composer">
      <div className="mock-composer__layout mock-composer__layout--reduced">
        <div className="mock-panel mock-composer__canvas-panel is-emphasis">
          <div className="mock-panel__header">
            <div>
              <h3>{mockComposerHeader.compositionName}</h3>
            </div>
            <span className="mock-composer__meta">180 × 170 mm</span>
          </div>

          <div className="mock-composer__canvas-surface">
            <div className="mock-composer__region mock-composer__region--wide">
              <div className="mock-composer__region-tag">Graph</div>
              <div className="mock-composer__mini-plot mock-composer__mini-plot--lines" />
            </div>
            <div className="mock-composer__region mock-composer__region--tall">
              <div className="mock-composer__region-tag">Panel</div>
              <div className="mock-composer__mini-plot mock-composer__mini-plot--bars" />
            </div>
            <div className="mock-composer__region mock-composer__region--asset">
              <div className="mock-composer__region-tag">Asset</div>
              <div className="mock-composer__micrograph" />
            </div>
            <div className="mock-composer__annotation">Crosslink density rises.</div>
            <div className="mock-composer__footer-note">Figure 3</div>
          </div>
        </div>

        <aside className="mock-composer__rail">
          <div className="mock-panel mock-composer__support-panel">
            <div className="mock-panel__header">
              <div>
                <h3>{railTitle}</h3>
              </div>
            </div>
            {railBody}
          </div>
        </aside>
      </div>
    </section>
  );
}
