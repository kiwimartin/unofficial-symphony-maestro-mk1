// Standalone, on-demand passive report. No CoreAudio setters, vendor commands,
// service activation, legacy probing, or fallback to selector 3/4.
import Foundation
import IOKit
import MaestroCore

private struct Source: LegacyXLinkDiagnosticSource {
    let connection: io_connect_t
    func readLegacyXLinkEvidence() throws -> LegacyXLinkEvidence {
        var words = [UInt32](repeating: 0, count: LegacyXLinkSnapshot.wordCount)
        var size = words.count * MemoryLayout<UInt32>.size
        let result = words.withUnsafeMutableBytes { bytes in
            IOConnectCallStructMethod(connection, LegacyXLinkSnapshot.selector,
                                      nil, 0, bytes.baseAddress, &size)
        }
        guard result == KERN_SUCCESS else {
            throw LegacyXLinkDiagnosticError.driverStatus(UInt32(bitPattern: result))
        }
        guard size == LegacyXLinkSnapshot.wordCount * 4 else {
            throw LegacyXLinkDiagnosticError.invalidPacket
        }
        return try .init(snapshot: LegacyXLinkSnapshot(words: words))
    }
}

private struct CardReport: Encodable {
    var registryID: UInt64
    var driverVersion: String?
    var snapshot: LegacyXLinkSnapshot?
    var ports: [LegacyXLinkPortDiagnostics]?
    var error: String?
    let converterEnumeration = "unavailable: no verified legacy enumeration protocol"
    let converterIdentities: [String] = []
    let activePhysicalChannelMap = "unavailable: no verified converter-to-XLink slot map"
    let coreAudioFormat = "not queried; existing driver publishes 32x32, not proof of physical I/O"
}
private struct Report: Encodable {
    let schemaVersion = 1
    let collectedAt: Date
    let os: String
    let cards: [CardReport]
    let limitations = [
        "Sequential passive register loads, not an atomic hardware snapshot.",
        "Clock detection is not PLL/word-clock lock; lock is unknown.",
        "No converter count or identity is inferred from saved assignments or port state.",
        "IRQ count is global; wrap count is port 1 only. DMA error counters unavailable.",
        "Loaded driver lifecycle/watch may independently perform recovery writes.",
        "No hardware validation or 64-channel audio claim."
    ]
}

private func collect() throws -> [CardReport] {
    guard let match = IOServiceNameMatching("SymphonyThunderbridge") else {
        throw LegacyXLinkDiagnosticError.invalidPacket
    }
    var iterator: io_iterator_t = IO_OBJECT_NULL
    let result = IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator)
    guard result == KERN_SUCCESS else {
        throw LegacyXLinkDiagnosticError.driverStatus(UInt32(bitPattern: result))
    }
    defer { IOObjectRelease(iterator) }
    var cards: [CardReport] = []
    while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
        defer { IOObjectRelease(service) }
        var registryID: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(service, &registryID)
        let version = IORegistryEntryCreateCFProperty(service, "CFBundleVersion" as CFString,
                                                     kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
        var card = CardReport(registryID: registryID, driverVersion: version)
        var connection: io_connect_t = IO_OBJECT_NULL
        let opened = IOServiceOpen(service, mach_task_self_, 0x53594D43, &connection)
        if opened != KERN_SUCCESS {
            card.error = "user-client unavailable: \(opened); own approved signing/entitlements may be required"
        } else {
            defer { IOServiceClose(connection) }
            do {
                let discovered = try LegacyXLinkDiscovery().refresh(source: Source(connection: connection))
                card.snapshot = discovered.snapshot
                card.ports = discovered.ports
            } catch {
                card.error = "passive selector unavailable: \(error); no fallback attempted"
            }
        }
        cards.append(card)
    }
    return cards
}

do {
    let cards = try collect()
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
