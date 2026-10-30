import SwiftUI

/// プロジェクト詳細画面（6言語対応）
struct ProjectDetailView: View {
    let project: Project

    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var storageManager: ProjectStorageManager
    @EnvironmentObject private var playerManager: AudioPlayerManager

    enum DetailSection: Int, CaseIterable, Identifiable {
        case audioFiles = 0
        case documents = 1
        case context = 2

        var id: Int { rawValue }
    }

    @State private var selectedSection: DetailSection = .audioFiles
    @State private var overviewText: String = ""
    @State private var statusText: String = ""
    @State private var showingSavedBanner: Bool = false

    var body: some View {
        let t = localization.t
        VStack(spacing: 0) {
            Picker("Section", selection: $selectedSection) {
                Text(t.sectionAudioAndAI).tag(DetailSection.audioFiles)
                Text(t.sectionDocuments).tag(DetailSection.documents)
                Text(t.sectionContext).tag(DetailSection.context)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            switch selectedSection {
            case .audioFiles:
                audioFilesListSection(t: t)
            case .documents:
                generatedDocumentsSection(t: t)
            case .context:
                projectContextEditorSection(t: t)
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            reloadContextFiles()
        }
    }

    // MARK: - 1. 格納済み音声ファイル & AI処理選択への導線

    private func audioFilesListSection(t: AppStrings) -> some View {
        let audioItems = storageManager.loadAudioFiles(for: project)
        return Group {
            if audioItems.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "waveform.badge.plus")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text(t.sectionAudioAndAI)
                        .font(.subheadline.weight(.semibold))
                    Text(t.triageFooterDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer()
                }
            } else {
                List {
                    Section {
                        ForEach(audioItems) { item in
                            NavigationLink {
                                AudioAIActionView(item: item, project: project)
                            } label: {
                                audioFileRow(item, t: t)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                storageManager.deleteRecording(audioItems[index])
                            }
                        }
                    } header: {
                        Text("\(t.sectionAudioAndAI) (\(audioItems.count))")
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private func audioFileRow(_ item: RecordingItem, t: AppStrings) -> some View {
        let hasTranscript = FileManager.default.fileExists(
            atPath: storageManager.existingDocumentURL(for: item, project: project, mode: .transcription).path
        )
        let hasDiarized = FileManager.default.fileExists(
            atPath: storageManager.existingDocumentURL(for: item, project: project, mode: .speakerDiarization).path
        )
        let hasMinutes = FileManager.default.fileExists(
            atPath: storageManager.existingDocumentURL(for: item, project: project, mode: .meetingMinutes).path
        )

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline.weight(.bold))
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
            }

            HStack(spacing: 6) {
                statusPill(title: t.modeTitle(.transcription), active: hasTranscript, color: .blue)
                statusPill(title: t.modeTitle(.speakerDiarization), active: hasDiarized, color: .purple)
                statusPill(title: t.modeTitle(.meetingMinutes), active: hasMinutes, color: .green)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusPill(title: String, active: Bool, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: active ? "checkmark.circle.fill" : "circle.dashed")
            Text(title)
                .lineLimit(1)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(active ? color.opacity(0.15) : Color.secondary.opacity(0.1), in: Capsule())
        .foregroundStyle(active ? color : .secondary)
    }

    // MARK: - 2. 生成された議事録・書き起こし一覧

    private func generatedDocumentsSection(t: AppStrings) -> some View {
        let docs = storageManager.loadDocuments(for: project)
        return Group {
            if docs.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text(t.sectionDocuments)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
            } else {
                List {
                    ForEach(docs) { doc in
                        NavigationLink {
                            MarkdownDocumentView(
                                title: doc.title,
                                fileURL: doc.fileURL,
                                categoryBadge: doc.category.rawValue
                            )
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: iconForCategory(doc.category))
                                    .font(.title3)
                                    .foregroundStyle(colorForCategory(doc.category))
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(doc.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(doc.formattedDate)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private func iconForCategory(_ cat: ProjectDocument.DocumentCategory) -> String {
        switch cat {
        case .minutes: return "sparkles.rectangle.stack.fill"
        case .diarizedTranscript: return "person.2.wave.2.fill"
        case .transcript: return "doc.text.fill"
        case .context: return "info.circle.fill"
        }
    }

    private func colorForCategory(_ cat: ProjectDocument.DocumentCategory) -> Color {
        switch cat {
        case .minutes: return .green
        case .diarizedTranscript: return .purple
        case .transcript: return .blue
        case .context: return .orange
        }
    }

    // MARK: - 3. プロジェクトの概要・進捗状況（文脈ファイル）編集セクション

    private func projectContextEditorSection(t: AppStrings) -> some View {
        Form {
            Section {
                TextEditor(text: $overviewText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 160)
            } header: {
                HStack {
                    Text("overview.md")
                    Spacer()
                    if showingSavedBanner {
                        Text("✓")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.green)
                    }
                }
            }

            Section {
                TextEditor(text: $statusText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 160)
            } header: {
                Text("current_status.md")
            }

            Section {
                Button {
                    saveContextFiles()
                } label: {
                    Label(t.saveButton, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }

    private func reloadContextFiles() {
        overviewText = storageManager.readTextFile(at: project.overviewURL)
        statusText = storageManager.readTextFile(at: project.currentStatusURL)
    }

    private func saveContextFiles() {
        storageManager.saveTextFile(overviewText, to: project.overviewURL)
        storageManager.saveTextFile(statusText, to: project.currentStatusURL)
        withAnimation {
            showingSavedBanner = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showingSavedBanner = false
            }
        }
    }
}
