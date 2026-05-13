import Foundation
import UniformTypeIdentifiers

enum FileTypeCatalog {
    static let projectExtension = "sciplot"
    static let plotProject = UTType(exportedAs: "io.github.codingtdx.sciplot.project")
    static let csv = UTType(filenameExtension: "csv") ?? .data
    static let txt = UTType(filenameExtension: "txt") ?? .data
    static let tsv = UTType(filenameExtension: "tsv") ?? .data
    static let xls = UTType(filenameExtension: "xls") ?? .data
    static let xlsx = UTType(filenameExtension: "xlsx") ?? .data
    static let xlsm = UTType(filenameExtension: "xlsm") ?? .data
    static let pdf = UTType.pdf
    static let png = UTType.png
    static let jpeg = UTType.jpeg
    static let webP = UTType(filenameExtension: "webp") ?? .image
    static let tiff = UTType.tiff

    static let plotInputs = [csv, xlsx, xlsm]
    static let plotDocumentInputs = [plotProject, csv, xlsx, xlsm]
    static let dataStudioRawInputs = [csv, txt, tsv, xls, xlsx, xlsm]
    static let dataStudioWorkbookInputs = [xlsx, xlsm]
    static let composerImports = [pdf, png, jpeg, webP, tiff]
    static let composerExport = [pdf, tiff]
    static let workbookExport = [xlsx]

    static func isProjectURL(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == projectExtension
    }
}
