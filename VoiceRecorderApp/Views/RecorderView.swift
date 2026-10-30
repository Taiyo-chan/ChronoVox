import SwiftUI

/// メイン録音画面（ChronoVox）：
/// - ストップウォッチのように大きく経過時間を表示
/// - 赤い録音ボタンで録音開始・終了
/// - 一時停止・再開、リアルタイム波形表示
/// - 録音を終了しても連続して別の音声ファイルを録り始めることが可能（区切って次へ録音 / 連続セッション一覧）
struct RecorderView: View {
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var recorderManager: AudioRecorderManager
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @EnvironmentObject private var storageManager: ProjectStorageManager

    @State private var showingTriageSheet = false

    var body: some View {
        let t = localization.t
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - 1. ステータスバッジ & 大型ストップウォッチタイマー表示
                VStack(spacing: 10) {
                    statusBadge(t: t)

                    // ストップウォッチ風大型タイマー
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(recorderManager.stopwatchMainText)
                            .font(.system(size: 64, weight: .bold, design: .monospaced))
                            .foregroundStyle(recorderManager.state == .recording ? Color.red : Color.primary)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)

                        Text(recorderManager.stopwatchSubsecondsText)
                            .font(.system(size: 32, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)

                    // MARK: - 2. リアルタイム波形ビュー
                    WaveformBarView(
                        samples: recorderManager.waveformSamples,
                        isRecording: recorderManager.state == .recording,
                        isPaused: recorderManager.state == .paused
                    )
                    .frame(height: 68)
                    .padding(.horizontal, 20)
                }
                .padding(.top, 12)
                .padding(.bottom, 16)

                // MARK: - 3. 録音コントロール（赤ボタン・一時停止・連続録音「次へ区切る」）
                recordingControlsSection(t: t)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .padding(.horizontal, 16)

                // MARK: - 4. 連続録音セッション一覧（録りためたファイル＆振り分け導線）
                sessionRecordingsSection(t: t)
                    .padding(.top, 12)
            }
            .navigationTitle(t.appTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Section(t.appLanguageLabel) {
                            ForEach(AppLanguage.allCases) { lang in
                                Button {
                                    localization.appLanguage = lang
                                } label: {
                                    HStack {
                                        Text(lang.displayName)
                                        if localization.appLanguage == lang {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                            Text(localization.appLanguage.rawValue.uppercased())
                                .font(.caption.weight(.bold))
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if !storageManager.unassignedRecordings.isEmpty || !recorderManager.currentSessionRecordings.isEmpty {
                        Button {
                            if recorderManager.state != .idle {
                                _ = recorderManager.finishCurrentRecording()
                                storageManager.reloadAll()
                            }
                            showingTriageSheet = true
                        } label: {
                            Label(t.tabTriage, systemImage: "folder.badge.plus")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
            .sheet(isPresented: $showingTriageSheet) {
                SessionTriageView()
            }
            .alert("Error", isPresented: Binding(
                get: { recorderManager.errorMessage != nil },
                set: { if !$0 { recorderManager.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { recorderManager.errorMessage = nil }
            } message: {
                Text(recorderManager.errorMessage ?? "")
            }
        }
    }

    // MARK: - Subviews

    private func statusBadge(t: AppStrings) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            Text(statusText(t: t))
                .font(.caption.weight(.bold))
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(statusColor.opacity(0.12), in: Capsule())
    }

    private var statusColor: Color {
        switch recorderManager.state {
        case .idle:
            return .secondary
        case .recording:
            return .red
        case .paused:
            return .orange
        }
    }

    private func statusText(t: AppStrings) -> String {
        switch recorderManager.state {
        case .idle:
            return recorderManager.currentSessionRecordings.isEmpty
                ? t.standbyBadge
                : t.standbySessionBadge(count: recorderManager.currentSessionRecordings.count)
        case .recording:
            return t.recordingBadge(take: recorderManager.currentSessionRecordings.count + 1)
        case .paused:
            return t.pausedBadge
        }
    }

    private func recordingControlsSection(t: AppStrings) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 32) {
                // 左ボタン：一時停止 / 再開
                Button {
                    if recorderManager.state == .recording {
                        recorderManager.pauseRecording()
                    } else if recorderManager.state == .paused {
                        recorderManager.resumeRecording()
                    }
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(Color(.tertiarySystemBackground))
                                .frame(width: 54, height: 54)
                            Image(systemName: recorderManager.state == .paused ? "play.fill" : "pause.fill")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(recorderManager.state == .idle ? Color.secondary.opacity(0.4) : Color.primary)
                        }
                        Text(recorderManager.state == .paused ? t.resumeButton : t.pauseButton)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(recorderManager.state == .idle)

                // 中央：赤い録音開始 / 1ファイル終了ボタン
                Button {
                    playerManager.stop()
                    if recorderManager.state == .idle {
                        recorderManager.startRecording(in: storageManager.stagingDirectoryURL)
                    } else {
                        _ = recorderManager.finishCurrentRecording()
                        storageManager.reloadAll()
                    }
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.25), lineWidth: 4)
                                .frame(width: 82, height: 82)

                            RoundedRectangle(
                                cornerRadius: recorderManager.state == .idle ? 35 : 10,
                                style: .continuous
                            )
                            .fill(Color.red)
                            .frame(
                                width: recorderManager.state == .idle ? 66 : 34,
                                height: recorderManager.state == .idle ? 66 : 34
                            )
                            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: recorderManager.state)
                        }
                        Text(recorderManager.state == .idle ? t.startRecordingButton : t.finishClipButton)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(recorderManager.state == .idle ? .red : .primary)
                    }
                }

                // 右ボタン：連続録音（現在のファイルを保存してすぐ次の録音を開始）
                Button {
                    if recorderManager.state != .idle {
                        recorderManager.splitAndStartNextRecording(in: storageManager.stagingDirectoryURL)
                        storageManager.reloadAll()
                    }
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(Color(.tertiarySystemBackground))
                                .frame(width: 54, height: 54)
                            Image(systemName: "forward.end.fill")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(recorderManager.state == .idle ? Color.secondary.opacity(0.4) : Color.blue)
                        }
                        Text(t.splitNextButton)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(recorderManager.state == .idle)
            }

            if recorderManager.state == .idle && !recorderManager.currentSessionRecordings.isEmpty {
                Text(t.continuousHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
    }

    private func sessionRecordingsSection(t: AppStrings) -> some View {
        let items = storageManager.unassignedRecordings
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(t.unassignedHeader(count: items.count), systemImage: "waveform.circle.fill")
                    .font(.subheadline.weight(.bold))
                Spacer()
                if !items.isEmpty {
                    Button {
                        if recorderManager.state != .idle {
                            _ = recorderManager.finishCurrentRecording()
                            storageManager.reloadAll()
                        }
                        showingTriageSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(t.finishSessionAndTriageButton)
                            Image(systemName: "arrow.right.circle.fill")
                        }
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                    }
                }
            }
            .padding(.horizontal, 20)

            if items.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "mic.badge.plus")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary.opacity(0.6))
                    Text(t.emptyRecordingsTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(t.emptyRecordingsSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
            } else {
                List {
                    ForEach(items) { item in
                        let fileURL = storageManager.audioFileURL(for: item)
                        HStack(spacing: 12) {
                            Button {
                                playerManager.togglePlay(url: fileURL)
                            } label: {
                                Image(systemName: (playerManager.playingURL == fileURL && playerManager.isPlaying) ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 30))
                                    .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                HStack(spacing: 8) {
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
                                showingTriageSheet = true
                            } label: {
                                Label(t.assignShortButton, systemImage: "folder.badge.plus")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                if playerManager.playingURL == fileURL {
                                    playerManager.stop()
                                }
                                recorderManager.removeFromCurrentSession(item)
                                storageManager.deleteRecording(item)
                            } label: {
                                Label(t.deleteButton, systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

/// リアルタイム音量波形コンポーネント
struct WaveformBarView: View {
    let samples: [CGFloat]
    let isRecording: Bool
    let isPaused: Bool

    var body: some View {
        GeometryReader { geo in
            let count = max(samples.count, 1)
            let spacing: CGFloat = 3
            let totalSpacing = spacing * CGFloat(count - 1)
            let barWidth = max(2, (geo.size.width - totalSpacing) / CGFloat(count))

            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor)
                        .frame(
                            width: barWidth,
                            height: max(4, geo.size.height * sample)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.05), value: samples)
        }
    }

    private var barColor: Color {
        if isRecording {
            return .red
        } else if isPaused {
            return .orange
        } else {
            return .secondary.opacity(0.35)
        }
    }
}
