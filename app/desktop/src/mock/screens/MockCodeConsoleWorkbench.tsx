import {
  mockConsoleCode,
  mockConsoleContextCards,
  mockConsoleGeneratedFiles,
  mockConsoleHandoff,
  mockConsoleRunFacts,
  mockConsoleStdout,
} from "../data/mockCodeConsoleData";
import type { MockConsoleStageId } from "../data/mockNavigationData";

type MockCodeConsoleWorkbenchProps = {
  stage: MockConsoleStageId;
};

export function MockCodeConsoleWorkbench({
  stage,
}: MockCodeConsoleWorkbenchProps) {
  const sideTitle = stage === "context" ? "Context" : stage === "outputs" ? "Outputs" : "Log";
  const sideBody =
    stage === "context" ? (
      <div className="mock-console__context-list">
        {mockConsoleContextCards.map((card) => (
          <div key={card.label} className="mock-console__context-item">
            <strong>{card.value}</strong>
            <small>{card.detail}</small>
          </div>
        ))}
      </div>
    ) : stage === "outputs" ? (
      <div className="mock-console__generated-list">
        {mockConsoleGeneratedFiles.map((item) => (
          <button
            key={item.name}
            className="mock-console__generated-item"
            type="button"
          >
            <strong>{item.name}</strong>
            <small>{item.role}</small>
          </button>
        ))}
        <div className="mock-console__handoff-list">
          {mockConsoleHandoff.slice(0, 2).map((item) => (
            <div key={item} className="mock-console__handoff-item">
              {item}
            </div>
          ))}
        </div>
        <button className="mock-button" type="button">
          Open output folder
        </button>
      </div>
    ) : (
      <div className="mock-console__stdout">
        {mockConsoleStdout.map((line) => (
          <div key={line} className="mock-console__stdout-line">
            {line}
          </div>
        ))}
      </div>
    );

  return (
    <section className="mock-screen mock-workbench mock-console">
      <div className="mock-console__layout mock-console__layout--reduced">
        <div className="mock-panel mock-console__workspace is-emphasis">
          <div className="mock-console__workspace-header">
            <div>
              <h3>Controlled plotting run</h3>
            </div>
            <button className="mock-button mock-button--primary" type="button">
              Run
            </button>
          </div>

          <div className="mock-console__context-strip" aria-label="Bound context">
            {mockConsoleContextCards.map((card) => (
              <div key={card.label} className="mock-console__context-inline">
                <span>{card.label}</span>
                <strong>{card.value}</strong>
              </div>
            ))}
          </div>

          <div className="mock-console__editor">
            <pre>{mockConsoleCode}</pre>
          </div>

          <div className="mock-console__run-facts mock-console__run-facts--compact">
            {mockConsoleRunFacts.map((fact) => (
              <div key={fact.label} className="mock-console__run-fact">
                <span>{fact.label}</span>
                <strong>{fact.value}</strong>
              </div>
            ))}
          </div>
        </div>

        <aside className="mock-console__artifacts">
          <div className="mock-panel mock-console__support-panel">
            <div className="mock-panel__header">
              <div>
                <h3>{sideTitle}</h3>
              </div>
            </div>
            {sideBody}
          </div>
        </aside>
      </div>
    </section>
  );
}
