import Foundation

enum SyncMode: String, Codable, CaseIterable, Identifiable {
    case oneWay = "One-way"
    case twoWay = "Two-way"
    var id: String { rawValue }
}

struct SyncRule: Codable, Equatable, Identifiable {
    var id: UUID
    var sourceDeviceID: String
    var destinationDeviceID: String
    var sourceRoot: String
    var destinationRoot: String
    var mode: SyncMode
    var createdAt: Date
    var baseline: [String: SyncBaselineEntry]

    private enum CodingKeys: String, CodingKey {
        case id, sourceDeviceID, destinationDeviceID, sourceRoot, destinationRoot, mode, createdAt, baseline
    }

    init(id: UUID = UUID(), sourceDeviceID: String, destinationDeviceID: String, sourceRoot: String, destinationRoot: String, mode: SyncMode, baseline: [String: SyncBaselineEntry] = [:]) {
        self.id = id
        self.sourceDeviceID = sourceDeviceID
        self.destinationDeviceID = destinationDeviceID
        self.sourceRoot = sourceRoot
        self.destinationRoot = destinationRoot
        self.mode = mode
        self.createdAt = Date()
        self.baseline = baseline
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        sourceDeviceID = try values.decode(String.self, forKey: .sourceDeviceID)
        destinationDeviceID = try values.decode(String.self, forKey: .destinationDeviceID)
        sourceRoot = try values.decode(String.self, forKey: .sourceRoot)
        destinationRoot = try values.decode(String.self, forKey: .destinationRoot)
        mode = try values.decode(SyncMode.self, forKey: .mode)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        baseline = try values.decodeIfPresent([String: SyncBaselineEntry].self, forKey: .baseline) ?? [:]
    }
}

struct SyncManifestEntry: Codable, Equatable, Identifiable {
    var id: String { relativePath }
    var relativePath: String
    var isDirectory: Bool
    var size: Int64
    var modifiedAt: Date?

    func matches(_ other: Self) -> Bool {
        guard isDirectory == other.isDirectory else { return false }
        if isDirectory { return true }
        guard size == other.size else { return false }
        if let modifiedAt, let otherDate = other.modifiedAt {
            return abs(modifiedAt.timeIntervalSince(otherDate)) < 2
        }
        return true
    }
}

struct SyncBaselineEntry: Codable, Equatable {
    var source: SyncManifestEntry?
    var destination: SyncManifestEntry?
}

enum SyncPlanAction: String, Equatable {
    case copyToDestination
    case copyToSource
    case createDestinationFolder
    case createSourceFolder
    case conflict
}

struct SyncPlanEntry: Identifiable, Equatable {
    var id: String { "\(relativePath):\(action.rawValue)" }
    var relativePath: String
    var action: SyncPlanAction
    var reason: String
}

enum SyncPlanner {
    static func compare(source: [SyncManifestEntry], destination: [SyncManifestEntry], mode: SyncMode, baseline: [String: SyncBaselineEntry] = [:]) -> [SyncPlanEntry] {
        let left = Dictionary(uniqueKeysWithValues: source.map { ($0.relativePath, $0) })
        let right = Dictionary(uniqueKeysWithValues: destination.map { ($0.relativePath, $0) })
        let paths = Set(left.keys).union(right.keys).sorted { a, b in
            let leftDirectory = left[a]?.isDirectory ?? right[a]?.isDirectory ?? false
            let rightDirectory = left[b]?.isDirectory ?? right[b]?.isDirectory ?? false
            if leftDirectory != rightDirectory { return leftDirectory }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
        return paths.compactMap { path in
            switch (left[path], right[path]) {
            case let (sourceEntry?, nil):
                if mode == .twoWay, baseline[path] != nil { return nil }
                return SyncPlanEntry(relativePath: path, action: sourceEntry.isDirectory ? .createDestinationFolder : .copyToDestination, reason: "Only on source")
            case let (nil, destinationEntry?):
                guard mode == .twoWay else { return nil }
                if baseline[path] != nil { return nil }
                return SyncPlanEntry(relativePath: path, action: destinationEntry.isDirectory ? .createSourceFolder : .copyToSource, reason: "Only on destination")
            case let (sourceEntry?, destinationEntry?):
                guard !sourceEntry.matches(destinationEntry) else { return nil }
                if sourceEntry.isDirectory != destinationEntry.isDirectory {
                    return SyncPlanEntry(relativePath: path, action: .conflict, reason: "A file and folder use the same path")
                }
                guard !sourceEntry.isDirectory else { return nil }
                guard let previous = baseline[path] else {
                    return mode == .oneWay
                        ? SyncPlanEntry(relativePath: path, action: .copyToDestination, reason: "Source version differs")
                        : SyncPlanEntry(relativePath: path, action: .conflict, reason: "Both sides contain different versions; choose one")
                }
                let sourceChanged = previous.source.map { !$0.matches(sourceEntry) } ?? true
                let destinationChanged = previous.destination.map { !$0.matches(destinationEntry) } ?? true
                if sourceChanged && destinationChanged {
                    return SyncPlanEntry(relativePath: path, action: .conflict, reason: "Both sides changed since the last sync; choose one")
                }
                if sourceChanged { return SyncPlanEntry(relativePath: path, action: .copyToDestination, reason: "Source changed since the last sync") }
                if destinationChanged {
                    return mode == .twoWay
                        ? SyncPlanEntry(relativePath: path, action: .copyToSource, reason: "Destination changed since the last sync")
                        : SyncPlanEntry(relativePath: path, action: .conflict, reason: "Destination changed; review before replacing it")
                }
                return nil
            case (nil, nil): return nil
            }
        }
    }
}

struct SyncRuleStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "transfer-hub.sync-rules.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [SyncRule] {
        guard let data = defaults.data(forKey: key),
              let rules = try? JSONDecoder().decode([SyncRule].self, from: data) else { return [] }
        return rules
    }

    func save(_ rules: [SyncRule]) {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        defaults.set(data, forKey: key)
    }
}
