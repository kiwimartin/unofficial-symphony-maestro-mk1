import Foundation
import IOKit
import MaestroCore

public struct LegacyDiagnosticCardReport: Encodable, Sendable, Identifiable {
    public let registryID: UInt64
    public let serviceName: String
    public let driverVersion: String?
    public let snapshot: LegacyXLinkSnapshot?
    public let error: String?
    public var id: UInt64 { registryID }
    public var ports: [LegacyXLinkPortDiagnostics] { snapshot.map(LegacyXLinkDiscovery.ports) ?? [] }
}
/// On-demand only. No AppState, activation, vendor method or recovery fallback.
public enum LegacyPassiveDiagnostics {
    public static func collect() throws -> [LegacyDiagnosticCardReport] {
        var reports: [LegacyDiagnosticCardReport] = []
        var seen = Set<UInt64>()
        for name in ["SymphonyThunderbridge", "SymphonyPassiveDiagnostics"] {
            guard let match = IOServiceNameMatching(name) else { throw LegacyXLinkDiagnosticError.invalidPacket }
            var iterator: io_iterator_t = IO_OBJECT_NULL
            let result = IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator)
            guard result == KERN_SUCCESS else { throw LegacyXLinkDiagnosticError.driverStatus(UInt32(bitPattern: result)) }
            defer { IOObjectRelease(iterator) }
            while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
                defer { IOObjectRelease(service) }
                var id: UInt64 = 0
                let identityResult = IORegistryEntryGetRegistryEntryID(service, &id)
                guard identityResult == KERN_SUCCESS else {
                    throw LegacyXLinkDiagnosticError.driverStatus(UInt32(bitPattern: identityResult))
                }
                guard seen.insert(id).inserted else { continue }
                let version = IORegistryEntryCreateCFProperty(service, "CFBundleVersion" as CFString,
                    kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
                var snapshot: LegacyXLinkSnapshot?
                var error: String?
                var connection: io_connect_t = IO_OBJECT_NULL
                let opened = IOServiceOpen(service, mach_task_self_, 0x53594D43, &connection)
                if opened != KERN_SUCCESS {
                    error = "User-client access denied or unavailable (\(opened)). Own approved signing may be required."
                } else {
                    defer { IOServiceClose(connection) }
                    do {
                        var words = [UInt32](repeating: 0, count: LegacyXLinkSnapshot.wordCount)
                        var size = words.count * 4
                        let result = words.withUnsafeMutableBytes {
                            IOConnectCallStructMethod(connection, LegacyXLinkSnapshot.selector, nil, 0, $0.baseAddress, &size)
                        }
                        guard result == KERN_SUCCESS else {
                            throw LegacyXLinkDiagnosticError.driverStatus(UInt32(bitPattern: result))
                        }
                        guard size == words.count * 4 else { throw LegacyXLinkDiagnosticError.invalidPacket }
                        snapshot = try .init(words: words)
                    } catch let failure {
                        error = "Passive capture unavailable: \(failure). No fallback attempted."
                    }
                }
                reports.append(.init(registryID: id, serviceName: name, driverVersion: version,
                                     snapshot: snapshot, error: error))
            }
        }
        return reports
    }
}
