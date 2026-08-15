import Foundation
import ManualImporter

struct CLI {
    static func run() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("--help") || arguments.isEmpty { print("Usage: accord-manual-import --input <Honda ESM> --output <ManualBundle> [--no-media]"); return }
        guard let input = value("--input", in: arguments), let output = value("--output", in: arguments) else { throw NSError(domain: "accord-manual-import", code: 2, userInfo: [NSLocalizedDescriptionKey: "--input and --output are required"]) }
        let report = try ESMImporter().importManual(input: URL(fileURLWithPath: input), output: URL(fileURLWithPath: output), copyMedia: !arguments.contains("--no-media"))
        print("Imported \(report.metadata.pageCount) pages, \(report.metadata.imageCount) image references and \(report.metadata.sectionCount) sections. Diagnostics: \(report.diagnostics.count).")
    }
    static func value(_ flag: String, in arguments: [String]) -> String? { guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }; return arguments[index + 1] }
}
do { try CLI.run() } catch { fputs("Import failed: \(error.localizedDescription)\\n", stderr); exit(1) }
