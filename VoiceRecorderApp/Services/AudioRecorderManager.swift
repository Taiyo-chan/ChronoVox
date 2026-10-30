import Foundation
import AVFoundation

/// 音声録音・大型ストップウォッチタイマー・リアルタイム波形・連続録音セッションを管理するクラス
@MainActor
final class AudioRecorderManager: NSObject, ObservableObject, AVAudioRecorderDelegate {
    enum RecordingState {
        case idle
        case recording
        case paused
    }

    @Published var state: RecordingState = .idle
    @Published var elapsedTime: TimeInterval = 0
    /// リアルタイム波形表示用の正規化された音量バー配列（0.05 ... 1.0）
    @Published var waveformSamples: [CGFloat] = Array(repeating: 0.08, count: 44)
    /// 今回の連続録音セッションで録りためた音声ファイル一覧
    @Published var currentSessionRecordings: [RecordingItem] = []
    @Published var permissionGranted: Bool = false
    @Published var errorMessage: String?

    private var audioRecorder: AVAudioRecorder?
    private var currentRecordingURL: URL?
    private var currentRecordingStartDate: Date?
    private var meterTimer: Timer?
    private var sessionTakeCounter: Int = 1

    static let barCount = 44

    override init() {
        super.init()
        checkMicrophonePermission()
    }

    /// ストップウォッチ風の大型経過時間表示（MM:SS.cc または H:MM:SS.cc）
    var stopwatchMainText: String {
        let totalCentiseconds = Int((elapsedTime * 100).rounded())
        let hours = totalCentiseconds / 360000
        let minutes = (totalCentiseconds % 360000) / 6000
        let seconds = (totalCentiseconds % 6000) / 100
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    /// 1/100秒（センチ秒）部分の表示（例: ".42"）
    var stopwatchSubsecondsText: String {
        let totalCentiseconds = Int((elapsedTime * 100).rounded())
        let centiseconds = totalCentiseconds % 100
        return String(format: ".%02d", centiseconds)
    }

    func checkMicrophonePermission() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            permissionGranted = true
        case .denied:
            permissionGranted = false
        case .undetermined:
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                Task { @MainActor in
                    self?.permissionGranted = granted
                }
            }
        @unknown default:
            permissionGranted = false
        }
    }

    /// 録音を開始する（StagingRecordings ディレクトリに新規 .m4a ファイルを作成）
    func startRecording(in stagingDirectory: URL) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]
            )
            try session.setActive(true)
        } catch {
            errorMessage = "オーディオセッションの設定に失敗しました: \(error.localizedDescription)"
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let takeNumber = currentSessionRecordings.count + 1
        let fileName = String(format: "録音_%@_Take%02d.m4a", timestamp, takeNumber)
        let fileURL = stagingDirectory.appendingPathComponent(fileName)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()
            guard recorder.record() else {
                errorMessage = "録音の開始に失敗しました。マイク権限を確認してください。"
                return
            }

            audioRecorder = recorder
            currentRecordingURL = fileURL
            currentRecordingStartDate = Date()
            elapsedTime = 0
            waveformSamples = Array(repeating: 0.08, count: Self.barCount)
            state = .recording
            startMeterTimer()
        } catch {
            errorMessage = "録音ファイルの初期化に失敗しました: \(error.localizedDescription)"
        }
    }

    /// 録音を一時停止する
    func pauseRecording() {
        guard state == .recording, let recorder = audioRecorder else { return }
        recorder.pause()
        elapsedTime = recorder.currentTime
        state = .paused
        stopMeterTimer()
    }

    /// 一時停止中の録音を再開する
    func resumeRecording() {
        guard state == .paused, let recorder = audioRecorder else { return }
        if recorder.record() {
            state = .recording
            startMeterTimer()
        }
    }

    /// 現在の音声ファイルの録音を完了し、セッション一覧（currentSessionRecordings）に追加する。
    /// 画面はそのまま次の録音を開始できる待機状態になる。
    @discardableResult
    func finishCurrentRecording() -> RecordingItem? {
        guard state != .idle, let recorder = audioRecorder, let url = currentRecordingURL else {
            return nil
        }

        let finalDuration = max(recorder.currentTime, elapsedTime)
        recorder.stop()
        stopMeterTimer()

        let createdAt = currentRecordingStartDate ?? Date()
        let item = RecordingItem(
            title: url.deletingPathExtension().lastPathComponent,
            fileName: url.lastPathComponent,
            createdAt: createdAt,
            duration: finalDuration,
            projectName: nil
        )

        currentSessionRecordings.insert(item, at: 0)
        audioRecorder = nil
        currentRecordingURL = nil
        currentRecordingStartDate = nil
        elapsedTime = 0
        state = .idle
        sessionTakeCounter += 1

        return item
    }

    /// 連続録音機能：現在の録音ファイルを保存して確定し、途切れなく即座に次の新しい音声ファイルの録音を開始する
    func splitAndStartNextRecording(in stagingDirectory: URL) {
        _ = finishCurrentRecording()
        startRecording(in: stagingDirectory)
    }

    /// セッションリストから削除済みのアイテムを除外する
    func removeFromCurrentSession(_ item: RecordingItem) {
        currentSessionRecordings.removeAll { $0.id == item.id || $0.fileName == item.fileName }
    }

    /// 一連の連続録音セッションをリセットする
    func clearCurrentSessionList() {
        currentSessionRecordings.removeAll()
        sessionTakeCounter = 1
    }

    // MARK: - Timer & Waveform Metering

    private func startMeterTimer() {
        stopMeterTimer()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMeters()
            }
        }
        if let meterTimer {
            RunLoop.main.add(meterTimer, forMode: .common)
        }
    }

    private func stopMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func updateMeters() {
        guard state == .recording, let recorder = audioRecorder else { return }
        recorder.updateMeters()
        elapsedTime = recorder.currentTime

        // -55dB ... 0dB を 0.06 ... 1.0 に正規化
        let power = recorder.averagePower(forChannel: 0)
        let minDb: Float = -55.0
        let clamped = max(minDb, min(0.0, power))
        let normalized = CGFloat((clamped - minDb) / (-minDb))
        let barHeight = max(0.06, min(1.0, pow(normalized, 1.3)))

        var next = waveformSamples
        if !next.isEmpty {
            next.removeFirst()
        }
        next.append(barHeight)
        waveformSamples = next
    }
}
