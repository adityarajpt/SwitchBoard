import Foundation

enum LinkKind: String, Codable, CaseIterable, Identifiable {
    case usb = "USB"
    case wifi = "Wi-Fi"
    var id: String { rawValue }
}

enum DeviceTransport: String, Codable {
    case adb
    case mtp
    case wifiBrowser
}

enum DevicePlatform: String, Codable {
    case android
    case ios
    case unknown
}

struct MTPStorage: Identifiable, Equatable {
    let id: String
    let name: String
}

struct ConnectedDevice: Identifiable, Codable, Equatable {
    var id: String { "\(transport.rawValue)-\(serial)" }
    let serial: String
    let model: String
    let state: String
    let link: LinkKind
    var transport: DeviceTransport
    let platform: DevicePlatform
    var isAuthorized: Bool { state == "device" || transport == .mtp }

    init(serial: String, model: String, state: String, link: LinkKind, transport: DeviceTransport, platform: DevicePlatform = .android) {
        self.serial = serial
        self.model = model
        self.state = state
        self.link = link
        self.transport = transport
        self.platform = platform
    }
}

struct PhoneFile: Identifiable, Equatable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64?
    var modifiedAt: Date? = nil
}

enum TransferDirection: String, Codable {
    case toPhone
    case fromPhone
    case betweenDevices
}

enum TransferState: String, Codable {
    case queued = "Queued"
    case running = "Transferring"
    case complete = "Complete"
    case failed = "Needs attention"
}

struct TransferRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let direction: TransferDirection
    let deviceSerial: String
    var localPath: String
    let remotePath: String
    var transport: DeviceTransport?
    var storageID: String?
    let createdAt: Date
    var state: TransferState
    var detail: String
    var progress: Double?
    var sourcePath: String?
    var destinationDeviceSerial: String?
    var destinationTransport: DeviceTransport?
    var destinationStorageID: String?
    var destinationPath: String?
    var syncRuleID: UUID?
    var syncRelativePath: String?

    init(id: UUID = UUID(), name: String, direction: TransferDirection, deviceSerial: String, localPath: String, remotePath: String, transport: DeviceTransport = .adb, storageID: String? = nil, state: TransferState = .queued, detail: String = "Waiting") {
        self.id = id
        self.name = name
        self.direction = direction
        self.deviceSerial = deviceSerial
        self.localPath = localPath
        self.remotePath = remotePath
        self.transport = transport
        self.storageID = storageID
        self.createdAt = Date()
        self.state = state
        self.detail = detail
        self.progress = nil
        self.sourcePath = nil
        self.destinationDeviceSerial = nil
        self.destinationTransport = nil
        self.destinationStorageID = nil
        self.destinationPath = nil
        self.syncRuleID = nil
        self.syncRelativePath = nil
    }
}

struct RememberedDevice: Codable, Equatable, Identifiable {
    var id: String
    var displayName: String
    var platform: DevicePlatform
    var firstSeenAt: Date
    var lastSeenAt: Date
    var connectionCount: Int
}
