import Foundation

/// プロジェクト格納後に音声ファイルに対して実行できる3つのAI処理モード
enum AIProcessingMode: String, CaseIterable, Identifiable {
    case transcription = "transcription"
    case speakerDiarization = "speaker_diarization"
    case meetingMinutes = "meeting_minutes"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transcription:
            return "書き起こし"
        case .speakerDiarization:
            return "人物ごとに書き起こし"
        case .meetingMinutes:
            return "議事録（要約）を作る"
        }
    }

    var subtitle: String {
        switch self {
        case .transcription:
            return "フィラーを除去し、読みやすく整形した全文書き起こしを作成します"
        case .speakerDiarization:
            return "発言者を識別し、誰が何を話したか人物ごとに分けて書き起こします"
        case .meetingMinutes:
            return "プロジェクトの概要・進捗状況・過去の記録を踏まえた文脈付き議事録を作成します"
        }
    }

    var iconName: String {
        switch self {
        case .transcription:
            return "doc.text"
        case .speakerDiarization:
            return "person.2.wave.2"
        case .meetingMinutes:
            return "sparkles.rectangle.stack"
        }
    }

    var outputFileSuffix: String {
        switch self {
        case .transcription:
            return "_transcript.md"
        case .speakerDiarization:
            return "_diarized.md"
        case .meetingMinutes:
            return "_minutes.md"
        }
    }
}

