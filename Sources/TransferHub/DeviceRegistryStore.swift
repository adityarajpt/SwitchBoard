import Foundation

struct DeviceRegistryStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "transfer-hub.devices.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [RememberedDevice] {
        guard let data = defaults.data(forKey: key),
              let records = try? JSONDecoder().decode([RememberedDevice].self, from: data) else { return [] }
        return records
    }

    func save(_ records: [RememberedDevice]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: key)
    }
}
