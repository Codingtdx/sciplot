import UniformTypeIdentifiers

enum FileTypeCatalog {
    static let csv = UTType(filenameExtension: "csv") ?? .data
    static let xlsx = UTType(filenameExtension: "xlsx") ?? .data
    static let xlsm = UTType(filenameExtension: "xlsm") ?? .data
    static let pdf = UTType.pdf
    static let png = UTType.png
    static let jpeg = UTType.jpeg
    static let webP = UTType(filenameExtension: "webp") ?? .image
    static let tiff = UTType.tiff

    static let plotInputs = [csv, xlsx, xlsm]
    static let cleanupRawInputs = [csv]
    static let cleanupWorkbookInputs = [xlsx, xlsm]
    static let composerImports = [pdf, png, jpeg, webP, tiff]
    static let workbookExport = [xlsx]
}
