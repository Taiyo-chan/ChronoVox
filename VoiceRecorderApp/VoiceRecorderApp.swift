import SwiftUI

@main
struct VoiceRecorderApp: App {
    @StateObject private var localization = LocalizationManager()
    @StateObject private var storageManager = ProjectStorageManager()
    @StateObject private var recorderManager = AudioRecorderManager()
    @StateObject private var playerManager = AudioPlayerManager()
    @StateObject private var geminiService = GeminiService()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(localization)
                .environmentObject(storageManager)
                .environmentObject(recorderManager)
                .environmentObject(playerManager)
                .environmentObject(geminiService)
        }
    }
}
