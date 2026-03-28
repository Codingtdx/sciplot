import {
  mockCleanupColumns,
  mockCleanupCompareCards,
  mockCleanupHandoff,
  mockCleanupHeader,
  mockCleanupIssues,
  mockCleanupRows,
  mockCleanupSources,
} from "../data/mockDataCleanupData";
import type { MockCleanupStageId } from "../data/mockNavigationData";

type MockDataCleanupWorkbenchProps = {
  stage: MockCleanupStageId;
};

export function MockDataCleanupWorkbench({
  stage,
}: MockDataCleanupWorkbenchProps) {
  const showSources = stage === "import";
  const showCompare = stage === "compare";
  const showExport = stage === "export";
  const supportTitle = showSources
    ? "Sources"
    : showExport
      ? "Handoff"
      : "Compare";

  const supportBody = showSources ? (
    <div className="mock-cleanup__source-list">
      {mockCleanupSources.map((source) => (
        <div key={source.name} className="mock-cleanup__source-item">
          <strong>{source.name}</strong>
          <span>{source.status}</span>
        </div>
      ))}
    </div>
  ) : showExport ? (
    <div className="mock-cleanup__handoff-list">
      {mockCleanupHandoff.map((item) => (
        <div key={item.label} className="mock-cleanup__handoff-item">
          <strong>{item.label}</strong>
          <span>{item.action}</span>
        </div>
      ))}
      <div className="mock-cleanup__handoff-actions">
        <button className="mock-button mock-button--primary" type="button">
          Export workbook
        </button>
        <button className="mock-button" type="button">
          Open in Plot
        </button>
      </div>
    </div>
  ) : (
    <div className="mock-cleanup__compare-grid mock-cleanup__compare-grid--compact">
      {mockCleanupCompareCards.map((card) => (
        <div key={card.title} className="mock-cleanup__compare-card">
          <strong>{card.title}</strong>
          <div className="mock-cleanup__mini-chart">
            {card.values.map((item) => (
              <div key={item.label} className="mock-cleanup__mini-bar">
                <div
                  className="mock-cleanup__mini-bar-fill"
                  style={{ height: `${item.value}%` }}
                />
                <small>{item.label}</small>
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  );

  return (
    <section className="mock-screen mock-workbench mock-cleanup">
      <div className="mock-cleanup__layout">
        <div className="mock-cleanup__main">
          <div className="mock-panel mock-cleanup__table-panel is-emphasis">
            <div className="mock-panel__header">
              <div>
                <h3>{mockCleanupHeader.sessionName}</h3>
              </div>
              <span className="mock-cleanup__meta">
                {mockCleanupRows.length} groups · {mockCleanupHeader.preferredSheet}
              </span>
            </div>

            <div className="mock-cleanup__table-wrap">
              <table className="mock-import__table">
                <thead>
                  <tr>
                    {mockCleanupColumns.map((column) => (
                      <th key={column}>{column}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {mockCleanupRows.map((row, rowIndex) => (
                    <tr key={`${row[0]}-${rowIndex}`}>
                      {row.map((cell, cellIndex) => (
                        <td key={`${mockCleanupColumns[cellIndex]}-${cell}`}>{cell}</td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </div>

        <aside className="mock-cleanup__rail">
          <div className="mock-panel mock-cleanup__issues-panel">
            <div className="mock-panel__header">
              <div>
                <h3>Issues</h3>
              </div>
            </div>
            <div className="mock-cleanup__issue-list">
              {mockCleanupIssues.map((issue) => (
                <div key={issue.title} className="mock-cleanup__issue-item">
                  <div className="mock-cleanup__issue-head">
                    <strong>{issue.title}</strong>
                    <span>{issue.severity}</span>
                  </div>
                </div>
              ))}
            </div>
          </div>

          <div className="mock-panel mock-cleanup__support-panel">
            <div className="mock-panel__header">
              <div>
                <h3>{supportTitle}</h3>
              </div>
            </div>
            {supportBody}
          </div>
        </aside>
      </div>
    </section>
  );
}
