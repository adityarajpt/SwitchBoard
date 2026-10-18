import SwiftUI
import QuickLook

@MainActor
private enum HubPalette {
    static var isLight: Bool {
        let preference = UserDefaults.standard.string(forKey: "transfer-hub.theme") ?? "Automatic"
        if preference == "Light" { return true }
        if preference == "Dark" { return false }
        return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .aqua
    }
    static var background: Color { isLight ? Color(red: 0.95, green: 0.96, blue: 0.94) : Color(red: 0.055, green: 0.067, blue: 0.086) }
    static var panel: Color { isLight ? .white : Color(red: 0.083, green: 0.098, blue: 0.122) }
    static var panelRaised: Color { isLight ? Color(red: 0.91, green: 0.93, blue: 0.90) : Color(red: 0.11, green: 0.13, blue: 0.16) }
    static var line: Color { isLight ? Color.black.opacity(0.09) : Color.white.opacity(0.075) }
    static var text: Color { isLight ? Color(red: 0.12, green: 0.15, blue: 0.13) : .white }
    static var muted: Color { isLight ? Color(red: 0.35, green: 0.40, blue: 0.38) : Color(red: 0.59, green: 0.63, blue: 0.69) }
    static let lime = Color(red: 0.72, green: 0.91, blue: 0.42)
}

struct HubView: View {
    @EnvironmentObject private var model: HubModel
    @State private var selection: String = "device"
    @State private var showWiFiInfo = false
    @State private var showAdvancedConnections = false
    @State private var selectedFileIDs = Set<String>()
    @State private var copiedFilePaths: [String] = []
    @State private var copiedDeviceID: String?
    @State private var copiedStorageID: String?
    @State private var searchText = ""
    @State private var transferFilter = "All"
    @State private var showClearHistoryConfirmation = false
    @State private var sourceSyncRoot = "/sdcard/Pictures"
    @State private var destinationSyncRoot = "/sdcard/Pictures"
    @State private var syncMode = SyncMode.oneWay
    @State private var showSyncApplyConfirmation = false
    @AppStorage("transfer-hub.theme") private var theme = "Automatic"

    private var sourceDevice: ConnectedDevice? { model.devices.first(where: { $0.id == model.transferSourceDeviceID }) }
    private var destinationDevice: ConnectedDevice? { model.devices.first(where: { $0.id == model.selectedDestinationDeviceID }) }

    private var visibleFiles: [PhoneFile] {
        guard !searchText.isEmpty else { return model.files }
        return model.files.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var selectedFiles: [PhoneFile] {
        visibleFiles.filter { selectedFileIDs.contains($0.id) && !$0.isDirectory }
    }

    private var filteredTransfers: [TransferRecord] {
        switch transferFilter {
        case "Active": model.transfers.filter { $0.state == .queued || $0.state == .running }
        case "Needs attention": model.transfers.filter { $0.state == .failed }
        case "Completed": model.transfers.filter { $0.state == .complete }
        default: model.transfers
        }
    }

    private var connectionStatusTitle: String {
        if let device = model.selectedDevice { return "\(device.model.uppercased()) CONNECTED" }
        return model.mtpAvailable || model.adbAvailable ? "READY TO CONNECT" : "CONNECTION SETUP"
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            mainContent
        }
        .background(HubPalette.background)
        .foregroundStyle(HubPalette.text)
        .preferredColorScheme(theme == "Light" ? .light : theme == "Dark" ? .dark : nil)
        .animation(.snappy(duration: 0.22), value: selection)
        .animation(.snappy(duration: 0.22), value: theme)
        .alert("Transfer Hub", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.dismissError() } })) {
            Button("OK", role: .cancel) { model.dismissError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .confirmationDialog("Clear transfer history?", isPresented: $showClearHistoryConfirmation, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) { model.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes transfer logs from this Mac. It does not remove files from either device.")
        }
        .confirmationDialog("Apply these sync changes?", isPresented: $showSyncApplyConfirmation, titleVisibility: .visible) {
            Button("Apply safe changes", role: .destructive) {
                if let rule = model.syncRules.first(where: { $0.id == model.activeSyncRuleID }) {
                    Task { await model.applySyncPlan(rule) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("One-way updates and chosen conflict resolutions can replace the other copy. Unresolved conflicts are skipped. Nothing is deleted.")
        }
        .sheet(isPresented: $showWiFiInfo) { wifiSheet }
        .quickLookPreview($model.previewURL)
        .onChange(of: model.currentPath) { _, _ in
            selectedFileIDs.removeAll()
            searchText = ""
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(HubPalette.lime).frame(width: 34, height: 34)
                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 15, weight: .bold)).foregroundStyle(HubPalette.background)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("SWITCHBOARD").font(.system(size: 12, weight: .black, design: .rounded)).tracking(1.3)
                    Text("Transfer Hub").font(.system(size: 11)).foregroundStyle(HubPalette.muted)
                }
            }.padding(.horizontal, 22).padding(.top, 25).padding(.bottom, 32)

            sideLabel("WORKSPACE")
            sidebarItem("Transfer", icon: "arrow.left.arrow.right", id: "transfer")
            sidebarItem("Sync", icon: "arrow.triangle.2.circlepath", id: "sync")
            sidebarItem("Devices", icon: "cable.connector", id: "device")
            sidebarItem("Activity", icon: "clock.arrow.circlepath", id: "transfers", badge: model.transfers.filter { $0.state == .queued || $0.state == .running }.count)
            sidebarItem("Shared", icon: "qrcode", id: "shared")

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle().fill(model.selectedDevice == nil && !model.mtpAvailable && !model.adbAvailable ? Color.orange : HubPalette.lime).frame(width: 7, height: 7)
                    Text(connectionStatusTitle).font(.system(size: 9, weight: .bold)).tracking(0.5).lineLimit(1)
                }
                Text(model.selectedDevice == nil ? "Your files stay on your devices and this Mac." : "Connected and ready to browse files.")
                    .font(.system(size: 11)).foregroundStyle(HubPalette.muted).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(HubPalette.panel, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 15).padding(.bottom, 17)
        }
        .frame(width: 232)
        .background(HubPalette.panel.opacity(0.72))
        .overlay(alignment: .trailing) { Rectangle().fill(HubPalette.line).frame(width: 1) }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            topBar
            Group {
                switch selection {
                case "transfer": transferSetupPage
                case "sync": syncPage
                case "transfers": transfersPage
                case "shared": sharedPage
                default: devicePage
                }
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(selection == "transfer" ? "Move between devices" : selection == "sync" ? "Folder sync" : selection == "transfers" ? "Activity" : selection == "shared" ? "Share between devices" : "Devices")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text(selection == "transfer" ? "Choose a source and destination. We’ll keep each device’s activity separate." : selection == "sync" ? "Save a folder rule, preview its changes, then apply them deliberately." : selection == "transfers" ? "A durable record of transfers, retries, and reconnects" : selection == "shared" ? "Use a browser to move files without installing a phone app" : "Connect a device, then choose what to move")
                    .font(.system(size: 12)).foregroundStyle(HubPalette.muted)
            }
            Spacer()
            Menu {
                Picker("Appearance", selection: $theme) {
                    Text("Automatic").tag("Automatic")
                    Text("Dark").tag("Dark")
                    Text("Light").tag("Light")
                }
            } label: {
                Image(systemName: theme == "Dark" ? "moon.stars" : theme == "Light" ? "sun.max" : "circle.lefthalf.filled")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(HubPalette.panelRaised, in: RoundedRectangle(cornerRadius: 9))
            }.menuStyle(.borderlessButton).help("Choose appearance")
            Button { Task { await model.refreshDevices() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold))
                    Text(model.isScanning ? "Scanning" : "Refresh")
                }.font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 13).padding(.vertical, 9)
                    .background(HubPalette.panelRaised, in: RoundedRectangle(cornerRadius: 9))
            }.buttonStyle(.plain).disabled(model.isScanning)
            Circle().fill(HubPalette.lime).frame(width: 8, height: 8).padding(.leading, 9)
            Text("ON THIS MAC").font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(HubPalette.muted)
        }
        .padding(.horizontal, 29).padding(.top, 24).padding(.bottom, 22)
        .overlay(alignment: .bottom) { Rectangle().fill(HubPalette.line).frame(height: 1) }
    }

    private var devicePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let device = model.selectedDevice, device.isAuthorized {
                    deviceHeader
                    transportSection
                    browserSection(device)
                    recentTransfers
                    rememberedDevicesSection
                } else if model.selectedDevice != nil {
                    deviceHeader
                    authorizationNotice
                    transportSection
                } else {
                    emptyDeviceState
                    transportSection
                }
            }.padding(28)
        }
    }

    private var transferSetupPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(HubPalette.lime)
                    Text(model.devices.count == 2 ? "Two devices found — ready to choose what moves." : model.devices.count > 2 ? "Several devices are connected. Pick the two you mean." : "Connect two devices, or choose one and use this Mac as the other side.")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(HubPalette.text.opacity(0.9))
                    Spacer()
                }.padding(14).background(HubPalette.lime.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                HStack(alignment: .center, spacing: 14) {
                    endpointCard(title: "FROM", device: sourceDevice, isSource: true)
                    Image(systemName: "arrow.right").font(.system(size: 16, weight: .bold)).foregroundStyle(HubPalette.lime)
                    endpointCard(title: "TO", device: destinationDevice, isSource: false)
                }
                HStack(spacing: 10) {
                    if let sourceDevice {
                        Button {
                            Task { await model.selectDevice(sourceDevice); selection = "device" }
                        } label: {
                            Label("Browse source files", systemImage: "folder").font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 14).padding(.vertical, 10).background(HubPalette.lime, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(HubPalette.background)
                        }.buttonStyle(.plain)
                    } else if let destinationDevice {
                        Button { Task { await model.sendMacFiles(to: destinationDevice) } } label: {
                            Label("Choose files on this Mac", systemImage: "folder.badge.plus").font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 14).padding(.vertical, 10).background(HubPalette.lime, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(HubPalette.background)
                        }.buttonStyle(.plain)
                    }
                    Text(sourceDevice == nil
                         ? "Choose files from this Mac to send to the selected device."
                         : "Select files in the browser, then choose “Send to destination”. Device-to-device transfers stage through this Mac so they can be retried if a connection drops.")
                        .font(.system(size: 10)).foregroundStyle(HubPalette.muted).fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("REMEMBERED DEVICES").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(HubPalette.muted)
                        Spacer()
                        Text("Identity and activity stay on this Mac").font(.system(size: 10)).foregroundStyle(HubPalette.muted)
                    }
                    if model.rememberedDevices.isEmpty {
                        Text("Connected devices appear here with their own history.").font(.system(size: 11)).foregroundStyle(HubPalette.muted).padding(.vertical, 10)
                    } else {
                        ForEach(model.rememberedDevices) { remembered in rememberedDeviceRow(remembered) }
                    }
                }.padding(16).background(HubPalette.panel, in: RoundedRectangle(cornerRadius: 12))
            }.padding(28)
        }
    }

    private var syncPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Preview first. Nothing syncs in the background.", systemImage: "hand.raised.square")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(HubPalette.lime)
                    Text("Folder rules are saved on this Mac. Deletions are never propagated. One-way updates follow the source; two-way sync copies new files and flags differing versions as conflicts.")
                        .font(.system(size: 11)).foregroundStyle(HubPalette.muted).fixedSize(horizontal: false, vertical: true)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(HubPalette.panel, in: RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 13) {
                    Text("NEW FOLDER RULE").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(HubPalette.muted)
                    HStack(spacing: 12) {
                        endpointCard(title: "SOURCE DEVICE", device: sourceDevice, isSource: true)
                        Image(systemName: "arrow.right").foregroundStyle(HubPalette.lime)
                        endpointCard(title: "DESTINATION DEVICE", device: destinationDevice, isSource: false)
                    }
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SOURCE FOLDER").font(.system(size: 9, weight: .bold)).tracking(0.7).foregroundStyle(HubPalette.muted)
                            TextField("/sdcard/Pictures", text: $sourceSyncRoot).textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced))
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("DESTINATION FOLDER").font(.system(size: 9, weight: .bold)).tracking(0.7).foregroundStyle(HubPalette.muted)
                            TextField("/sdcard/Pictures", text: $destinationSyncRoot).textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced))
                        }
                    }
                    HStack {
                        Picker("Policy", selection: $syncMode) {
                            ForEach(SyncMode.allCases) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented).frame(maxWidth: 250)
                        Text(syncMode == .oneWay ? "Source is authoritative; destination-only files are kept." : "New files copy both ways; different versions are conflicts.")
                            .font(.system(size: 10)).foregroundStyle(HubPalette.muted)
                        Spacer()
                        Button {
                            guard let sourceDevice, let destinationDevice else { model.dismissError(); return }
                            model.saveSyncRule(sourceDevice: sourceDevice, destinationDevice: destinationDevice, sourceRoot: sourceSyncRoot, destinationRoot: destinationSyncRoot, mode: syncMode)
                        } label: {
                            Label("Save rule", systemImage: "plus").font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 13).padding(.vertical, 9).background(HubPalette.lime, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(HubPalette.background)
                        }.buttonStyle(.plain).disabled(sourceDevice == nil || destinationDevice == nil || sourceDevice?.id == destinationDevice?.id)
                    }
                    Text("Use paths from the device browser. ADB is limited to shared storage (/sdcard); MTP “/” scans that storage and may take a while.")
                        .font(.system(size: 9)).foregroundStyle(HubPalette.muted)
                }.padding(16).background(HubPalette.panel, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 11) {
                    HStack {
                        Text("SAVED RULES").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(HubPalette.muted)
                        Spacer()
                        Text("Manual only · deletes off").font(.system(size: 9, weight: .medium)).foregroundStyle(HubPalette.muted)
                    }
                    if model.syncRules.isEmpty {
                        Text("Save a source and destination folder pair to begin.").font(.system(size: 11)).foregroundStyle(HubPalette.muted).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(HubPalette.panel, in: RoundedRectangle(cornerRadius: 9))
                    } else {
                        ForEach(model.syncRules) { rule in syncRuleCard(rule) }
                    }
                }
            }.padding(26)
        }
    }

    private func syncRuleCard(_ rule: SyncRule) -> some View {
        let isActive = model.activeSyncRuleID == rule.id
        let plan = isActive ? model.syncPlan : []
        let conflictPaths = Set(plan.filter { $0.action == .conflict }.map(\.relativePath))
        let chosenConflicts = conflictPaths.filter { model.syncConflictChoices[$0] != nil }.count
        let actionable = plan.filter { $0.action != .conflict }.count + chosenConflicts
        let conflictCount = conflictPaths.count - chosenConflicts
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(HubPalette.lime).padding(.top, 2)
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(model.displayName(for: rule.sourceDeviceID)) → \(model.displayName(for: rule.destinationDeviceID))")
                        .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text("\(rule.sourceRoot)  →  \(rule.destinationRoot)").font(.system(size: 10, design: .monospaced)).foregroundStyle(HubPalette.muted).lineLimit(1)
                    Text(rule.mode.rawValue + (rule.mode == .oneWay ? " · source authoritative" : " · conflicting edits are skipped"))
                        .font(.system(size: 9)).foregroundStyle(HubPalette.muted)
                }
                Spacer(minLength: 8)
                Button { Task { await model.previewSync(rule) } } label: {
                    Label(model.isSyncing && isActive ? "Working…" : "Preview", systemImage: "eye")
                }.buttonStyle(.bordered).tint(HubPalette.lime).disabled(model.isSyncing)
                Button { model.deleteSyncRule(rule) } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(HubPalette.muted).help("Delete saved rule")
            }
            if isActive, let syncMessage = model.syncMessage {
                Text(syncMessage).font(.system(size: 10, weight: .medium)).foregroundStyle(conflictCount > 0 ? .orange : HubPalette.muted)
                if !plan.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(plan) { item in
                            HStack(spacing: 9) {
                                Image(systemName: syncActionIcon(item.action)).foregroundStyle(item.action == .conflict ? .orange : HubPalette.lime).frame(width: 15)
                                Text(item.relativePath).font(.system(size: 10, design: .monospaced)).lineLimit(1)
                                Spacer()
                                Text(item.reason).font(.system(size: 9)).foregroundStyle(item.action == .conflict ? .orange : HubPalette.muted).lineLimit(1)
                                if item.action == .conflict, item.reason.hasPrefix("Both sides") || item.reason.hasPrefix("Destination changed") {
                                    Button(model.syncConflictChoices[item.relativePath] == .copyToDestination ? "✓ Use source" : "Use source") {
                                        model.chooseSyncConflict(item.relativePath, action: .copyToDestination)
                                    }.font(.system(size: 9, weight: .medium)).buttonStyle(.plain).foregroundStyle(HubPalette.lime)
                                    Button(model.syncConflictChoices[item.relativePath] == .copyToSource ? "✓ Use destination" : "Use destination") {
                                        model.chooseSyncConflict(item.relativePath, action: .copyToSource)
                                    }.font(.system(size: 9, weight: .medium)).buttonStyle(.plain).foregroundStyle(HubPalette.lime)
                                }
                            }.padding(.vertical, 7)
                            if item.id != plan.last?.id { Rectangle().fill(HubPalette.line).frame(height: 1) }
                        }
                    }.padding(.horizontal, 10).background(HubPalette.panelRaised.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                }
                HStack {
                    if conflictCount > 0 { Label("\(conflictCount) conflict\(conflictCount == 1 ? "" : "s") will be left untouched", systemImage: "exclamationmark.triangle").font(.system(size: 9)).foregroundStyle(.orange) }
                    Spacer()
                    Button { showSyncApplyConfirmation = true } label: {
                        Label("Apply \(actionable) safe change\(actionable == 1 ? "" : "s")", systemImage: "checkmark")
                    }.buttonStyle(.borderedProminent).tint(HubPalette.lime).foregroundStyle(HubPalette.background)
                        .disabled(actionable == 0 || model.isSyncing)
                }
            }
        }.padding(14).background(HubPalette.panel, in: RoundedRectangle(cornerRadius: 11)).overlay(RoundedRectangle(cornerRadius: 11).stroke(HubPalette.line, lineWidth: 1))
    }

    private func syncActionIcon(_ action: SyncPlanAction) -> String {
        return switch action {
        case .copyToDestination, .createDestinationFolder: "arrow.right.to.line"
        case .copyToSource, .createSourceFolder: "arrow.left.to.line"
        case .conflict: "exclamationmark.triangle"
        }
    }

    private func endpointCard(title: String, device: ConnectedDevice?, isSource: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(HubPalette.muted)
            Menu {
                Button("This Mac") {
                    if isSource { model.chooseTransferSource(nil) } else { model.chooseTransferDestination(nil) }
                }
                ForEach(model.devices) { candidate in
                    Button("\(candidate.model) · \(candidate.link.rawValue)") {
                        if isSource { model.chooseTransferSource(candidate.id) }
                        else { model.chooseTransferDestination(candidate.id) }
                    }.disabled(candidate.id == (isSource ? model.selectedDestinationDeviceID : model.transferSourceDeviceID))
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: device == nil ? "laptopcomputer" : "iphone.gen3")
                        .font(.system(size: 17)).foregroundStyle(HubPalette.lime).frame(width: 37, height: 37).background(HubPalette.lime.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(device.map { model.displayName(for: $0.id) } ?? "This Mac").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text(device.map { "Connected · \($0.link.rawValue)" } ?? "Local files").font(.system(size: 10)).foregroundStyle(HubPalette.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(HubPalette.muted)
                }
                .padding(13).frame(maxWidth: .infinity, alignment: .leading).background(HubPalette.panelRaised, in: RoundedRectangle(cornerRadius: 10))
            }.menuStyle(.borderlessButton)
        }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(HubPalette.panel, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(HubPalette.line, lineWidth: 1))
    }

    private var rememberedDevicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DEVICE HISTORY").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(HubPalette.muted)
            ForEach(model.rememberedDevices) { remembered in rememberedDeviceRow(remembered) }
        }
    }

    private func rememberedDeviceRow(_ remembered: RememberedDevice) -> some View {
        HStack(spacing: 11) {
            Image(systemName: model.devices.contains(where: { $0.id == remembered.id }) ? "iphone.gen3" : "iphone.slash")
                .foregroundStyle(model.devices.contains(where: { $0.id == remembered.id }) ? HubPalette.lime : HubPalette.muted)
            VStack(alignment: .leading, spacing: 3) {
                Text(remembered.displayName).font(.system(size: 11, weight: .medium))
                Text(model.devices.contains(where: { $0.id == remembered.id }) ? "Connected now" : "Last seen \(remembered.lastSeenAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 9)).foregroundStyle(HubPalette.muted)
            }
            Spacer()
            Text("\(model.transferCount(for: remembered.id)) transfers").font(.system(size: 9)).foregroundStyle(HubPalette.muted)
            Button { model.forgetDevice(remembered.id) } label: { Image(systemName: "minus.circle").foregroundStyle(HubPalette.muted) }.buttonStyle(.plain).help("Forget this device")
        }.padding(10).background(HubPalette.panelRaised.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
    }

    private var deviceHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("CONNECTED DEVICES").font(.system(size: 10, weight: .bold)).tracking(1.1).foregroundStyle(HubPalette.muted)
                Text(model.devices.isEmpty ? "No device connected yet" : "\(model.devices.count) device\(model.devices.count == 1 ? "" : "s") ready")
                    .font(.system(size: 16, weight: .medium))
            }
            Spacer()
            if selection == "device", !model.devices.isEmpty {
                Menu {
                    ForEach(model.devices) { device in
                        Button {
                            Task { await model.selectDevice(device) }
                        } label: {
                            Label("\(device.model) · \(device.link.rawValue)", systemImage: device.isAuthorized ? "checkmark.circle" : "exclamationmark.circle")
                        }
                    }
                } label: {
                    HStack(spacing: 7) {
                        Text(model.selectedDevice?.model ?? "Choose device")
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    }.font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 9)
                        .background(HubPalette.panel, in: RoundedRectangle(cornerRadius: 8))
                }.menuStyle(.borderlessButton)
            }
        }
    }

    private var transportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CONNECTION OPTIONS").font(.system(size: 10, weight: .bold)).tracking(1.1).foregroundStyle(HubPalette.muted)
                    Text("Start simple. You can change methods any time.").font(.system(size: 10)).foregroundStyle(HubPalette.muted.opacity(0.85))
                }
                Spacer()
                Button { Task { await model.scanMTP() } } label: {
                    Label(model.isScanning ? "Looking…" : "Scan USB", systemImage: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold)).padding(.horizontal, 12).padding(.vertical, 9)
                        .background(HubPalette.lime, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(HubPalette.background)
                }.buttonStyle(.plain).disabled(model.isScanning)
            }
            HStack(spacing: 12) {
                methodCard(title: "USB cable", subtitle: "Recommended · no debugging setup", icon: "cable.connector", tint: HubPalette.lime, actionTitle: "Scan for phone", action: { Task { await model.scanMTP() } })
                methodCard(title: "Wi-Fi sharing", subtitle: "Use your phone's browser · no install", icon: "qrcode", tint: .orange, actionTitle: model.wifiActive ? "Portal is on" : "Set up sharing", action: { selection = "shared" })
            }
            DisclosureGroup(isExpanded: $showAdvancedConnections) {
                HStack(spacing: 12) {
                    methodCard(title: "Android debugging", subtitle: model.adbAvailable ? "Available on this Mac" : "Optional · requires Platform-Tools", icon: "hammer", tint: .purple, actionTitle: model.adbAvailable ? "Wireless setup" : "Set up ADB", action: { showWiFiInfo = true })
                    Spacer(minLength: 0)
                }.padding(.top, 10)
            } label: {
                Label("More connection methods", systemImage: "slider.horizontal.3").font(.system(size: 11, weight: .medium)).foregroundStyle(HubPalette.text.opacity(0.88))
            }
            .tint(HubPalette.muted)
            .padding(13).background(HubPalette.panel, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func methodCard(title: String, subtitle: String, icon: String, tint: Color, actionTitle: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint).frame(width: 31, height: 31).background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(HubPalette.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            Button(action: action) { Text(actionTitle).font(.system(size: 10, weight: .semibold)).foregroundStyle(tint) }.buttonStyle(.plain)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(HubPalette.panel, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(HubPalette.line, lineWidth: 1))
    }

    private func browserSection(_ device: ConnectedDevice) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DEVICE STORAGE").font(.system(size: 10, weight: .bold)).tracking(1.1).foregroundStyle(HubPalette.muted)
                    HStack(spacing: 6) {
                        Text(device.model).font(.system(size: 16, weight: .semibold))
                        Text("·  \(device.serial)").font(.system(size: 11, design: .monospaced)).foregroundStyle(HubPalette.muted)
                    }
                }
                Spacer()
                Menu {
                    Button("Use this folder as sync source") {
                        model.chooseTransferSource(device.id)
                        sourceSyncRoot = model.currentPath
                        selection = "sync"
                    }
                    Button("Use this folder as sync destination") {
                        model.chooseTransferDestination(device.id)
                        destinationSyncRoot = model.currentPath
                        selection = "sync"
                    }
                } label: {
                    Label("Use for sync", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 8)
                        .background(HubPalette.panelRaised, in: RoundedRectangle(cornerRadius: 7))
                }.menuStyle(.borderlessButton)
                Button { model.pasteFromMacClipboard() } label: {
                    Label("Paste from Mac", systemImage: "clipboard")
                        .font(.system(size: 10, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 8)
                        .background(HubPalette.panelRaised, in: RoundedRectangle(cornerRadius: 7)).foregroundStyle(HubPalette.text.opacity(0.9))
                }.buttonStyle(.plain).help("Upload files copied in Finder")
                Button { model.sendFiles() } label: {
                    Label("Upload files", systemImage: "arrow.up.to.line")
                        .font(.system(size: 11, weight: .semibold)).padding(.horizontal, 12).padding(.vertical, 9)
                        .background(HubPalette.lime, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(HubPalette.background)
                }.buttonStyle(.plain).help("Choose one or more files from this Mac to upload")
            }
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button { Task { await model.goUp() } } label: { Image(systemName: "arrow.left").font(.system(size: 11, weight: .semibold)).frame(width: 28, height: 27).background(HubPalette.panelRaised, in: RoundedRectangle(cornerRadius: 6)) }.buttonStyle(.plain)
                    Image(systemName: "folder").foregroundStyle(HubPalette.lime).font(.system(size: 12))
                    Text(model.currentPath).font(.system(size: 11, design: .monospaced)).foregroundStyle(HubPalette.muted)
                    Spacer()
                    if model.selectedDevice?.transport == .mtp, model.mtpStorages.count > 1 {
                        Menu {
                            ForEach(model.mtpStorages) { storage in
                                Button(storage.name) { Task { await model.selectStorage(storage) } }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(model.mtpStorages.first(where: { $0.id == model.selectedStorageID })?.name ?? "Storage")
                                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                            }.font(.system(size: 10, weight: .medium)).foregroundStyle(HubPalette.text.opacity(0.9))
                        }.menuStyle(.borderlessButton)
                    }
                    Text("\(visibleFiles.count) ITEMS").font(.system(size: 9, weight: .bold)).tracking(0.7).foregroundStyle(HubPalette.muted)
                }.padding(10).background(HubPalette.panelRaised.opacity(0.7))
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundStyle(HubPalette.muted)
                    TextField("Search this folder", text: $searchText).textFieldStyle(.plain).font(.system(size: 11))
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(HubPalette.muted) }.buttonStyle(.plain)
                    }
                    Button(selectedFileIDs.count == visibleFiles.filter({ !$0.isDirectory }).count ? "Deselect all" : "Select all") {
                        let ids = Set(visibleFiles.filter { !$0.isDirectory }.map(\.id))
                        if selectedFileIDs.isSuperset(of: ids) { selectedFileIDs.subtract(ids) }
                        else { selectedFileIDs.formUnion(ids) }
                    }.font(.system(size: 10, weight: .medium)).buttonStyle(.plain).foregroundStyle(HubPalette.lime)
                }.padding(.horizontal, 11).padding(.vertical, 9).background(HubPalette.panelRaised.opacity(0.45))
                if !selectedFiles.isEmpty || (!copiedFilePaths.isEmpty && copiedDeviceID == model.selectedDeviceID && copiedStorageID == model.selectedStorageID) {
                    HStack(spacing: 10) {
                        if !selectedFiles.isEmpty {
                            Text("\(selectedFiles.count) selected").font(.system(size: 10, weight: .semibold)).foregroundStyle(HubPalette.text)
                        } else {
                            Text("Copied \(copiedFilePaths.count) file\(copiedFilePaths.count == 1 ? "" : "s")").font(.system(size: 10, weight: .semibold)).foregroundStyle(HubPalette.text)
                        }
                        Spacer()
                        if !selectedFiles.isEmpty {
                            Button { copiedFilePaths = selectedFiles.map(\.path); copiedDeviceID = model.selectedDeviceID; copiedStorageID = model.selectedStorageID } label: { Label("Copy files", systemImage: "doc.on.doc") }
                                .buttonStyle(.plain).font(.system(size: 10, weight: .medium)).foregroundStyle(HubPalette.text.opacity(0.9))
                            Button { Task { await model.copyToMacClipboard(selectedFiles) } } label: { Label("Copy to Mac", systemImage: "laptopcomputer.and.arrow.down") }
                                .buttonStyle(.plain).font(.system(size: 10, weight: .medium)).foregroundStyle(HubPalette.text.opacity(0.9))
                        }
                        if !copiedFilePaths.isEmpty, copiedDeviceID == model.selectedDeviceID, copiedStorageID == model.selectedStorageID {
                            Button { Task { await model.copyOnDevice(paths: copiedFilePaths) } } label: { Label("Paste here", systemImage: "clipboard") }
                                .buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(HubPalette.lime)
                        }
                        if !selectedFiles.isEmpty {
                            Button { model.receive(selectedFiles); selectedFileIDs.removeAll() } label: { Label("Save selected", systemImage: "arrow.down.to.line") }
                                .buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(HubPalette.lime)
                            if let destinationDevice, destinationDevice.id != model.transferSourceDeviceID {
                                Button {
                                    Task {
                                        await model.transferSelectedFiles(selectedFiles, to: destinationDevice)
                                        selectedFileIDs.removeAll()
                                    }
                                } label: { Label("Send to \(model.displayName(for: destinationDevice.id))", systemImage: "arrow.right.to.line") }
                                    .buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(HubPalette.lime)
                            } else if destinationDevice == nil {
                                Button { model.receive(selectedFiles); selectedFileIDs.removeAll() } label: {
                                    Label("Save to Mac", systemImage: "arrow.down.to.line")
                                }.buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(HubPalette.lime)
                            }
                            Button { selectedFileIDs.removeAll() } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain).foregroundStyle(HubPalette.muted).help("Clear selection")
                        }
                        if let notice = model.clipboardNotice {
                            Text(notice).font(.system(size: 9)).foregroundStyle(HubPalette.muted).lineLimit(1)
                        }
                    }.padding(.horizontal, 12).padding(.vertical, 9).background(HubPalette.lime.opacity(0.07))
                }
                if model.isLoadingFiles {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(28)
                } else if visibleFiles.isEmpty {
                    VStack(spacing: 7) {
                        Image(systemName: searchText.isEmpty ? "folder" : "magnifyingglass").font(.system(size: 20)).foregroundStyle(HubPalette.muted)
                        Text(searchText.isEmpty ? "This folder is empty" : "No matches in this folder").font(.system(size: 12)).foregroundStyle(HubPalette.muted)
                    }.frame(maxWidth: .infinity).padding(25)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleFiles) { file in
                            fileRow(file)
                            if file.id != visibleFiles.last?.id { Rectangle().fill(HubPalette.line).frame(height: 1).padding(.leading, 42) }
                        }
                    }
                }
            }
            .background(HubPalette.panel, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(HubPalette.line, lineWidth: 1))
        }
    }

    private func fileRow(_ file: PhoneFile) -> some View {
        HStack(spacing: 11) {
            if !file.isDirectory {
                Button {
                    if selectedFileIDs.contains(file.id) { selectedFileIDs.remove(file.id) }
                    else { selectedFileIDs.insert(file.id) }
                } label: {
                    Image(systemName: selectedFileIDs.contains(file.id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14)).foregroundStyle(selectedFileIDs.contains(file.id) ? HubPalette.lime : HubPalette.muted)
                }.buttonStyle(.plain).help("Select \(file.name)")
            } else {
                Color.clear.frame(width: 14, height: 14)
            }
            Image(systemName: file.isDirectory ? "folder.fill" : fileIcon(file.name))
                .font(.system(size: 14)).foregroundStyle(file.isDirectory ? HubPalette.lime : Color(red: 0.48, green: 0.67, blue: 0.94)).frame(width: 23)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(file.isDirectory ? "Folder" : formattedSize(file.size)).font(.system(size: 10)).foregroundStyle(HubPalette.muted)
            }
            Spacer()
            if !file.isDirectory {
                if let device = model.selectedDevice, model.wasTransferredBefore(file, on: device) {
                    Label("Moved before", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(HubPalette.lime)
                        .help("A completed transfer for this file is in Activity")
                }
                Button { Task { await model.preview(file) } } label: {
                    Image(systemName: "eye").font(.system(size: 10, weight: .medium)).padding(7).background(HubPalette.panelRaised, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain).help("Preview \(file.name)")
                Button { model.receive(file) } label: {
                    Label("Save to Mac", systemImage: "arrow.down.to.line").font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 9).padding(.vertical, 6).background(HubPalette.panelRaised, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain)
            }
            if file.isDirectory {
                Button { Task { await model.open(file) } } label: { Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(HubPalette.muted).frame(width: 25, height: 25) }.buttonStyle(.plain)
            }
        }.padding(.horizontal, 12).padding(.vertical, 9)
            .contentShape(Rectangle())
            .onTapGesture { if file.isDirectory { Task { await model.open(file) } } }
    }

    private var recentTransfers: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RECENT TRANSFERS").font(.system(size: 10, weight: .bold)).tracking(1.1).foregroundStyle(HubPalette.muted)
                Spacer()
                Button("View all") { selection = "transfers" }.font(.system(size: 10, weight: .medium)).foregroundStyle(HubPalette.lime).buttonStyle(.plain)
            }
            let recent = Array(model.transfers.prefix(3))
            if recent.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.left.arrow.right").foregroundStyle(HubPalette.muted)
                    Text("Your transfers will appear here").font(.system(size: 11)).foregroundStyle(HubPalette.muted)
                    Spacer()
                }.padding(14).background(HubPalette.panel, in: RoundedRectangle(cornerRadius: 10))
            } else {
                ForEach(recent) { transferRow($0) }
            }
        }
    }

    private var authorizationNotice: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "iphone.gen3.radiowaves.left.and.right").font(.system(size: 26)).foregroundStyle(HubPalette.lime)
            Text("Approve this Mac on your phone").font(.system(size: 17, weight: .semibold))
            Text("Unlock the Android device and accept the USB debugging prompt. If it doesn’t appear, open Developer options and enable USB debugging.")
                .font(.system(size: 12)).foregroundStyle(HubPalette.muted).fixedSize(horizontal: false, vertical: true)
            Button("Check again") { Task { await model.refreshDevices() } }.buttonStyle(.borderedProminent).tint(HubPalette.lime).foregroundStyle(HubPalette.background)
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(HubPalette.panel, in: RoundedRectangle(cornerRadius: 12))
    }

    private var wifiPortalSection: some View {
        HStack(spacing: 20) {
            if let qr = model.wifiQRImage {
                Image(nsImage: qr).interpolation(.none).resizable().frame(width: 126, height: 126)
                    .padding(8).background(.white, in: RoundedRectangle(cornerRadius: 10))
            } else {
                ProgressView().frame(width: 142, height: 142)
            }
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Circle().fill(model.wifiActive ? HubPalette.lime : .orange).frame(width: 7, height: 7)
                    Text(model.wifiActive ? "PHONE PORTAL READY" : "STARTING LOCAL PORTAL").font(.system(size: 9, weight: .bold)).tracking(0.9).foregroundStyle(model.wifiActive ? HubPalette.lime : .orange)
                }
                Text("Scan to transfer over Wi-Fi").font(.system(size: 16, weight: .semibold))
                Text("Open this link on your phone to send files here or download files you share from the Mac.")
                    .font(.system(size: 11)).foregroundStyle(HubPalette.muted).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 9) {
                    Text(model.wifiAddress ?? "Finding local address…").font(.system(size: 10, design: .monospaced)).foregroundStyle(HubPalette.text.opacity(0.85)).textSelection(.enabled)
                    Button {
                        if let url = model.wifiAddress { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url, forType: .string) }
                    } label: { Image(systemName: "doc.on.doc").font(.system(size: 10)).padding(6).background(HubPalette.panelRaised, in: RoundedRectangle(cornerRadius: 5)) }.buttonStyle(.plain)
                }
                HStack(spacing: 10) {
                    Button("Share files from Mac") { model.addFilesToWiFiOutbox() }.font(.system(size: 10, weight: .semibold)).buttonStyle(.borderedProminent).tint(HubPalette.lime).foregroundStyle(HubPalette.background)
                    Button("Stop portal") { model.stopWiFiPortal() }.font(.system(size: 10, weight: .medium)).buttonStyle(.bordered).tint(.white.opacity(0.7))
                }
                Label("Your Mac and phone must be on the same Wi-Fi network. Guest Wi-Fi or router isolation may block the connection.", systemImage: "wifi.exclamationmark")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                Text("Use a trusted network; anyone with this temporary link can access files you choose to share. Session ends when stopped.")
                    .font(.system(size: 9)).foregroundStyle(HubPalette.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16).background(HubPalette.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(HubPalette.line, lineWidth: 1))
    }

    private var emptyDeviceState: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 15) {
                Image(systemName: "iphone.gen3").font(.system(size: 25)).foregroundStyle(HubPalette.lime).frame(width: 54, height: 54).background(HubPalette.lime.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bring your phone close") .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("Connect a device to browse its files, or use Shared for a quick browser-based transfer. Your files stay local.")
                        .font(.system(size: 12)).foregroundStyle(HubPalette.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(alignment: .top, spacing: 0) {
                setupStep("1", "Connect a data cable")
                Spacer(minLength: 8)
                setupStep("2", "Unlock your phone")
                Spacer(minLength: 8)
                setupStep("3", "Scan for devices")
            }
            HStack(spacing: 10) {
                Button { Task { await model.scanMTP() } } label: {
                    Label("Scan for phone", systemImage: "arrow.clockwise").font(.system(size: 11, weight: .semibold)).padding(.horizontal, 13).padding(.vertical, 9)
                        .background(HubPalette.lime, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(HubPalette.background)
                }.buttonStyle(.plain)
                Button { selection = "shared" } label: {
                    Label("Use Wi-Fi instead", systemImage: "qrcode").font(.system(size: 11, weight: .medium)).padding(.horizontal, 13).padding(.vertical, 9)
                        .background(HubPalette.panelRaised, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(.white)
                }.buttonStyle(.plain)
            }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(HubPalette.panel, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(HubPalette.line, lineWidth: 1))
    }

    private var sharedPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("A simple bridge between devices") .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("Open the link on a phone or tablet browser. No companion app is needed. Your phone and Mac must be on the same Wi-Fi network; cellular, guest Wi-Fi, or client isolation may not work.")
                        .font(.system(size: 12)).foregroundStyle(HubPalette.muted).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Label("Android", systemImage: "checkmark.circle.fill")
                        Label("iPhone and iPad", systemImage: "checkmark.circle.fill")
                        Label("No cloud upload", systemImage: "checkmark.circle.fill")
                    }.font(.system(size: 10, weight: .medium)).foregroundStyle(HubPalette.lime).padding(.top, 3)
                }.padding(21).frame(maxWidth: .infinity, alignment: .leading).background(HubPalette.panel, in: RoundedRectangle(cornerRadius: 13))

                if model.wifiActive || model.wifiAddress != nil {
                    wifiPortalSection
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Private local session", systemImage: "lock.shield").font(.system(size: 13, weight: .semibold))
                        Text("The portal is off until you start it. When active, anyone with its temporary link on your local network can access files you explicitly share or upload.")
                            .font(.system(size: 11)).foregroundStyle(HubPalette.muted).fixedSize(horizontal: false, vertical: true)
                        Label("Before scanning: connect your phone to the same Wi-Fi network as this Mac. Avoid guest networks; client isolation can prevent devices from seeing each other.", systemImage: "wifi.exclamationmark")
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                        Button { model.startWiFiPortal() } label: {
                            Label("Start sharing", systemImage: "qrcode").font(.system(size: 11, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 10)
                                .background(HubPalette.lime, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(HubPalette.background)
                        }.buttonStyle(.plain)
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(HubPalette.panel, in: RoundedRectangle(cornerRadius: 13))
                }

                VStack(alignment: .leading, spacing: 11) {
                    Text("HOW SHARING WORKS").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(HubPalette.muted)
                    HStack(alignment: .top, spacing: 15) {
                        setupStep("1", "Start a temporary session")
                        setupStep("2", "Scan the QR code")
                        setupStep("3", "Choose upload or download")
                    }
                    Text("Received files are saved to Downloads / Transfer Hub. Stop the session when you’re done.")
                        .font(.system(size: 10)).foregroundStyle(HubPalette.muted)
                }.padding(17).background(HubPalette.panel, in: RoundedRectangle(cornerRadius: 12))
            }.padding(28)
        }
    }

    private var transfersPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your queue").font(.system(size: 18, weight: .semibold))
                        Text("Transfers stay here so you can retry after a connection drops.").font(.system(size: 11)).foregroundStyle(HubPalette.muted)
                    }
                    Spacer()
                    Text("\(model.transfers.count) TOTAL").font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(HubPalette.muted)
                    Button("Clear history", systemImage: "trash") { showClearHistoryConfirmation = true }
                        .font(.system(size: 10, weight: .medium)).buttonStyle(.bordered).tint(.orange)
                }
                Picker("Transfer history", selection: $transferFilter) {
                    ForEach(["All", "Active", "Completed", "Needs attention"], id: \.self) { filter in
                        Text(filter).tag(filter)
                    }
                }.pickerStyle(.segmented).labelsHidden()
                if model.transfers.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray").font(.system(size: 25)).foregroundStyle(HubPalette.muted)
                        Text("No transfers yet").font(.system(size: 13, weight: .medium))
                        Text("Connect a device and send or save a file to get started.").font(.system(size: 11)).foregroundStyle(HubPalette.muted)
                    }.frame(maxWidth: .infinity).padding(48).background(HubPalette.panel, in: RoundedRectangle(cornerRadius: 12))
                } else {
                    if filteredTransfers.isEmpty {
                        Text("No \(transferFilter.lowercased()) transfers").font(.system(size: 12)).foregroundStyle(HubPalette.muted)
                            .frame(maxWidth: .infinity).padding(30).background(HubPalette.panel, in: RoundedRectangle(cornerRadius: 12))
                    } else {
                        ForEach(filteredTransfers) { transferRow($0, full: true) }
                    }
                }
            }.padding(28)
        }
    }

    private func transferRow(_ transfer: TransferRecord, full: Bool = false) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(HubPalette.panelRaised).frame(width: 35, height: 35)
                Image(systemName: transfer.direction == .toPhone ? "arrow.up.to.line" : transfer.direction == .betweenDevices ? "arrow.left.arrow.right" : "arrow.down.to.line").font(.system(size: 13, weight: .semibold)).foregroundStyle(transfer.state == .complete ? HubPalette.lime : .white.opacity(0.8))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(transfer.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                if transfer.direction == .betweenDevices, let destinationID = transfer.destinationDeviceSerial {
                    Text("\(model.displayName(for: "\((transfer.transport ?? .adb).rawValue)-\(transfer.deviceSerial)")) → \(model.displayName(for: "\((transfer.destinationTransport ?? .adb).rawValue)-\(destinationID)"))")
                        .font(.system(size: 9)).foregroundStyle(HubPalette.muted).lineLimit(1)
                }
                Text(transfer.detail).font(.system(size: 10)).foregroundStyle(transfer.state == .failed ? .orange : HubPalette.muted).lineLimit(full ? 2 : 1)
                if transfer.state == .running, let progress = transfer.progress {
                    ProgressView(value: progress).tint(HubPalette.lime).frame(maxWidth: full ? 300 : 180)
                }
            }
            Spacer()
            Text(transfer.state.rawValue.uppercased()).font(.system(size: 8, weight: .bold)).tracking(0.5)
                .foregroundStyle(transfer.state == .complete ? HubPalette.lime : transfer.state == .failed ? .orange : HubPalette.muted)
            if transfer.state == .failed {
                Button("Retry") { model.retry(transfer) }.font(.system(size: 10, weight: .semibold)).buttonStyle(.bordered).tint(HubPalette.lime)
            }
            if full { Text(transfer.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10, design: .monospaced)).foregroundStyle(HubPalette.muted).frame(width: 118, alignment: .trailing) }
        }.padding(12).background(HubPalette.panel, in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(HubPalette.line, lineWidth: 1))
    }

    private var wifiSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "wrench.and.screwdriver").font(.system(size: 24)).foregroundStyle(.purple)
            Text("Advanced Android connection").font(.system(size: 20, weight: .semibold))
            Text("ADB is an optional Android developer connection. It can provide direct cable or wireless access, but requires Android Platform-Tools and approval on the phone.")
                .font(.system(size: 13)).foregroundStyle(HubPalette.muted).fixedSize(horizontal: false, vertical: true)
            if model.adbAvailable {
                Text("Platform-Tools are available. For Wi-Fi, open Android Developer options → Wireless debugging and pair this Mac on the same network. A paired device appears automatically.")
                    .font(.system(size: 11)).foregroundStyle(HubPalette.muted).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("For a simpler cable transfer, use USB file-transfer mode and Scan USB instead—ADB is not required.")
                    .font(.system(size: 11)).foregroundStyle(HubPalette.muted).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Get Platform-Tools") { model.openADBDownloadPage() }.buttonStyle(.borderedProminent).tint(HubPalette.lime).foregroundStyle(HubPalette.background)
                    Button("Locate adb") { model.locateADB() }.buttonStyle(.bordered).tint(.white.opacity(0.8))
                }
            }
            Button("Done") { showWiFiInfo = false }.buttonStyle(.plain).foregroundStyle(HubPalette.lime)
        }.padding(25).frame(width: 410).background(HubPalette.panel)
    }

    private func sidebarItem(_ title: String, icon: String, id: String, badge: Int = 0) -> some View {
        Button { selection = id } label: {
            HStack(spacing: 11) {
                Image(systemName: icon).font(.system(size: 13, weight: .medium)).frame(width: 17)
                Text(title).font(.system(size: 12, weight: selection == id ? .semibold : .regular))
                Spacer()
                if badge > 0 { Text("\(badge)").font(.system(size: 9, weight: .bold)).foregroundStyle(HubPalette.background).frame(width: 19, height: 19).background(HubPalette.lime, in: Circle()) }
            }.foregroundStyle(selection == id ? HubPalette.text : HubPalette.muted)
                .padding(.horizontal, 11).padding(.vertical, 10)
                .background(selection == id ? HubPalette.lime.opacity(HubPalette.isLight ? 0.18 : 0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 11)
        }.buttonStyle(.plain)
    }

    private func sideLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(HubPalette.muted.opacity(0.75)).padding(.horizontal, 22).padding(.bottom, 8)
    }

    private func setupStep(_ number: String, _ title: String) -> some View {
        HStack(spacing: 7) {
            Text(number).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(HubPalette.lime)
            Text(title).font(.system(size: 10)).foregroundStyle(HubPalette.muted)
        }
    }

    private func fileIcon(_ name: String) -> String {
        switch URL(fileURLWithPath: name).pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "webp": return "photo"
        case "mp4", "mov", "mkv": return "film"
        case "pdf": return "doc.richtext"
        case "zip", "gz", "rar": return "doc.zipper"
        case "mp3", "wav", "flac": return "waveform"
        default: return "doc"
        }
    }

    private func formattedSize(_ size: Int64?) -> String {
        guard let size else { return "File" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
