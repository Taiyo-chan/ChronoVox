import SwiftUI

/// プロジェクトディレクトリ一覧画面（6言語対応）
struct ProjectListView: View {
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var storageManager: ProjectStorageManager

    @State private var showingNewProjectSheet = false
    @State private var newProjectName = ""
    @State private var newProjectOverview = ""
    @State private var newProjectStatus = ""

    var body: some View {
        let t = localization.t
        NavigationStack {
            Group {
                if storageManager.projects.isEmpty {
                    emptyProjectsView(t: t)
                } else {
                    List {
                        Section {
                            ForEach(storageManager.projects) { project in
                                NavigationLink(value: project) {
                                    projectRow(project)
                                }
                            }
                            .onDelete { offsets in
                                for index in offsets {
                                    storageManager.deleteProject(storageManager.projects[index])
                                }
                            }
                        } header: {
                            Text("\(t.tabProjects) (\(storageManager.projects.count))")
                        } footer: {
                            Text(t.projectsFooterDescription)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        storageManager.reloadAll()
                    }
                }
            }
            .navigationTitle(t.tabProjects)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newProjectName = ""
                        newProjectOverview = ""
                        newProjectStatus = ""
                        showingNewProjectSheet = true
                    } label: {
                        Label(t.newProjectButton, systemImage: "folder.badge.plus")
                    }
                }
            }
            .navigationDestination(for: Project.self) { project in
                ProjectDetailView(project: project)
            }
            .sheet(isPresented: $showingNewProjectSheet) {
                createProjectSheet(t: t)
            }
        }
    }

    private func projectRow(_ project: Project) -> some View {
        let audioCount = storageManager.loadAudioFiles(for: project).count
        let docs = storageManager.loadDocuments(for: project)
        let minutesCount = docs.filter { $0.category == .minutes }.count
        let transcriptsCount = docs.count - minutesCount

        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 46, height: 46)
                Image(systemName: "folder.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.headline)
                HStack(spacing: 10) {
                    Label("\(audioCount)", systemImage: "waveform")
                    Label("\(minutesCount)", systemImage: "sparkles.rectangle.stack")
                    Label("\(transcriptsCount)", systemImage: "doc.text")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func emptyProjectsView(t: AppStrings) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 52))
                .foregroundStyle(Color.accentColor.opacity(0.75))
            Text(t.tabProjects)
                .font(.headline)
            Text(t.projectsFooterDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Button {
                newProjectName = ""
                newProjectOverview = ""
                newProjectStatus = ""
                showingNewProjectSheet = true
            } label: {
                Label(t.newProjectButton, systemImage: "plus")
                    .font(.subheadline.weight(.bold))
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 6)
            Spacer()
        }
    }

    private func createProjectSheet(t: AppStrings) -> some View {
        NavigationStack {
            Form {
                Section(t.newProjectButton) {
                    TextField("Project Name", text: $newProjectName)
                }

                Section("overview.md") {
                    TextEditor(text: $newProjectOverview)
                        .frame(minHeight: 100)
                }

                Section("current_status.md") {
                    TextEditor(text: $newProjectStatus)
                        .frame(minHeight: 90)
                }
            }
            .navigationTitle(t.newProjectButton)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t.cancelButton) {
                        showingNewProjectSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t.saveButton) {
                        _ = try? storageManager.createProject(
                            name: newProjectName,
                            initialOverview: newProjectOverview,
                            initialStatus: newProjectStatus
                        )
                        showingNewProjectSheet = false
                    }
                    .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
