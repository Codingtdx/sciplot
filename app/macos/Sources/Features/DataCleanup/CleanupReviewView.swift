import SwiftUI

struct CleanupReviewView: View {
    let session: DataCleanupSession

    var body: some View {
        if let workbook = session.focusedWorkbook {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("Prepared Workbook") {
                    VStack(alignment: .leading, spacing: 12) {
                        KeyValueGrid(values: [
                            ("Label", workbook.label),
                            ("Specimens", "\(workbook.sampleCount)"),
                            ("Representative file", workbook.representativeFilename),
                            ("Preferred sheet", workbook.preferredSheet.displayName),
                            ("Review template", workbook.reviewTemplateID ?? "Waiting for inspect"),
                        ])
                    }
                    .padding(.top, 8)
                }

                GroupBox("Representative Curve Preview") {
                    VStack(alignment: .leading, spacing: 12) {
                        if workbook.isReviewLoading {
                            BusyStateCard(
                                title: "Preparing workbook preview",
                                message: "The sidecar is inspecting the prepared workbook and rendering the representative curve."
                            )
                        } else if let errorMessage = workbook.reviewErrorMessage {
                            ErrorStateCard(
                                title: "Preview issue",
                                message: errorMessage,
                                retryTitle: "Retry Preview",
                                retryAction: {
                                    Task { await session.refreshFocusedReview() }
                                }
                            )
                        } else if let preview = workbook.reviewPreview {
                            Base64PDFPreviewView(base64PDF: preview.pdfBase64)
                                .frame(minHeight: 340)
                        } else {
                            EmptyStateCard(
                                title: "Preview unavailable",
                                message: "Import or focus a prepared workbook to render its representative curve preview."
                            )
                        }
                    }
                    .padding(.top, 8)
                }

                GroupBox("Metric Summary") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(workbook.metrics, id: \.label) { metric in
                            KeyValueGrid(values: [
                                ("Metric", metric.label),
                                ("Unit", metric.unit),
                                ("Mean", metric.mean?.formatted() ?? "—"),
                                ("Std", metric.std?.formatted() ?? "—"),
                            ])
                            Divider()
                        }
                    }
                    .padding(.top, 8)
                }

                if let inspection = workbook.reviewInspection {
                    GroupBox("Inspection Summary") {
                        VStack(alignment: .leading, spacing: 12) {
                            KeyValueGrid(values: [
                                ("Model", inspection.modelLabel),
                                ("Recommendation", inspection.recommendation.template),
                                ("Confidence", inspection.recommendationConfidence.formatted(.number.precision(.fractionLength(2)))),
                            ])

                            if !inspection.signals.isEmpty {
                                Text("Signals: \(inspection.signals.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if !inspection.warnings.isEmpty {
                                Text("Inspect warnings: \(inspection.warnings.joined(separator: " | "))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let dataset = workbook.reviewDataset {
                                Text("Dataset preview: \(dataset.rawRows) rows × \(dataset.rawCols) columns")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 8)
                    }
                }

                if let submissionReport = workbook.reviewSubmissionReport {
                    GroupBox("Submission Readiness") {
                        VStack(alignment: .leading, spacing: 8) {
                            KeyValueGrid(values: [
                                ("Readiness", submissionReport.readiness),
                                ("Context", submissionReport.context),
                                ("Outputs", "\(submissionReport.outputCount)"),
                            ])
                            Text(submissionReport.summary)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)
                    }
                }

                if !workbook.warnings.isEmpty {
                    GroupBox("Warnings") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(workbook.warnings, id: \.self) { warning in
                                Label(warning, systemImage: "exclamationmark.triangle")
                            }
                        }
                        .padding(.top, 8)
                    }
                }
            }
        } else {
            EmptyStateCard(
                title: "No prepared workbook yet",
                message: "Import raw tensile CSV files or open an existing prepared workbook to review cleanup results."
            )
        }
    }
}
