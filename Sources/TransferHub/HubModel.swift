Warning: truncated output (original token count: 13199)
Total output lines: 979

import AppKit
import Foundation

@MainActor
final class HubModel: ObservableObject {
    @Published var devices: [ConnectedDevice] = []
    @Published var selectedDeviceID: String?
    @Published var files: [PhoneFile] = []
    @Published var currentPath = "/sdcard"
    @Published var transfers: [TransferRecord] = []
    @Published var isScanning = false
    @Published var isLoadingFiles = false
    @Published var errorMessage: String?
    @Published var adbAvailable = false
    @Published var mtpAvailable = false
    @Published var mtpStorages: [MTPStorage] = []
    @Published var selectedStorageID: String?
    @Published var wifiActive = false
    @Published var wifiAddress: String?
    @Published var wifiQRImage: NSImage?
    @Published var selectedTransport = "ADB"
    @Published var previewURL: URL?
    @Published var clipboardNotice: String?
    @Published var rememberedDevices: [RememberedDevice] = []
    @Published var selectedDestinationDeviceID: String?
    @Published var transferSourceDeviceID: String?
    @Published var syncRules: [SyncRule] = []
    @Published var syncPlan: [SyncPlanEntry] = []
    @Published var activeSyncRuleID: UUID?
    @Published var syncConflictChoices: [String: SyncPlanAction] = [:]
    @Published var isSyncing = false
    @Published var syncMessage: String?

    private let adb = ADBClient()
    private let mtp = MTPClient()
    private let wifiPortal = WiFiPortal()
    private let historyStore = TransferHistoryStore()
    private let deviceRegistry = DeviceRegistryStore()
    private let syncRuleStore = SyncRuleStore()
    private var pollTask: Task<Void, Never>?
    private var isTransferRunning = false
    private var hasInitializedTransferEndpoints = false
    private var lastProgressPersistence: [UUID: Date] = [:]

    var selectedDevice: ConnectedDevice? { devices.first(where: { $0.id == selectedDeviceID }) }

    func start() async {
        adbAvailable = adb.isAvailable
        mtpAvailable = mtp.isAvailable
        loadTransfers()
        rememberedDevices = deviceRegistry.load()
        syncRules = syncRuleStore.load()
        wifiPortal.onUploadComplete = { [weak self] upload in
            guard let self else { return }
            guard let id = UUID(uuidString: upload.id) else { return }
            if let index = self.transfers.firstIndex(where: { $0.id == id }) {
                self.transfers[index].state = .complete
                self.transfers[index].localPath = upload.url.path
                self.transfers[index].progress = 1
                self.transfers[index].detail = "Received over local Wi-Fi"
            } else {
                let item = TransferRecord(id: id, name: upload.name, direction: .fromPhone, deviceSerial: "Wi-Fi browser", localPath: upload.url.path, remotePath: upload.name, transport: .wifiBrowser, state: .complete, detail: "Received over local Wi-Fi")
                self.transfers.insert(item, at: 0)
            }
            self.persistTransfers()
        }
        wifiPortal.onUploadProgress = { [weak self] idString, name, completed, total in
            guard let self, let id = UUID(uuidString: idString) else { return }
            if let index = self.transfers.firstIndex(where: { $0.id == id }) {
                let fraction = total > 0 ? min(1, max(0, Double(completed) / Double(total))) : 1
                self.transfers[index].progress = fraction
                self.transfers[index].detail = "\(Int(fraction * 100))% · \(ByteCountFormatter.string(fromByteCount: completed, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
            } else {
                var item = TransferRecord(id: id, name: name, direction: .fromPhone, deviceSerial: "Wi-Fi browser", localPath: "", remotePath: name, transport: .wifiBrowser, state: .running, detail: "Preparing local Wi-Fi transfer")
                item.progress = total > 0 ? Double(completed) / Double(total) : 1
                self.transfers.insert(item, at: 0)
            }
            self.persistTransfers()
        }
        pollTask?.cancel()
        // Let the window appear immediately; device discovery can take several seconds
        // when a USB stack or helper is waking up.
        Task { await refreshDevices(includeMTP: true) }
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled else { break }
                if !isTransferRunning && !isSyncing { await refreshDevices(silent: true, includeMTP: false) }
            }
        }
    }

    func refreshDevices(silent: Bool = false, includeMTP: Bool = false) async {
        if !silent { isScanning = true }
        defer { isScanning = false }
        adbAvailable = adb.isAvailable
        mtpAvailable = mtp.isAvailable
        do {
            let previousSelection = selectedDeviceID
            let previousDevices = devices
            var found = adbAvailable ? try await adb.devices() : []
            if !includeMTP {
                found.append(contentsOf: devices.filter { $0.transport == .mtp })
            }
            if includeMTP, mtpAvailable {
                do {
                    mtpStorages = try await mtp.storages()
                    found.append(ConnectedDevice(serial: "usb-mtp", model: "USB phone (MTP)", state: "device", link: .usb, transport: .mtp))
                    if selectedStorageID == nil || !mtpStorages.contains(where: { $0.id == selectedStorageID }) {
                        selectedStorageID = mtpStorages.first?.id
                    }
                } catch {
                    mtpStorages = []
                    selectedStorageID = nil
                }
            }
            devices = found
            updateRememberedDevices(found, previouslyConnected: Set(previousDevices.map(\.id)))
            if !hasInitializedTransferEndpoints, !devices.isEmpty {
                let ready = devices.filter(\.isAuthorized)
                transferSourceDeviceID = ready.first?.id
                selectedDestinationDeviceID = ready.dropFirst().first?.id
                hasInitializedTransferEndpoints = true
            }
            if selectedDeviceID == nil || !devices.contains(where: { $0.id == selectedDeviceID }) {
                selectedDeviceID = devices.first(where: \.isAuthorized)?.id ?? devices.first?.id
            }
            let changed = previousSelection != selectedDeviceID || previousDevices != devices
            if changed, let selectedDevice {
                currentPath = selectedDevice.transport == .mtp ? "/" : "/sdcard"
                files = []
                let deviceID = selectedDevice.id
                Task { [weak self] in
                    await self?.loadFiles(for: deviceID)
                }
            }
            runQueuedTransfers()
        } catch {
            if !silent { errorMessage = error.localizedDescription }
        }
    }

    private func updateRememberedDevices(_ connected: [ConnectedDevice], previouslyConnected: Set<String>) {
        let now = Date()
        for device in connected {
            if let index = rememberedDevices.firstIndex(where: { $0.id == device.id }) {
                rememberedDevices[index].lastSeenAt = now
                if !previouslyConnected.contains(device.id) { rememberedDevices[index].connectionCount += 1 }
                if rememberedDevices[index].displayName.isEmpty { rememberedDevices[index].displayName = device.model }
            } else {
                rememberedDevices.append(RememberedDevice(id: device.id, displayName: device.model, platform: device.platform, firstSeenAt: now, lastSeenAt: now, connectionCount: 1))
            }
        }
        rememberedDevices.sort { $0.lastSeenAt > $1.lastSeenAt }
        deviceRegistry.save(rememberedDevices)
    }

    func displayName(for deviceID: String) -> String {
        rememberedDevices.first(where: { $0.id == deviceID })?.displayName
            ?? devices.first(where: { $0.id == deviceID })?.model
            ?? "Previously connected device"
    }

    func transferCount(for deviceID: String) -> Int {
        transfers.filter { record in
            "\((record.transport ?? .adb).rawValue)-\(record.deviceSerial)" == deviceID
                || record.destinationTransport.map { "\($0.rawValue)-\(record.destinationDeviceSerial ?? "")" == deviceID } == true
        }.count
    }

    func wasTransferredBefore(_ file: PhoneFile, on device: ConnectedDevice) -> Bool {
        transfers.contains { record in
            guard record.state == .complete, record.deviceSerial == device.serial else { return false }
            switch record.direction {
            case .fromPhone: return record.remotePath == file.path
            case .toPhone: return URL(fileURLWithPath: record.localPath).lastPathComponent == file.name
            case .betweenDevices: return (record.sourcePath ?? record.remotePath) == file.path
            }
        }
    }

    func clearHistory() {
        transfers.removeAll()
        persistTransfers()
    }

    func forgetDevice(_ deviceID: String) {
        rememberedDevices.removeAll { $0.id == deviceID }
        deviceRegistry.save(rememberedDevices)
    }

    func saveSyncRule(sourceDevice: ConnectedDevice, destinationDevice: ConnectedDevice, sourceRoot: String, destinationRoot: String, mode: SyncMode) {
        guard sourceDevice.id != destinationDevice.id else { errorMessage = "A sync rule needs two different devices."; return }
        guard let sourceRoot = normalizedSyncRoot(sourceRoot), let destinationRoot = normalizedSyncRoot(destinationRoot) else {
            errorMessage = "Enter absolute device folders such as /sdcard/Pictures or / for MTP storage. Parent-folder shortcuts are not allowed."
            return
        }
        guard safeSyncRoot(sourceRoot, for: sourceDevice), safeSyncRoot(destinationRoot, for: destinationDevice) else {
            errorMessage = "ADB sync folders must be inside shared storage (/sdcard or /storage/emulated/0). MTP paths are relative to the selected storage."
            return
        }
        let rule = SyncRule(sourceDeviceID: sourceDevice.id, destinationDeviceID: destinationDevice.id, sourceRoot: sourceRoot, destinationRoot: destinationRoot, mode: mode)
        syncRules.insert(rule, at: 0)
        syncRuleStore.save(syncRules)
        activeSyncRuleID = rule.id
        syncPlan = []
        syncMessage = "Saved. Preview the changes before applying them."
    }

    func deleteSyncRule(_ rule: SyncRule) {
        syncRules.removeAll { $0.id == rule.id }
        syncRuleStore.save(syncRules)
        if activeSyncRuleID == rule.id { activeSyncRuleID = nil; syncPlan = [] }
    }

    func previewSync(_ rule: SyncRule) async {
        guard let source = devices.first(where: { $0.id == rule.sourceDeviceID && $0.isAuthorized }),
              let destination = devices.first(where: { $0.id == rule.destinationDeviceID && $0.isAuthorized }) else {
            syncMessage = "Reconnect both devices to preview this rule."
            return
        }
        guard source.id != destination.id else { syncMessage = "This rule points both endpoints at the same device."; return }
        if activeSyncRuleID != rule.id { syncConflictChoices.removeAll() }
        isSyncing = true
        activeSyncRuleID = rule.id
        syncMessage = "Scanning folders…"
        defer { isSyncing = false }
        do {
            async let sourceManifest = scanManifest(device: source, root: rule.sourceRoot)
            async let destinationManifest = scanManifest(device: destination, root: rule.destinationRoot)
            let left = try await sourceManifest
            let right = try await destinationManifest
            syncPlan = SyncPlanner.compare(source: left, destination: right, mode: rule.mode, baseline: rule.baseline)
            let conflicts = Set(syncPlan.filter { $0.action == .conflict }.map(\.relativePath))
            syncConflictChoices = syncConflictChoices.filter { conflicts.contains($0.key) }
            let conflictCount = conflicts.count
            syncMessage = syncPlan.isEmpty
                ? "Everything matches. No changes to apply."
                : "Preview ready · \(syncPlan.count) change\(syncPlan.count == 1 ? "" : "s") · \(conflictCount) conflict\(conflictCount == 1 ? "" : "s") need review"
            if syncPlan.isEmpty { persistBaseline(for: rule, source: left, destination: right, excluding: []) }
        } catch {
            syncPlan = []
            syncMessage = "Could not scan folders: \(error.localizedDescription)"
        }
    }

    func chooseSyncConflict(_ path: String, action: SyncPlanAction?) {
        guard action == .copyToSource || action == .copyToDestination else {
            syncConflictChoices.removeValue(forKey: path)
            return
        }
        syncConflictChoices[path] = action
    }

    func applySyncPlan(_ rule: SyncRule) async {
        guard !isSyncing, !isTransferRunning else { syncMessage = "Finish the active transfer before applying a sync."; return }
        guard let source = devices.first(where: { $0.id == rule.sourceDeviceID && $0.isAuthorized }),
              let destination = devices.first(where: { $0.id == rule.destinationDeviceID && $0.isAuthorized }) else {
            syncMessage = "Reconnect both devices before applying this preview."
            return
        }
        guard activeSyncRuleID == rule.id else { syncMessage = "Preview this rule before applying it."; return }
        isSyncing = true
        syncMessage = "Checking that the preview is still current…"
        defer { isSyncing = false }
        do {
            async let sourceManifest = scanManifest(device: source, root: rule.sourceRoot)
            async let destinationManifest = scanManifest(device: destination, root: rule.destinationRoot)
            let currentSourceManifest = try await sourceManifest
            let currentDestinationManifest = try await destinationManifest
            let currentPlan = SyncPlanner.compare(source: currentSourceManifest, destination: currentDestinationManifest, mode: rule.mode, baseline: rule.baseline)
            guard currentPlan == syncPlan else {
                syncPlan = currentPlan
                syncMessage = "Folder contents changed since preview. Review the refreshed plan before applying."
                return
            }
            let resolvedPlan = currentPlan.map { entry -> SyncPlanEntry in
                guard entry.action == .conflict, let choice = syncConflictChoices[entry.relativePath] else { return entry }
                return SyncPlanEntry(relativePath: entry.relativePath, action: choice, reason: choice == .copyToDestination ? "Conflict resolved: keep source" : "Conflict resolved: keep destination")
            }
            let safeEntries = resolvedPlan.filter { $0.action != .conflict }
            guard !safeEntries.isEmpty else { syncMessage = "There are no safe changes to apply."; return }
            syncMessage = "Applying safe changes…"
            for entry in safeEntries.filter({ $0.action == .createDestinationFolder || $0.action == .createSourceFolder }).sorted(by: {
                $0.relativePath.split(separator: "/").count < $1.relativePath.split(separator: "/").count
            }) {
                let targetDevice = entry.action == .createDestinationFolder ? destination : source
                let root = entry.action == .createDestinationFolder ? rule.destinationRoot : rule.sourceRoot
                try await makeDirectory(on: targetDevice, path: syncPath(root: root, relative: entry.relativePath))
            }
            for entry in safeEntries where entry.action == .copyToDestination || entry.action == .copyToSource {
                let isForward = entry.action == .copyToDestination
                let from = isForward ? source : destination
                let to = isForward ? destination : source
                let fromRoot = isForward ? rule.sourceRoot : rule.destinationRoot
                let toRoot = isForward ? rule.destinationRoot : rule.sourceRoot
                try await syncCopyFile(rule: rule, relativePath: entry.relativePath, from: from, to: to,
                                       sourcePath: syncPath(root: fromRoot, relative: entry.relativePath),
                                       destinationPath: syncPath(root: toRoot, relative: entry.relativePath),
                                       name: URL(fileURLWithPath: entry.relativePath).lastPathComponent)
            }
            syncMessage = "Safe changes applied. Conflicts were left untouched; deletions are never propagated."
            async let updatedSourceManifest = scanManifest(device: source, root: rule.sourceRoot)
            async let updatedDestinationManifest = scanManifest(device: destination, root: rule.destinationRoot)
            let postSource = try await updatedSourceManifest
            let postDestination = try await updatedDestinationManifest
            let unresolved = Set(currentPlan.filter { $0.action == .conflict && syncConflictChoices[$0.relativePath] == nil }.map(\.relativePath))
            persistBaseline(for: rule, source: postSource, destination: postDestination, excluding: unresolved)
            if let updatedRule = syncRules.first(where: { $0.id == rule.id }) { await previewSync(updatedRule) }
        } catch {
            syncMessage = "Sync stopped safely: \(error.localizedDescription)"
        }
    }

    private func normalizedSyncRoot(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/"), !trimmed.isEmpty else { return nil }
        let components = NSString(string: trimmed).pathComponents
        guard !components.contains("..") else { return nil }
        let standardized = NSString(string: trimmed).standardizingPath
        return standardized.isEmpty ? "/" : standardized
    }

    private func safeSyncRoot(_ path: String, for device: ConnectedDevice) -> Bool {
        guard device.transport == .adb else { return true }
        return ["/sdcard", "/storage/emulated/0"].contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    private func persistBaseline(for rule: SyncRule, source: [SyncManifestEntry], destination: [SyncManifestEntry], excluding: Set<String>) {
        guard let index = syncRules.firstIndex(where: { $0.id == rule.id }) else { return }
        let sourceByPath = Dictionary(uniqueKeysWithValues: source.map { ($0.relativePath, $0) })
        let destinationByPath = Dictionary(uniqueKeysWithValues: destination.map { ($0.relativePath, $0) })
        for path in Set(sourceByPath.keys).union(destinationByPath.keys) where !excluding.contains(path) {
            syncRules[index].baseline[path] = SyncBaselineEntry(source: sourceByPath[path], destination: destinationByPath[path])
        }
        let baselinePaths = Array(syncRules[index].baseline.keys)
        for path in baselinePaths where !sourceByPath.keys.contains(path) && !destinationByPath.keys.contains(path) && !excluding.contains(path) {
            syncRules[index].baseline.removeValue(forKey: path)
        }
        syncRuleStore.save(syncRules)
    }

    private func syncPath(root: String, relative: String) -> String {
        root == "/" ? "/\(relative)" : "\(root)/\(relative)"
    }

    private func scanManifest(device: ConnectedDevice, root: String) async throws -> [SyncManifestEntry] {
        var result: [SyncManifestEntry] = []
        var pending = [root]
        var visited = Set<String>()
        while let folder = pending.popLast() {
            guard visited.insert(folder).inserted else { continue }
            for file in try await listRemoteFiles(device, path: folder) {
                let relative = String(file.path.dropFirst(root == "/" ? 1 : root.count + 1))
                guard !relative.isEmpty, !relative.split(separator: "/")…3199 tokens truncated… try await adb.listFiles(serial: destination.serial, path: targetFolder)
            }
            occupied = Set(targetItems.map(\.name))
        } catch {
            errorMessage = "Could not check the destination folder: \(error.localizedDescription)"
            return
        }
        var reservedNames = occupied
        for file in candidates {
            let staged = stagingDirectory.appendingPathComponent("\(UUID().uuidString)-\(file.name)")
            var record = TransferRecord(name: file.name, direction: .betweenDevices, deviceSerial: source.serial, localPath: staged.path, remotePath: file.path, transport: source.transport, storageID: source.transport == .mtp ? selectedStorageID : nil)
            record.sourcePath = file.path
            record.destinationDeviceSerial = destination.serial
            record.destinationTransport = destination.transport
            record.destinationStorageID = targetStorage
            let safeName = uniqueRemoteName(file.name, occupied: reservedNames)
            reservedNames.insert(safeName)
            record.destinationPath = (targetFolder as NSString).appendingPathComponent(safeName)
            record.detail = "Waiting to move through this Mac"
            transfers.insert(record, at: 0)
        }
        selectedDestinationDeviceID = destination.id
        persistTransfers()
        runQueuedTransfers()
    }

    func pasteFromMacClipboard() {
        guard let device = selectedDevice, device.isAuthorized else { errorMessage = "Connect a device before pasting files."; return }
        let objects = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ?? []
        let urls = objects.compactMap { ($0 as? NSURL).map { $0 as URL } }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        let eligible = urls.filter { url in
            var isDirectory = ObjCBool(false)
            _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            return device.transport == .adb || !isDirectory.boolValue
        }
        guard !eligible.isEmpty else { errorMessage = "Copy one or more files in Finder, then choose Paste from Mac."; return }
        for url in eligible {
            let remote = (currentPath as NSString).appendingPathComponent(url.lastPathComponent)
            enqueue(name: url.lastPathComponent, direction: .toPhone, device: device, local: url.path, remote: remote)
        }
        clipboardNotice = "Added \(eligible.count) file\(eligible.count == 1 ? "" : "s") from the Mac clipboard."
        runQueuedTransfers()
    }

    func copyToMacClipboard(_ selectedFiles: [PhoneFile]) async {
        let files = selectedFiles.filter { !$0.isDirectory }
        guard !files.isEmpty, let device = selectedDevice, device.isAuthorized else { return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TransferHubClipboard-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var urls: [URL] = []
            for file in files {
                let url = uniqueLocalURL(in: folder, name: file.name)
                if device.transport == .mtp {
                    guard let selectedStorageID else { throw MTPError.noDevice }
                    try await mtp.download(storageID: selectedStorageID, remotePath: file.path, localPath: url.path)
                } else {
                    try await adb.pull(serial: device.serial, remotePath: file.path, localPath: url.path)
                }
                urls.append(url)
            }
            guard NSPasteboard.general.writeObjects(urls.map { $0 as NSURL }) else { throw CocoaError(.fileWriteUnknown) }
            clipboardNotice = "Copied \(urls.count) file\(urls.count == 1 ? "" : "s") for pasting in Finder."
        } catch {
            try? FileManager.default.removeItem(at: folder)
            errorMessage = "Could not copy files to the Mac clipboard: \(error.localizedDescription)"
        }
    }

    func preview(_ file: PhoneFile) async {
        guard !file.isDirectory, let device = selectedDevice, device.isAuthorized else { return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TransferHubPreview", isDirectory: true)
        let url = folder.appendingPathComponent("\(UUID().uuidString)-\(file.name)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if device.transport == .mtp {
                guard let selectedStorageID else { throw MTPError.noDevice }
                try await mtp.download(storageID: selectedStorageID, remotePath: file.path, localPath: url.path)
            } else {
                try await adb.pull(serial: device.serial, remotePath: file.path, localPath: url.path)
            }
            previewURL = url
        } catch {
            try? FileManager.default.removeItem(at: url)
            errorMessage = "Could not preview \(file.name): \(error.localizedDescription)"
        }
    }

    func copyOnDevice(paths: [String]) async {
        guard let device = selectedDevice, device.isAuthorized, !paths.isEmpty else { return }
        do {
            let currentItems = try await currentDirectoryItems(for: device)
            var occupiedNames = Set(currentItems.map(\.name))
            for source in paths {
                let name = URL(fileURLWithPath: source).lastPathComponent
                guard !name.isEmpty else { continue }
                let destinationName = uniqueRemoteName(name, occupied: occupiedNames)
                occupiedNames.insert(destinationName)
                let destination = (currentPath as NSString).appendingPathComponent(destinationName)
                if device.transport == .mtp {
                    guard let selectedStorageID else { throw MTPError.noDevice }
                    let tempFolder = FileManager.default.temporaryDirectory.appendingPathComponent("TransferHubCopy-\(UUID().uuidString)", isDirectory: true)
                    let tempURL = tempFolder.appendingPathComponent(destinationName)
                    do {
                        try FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
                        try await mtp.download(storageID: selectedStorageID, remotePath: source, localPath: tempURL.path)
                        try await mtp.upload(storageID: selectedStorageID, localPath: tempURL.path, remoteDirectory: currentPath)
                        try? FileManager.default.removeItem(at: tempFolder)
                    } catch {
                        try? FileManager.default.removeItem(at: tempFolder)
                        throw error
                    }
                } else {
                    try await adb.copyRemoteFile(serial: device.serial, source: source, destination: destination)
                }
            }
            await loadFiles()
        } catch {
            await loadFiles()
            errorMessage = "Could not paste files here: \(error.localizedDescription)"
        }
    }

    private func currentDirectoryItems(for device: ConnectedDevice) async throws -> [PhoneFile] {
        if device.transport == .mtp {
            guard let selectedStorageID else { throw MTPError.noDevice }
            return try await mtp.listFiles(storageID: selectedStorageID, path: currentPath)
        }
        return try await adb.listFiles(serial: device.serial, path: currentPath)
    }

    private func uniqueRemoteName(_ name: String, occupied: Set<String>) -> String {
        guard occupied.contains(name) else { return name }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var suffix = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) copy \(suffix)" : "\(base) copy \(suffix).\(ext)"
            if !occupied.contains(candidate) { return candidate }
            suffix += 1
        }
    }

    private func uniqueLocalURL(in folder: URL, name: String) -> URL {
        let first = folder.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: first.path) else { return first }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var suffix = 2
        while true {
            let candidateName = ext.isEmpty ? "\(base) \(suffix)" : "\(base) \(suffix).\(ext)"
            let candidate = folder.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            suffix += 1
        }
    }

    func retry(_ record: TransferRecord) {
        guard let index = transfers.firstIndex(where: { $0.id == record.id }) else { return }
        transfers[index].state = .queued
        transfers[index].detail = "Retrying current file"
        if transfers[index].transport == .mtp { transfers[index].progress = nil }
        persistTransfers()
        runQueuedTransfers()
    }

    func dismissError() { errorMessage = nil }

    func locateADB() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use adb"
        panel.message = "Choose adb from the Android SDK Platform-Tools folder."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try adb.setExecutable(url)
            adbAvailable = true
            Task { await refreshDevices() }
        } catch { errorMessage = error.localizedDescription }
    }

    func openADBDownloadPage() {
        NSWorkspace.shared.open(URL(string: "https://developer.android.com/tools/releases/platform-tools")!)
    }

    private func enqueue(name: String, direction: TransferDirection, device: ConnectedDevice, local: String, remote: String) {
        transfers.insert(TransferRecord(name: name, direction: direction, deviceSerial: device.serial, localPath: local, remotePath: remote, transport: device.transport, storageID: device.transport == .mtp ? selectedStorageID : nil), at: 0)
        persistTransfers()
    }

    private func runQueuedTransfers() {
        guard !isTransferRunning, !isSyncing else { return }
        guard let index = transfers.lastIndex(where: { $0.state == .queued }) else { return }
        let candidate = transfers[index]
        let deviceIsReady: Bool
        switch candidate.transport ?? .adb {
        case .mtp:
            deviceIsReady = mtpAvailable && devices.contains(where: { $0.transport == .mtp }) && candidate.storageID.map { id in mtpStorages.contains(where: { $0.id == id }) } == true
        case .adb:
            deviceIsReady = adbAvailable && devices.contains(where: { $0.serial == candidate.deviceSerial && $0.transport == .adb && $0.isAuthorized })
        case .wifiBrowser:
            deviceIsReady = false
        }
        let destinationIsReady: Bool
        if candidate.direction == .betweenDevices {
            switch candidate.destinationTransport ?? .adb {
            case .mtp:
                destinationIsReady = mtpAvailable && devices.contains(where: { $0.transport == .mtp }) && candidate.destinationStorageID.map { id in mtpStorages.contains(where: { $0.id == id }) } == true
            case .adb:
                destinationIsReady = adbAvailable && devices.contains(where: { $0.serial == candidate.destinationDeviceSerial && $0.transport == .adb && $0.isAuthorized })
            case .wifiBrowser:
                destinationIsReady = false
            }
        } else { destinationIsReady = true }
        guard deviceIsReady, destinationIsReady else { return }
        isTransferRunning = true
        let id = transfers[index].id
        transfers[index].state = .running
        transfers[index].detail = "Connecting to device"
        persistTransfers()
        let job = transfers[index]
        Task {
            do {
                if job.direction == .betweenDevices {
                    try await transferBetweenDevices(job, id: id)
                    if job.syncRuleID != nil { await refreshSyncBaseline(for: job) }
                } else if job.transport == .mtp {
                    guard let storageID = job.storageID else { throw MTPError.noDevice }
                    let progress: @Sendable (MTPProgress) -> Void = { [weak self] value in
                        Task { @MainActor in
                            self?.setProgress(id: id, completed: value.bytesCopied, total: value.totalBytes)
                        }
                    }
                    if job.direction == .toPhone {
                        try await mtp.upload(storageID: storageID, localPath: job.localPath, remoteDirectory: (job.remotePath as NSString).deletingLastPathComponent, progress: progress)
                    } else {
                        try await mtp.download(storageID: storageID, remotePath: job.remotePath, localPath: job.localPath, progress: progress)
                    }
                } else if job.direction == .toPhone {
                    let progress: @Sendable (Int64, Int64) -> Void = { [weak self] completed, total in
                        Task { @MainActor in self?.setProgress(id: id, completed: completed, total: total) }
                    }
                    try await adb.pushResumable(serial: job.deviceSerial, localPath: job.localPath, remotePath: job.remotePath, jobID: id.uuidString, progress: progress)
                } else {
                    let progress: @Sendable (Int64, Int64) -> Void = { [weak self] completed, total in
                        Task { @MainActor in self?.setProgress(id: id, completed: completed, total: total) }
                    }
                    try await adb.pullResumable(serial: job.deviceSerial, remotePath: job.remotePath, localPath: job.localPath, jobID: id.uuidString, progress: progress)
                }
                update(id: id, state: .complete, detail: "Transferred successfully")
                await loadFiles()
            } catch {
                update(id: id, state: .failed, detail: error.localizedDescription)
            }
            isTransferRunning = false
            runQueuedTransfers()
        }
    }

    private func refreshSyncBaseline(for job: TransferRecord) async {
        guard let ruleID = job.syncRuleID, let relativePath = job.syncRelativePath,
              let ruleIndex = syncRules.firstIndex(where: { $0.id == ruleID }),
              let sourceDevice = devices.first(where: { $0.id == syncRules[ruleIndex].sourceDeviceID }),
              let destinationDevice = devices.first(where: { $0.id == syncRules[ruleIndex].destinationDeviceID }) else { return }
        let rule = syncRules[ruleIndex]
        do {
            async let sourceScan = scanManifest(device: sourceDevice, root: rule.sourceRoot)
            async let destinationScan = scanManifest(device: destinationDevice, root: rule.destinationRoot)
            let sourceManifest = try await sourceScan
            let destinationManifest = try await destinationScan
            let source = sourceManifest.first(where: { $0.relativePath == relativePath })
            let destination = destinationManifest.first(where: { $0.relativePath == relativePath })
            if source == nil && destination == nil { syncRules[ruleIndex].baseline.removeValue(forKey: relativePath) }
            else { syncRules[ruleIndex].baseline[relativePath] = SyncBaselineEntry(source: source, destination: destination) }
            syncRuleStore.save(syncRules)
        } catch {
            // Keep the previous baseline if metadata could not be refreshed; the next preview will surface any divergence.
        }
    }

    private func transferBetweenDevices(_ job: TransferRecord, id: UUID) async throws {
        guard let sourcePath = job.sourcePath,
              let destinationSerial = job.destinationDeviceSerial,
              let destinationPath = job.destinationPath,
              let destinationTransport = job.destinationTransport else {
            throw MTPError.command("This transfer is missing an endpoint. Remove it and add it again.")
        }
        let stagedURL = URL(fileURLWithPath: job.localPath)
        if !FileManager.default.fileExists(atPath: stagedURL.path) {
            let partialURL = stagedURL.appendingPathExtension("partial")
            setDetail(id: id, detail: "Copying from \(displayName(for: job.deviceSerial)) to this Mac")
            if job.transport == .mtp {
                guard let storage = job.storageID else { throw MTPError.noDevice }
                try? FileManager.default.removeItem(at: partialURL)
                try await mtp.download(storageID: storage, remotePath: sourcePath, localPath: partialURL.path) { [weak self] value in
                    Task { @MainActor in self?.setProgress(id: id, completed: value.bytesCopied, total: value.totalBytes) }
                }
            } else {
                try await adb.pullResumable(serial: job.deviceSerial, remotePath: sourcePath, localPath: partialURL.path, jobID: id.uuidString) { [weak self] completed, total in
                    Task { @MainActor in self?.setProgress(id: id, completed: completed, total: total) }
                }
            }
            try FileManager.default.moveItem(at: partialURL, to: stagedURL)
        }
        setDetail(id: id, detail: "Sending to \(displayName(for: "\(destinationTransport.rawValue)-\(destinationSerial)"))")
        if destinationTransport == .mtp {
            guard let storage = job.destinationStorageID else { throw MTPError.noDevice }
            let folder = (destinationPath as NSString).deletingLastPathComponent
            try await mtp.upload(storageID: storage, localPath: stagedURL.path, remoteDirectory: folder) { [weak self] value in
                Task { @MainActor in self?.setProgress(id: id, completed: value.bytesCopied, total: value.totalBytes) }
            }
        } else {
            try await adb.pushResumable(serial: destinationSerial, localPath: stagedURL.path, remotePath: destinationPath, jobID: id.uuidString) { [weak self] completed, total in
                Task { @MainActor in self?.setProgress(id: id, completed: completed, total: total) }
            }
        }
    }

    private func update(id: UUID, state: TransferState, detail: String) {
        guard let index = transfers.firstIndex(where: { $0.id == id }) else { return }
        transfers[index].state = state
        transfers[index].detail = detail
        if state == .complete { transfers[index].progress = 1 }
        lastProgressPersistence.removeValue(forKey: id)
        persistTransfers()
    }

    private func setDetail(id: UUID, detail: String) {
        guard let index = transfers.firstIndex(where: { $0.id == id }), transfers[index].state == .running else { return }
        transfers[index].detail = detail
    }

    private func setProgress(id: UUID, completed: Int64, total: Int64) {
        guard let index = transfers.firstIndex(where: { $0.id == id }), transfers[index].state == .running else { return }
        let fraction = total > 0 ? min(1, max(0, Double(completed) / Double(total))) : 1
        transfers[index].progress = fraction
        transfers[index].detail = "\(Int(fraction * 100))% · \(ByteCountFormatter.string(fromByteCount: completed, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
        let now = Date()
        if now.timeIntervalSince(lastProgressPersistence[id] ?? .distantPast) >= 1 {
            lastProgressPersistence[id] = now
            persistTransfers()
        }
    }

    private func loadTransfers() {
        transfers = historyStore.load()
    }

    private func persistTransfers() {
        historyStore.save(transfers)
    }
}
