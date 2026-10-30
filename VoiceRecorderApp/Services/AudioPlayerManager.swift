import Foundation
import AVFoundation

/// 録音済み音声ファイルの再生・シーク・15秒スキップ・再生速度変更を管理するクラス（標準ボイスメモ準拠の再生体験）
@MainActor
final class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var playingURL: URL?
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackRate: Float = 1.0

    static let availableRates: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?

    func togglePlay(url: URL) {
        if playingURL == url, let player {
            if player.isPlaying {
                pause()
            } else {
                resume()
            }
            return
        }
        startPlayback(url: url)
    }

    func startPlayback(url: URL) {
        stop()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = self
            newPlayer.enableRate = true
            newPlayer.rate = playbackRate
            newPlayer.prepareToPlay()
            newPlayer.play()

            player = newPlayer
            playingURL = url
            duration = max(newPlayer.duration, 0.01)
            currentTime = 0
            isPlaying = true
            startTimer()
        } catch {
            stop()
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    func resume() {
        guard let player else { return }
        player.rate = playbackRate
        player.play()
        isPlaying = true
        startTimer()
    }

    func stop() {
        stopTimer()
        player?.stop()
        player = nil
        playingURL = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    /// 指定秒数へシーク
    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = max(0, min(player.duration, time))
        player.currentTime = clamped
        currentTime = clamped
    }

    /// 前後スキップ（例: -15秒 / +15秒）
    func skip(by delta: TimeInterval) {
        guard let player else { return }
        seek(to: player.currentTime + delta)
    }

    /// 再生速度を変更（0.75x 〜 2.0x）
    func setRate(_ rate: Float) {
        playbackRate = rate
        player?.rate = rate
    }

    func formatTime(_ time: TimeInterval) -> String {
        let total = max(0, Int(time.rounded()))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func startTimer() {
        stopTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                self.isPlaying = player.isPlaying
            }
        }
        if let progressTimer {
            RunLoop.main.add(progressTimer, forMode: .common)
        }
    }

    private func stopTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = 0
            self.stopTimer()
        }
    }
}

