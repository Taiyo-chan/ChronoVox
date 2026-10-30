import Foundation

/// Gemini Interactions API (`https://generativelanguage.googleapis.com/v1beta/interactions`) を利用して
/// 1. 書き起こし (`gemini-3.5-transcribe` / `gemini-3.8-flash`) — Automatic または 6言語指定対応
/// 2. 人物ごとに書き起こし (`gemini-3.5-transcribe` speaker diarization + `gemini-3.8-flash` 整形)
/// 3. 過去の文脈を持った議事録作成 (`gemini-3.8-flash` / `gemini-4-argon`)
/// を行うサービスクラス
@MainActor
final class GeminiService: ObservableObject {
    enum ReasoningModel: String, CaseIterable, Identifiable {
        case gemini38Flash = "gemini-3.8-flash"
        case gemini4Argon = "gemini-4-argon"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .gemini38Flash:
                return "Gemini 3.8 Flash"
            case .gemini4Argon:
                return "Gemini 4 Argon"
            }
        }
    }

    @Published var apiKey: String {
        didSet {
            UserDefaults.standard.set(apiKey, forKey: Self.apiKeyStorageKey)
        }
    }

    @Published var selectedModel: ReasoningModel {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: Self.modelStorageKey)
        }
    }

    @Published var isProcessing: Bool = false
    @Published var statusMessage: String = ""

    private static let apiKeyStorageKey = "GEMINI_API_KEY"
    private static let modelStorageKey = "GEMINI_REASONING_MODEL"
    private let interactionsEndpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions")!

    init() {
        let savedKey = UserDefaults.standard.string(forKey: Self.apiKeyStorageKey)
            ?? ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
            ?? ""
        self.apiKey = savedKey

        let savedModelRaw = UserDefaults.standard.string(forKey: Self.modelStorageKey) ?? ReasoningModel.gemini38Flash.rawValue
        self.selectedModel = ReasoningModel(rawValue: savedModelRaw) ?? .gemini38Flash
    }

    var hasValidAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Public AI Operations

    /// 音声ファイルに対して指定されたモード（書き起こし / 人物ごと書き起こし / 文脈付き議事録）と指定言語で処理を実行する
    func processAudio(
        audioURL: URL,
        item: RecordingItem,
        project: Project,
        mode: AIProcessingMode,
        languageOption: TranscriptionLanguageOption,
        uiLanguage: AppLanguage,
        storage: ProjectStorageManager
    ) async throws -> String {
        guard hasValidAPIKey else {
            throw NSError(
                domain: "GeminiService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: uiLanguage == .japanese
                    ? "設定タブから Gemini API キーを設定してください。"
                    : "Please configure your Gemini API key in the Settings tab."]
            )
        }

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw NSError(
                domain: "GeminiService",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Audio file not found: \(audioURL.lastPathComponent)"]
            )
        }

        isProcessing = true
        defer {
            isProcessing = false
            statusMessage = ""
        }

        statusMessage = "Loading audio..."
        let audioData = try Data(contentsOf: audioURL)
        let base64Audio = audioData.base64EncodedString()
        let mimeType = mimeTypeForExtension(audioURL.pathExtension)

        let targetOutputLang = languageOption.specificLanguage ?? uiLanguage

        switch mode {
        case .transcription:
            statusMessage = "Gemini 3.5 Transcribe (\(languageOption.displayName(in: uiLanguage)))..."
            return try await runSmartTranscription(
                base64Audio: base64Audio,
                mimeType: mimeType,
                item: item,
                project: project,
                languageOption: languageOption,
                targetOutputLang: targetOutputLang
            )

        case .speakerDiarization:
            statusMessage = "Speaker Diarization (\(languageOption.displayName(in: uiLanguage)))..."
            let overviewText = storage.readTextFile(at: project.overviewURL)
            return try await runSpeakerDiarizedTranscription(
                base64Audio: base64Audio,
                mimeType: mimeType,
                item: item,
                project: project,
                projectOverview: overviewText,
                languageOption: languageOption,
                targetOutputLang: targetOutputLang
            )

        case .meetingMinutes:
            statusMessage = "Generating Context-Aware Minutes (\(targetOutputLang.shortName))..."
            let historicalContext = storage.buildHistoricalContext(
                for: project,
                excludingAudioFileName: item.fileName
            )
            return try await runContextAwareMeetingMinutes(
                base64Audio: base64Audio,
                mimeType: mimeType,
                item: item,
                project: project,
                historicalContext: historicalContext,
                languageOption: languageOption,
                targetOutputLang: targetOutputLang
            )
        }
    }

    /// 生成された議事録をもとに、プロジェクトの `current_status.md` の更新案を生成する
    func generateUpdatedCurrentStatus(
        project: Project,
        latestMinutes: String,
        targetLanguage: AppLanguage,
        storage: ProjectStorageManager
    ) async throws -> String {
        guard hasValidAPIKey else {
            throw NSError(domain: "GeminiService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Gemini API Key missing."])
        }

        isProcessing = true
        statusMessage = "Updating current_status.md..."
        defer {
            isProcessing = false
            statusMessage = ""
        }

        let currentStatus = storage.readTextFile(at: project.currentStatusURL)
        let overview = storage.readTextFile(at: project.overviewURL)

        let prompt = """
        You are the Project Manager and Secretary for project "\(project.name)".
        Based on the Project Overview, the previous `current_status.md`, and the newly generated Meeting Minutes below,
        output the updated full Markdown text for `current_status.md` in **\(targetLanguage.promptLanguageName)**.

        [Project Overview]
        \(overview)

        [Previous current_status.md]
        \(currentStatus)

        [Latest Meeting Minutes]
        \(latestMinutes)
        """

        let body: [String: Any] = [
            "model": selectedModel.rawValue,
            "system_instruction": "Output only the updated Markdown content for current_status.md in \(targetLanguage.promptLanguageName).",
            "input": [
                ["type": "text", "text": prompt]
            ]
        ]

        return try await sendInteractionsRequest(body: body)
    }

    // MARK: - Mode Implementations

    /// ① 通常の書き起こし (`gemini-3.5-transcribe` Smart mode + `language_codes` 指定対応)
    private func runSmartTranscription(
        base64Audio: String,
        mimeType: String,
        item: RecordingItem,
        project: Project,
        languageOption: TranscriptionLanguageOption,
        targetOutputLang: AppLanguage
    ) async throws -> String {
        let transcribeBody: [String: Any] = [
            "model": "models/gemini-3.5-transcribe",
            "input": [
                [
                    "type": "audio",
                    "data": base64Audio,
                    "mime_type": mimeType
                ]
            ],
            "generation_config": [
                "transcription_config": [
                    "mode": "smart",
                    "language_codes": languageOption.bcp47Codes
                ]
            ]
        ]

        let langBadge = languageOption == .automatic
            ? "Automatic"
            : "\(targetOutputLang.shortName) (\(targetOutputLang.bcp47Code))"

        do {
            let rawTranscript = try await sendInteractionsRequest(body: transcribeBody)
            return """
            # 📝 Transcription: \(item.title)

            - **Project**: \(project.name)
            - **Audio File**: `\(item.fileName)`
            - **Recorded**: \(item.formattedDate) (\(item.formattedDuration))
            - **Language Mode**: \(langBadge)
            - **Model**: `gemini-3.5-transcribe` (Smart Mode)

            ---

            \(rawTranscript)
            """
        } catch {
            let langInstruction = languageOption == .automatic
                ? "Detect the spoken language automatically and transcribe in that language (or \(targetOutputLang.promptLanguageName) if requested)."
                : "The spoken language is \(targetOutputLang.promptLanguageName) (\(targetOutputLang.bcp47Code)). Transcribe accurately in \(targetOutputLang.promptLanguageName)."

            let fallbackBody: [String: Any] = [
                "model": selectedModel.rawValue,
                "input": [
                    [
                        "type": "audio",
                        "data": base64Audio,
                        "mime_type": mimeType
                    ],
                    [
                        "type": "text",
                        "text": "Generate a clean, full transcription of this audio file with filler words removed and structured into readable paragraphs. \(langInstruction)"
                    ]
                ]
            ]
            let fallbackTranscript = try await sendInteractionsRequest(body: fallbackBody)
            return """
            # 📝 Transcription: \(item.title)

            - **Project**: \(project.name)
            - **Audio File**: `\(item.fileName)`
            - **Recorded**: \(item.formattedDate) (\(item.formattedDuration))
            - **Language Mode**: \(langBadge)

            ---

            \(fallbackTranscript)
            """
        }
    }

    /// ② 人物ごとに書き起こし (`gemini-3.5-transcribe` diarization_mode: "speaker" + `language_codes` 対応)
    private func runSpeakerDiarizedTranscription(
        base64Audio: String,
        mimeType: String,
        item: RecordingItem,
        project: Project,
        projectOverview: String,
        languageOption: TranscriptionLanguageOption,
        targetOutputLang: AppLanguage
    ) async throws -> String {
        var rawDiarizedText: String?

        let diarizationBody: [String: Any] = [
            "model": "models/gemini-3.5-transcribe",
            "input": [
                [
                    "type": "audio",
                    "data": base64Audio,
                    "mime_type": mimeType
                ]
            ],
            "generation_config": [
                "transcription_config": [
                    "language_codes": languageOption.bcp47Codes,
                    "mode": [
                        "type": "verbatim",
                        "diarization_mode": "speaker"
                    ]
                ]
            ]
        ]

        if let result = try? await sendInteractionsRequest(body: diarizationBody), !result.isEmpty {
            rawDiarizedText = result
        }

        let langRequirement = languageOption == .automatic
            ? "Keep the spoken language of the transcript (or format labels in \(targetOutputLang.promptLanguageName))."
            : "Ensure the speaker-separated transcript is output in **\(targetOutputLang.promptLanguageName)**."

        let prompt: String
        if let rawDiarizedText {
            prompt = """
            Below is a raw speaker-diarized transcription and the project's `overview.md`.
            Replace generic speaker tags (`spk_1`, `spk_2`, etc.) with participant names/roles if they can be inferred from `overview.md`, or clear speaker labels (e.g. Speaker A / Speaker B) in \(targetOutputLang.promptLanguageName).
            Format the conversation cleanly in Markdown by speaker turn.
            \(langRequirement)

            [Project Overview (overview.md)]
            \(projectOverview)

            [Raw Speaker-Diarized Transcript]
            \(rawDiarizedText)
            """
        } else {
            prompt = """
            Listen to this audio file and generate a complete **speaker-separated (diarized) transcription**.
            Identify each distinct speaker (matching participant names from `overview.md` when possible, or labeling as Speaker A, Speaker B, etc.) and format their statements chronologically in Markdown.
            \(langRequirement)

            [Project Overview (overview.md)]
            \(projectOverview)
            """
        }

        var inputItems: [[String: Any]] = [
            [
                "type": "audio",
                "data": base64Audio,
                "mime_type": mimeType
            ],
            [
                "type": "text",
                "text": prompt
            ]
        ]
        if rawDiarizedText != nil {
            inputItems = [
                [
                    "type": "text",
                    "text": prompt
                ]
            ]
        }

        let formatBody: [String: Any] = [
            "model": selectedModel.rawValue,
            "input": inputItems
        ]

        let langBadge = languageOption == .automatic
            ? "Automatic"
            : "\(targetOutputLang.shortName) (\(targetOutputLang.bcp47Code))"

        let formattedDiarization = try await sendInteractionsRequest(body: formatBody)
        return """
        # 👥 Speaker-Separated Transcript: \(item.title)

        - **Project**: \(project.name)
        - **Audio File**: `\(item.fileName)`
        - **Recorded**: \(item.formattedDate) (\(item.formattedDuration))
        - **Language Mode**: \(langBadge)

        ---

        \(formattedDiarization)
        """
    }

    /// ③ プロジェクトの概要・進捗・過去ログを踏まえた「文脈付き議事録」生成
    private func runContextAwareMeetingMinutes(
        base64Audio: String,
        mimeType: String,
        item: RecordingItem,
        project: Project,
        historicalContext: String,
        languageOption: TranscriptionLanguageOption,
        targetOutputLang: AppLanguage
    ) async throws -> String {
        let systemInstruction = """
        You are the dedicated Project Manager and Secretary for project "\(project.name)".
        Analyze the audio recording while referencing the project's `overview.md`, `current_status.md`, and past audio/minutes history.
        Write the entire meeting minutes output in **\(targetOutputLang.promptLanguageName)**.
        """

        let audioLangHint = languageOption == .automatic
            ? "The audio language should be detected automatically."
            : "The audio language is \(languageOption.specificLanguage?.promptLanguageName ?? targetOutputLang.promptLanguageName)."

        let prompt = """
        \(audioLangHint)
        Using the [Project Historical Context (Overview, Current Status, Past Logs)] below, analyze the attached audio recording and generate **Context-Aware Meeting Minutes** in Markdown format written in **\(targetOutputLang.promptLanguageName)**.

        ### Required Sections (translate headings naturally into \(targetOutputLang.promptLanguageName)):
        1. **📌 Executive Summary**
        2. **🔗 Connection & Progress Since Previous Context (`current_status.md` & Past Minutes)**
        3. **💬 Key Discussion Points (by topic & speaker)**
        4. **✅ Decisions Made**
        5. **🚀 Next Actions & TODOs (Owner / Deadline)**
        6. **📊 Suggested Updates to `current_status.md`**

        ---

        # [Project Historical Context]
        \(historicalContext)
        """

        let body: [String: Any] = [
            "model": selectedModel.rawValue,
            "system_instruction": systemInstruction,
            "input": [
                [
                    "type": "audio",
                    "data": base64Audio,
                    "mime_type": mimeType
                ],
                [
                    "type": "text",
                    "text": prompt
                ]
            ]
        ]

        let generatedMinutes = try await sendInteractionsRequest(body: body)
        return """
        # 📋 Context-Aware Meeting Minutes: \(item.title)

        - **Project**: \(project.name)
        - **Audio File**: `\(item.fileName)`
        - **Recorded**: \(item.formattedDate) (\(item.formattedDuration))
        - **Language**: \(targetOutputLang.shortName)
        - **Model**: `\(selectedModel.rawValue)`

        ---

        \(generatedMinutes)
        """
    }

    // MARK: - Networking (Gemini Interactions API v1beta)

    private func sendInteractionsRequest(body: [String: Any]) async throws -> String {
        var request = URLRequest(url: interactionsEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "GeminiService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid server response."])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw NSError(
                domain: "GeminiService",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Gemini API Error (\(httpResponse.statusCode)): \(errorBody)"]
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "GeminiService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse JSON response."])
        }

        if let outputText = json["output_text"] as? String, !outputText.isEmpty {
            return outputText
        }

        if let steps = json["steps"] as? [[String: Any]] {
            var collectedTexts: [String] = []
            for step in steps where (step["type"] as? String) == "model_output" {
                if let contents = step["content"] as? [[String: Any]] {
                    for content in contents where (content["type"] as? String) == "text" {
                        if let text = content["text"] as? String {
                            collectedTexts.append(text)
                        }
                    }
                }
            }
            if !collectedTexts.isEmpty {
                return collectedTexts.joined(separator: "\n")
            }
        }

        throw NSError(
            domain: "GeminiService",
            code: -3,
            userInfo: [NSLocalizedDescriptionKey: "No text output returned from model."]
        )
    }

    private func mimeTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "m4a", "mp4":
            return "audio/mp4"
        case "mp3":
            return "audio/mp3"
        case "wav":
            return "audio/wav"
        case "aac":
            return "audio/aac"
        default:
            return "audio/mp4"
        }
    }
}
