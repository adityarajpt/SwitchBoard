import XCTest
@testable import TransferHub

final class TransferHistoryStoreTests: XCTestCase {
    func testCompletedTransferSurvivesReload() throws {
        let suite = "TransferHubTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TransferHistoryStore(defaults: defaults)
        let record = TransferRecord(name: "photo.jpg", direction: .fromPhone, deviceSerial: "phone", localPath: "/tmp/photo.jpg", remotePath: "/DCIM/photo.jpg", state: .complete, detail: "Transferred successfully")

        store.save([record])
        let loaded = store.load()

        XCTAssertEqual(loaded, [record])
    }

    func testInterruptedTransferIsRecoveredAndPersistedAsNeedsAttention() throws {
        let suite = "TransferHubTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TransferHistoryStore(defaults: defaults)
        let record = TransferRecord(name: "archive.zip", direction: .toPhone, deviceSerial: "phone", localPath: "/tmp/archive.zip", remotePath: "/sdcard/archive.zip", state: .running, detail: "40%")
        store.save([record])

        let recovered = try XCTUnwrap(store.load().first)
        XCTAssertEqual(recovered.state, .failed)
        XCTAssertTrue(recovered.detail.contains("App closed"))
        XCTAssertEqual(store.load().first, recovered)
    }

    func testLegacyTransferRecordWithoutPairFieldsStillLoads() throws {
        let record = TransferRecord(name: "photo.jpg", direction: .fromPhone, deviceSerial: "phone", localPath: "/tmp/photo.jpg", remotePath: "/DCIM/photo.jpg")
        let encoded = try JSONEncoder().encode(record)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for key in ["sourcePath", "destinationDeviceSerial", "destinationTransport", "destinationStorageID", "destinationPath", "syncRuleID", "syncRelativePath"] {
            object.removeValue(forKey: key)
        }
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(TransferRecord.self, from: legacyData)
        XCTAssertEqual(decoded.name, record.name)
        XCTAssertEqual(decoded.destinationPath, nil)
    }

    func testRememberedDeviceIdentitySurvivesReload() throws {
        let suite = "TransferHubTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DeviceRegistryStore(defaults: defaults)
        let now = Date()
        let device = RememberedDevice(id: "adb-serial-1", displayName: "Pixel", platform: .android, firstSeenAt: now, lastSeenAt: now, connectionCount: 2)

        store.save([device])

        XCTAssertEqual(store.load(), [device])
    }

    func testOneWaySyncKeepsDestinationOnlyFilesAndPlansFoldersFirst() {
        let source = [
            SyncManifestEntry(relativePath: "Photos", isDirectory: true, size: 0),
            SyncManifestEntry(relativePath: "Photos/a.jpg", isDirectory: false, size: 10)
        ]
        let destination = [SyncManifestEntry(relativePath: "keep.txt", isDirectory: false, size: 4)]

        let plan = SyncPlanner.compare(source: source, destination: destination, mode: .oneWay)

        XCTAssertEqual(plan.map(\.action), [.createDestinationFolder, .copyToDestination])
        XCTAssertFalse(plan.contains(where: { $0.relativePath == "keep.txt" }))
    }

    func testTwoWaySyncFlagsDifferingFileAsConflictAndCopiesNewFiles() {
        let source = [
            SyncManifestEntry(relativePath: "same-name.txt", isDirectory: false, size: 10),
            SyncManifestEntry(relativePath: "new-on-source.txt", isDirectory: false, size: 8)
        ]
        let destination = [
            SyncManifestEntry(relativePath: "same-name.txt", isDirectory: false, size: 11),
            SyncManifestEntry(relativePath: "new-on-destination.txt", isDirectory: false, size: 5)
        ]

        let plan = SyncPlanner.compare(source: source, destination: destination, mode: .twoWay)

        XCTAssertEqual(Set(plan.map(\.relativePath)), ["same-name.txt", "new-on-source.txt", "new-on-destination.txt"])
        XCTAssertEqual(plan.first(where: { $0.relativePath == "same-name.txt" })?.action, .conflict)
        XCTAssertEqual(plan.first(where: { $0.relativePath == "new-on-source.txt" })?.action, .copyToDestination)
        XCTAssertEqual(plan.first(where: { $0.relativePath == "new-on-destination.txt" })?.action, .copyToSource)
    }

    func testSyncRulesPersistAcrossReload() throws {
        let suite = "TransferHubTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SyncRuleStore(defaults: defaults)
        let rule = SyncRule(sourceDeviceID: "adb-a", destinationDeviceID: "adb-b", sourceRoot: "/sdcard/Pictures", destinationRoot: "/sdcard/Photos", mode: .twoWay)

        store.save([rule])

        XCTAssertEqual(store.load(), [rule])
    }

    func testSyncBaselinePreventsRepeatedUpdatesWhenDeviceTimestampsDiffer() {
        let sourceBase = SyncManifestEntry(relativePath: "photo.jpg", isDirectory: false, size: 10, modifiedAt: Date(timeIntervalSince1970: 100))
        let destinationBase = SyncManifestEntry(relativePath: "photo.jpg", isDirectory: false, size: 10, modifiedAt: Date(timeIntervalSince1970: 110))
        let baseline = ["photo.jpg": SyncBaselineEntry(source: sourceBase, destination: destinationBase)]

        let plan = SyncPlanner.compare(source: [sourceBase], destination: [destinationBase], mode: .oneWay, baseline: baseline)

        XCTAssertTrue(plan.isEmpty)
    }

    func testSyncBaselineRoutesSingleSideEditAndFlagsConcurrentEdits() {
        let oldSource = SyncManifestEntry(relativePath: "doc.txt", isDirectory: false, size: 10, modifiedAt: Date(timeIntervalSince1970: 100))
        let oldDestination = SyncManifestEntry(relativePath: "doc.txt", isDirectory: false, size: 10, modifiedAt: Date(timeIntervalSince1970: 100))
        let sourceEdit = SyncManifestEntry(relativePath: "doc.txt", isDirectory: false, size: 11, modifiedAt: Date(timeIntervalSince1970: 120))
        let destinationEdit = SyncManifestEntry(relativePath: "doc.txt", isDirectory: false, size: 12, modifiedAt: Date(timeIntervalSince1970: 130))
        let baseline = ["doc.txt": SyncBaselineEntry(source: oldSource, destination: oldDestination)]

        let singleEdit = SyncPlanner.compare(source: [sourceEdit], destination: [oldDestination], mode: .twoWay, baseline: baseline)
        let simultaneousEdits = SyncPlanner.compare(source: [sourceEdit], destination: [destinationEdit], mode: .twoWay, baseline: baseline)

        XCTAssertEqual(singleEdit.first?.action, .copyToDestination)
        XCTAssertEqual(simultaneousEdits.first?.action, .conflict)
    }

    func testTwoWaySyncDoesNotRecreateFilesDeletedOnOneSide() {
        let source = [SyncManifestEntry(relativePath: "kept-on-source.txt", isDirectory: false, size: 2)]
        let destination = [SyncManifestEntry(relativePath: "kept-on-destination.txt", isDirectory: false, size: 3)]
        let baseline = [
            "kept-on-source.txt": SyncBaselineEntry(source: source[0], destination: nil),
            "kept-on-destination.txt": SyncBaselineEntry(source: nil, destination: destination[0])
        ]

        let plan = SyncPlanner.compare(source: source, destination: destination, mode: .twoWay, baseline: baseline)

        XCTAssertTrue(plan.isEmpty)
    }
}
