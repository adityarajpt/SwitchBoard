import SwiftUI

@main
struct TransferHubApp: App {
    @StateObject private var model = HubModel()

    var body: some Scene {
        WindowGroup {
            HubView()
                .environmentObject(model)
                .frame(minWidth: 1040, minHeight: 700)
                .task { await model.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 780)
    }
}
