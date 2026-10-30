import SwiftUI

/// アプリ全体のメインタブビュー（6言語ローカライズ対応）
struct MainTabView: View {
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var storageManager: ProjectStorageManager

    var body: some View {
        let t = localization.t
        TabView {
            RecorderView()
                .tabItem {
                    Label(t.tabRecord, systemImage: "record.circle")
                }

            SessionTriageView()
                .tabItem {
                    Label(t.tabTriage, systemImage: "tray.full")
                }
                .badge(storageManager.unassignedRecordings.count)

            ProjectListView()
                .tabItem {
                    Label(t.tabProjects, systemImage: "folder.fill")
                }

            SettingsView()
                .tabItem {
                    Label(t.tabSettings, systemImage: "gearshape.fill")
                }
        }
    }
}
