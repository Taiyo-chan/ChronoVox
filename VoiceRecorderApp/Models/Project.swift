import Foundation

/// プロジェクトディレクトリ内のマークダウン文書（書き起こし・議事録など）を表すモデル
struct ProjectDocument: Identifiable, Hashable {
    var id: String { fileURL.path }
    let title: String
    let fileName: String
    let fileURL: URL
    let updatedAt: Date
    let category: DocumentCategory

    enum DocumentCategory: String, CaseIterable {
        case transcript = "書き起こし"
        case diarizedTranscript = "人物別書き起こし"
        case minutes = "議事録"
        case context = "プロジェクト文脈"
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: updatedAt)
    }
}

/// プロジェクトディレクトリ1つを表すモデル
/// ディレクトリ構成:
/// Projects/<name>/
///   ├── overview.md         (プロジェクトの概要・参加者など)
///   ├── current_status.md   (現在の進捗状況)
///   ├── audio/              (格納された音声ファイル .m4a)
///   ├── transcripts/        (書き起こし・人物別書き起こし .md)
///   └── minutes/            (過去の文脈を踏まえた議事録 .md)
struct Project: Identifiable, Hashable {
    var id: String { name }
    var name: String
    let directoryURL: URL
    let createdAt: Date

    var overviewURL: URL {
        directoryURL.appendingPathComponent("overview.md")
    }

    var currentStatusURL: URL {
        directoryURL.appendingPathComponent("current_status.md")
    }

    var audioDirectoryURL: URL {
        directoryURL.appendingPathComponent("audio", isDirectory: true)
    }

    var transcriptsDirectoryURL: URL {
        directoryURL.appendingPathComponent("transcripts", isDirectory: true)
    }

    var minutesDirectoryURL: URL {
        directoryURL.appendingPathComponent("minutes", isDirectory: true)
    }
}

