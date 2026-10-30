import Foundation

/// 録音された音声ファイル1件を表すモデル
struct RecordingItem: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var fileName: String
    let createdAt: Date
    var duration: TimeInterval
    /// 格納先のプロジェクト名（未振り分けの場合は nil）
    var projectName: String?

    init(
        id: UUID = UUID(),
        title: String,
        fileName: String,
        createdAt: Date = Date(),
        duration: TimeInterval,
        projectName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.createdAt = createdAt
        self.duration = duration
        self.projectName = projectName
    }

    /// ストップウォッチ・一覧表示用のフォーマット済み時間（例: 02:15）
    var formattedDuration: String {
        let totalSeconds = Int(duration.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: createdAt)
    }
}

