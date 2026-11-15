import SwiftUI
import SwiftData

@main
struct ProductScanApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: ScanRecord.self)
    }
}
