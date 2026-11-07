// Standalone, on-demand passive report. No CoreAudio setters, vendor commands,
// service activation, legacy probing, or fallback to selector 3/4.
import Foundation
import LegacyDiagnosticTransport
import MaestroCore

private struct Report: Encodable {
    let schemaVersion = 1
    let collectedAt: Date
    let os: String
    let cards: [LegacyDiagnosticCardReport]
    let limitations = [
        "Sequential passive register loads, not an atomic hardware snapshot.",
        "Clock detection is not PLL/word-clock lock; lock is unknown.",
        "No converter count or identity is inferred from saved assignments or port state.",
        "IRQ count is global; wrap count is port 1 only. DMA error counters unavailable.",
        "Loaded driver lifecycle/watch may independently perform recovery writes.",
        "No hardware validation or 64-channel audio claim."
    ]
}


do {
    let cards = try LegacyPassiveDiagnostics.collect()
    let report = Report(collectedAt: Date(), os: ProcessInfo.processInfo.operatingSystemVersionString,
                        cards: cards)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    FileHandle.standardOutput.write(try encoder.encode(report))
    FileHandle.standardOutput.write(Data([0x0A]))
    if cards.isEmpty || cards.contains(where: { $0.error != nil }) { exit(2) }
} catch {
    FileHandle.standardError.write(Data("Diagnostic failed: \(error)\n".utf8))
    exit(1)
}
