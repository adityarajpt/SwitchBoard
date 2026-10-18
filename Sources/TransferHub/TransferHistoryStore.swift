import Foundation

struct TransferHistoryStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "transfer-hub.transfers.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [TransferRecord] {
        guard let data = defaults.data(forKey: key),
              let saved = try? JSONDecoder().decode([TransferRecord].self, from: data) else { return [] }
        let recovered = saved.map { item -> TransferRecord in
            var record = item
            if record.state == .running {
                record.state = .failed
                record.detail = "App closed during transfer. Retry to continue the queue."
            }
            return record
        }
        if recovered != saved { save(recovered) }
        return recovered
    }

    func save(_ transfers: [TransferRecord]) {
        guard let data = try? JSONEncoder().encode(transfers) else { return }
        defaults.set(data, forKey: key)
    }
}
