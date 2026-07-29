import SwiftUI

@main
struct PhotoStorageAnalyzerApp: App {
    @StateObject private var analyzer = PhotoAnalyzer()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(analyzer)
        }
    }
}
