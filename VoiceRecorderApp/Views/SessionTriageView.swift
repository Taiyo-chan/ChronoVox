import SwiftUI

/// 一連の録音を終了した後の「トリアージ（削除・プロジェクトディレクトリ指定格納・その場での新規プロジェクト作成）」画面（6言語対応）
struct SessionTriageView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var storageManager: ProjectStorageManager
    @EnvironmentObject private var recorderManager: AudioRecorderManager
    @EnvironmentObject private var playerManager: AudioPlayerManager

    @State private var showingNewProjectAlert = false
    @State private var newProjectName = ""
    @State private var newProjectOverview = ""
    @State private var pendingItemForNewProject: RecordingItem?
    @State private var moveAllToNewProject = false

    @State private var renamingItem: RecordingItem?
    @State private var renameText = ""

    /// プロジェクト格納後にそのままAI処理画面（書き起こし・人物別・議事録）を開くための遷移状態
    @State private var recentlyMovedDestination: MovedAudioDestination?

    struct MovedAudioDestination: Identifiable, Hashable {
        var id: UUID { item.id }
        let item: RecordingItem
        let project: Project
    }

    var body: some View {
        let t = localization.t
        NavigationStack {
            VStack(spacing: 0) {
                if !storageManager.unassignedRecordings.isEmpty {
                    batchActionHeader(t: t)
                }

                if storageManager.unassignedRecordings.isEmpty {
                    emptyTriageView(t: t)
                } else {
                    List {
                        Section {
                            ForEach(storageManager.unassignedRecordings) { item in
                                triageRow(for: item, t: t)
                            }
                        } header: {
                            Text(t.unassignedHeader(count: storageManager.unassignedRecordings.count))
                        } footer: {
                            Text(t.triageFooterDescription)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(t.triageNavTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(t.closeButton) {
                        playerManager.stop()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        pendingItemForNewProject = nil
                        moveAllToNewProject = false
                        newProjectName = ""
                        newProjectOverview = ""
                        showingNewProjectAlert = true
                    } label: {
                        Label(t.newProjectButton, systemImage: "folder.badge.plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewProjectAlert) {
                newProjectCreationSheet(t: t)
            }
            .alert("Rename", isPresented: Binding(
                get: { renamingItem != nil },
                set: { if !$0 { renamingItem = nil } }
            )) {
                TextField("Title", text: $renameText)
                Button(t.cancelButton, role: .cancel) { renamingItem = nil }
                Button(t.saveButton) {
                    if let item = renamingItem {
                        _ = storageManager.renameRecording(item, newTitle: renameText)
                    }
                    renamingItem = nil
                }
            }
            .navigationDestination(
                isPresented: Binding(
                    get: { recentlyMovedDestination != nil },
                    set: { if !$0 { recentlyMovedDestination = nil } }
                )
            ) {
                if let dest = recentlyMovedDestination {
                    AudioAIActionView(item: dest.item, project: dest.project)
                }
            }
        }
    }

    // MARK: - Batch Action Header

    private func batchActionHeader(t: AppStrings) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.batchAssignTitle)
                        .font(.subheadline.weight(.bold))
                    Text(t.batchAssignSubtitle(count: storageManager.unassignedRecordings.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    if !storageManager.projects.isEmpty {
                        ForEach(storageManager.projects) { project in
                            Button {
                                moveAllRecordings(to: project)
                            } label: {
                                Label(project.name, systemImage: "folder.fill")
                            }
                        }
                    }
                    Button {
                        pendingItemForNewProject = nil
                        moveAllToNewProject = true
                        newProjectName = ""
                        newProjectOverview = ""
                        showingNewProjectAlert = true
                    } label: {
                        Label(t.createNewProjectAndStore, systemImage: "plus.rectangle.on.folder.fill")
                    }
                } label: {
                    Label(t.batchAssignButton, systemImage: "tray.and.arrow.down.fill")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Individual Recording Row

    private func triageRow(for item: RecordingItem, t: AppStrings) -> some View {
        let fileURL = storageManager.audioFileURL(for: item)
        let isPlayingThis = (playerManager.playingURL == fileURL)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    playerManager.togglePlay(url: fileURL)
                } label: {
                    Image(systemName: (isPlayingThis && playerManager.isPlaying) ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(item.formattedDate)
                        Text("•")
                        Text(item.formattedDuration)
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    renamingItem = item
                    renameText = item.title
                } label: {
                    Image(systemName: "pencil")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }

            if isPlayingThis {
                VStack(spacing: 6) {
                    Slider(
                        value: Binding(
                            get: { playerManager.currentTime },
                            set: { playerManager.seek(to: $0) }
                        ),
                        in: 0...max(playerManager.duration, 0.01)
                    )
                    HStack {
                        Text(playerManager.formatTime(playerManager.currentTime))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        HStack(spacing: 20) {
                            Button {
                                playerManager.skip(by: -15)
                            } label: {
                                Image(systemName: "gobackward.15")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.plain)

                            Button {
                                playerManager.skip(by: 15)
                            } label: {
                                Image(systemName: "goforward.15")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                        Text(playerManager.formatTime(playerManager.duration))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }

            Divider()

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    if isPlayingThis {
                        playerManager.stop()
                    }
                    recorderManager.removeFromCurrentSession(item)
                    storageManager.deleteRecording(item)
                } label: {
                    Label(t.deleteButton, systemImage: "trash")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)

                Menu {
                    if !storageManager.projects.isEmpty {
                        ForEach(storageManager.projects) { project in
                            Button {
                                assignItem(item, to: project, openAIViewAfter: false)
                            } label: {
                                Label(project.name, systemImage: "folder")
                            }
                            Button {
                                assignItem(item, to: project, openAIViewAfter: true)
                            } label: {
                                Label("\(project.name) (+ AI)", systemImage: "sparkles")
                            }
                        }
                    }

                    Button {
                        pendingItemForNewProject = item
                        moveAllToNewProject = false
                        newProjectName = ""
                        newProjectOverview = ""
                        showingNewProjectAlert = true
                    } label: {
                        Label(t.createNewProjectAndStore, systemImage: "folder.badge.plus")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.badge.plus")
                        Text(t.selectProjectToStore)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty View

    private func emptyTriageView(t: AppStrings) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text(t.allTriageDoneTitle)
                .font(.headline)
            Text(t.allTriageDoneSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button(t.closeButton) {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
            Spacer()
        }
    }

    // MARK: - New Project Creation Sheet

    private func newProjectCreationSheet(t: AppStrings) -> some View {
        NavigationStack {
            Form {
                Section(t.newProjectButton) {
                    TextField("Project Name", text: $newProjectName)
                }

                Section {
                    TextEditor(text: $newProjectOverview)
                        .frame(minHeight: 110)
                } header: {
                    Text("overview.md")
                }
            }
            .navigationTitle(t.newProjectButton)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t.cancelButton) {
                        showingNewProjectAlert = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t.saveButton) {
                        createProjectAndAssign()
                    }
                    .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Actions

    private func assignItem(_ item: RecordingItem, to project: Project, openAIViewAfter: Bool) {
        playerManager.stop()
        recorderManager.removeFromCurrentSession(item)
        if let moved = storageManager.moveRecording(item, to: project), openAIViewAfter {
            recentlyMovedDestination = MovedAudioDestination(item: moved, project: project)
        }
    }

    private func moveAllRecordings(to project: Project) {
        playerManager.stop()
        let allItems = storageManager.unassignedRecordings
        var lastMoved: RecordingItem?
        for item in allItems {
            recorderManager.removeFromCurrentSession(item)
            lastMoved = storageManager.moveRecording(item, to: project)
        }
        if let lastMoved {
            recentlyMovedDestination = MovedAudioDestination(item: lastMoved, project: project)
        }
    }

    private func createProjectAndAssign() {
        guard let createdProject = try? storageManager.createProject(
            name: newProjectName,
            initialOverview: newProjectOverview
        ) else {
            return
        }
        showingNewProjectAlert = false

        if moveAllToNewProject {
            moveAllRecordings(to: createdProject)
        } else if let item = pendingItemForNewProject {
            assignItem(item, to: createdProject, openAIViewAfter: true)
        }
        pendingItemForNewProject = nil
        moveAllToNewProject = false
    }
}
