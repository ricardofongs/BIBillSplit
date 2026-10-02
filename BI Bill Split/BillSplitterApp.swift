import SwiftUI

// MARK: - App
@main
struct BillSplitterApp: App {
    @StateObject private var model = BillViewModel()
    @StateObject private var groupsModel = ContactGroupsViewModel()
    @StateObject private var purchaseManager = PurchaseManager()
    /// "light", "dark", or "system" — persisted across launches.
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(groupsModel)
                .environmentObject(purchaseManager)
                .environment(\.appearanceMode, $appearanceMode)
                .preferredColorScheme(appearanceMode.colorScheme)
                // Handle deep-link bill imports (billsplit://import?data=<base64>)
                .onOpenURL { url in
                    guard
                        url.scheme == "billsplit",
                        url.host == "import",
                        let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                        let dataParam = components.queryItems?.first(where: { $0.name == "data" })?.value,
                        let jsonData = Data(base64Encoded: dataParam),
                        let importedBill = try? JSONDecoder().decode(Bill.self, from: jsonData)
                    else { return }

                    model.stageImportedBill(importedBill)
                }
        }
    }
}

// MARK: - Appearance Mode
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "system"
    case light  = "light"
    case dark   = "dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon.stars"
        }
    }
}

// MARK: - Environment Key for AppearanceMode binding
private struct AppearanceModeKey: EnvironmentKey {
    static let defaultValue: Binding<AppearanceMode> = .constant(.system)
}

extension EnvironmentValues {
    var appearanceMode: Binding<AppearanceMode> {
        get { self[AppearanceModeKey.self] }
        set { self[AppearanceModeKey.self] = newValue }
    }
}


// MARK: - Content View
struct ContentView: View {
    @EnvironmentObject private var vm: BillViewModel
    @State private var selectedTab = 0
    @Environment(\.appearanceMode) private var appearanceMode

    var body: some View {
        TabView(selection: $selectedTab) {
            CurrentBillView()
                .tabItem {
                    Label("Bill", systemImage: "doc.text")
                }
                .tag(0)

            SavedBillsView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Saved Bills", systemImage: "tray.full")
                }
                .tag(1)

            SpendingChartView()
                .tabItem {
                    Label("Spending", systemImage: "chart.bar")
                }
                .tag(2)

            ContactGroupsView()
                .tabItem {
                    Label("Groups", systemImage: "folder")
                }
                .tag(3)

            AppearanceSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(4)
        }
        // Confirm before a shared/deep-linked bill replaces whatever is
        // currently in the Bill tab — see `onOpenURL` in BillSplitterApp.
        .alert("Import Bill?", isPresented: Binding(
            get: { vm.pendingImportedBill != nil },
            set: { if !$0 { vm.cancelPendingImport() } }
        )) {
            Button("Replace Current Bill", role: .destructive) {
                vm.confirmPendingImport()
                selectedTab = 0
            }
            Button("Cancel", role: .cancel) {
                vm.cancelPendingImport()
            }
        } message: {
            if let imported = vm.pendingImportedBill {
                let name = imported.restaurantName.isEmpty ? "This bill" : imported.restaurantName
                Text("'\(name)' will replace what's currently in the Bill tab. This can't be undone.")
            }
        }
    }
}

