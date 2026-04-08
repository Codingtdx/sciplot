import PDFKit
import SwiftUI

final class PlotPDFView: PDFView {
    private var pendingFitReset = false

    func configureForPlotPreview() {
        autoScales = true
        displayMode = .singlePage
        displaysPageBreaks = false
        backgroundColor = .clear
    }

    override func layout() {
        super.layout()
        applyPendingFitResetIfPossible()
    }

    func resetToFit() {
        pendingFitReset = true
        applyPendingFitResetIfPossible()
        if pendingFitReset {
            needsLayout = true
            layoutSubtreeIfNeeded()
            applyPendingFitResetIfPossible()
        }
    }

    private func applyPendingFitResetIfPossible() {
        guard pendingFitReset else {
            return
        }
        guard document != nil, bounds.width > 1, bounds.height > 1 else {
            return
        }

        autoScales = true
        goToFirstPage(nil)

        let fitScale = scaleFactorForSizeToFit
        let resolvedScale: CGFloat
        if fitScale.isFinite, fitScale > 0 {
            resolvedScale = fitScale
        } else if scaleFactor.isFinite, scaleFactor > 0 {
            resolvedScale = scaleFactor
        } else {
            resolvedScale = 1.0
        }

        minScaleFactor = min(0.1, resolvedScale)
        maxScaleFactor = max(4.0, resolvedScale * 6.0)
        if fitScale.isFinite, fitScale > 0 {
            scaleFactor = fitScale
        }
        autoScales = true
        pendingFitReset = false
    }
}

struct PDFPreviewView: NSViewRepresentable {
    final class Coordinator {
        var lastURL: URL?
        var lastDataFingerprint: Int?
    }

    private let url: URL?
    private let data: Data?

    init(url: URL) {
        self.url = url
        self.data = nil
    }

    init(data: Data) {
        self.url = nil
        self.data = data
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PlotPDFView {
        let view = PlotPDFView()
        view.configureForPlotPreview()
        return view
    }

    func updateNSView(_ pdfView: PlotPDFView, context: Context) {
        if let url {
            if context.coordinator.lastURL != url {
                pdfView.document = PDFDocument(url: url)
                context.coordinator.lastURL = url
                context.coordinator.lastDataFingerprint = nil
                pdfView.resetToFit()
            }
            return
        }

        if let data {
            let fingerprint = dataFingerprint(data)
            if context.coordinator.lastDataFingerprint != fingerprint {
                pdfView.document = PDFDocument(data: data)
                context.coordinator.lastDataFingerprint = fingerprint
                context.coordinator.lastURL = nil
                pdfView.resetToFit()
            }
        }
    }

    private func dataFingerprint(_ data: Data) -> Int {
        var hasher = Hasher()
        hasher.combine(data.count)
        if let first = data.first {
            hasher.combine(first)
        }
        if let last = data.last {
            hasher.combine(last)
        }
        hasher.combine(data.prefix(32))
        hasher.combine(data.suffix(32))
        return hasher.finalize()
    }
}

struct Base64PDFPreviewView: View {
    let base64PDF: String

    var body: some View {
        if let data = Data(base64Encoded: base64PDF),
           PDFDocument(data: data) != nil
        {
            PDFPreviewView(data: data)
                .background(.black.opacity(0.02), in: RoundedRectangle(cornerRadius: 18))
        } else {
            EmptyStateCard(
                title: "Preview unavailable",
                message: "The sidecar returned preview data that could not be decoded as a PDF."
            )
        }
    }
}
