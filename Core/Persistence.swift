import Foundation
private struct ReportEnvelope: Codable { var schema: Int; var networkID: String; var networkVersion: String; var reports: [Report] }
public final class ReportStore {
    public let url: URL
    public var failRead = false; public var failWrite = false
    public init(url: URL) { self.url = url }
    public func load(network: Network) throws -> [Report] {
        if failRead { throw CoreError.corruptReports }
        guard FileManager.default.fileExists(atPath:url.path) else { return [] }
        let envelope: ReportEnvelope
        do { envelope = try JSONDecoder().decode(ReportEnvelope.self,from:Data(contentsOf:url)) } catch { throw CoreError.corruptReports }
        guard envelope.schema == 1, envelope.networkID == network.id, envelope.networkVersion == network.version, envelope.reports.allSatisfy({ network.edge($0.segmentID) != nil }) else { throw CoreError.incompatibleReports }
        return envelope.reports
    }
    /// Explicit, user-confirmed migration after a network update: keeps reports whose segment ID still exists.
    public func migrationPreview(network: Network) throws -> (kept: [Report], dropped: [Report]) {
        guard FileManager.default.fileExists(atPath:url.path) else { return ([],[]) }
        guard let envelope = try? JSONDecoder().decode(ReportEnvelope.self,from:Data(contentsOf:url)), envelope.schema == 1, envelope.networkID == network.id else { throw CoreError.corruptReports }
        let ids = Set(network.edges.map(\.id))
        return (envelope.reports.filter { ids.contains($0.segmentID) }, envelope.reports.filter { !ids.contains($0.segmentID) })
    }
    /// Moves the current file aside instead of deleting it. Returns the backup location.
    @discardableResult public func archive(label: String) throws -> URL? {
        guard FileManager.default.fileExists(atPath:url.path) else { return nil }
        let safe = label.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let backup = url.deletingLastPathComponent().appendingPathComponent(url.deletingPathExtension().lastPathComponent+"-backup-"+String(safe)+"-"+UUID().uuidString.prefix(8)+".json")
        try FileManager.default.moveItem(at:url,to:backup)
        return backup
    }
    public func save(_ reports: [Report], network: Network) throws {
        if failWrite { throw CocoaError(.fileWriteUnknown) }
        guard reports.allSatisfy({ network.edge($0.segmentID) != nil }) else { throw CoreError.incompatibleReports }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        let data = try encoder.encode(ReportEnvelope(schema:1,networkID:network.id,networkVersion:network.version,reports:reports))
        _ = try JSONDecoder().decode(ReportEnvelope.self,from:data)
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try data.write(to:url,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
    }
}
