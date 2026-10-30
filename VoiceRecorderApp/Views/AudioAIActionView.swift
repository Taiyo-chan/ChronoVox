import SwiftUI

/// プロジェクトディレクトリ格納後の音声ファイル詳細＆AI処理選択画面（6言語対応 + Automatic/個別言語指定対応）
struct AudioAIActionView: View {
    let item: RecordingItem
    let project: Project

    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var storageManager: ProjectStorageManager
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @EnvironmentObject private var geminiService: GeminiService

    @State private var selectedMode: AIProcessingMode = .meetingMinutes
    @State private var outputText: String = ""
    @State private var errorMessage: String?
    @State private var showingContextPreview = false
    @State private var statusUpdatedBanner = false

    private var audioURL: URL {
        storageManager.audioFileURL(for: item)
    }

    var body: some View {
        let t = localization.t
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // MARK: - 1. オーディオプレイヤーカード
                audioPlayerCard

                // MARK: - 2. 3つのAI処理選択カード（書き起こし / 人物ごと / 文脈議事録）
                aiModeSelectorSection(t: t)

                // MARK: - 3. 文字起こし・出力言語の選択（Automatic / 6言語指定）＆ 実行ボタン
                executeButtonSection(t: t)

                // MARK: - 4. 生成結果ビューア＆エディタ
                if !outputText.isEmpty {
                    resultOutputSection(t: t)
                }
            }
            .padding(16)
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadExistingOutput(for: selectedMode)
        }
        .onChange(of: selectedMode) { _, newMode in
            loadExistingOutput(for: newMode)
        }
        .sheet(isPresented: $showingContextPreview) {
            contextPreviewSheet(t: t)
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - 1. Audio Player Card

    private var audioPlayerCard: some View {
        let isPlayingThis = (playerManager.playingURL == audioURL)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Label(project.name, systemImage: "folder.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                    Text(item.fileName)
                        .font(.headline)
                    Text("\(item.formattedDate) • \(item.formattedDuration)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ShareLink(item: audioURL) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .padding(8)
                        .background(Color(.tertiarySystemBackground), in: Circle())
                }
            }

            if isPlayingThis {
                Slider(
                    value: Binding(
                        get: { playerManager.currentTime },
                        set: { playerManager.seek(to: $0) }
                    ),
                    in: 0...max(playerManager.duration, 0.01)
                )
            }

            HStack {
                Text(isPlayingThis ? playerManager.formatTime(playerManager.currentTime) : "00:00")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 24) {
                    Button {
                        if !isPlayingThis { playerManager.startPlayback(url: audioURL) }
                        playerManager.skip(by: -15)
                    } label: {
                        Image(systemName: "gobackward.15")
                            .font(.title3)
                    }

                    Button {
                        playerManager.togglePlay(url: audioURL)
                    } label: {
                        Image(systemName: (isPlayingThis && playerManager.isPlaying) ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.accentColor)
                    }

                    Button {
                        if !isPlayingThis { playerManager.startPlayback(url: audioURL) }
                        playerManager.skip(by: 15)
                    } label: {
                        Image(systemName: "goforward.15")
                            .font(.title3)
                    }
                }

                Spacer()

                Menu {
                    ForEach(AudioPlayerManager.availableRates, id: \.self) { rate in
                        Button {
                            playerManager.setRate(rate)
                        } label: {
                            HStack {
                                Text(String(format: "%.2gx", rate))
                                if playerManager.playbackRate == rate {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Text(String(format: "%.2gx", playerManager.playbackRate))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.tertiarySystemBackground), in: Capsule())
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - 2. AI Processing Mode Selector

    private func aiModeSelectorSection(t: AppStrings) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t.selectAIActionHeader)
                .font(.subheadline.weight(.bold))

            ForEach(AIProcessingMode.allCases) { mode in
                let isSelected = (selectedMode == mode)
                let docURL = storageManager.existingDocumentURL(for: item, project: project, mode: mode)
                let alreadyExists = FileManager.default.fileExists(atPath: docURL.path)

                Button {
                    selectedMode = mode
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(isSelected ? Color.accentColor : Color(.tertiarySystemBackground))
                                .frame(width: 38, height: 38)
                            Image(systemName: mode.iconName)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(isSelected ? Color.white : Color.primary)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("・\(t.modeTitle(mode))")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if alreadyExists {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.green)
                                }
                            }
                            Text(t.modeSubtitle(mode))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(.secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 3. Language Selector & Execute Button

    private func executeButtonSection(t: AppStrings) -> some View {
        let pastAudioCount = max(0, storageManager.loadAudioFiles(for: project).count - 1)
        let pastDocsCount = storageManager.loadDocuments(for: project).count

        return VStack(alignment: .leading, spacing: 10) {
            // 音声認識・出力言語のセレクター（Automatic または 6言語から選択）
            HStack {
                Label(t.audioLanguagePickerLabel, systemImage: "globe")
                    .font(.caption.weight(.bold))
                Spacer()
                Picker(t.audioLanguagePickerLabel, selection: $localization.transcriptionLanguage) {
                    ForEach(TranscriptionLanguageOption.allCases) { option in
                        Text(option.displayName(in: localization.appLanguage)).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

            if selectedMode == .meetingMinutes || selectedMode == .speakerDiarization {
                HStack {
                    Image(systemName: "folder.badge.gearshape")
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(t.sectionContext): \(project.name)")
                            .font(.caption.weight(.bold))
                        Text("overview.md • current_status.md • Audio(\(pastAudioCount)) • Docs(\(pastDocsCount))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        showingContextPreview = true
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .padding(10)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }

            Button {
                runSelectedAIOperation()
            } label: {
                HStack(spacing: 10) {
                    if geminiService.isProcessing {
                        ProgressView()
                            .tint(.white)
                        Text(geminiService.statusMessage.isEmpty ? "Processing..." : geminiService.statusMessage)
                            .font(.subheadline.weight(.bold))
                    } else {
                        Image(systemName: "sparkles")
                        Text(t.modeTitle(selectedMode))
                            .font(.subheadline.weight(.bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(geminiService.isProcessing ? Color.secondary : Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
            }
            .disabled(geminiService.isProcessing)
        }
    }

    // MARK: - 4. Output Viewer & Editor

    private func resultOutputSection(t: AppStrings) -> some View {
        let targetURL = storageManager.existingDocumentURL(for: item, project: project, mode: selectedMode)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(t.modeTitle(selectedMode), systemImage: "doc.richtext")
                    .font(.headline)
                Spacer()
                ShareLink(item: outputText) {
                    Label(t.shareButton, systemImage: "square.and.arrow.up")
                        .font(.caption.weight(.bold))
                }
                Button {
                    storageManager.saveTextFile(outputText, to: targetURL)
                } label: {
                    Label(t.saveButton, systemImage: "square.and.arrow.down")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.bordered)
            }

            Text("Projects/\(project.name)/\(selectedMode == .meetingMinutes ? "minutes" : "transcripts")/\(targetURL.lastPathComponent)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            TextEditor(text: $outputText)
                .font(.system(.subheadline, design: .monospaced))
                .frame(minHeight: 300)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                )

            if selectedMode == .meetingMinutes {
                Button {
                    updateProjectCurrentStatusFromMinutes()
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath.doc.on.clipboard")
                        Text(statusUpdatedBanner ? "✓ Updated current_status.md" : "Update current_status.md")
                    }
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(statusUpdatedBanner ? Color.green.opacity(0.18) : Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(statusUpdatedBanner ? .green : .orange)
                }
                .disabled(geminiService.isProcessing)
            }
        }
        .padding(.top, 6)
    }

    // MARK: - Context Preview Sheet

    private func contextPreviewSheet(t: AppStrings) -> some View {
        let contextString = storageManager.buildHistoricalContext(
            for: project,
            excludingAudioFileName: item.fileName
        )
        return NavigationStack {
            ScrollView {
                Text(contextString)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .navigationTitle(t.sectionContext)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t.closeButton) {
                        showingContextPreview = false
                    }
                }
            }
        }
    }

    // MARK: - Logic

    private func loadExistingOutput(for mode: AIProcessingMode) {
        let url = storageManager.existingDocumentURL(for: item, project: project, mode: mode)
        if FileManager.default.fileExists(atPath: url.path) {
            outputText = storageManager.readTextFile(at: url)
        } else {
            outputText = ""
        }
    }

    private func runSelectedAIOperation() {
        Task {
            do {
                let result = try await geminiService.processAudio(
                    audioURL: audioURL,
                    item: item,
                    project: project,
                    mode: selectedMode,
                    languageOption: localization.transcriptionLanguage,
                    uiLanguage: localization.appLanguage,
                    storage: storageManager
                )
                outputText = result
                storageManager.saveAIResult(
                    content: result,
                    for: item,
                    in: project,
                    mode: selectedMode
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func updateProjectCurrentStatusFromMinutes() {
        Task {
            do {
                let targetLang = localization.transcriptionLanguage.specificLanguage ?? localization.appLanguage
                let newStatus = try await geminiService.generateUpdatedCurrentStatus(
                    project: project,
                    latestMinutes: outputText,
                    targetLanguage: targetLang,
                    storage: storageManager
                )
                storageManager.saveTextFile(newStatus, to: project.currentStatusURL)
                statusUpdatedBanner = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    statusUpdatedBanner = false
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
