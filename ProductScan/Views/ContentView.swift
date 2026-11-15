import SwiftUI

struct ContentView: View {
    @State private var showPrivacy = PrivacyView.needsConsent

    var body: some View {
        TabView {
            ScanView()
                .tabItem { Label("扫描", systemImage: "camera.viewfinder") }
            HistoryView()
                .tabItem { Label("历史", systemImage: "clock.arrow.circlepath") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .tint(Theme.blue)
        .sheet(isPresented: $showPrivacy) {
            NavigationStack {
                PrivacyView(isOnboarding: true) { showPrivacy = false }
            }
            .interactiveDismissDisabled()
        }
    }
}
