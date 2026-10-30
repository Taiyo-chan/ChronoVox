import Foundation
import AVFoundation

/// プロジェクトディレクトリ（Documents/Projects/）および未整理録音（Documents/StagingRecordings/）を管理するサービス
/// Info.plist の UIFileSharingEnabled / LSSupportsOpeningDocumentsInPlace により、
/// iOS標準の「ファイル」アプリやMacのFinderから直接フォルダ・Markdownを参照・編集可能。
@MainActor
final class ProjectStorageManager: ObservableObject {
    @Published var projects: [Project] = []
    @Published var unassignedRecordings: [RecordingItem] = []
    @Published var lastErrorMessage: String?

    private let fileManager = FileManager.default

    /// アプリの Documents ディレクトリ
    var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// プロジェクト一覧のルートディレクトリ (`Documents/Projects/`)
    var projectsRootURL: URL {
        documentsDirectory.appendingPathComponent("Projects", isDirectory: true)
    }

    /// 録音直後（プロジェクト振り分け前）の音声ファイル一時保管ディレクトリ (`Documents/StagingRecordings/`)
    var stagingDirectoryURL: URL {
        documentsDirectory.appendingPathComponent("StagingRecordings", isDirectory: true)
    }

    init() {
        ensureBaseDirectoriesExist()
        reloadAll()
    }

    /// ベースディレクトリを作成し、初回起動時はサンプルプロジェクトを用意する
    func ensureBaseDirectoriesExist() {
        do {
            if !fileManager.fileExists(atPath: projectsRootURL.path) {
                try fileManager.createDirectory(at: projectsRootURL, withIntermediateDirectories: true)
            }
            if !fileManager.fileExists(atPath: stagingDirectoryURL.path) {
                try fileManager.createDirectory(at: stagingDirectoryURL, withIntermediateDirectories: true)
            }
        } catch {
            lastErrorMessage = "ディレクトリの初期化に失敗しました: \(error.localizedDescription)"
        }
    }

    /// プロジェクト一覧と未振り分け録音一覧を再読み込みする
    func reloadAll() {
        loadProjects()
        loadUnassignedRecordings()
    }

    // MARK: - Projects Management

    func loadProjects() {
        ensureBaseDirectoriesExist()
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: projectsRootURL,
                includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey],
                options: [.skipsHiddenFiles]
            )
            var loaded: [Project] = []
            for url in contents {
                let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .creationDateKey])
                if resourceValues.isDirectory == true {
                    let project = Project(
                        name: url.lastPathComponent,
                        directoryURL: url,
                        createdAt: resourceValues.creationDate ?? Date()
                    )
                    ensureProjectSubdirectories(for: project)
                    loaded.append(project)
                }
            }
            projects = loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch {
            lastErrorMessage = "プロジェクト一覧の読み込みに失敗しました: \(error.localizedDescription)"
        }
    }

    /// 新規プロジェクトディレクトリを作成し、overview.md / current_status.md / サブフォルダを初期化する
    @discardableResult
    func createProject(
        name: String,
        initialOverview: String = "",
        initialStatus: String = ""
    ) throws -> Project {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        guard !trimmed.isEmpty else {
            throw NSError(domain: "ProjectStorage", code: 400, userInfo: [NSLocalizedDescriptionKey: "プロジェクト名を入力してください。"])
        }

        let dirURL = projectsRootURL.appendingPathComponent(trimmed, isDirectory: true)
        if !fileManager.fileExists(atPath: dirURL.path) {
            try fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }

        let project = Project(name: trimmed, directoryURL: dirURL, createdAt: Date())
        ensureProjectSubdirectories(for: project, initialOverview: initialOverview, initialStatus: initialStatus)
        loadProjects()
        return project
    }

    private func ensureProjectSubdirectories(
        for project: Project,
        initialOverview: String = "",
        initialStatus: String = ""
    ) {
        try? fileManager.createDirectory(at: project.audioDirectoryURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: project.transcriptsDirectoryURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: project.minutesDirectoryURL, withIntermediateDirectories: true)

        if !fileManager.fileExists(atPath: project.overviewURL.path) {
            let defaultOverview = initialOverview.isEmpty ? """
            # 🗺️ Project Overview: \(project.name)

            ## プロジェクトの目的・概要
            - （ここにプロジェクトの目的や背景を記入してください。「ファイル」アプリやMacからも編集可能です）

            ## 主な参加者・登場人物
            - （参加者名や役割を書いておくと、人物ごとの書き起こしや議事録で自動的に名前が反映されます）
            """ : initialOverview
            try? defaultOverview.write(to: project.overviewURL, atomically: true, encoding: .utf8)
        }

        if !fileManager.fileExists(atPath: project.currentStatusURL.path) {
            let defaultStatus = initialStatus.isEmpty ? """
            # 📊 Current Status: \(project.name)

            ## 🟢 現在のフェーズ・進捗状況
            - プロジェクト進行中

            ## 📝 直近の課題・タスク
            - [ ] （ここに現在の進捗や直近の課題を記入してください。議事録生成時の文脈として参照されます）
            """ : initialStatus
            try? defaultStatus.write(to: project.currentStatusURL, atomically: true, encoding: .utf8)
        }
    }

    func deleteProject(_ project: Project) {
        do {
            if fileManager.fileExists(atPath: project.directoryURL.path) {
                try fileManager.removeItem(at: project.directoryURL)
            }
            loadProjects()
        } catch {
            lastErrorMessage = "プロジェクトの削除に失敗しました: \(error.localizedDescription)"
        }
    }

    // MARK: - Staging & Project Audio Files

    func loadUnassignedRecordings() {
        ensureBaseDirectoriesExist()
        unassignedRecordings = loadAudioFiles(in: stagingDirectoryURL, projectName: nil)
    }

    func loadAudioFiles(for project: Project) -> [RecordingItem] {
        loadAudioFiles(in: project.audioDirectoryURL, projectName: project.name)
    }

    private func loadAudioFiles(in directoryURL: URL, projectName: String?) -> [RecordingItem] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let audioExtensions: Set<String> = ["m4a", "wav", "mp3", "aac", "caf"]
        var items: [RecordingItem] = []

        for url in urls where audioExtensions.contains(url.pathExtension.lowercased()) {
            let values = try? url.resourceValues(forKeys: [.creationDateKey])
            let createdAt = values?.creationDate ?? Date()
            let duration = audioDuration(for: url)
            let baseTitle = url.deletingPathExtension().lastPathComponent
            items.append(
                RecordingItem(
                    title: baseTitle,
                    fileName: url.lastPathComponent,
                    createdAt: createdAt,
                    duration: duration,
                    projectName: projectName
                )
            )
        }

        return items.sorted { $0.createdAt > $1.createdAt }
    }

    func audioFileURL(for item: RecordingItem) -> URL {
        if let projectName = item.projectName {
            return projectsRootURL
                .appendingPathComponent(projectName, isDirectory: true)
                .appendingPathComponent("audio", isDirectory: true)
                .appendingPathComponent(item.fileName)
        } else {
            return stagingDirectoryURL.appendingPathComponent(item.fileName)
        }
    }

    /// 音声ファイルを改名する
    func renameRecording(_ item: RecordingItem, newTitle: String) -> RecordingItem? {
        let sanitized = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        guard !sanitized.isEmpty else { return nil }

        let oldURL = audioFileURL(for: item)
        let ext = oldURL.pathExtension.isEmpty ? "m4a" : oldURL.pathExtension
        let newFileName = "\(sanitized).\(ext)"
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newFileName)

        guard oldURL != newURL else { return item }

        do {
            if fileManager.fileExists(atPath: newURL.path) {
                throw NSError(domain: "ProjectStorage", code: 409, userInfo: [NSLocalizedDescriptionKey: "同名のファイルが既に存在します。"])
            }
            try fileManager.moveItem(at: oldURL, to: newURL)
            var updated = item
            updated.title = sanitized
            updated.fileName = newFileName
            reloadAll()
            return updated
        } catch {
            lastErrorMessage = "ファイル名の変更に失敗しました: \(error.localizedDescription)"
            return nil
        }
    }

    /// 録音ファイルを削除する
    func deleteRecording(_ item: RecordingItem) {
        let url = audioFileURL(for: item)
        do {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            reloadAll()
        } catch {
            lastErrorMessage = "音声ファイルの削除に失敗しました: \(error.localizedDescription)"
        }
    }

    /// 録音ファイルを指定したプロジェクトの `audio/` ディレクトリに移動・格納する
    @discardableResult
    func moveRecording(_ item: RecordingItem, to project: Project) -> RecordingItem? {
        ensureProjectSubdirectories(for: project)
        let sourceURL = audioFileURL(for: item)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            lastErrorMessage = "移動元の音声ファイルが見つかりません。"
            return nil
        }

        var destinationFileName = item.fileName
        var destinationURL = project.audioDirectoryURL.appendingPathComponent(destinationFileName)

        // 同名ファイルが存在する場合は連番を付与
        var counter = 2
        let baseName = (item.fileName as NSString).deletingPathExtension
        let ext = (item.fileName as NSString).pathExtension
        while fileManager.fileExists(atPath: destinationURL.path) && sourceURL != destinationURL {
            destinationFileName = "\(baseName)_\(counter).\(ext)"
            destinationURL = project.audioDirectoryURL.appendingPathComponent(destinationFileName)
            counter += 1
        }

        do {
            if sourceURL != destinationURL {
                try fileManager.moveItem(at: sourceURL, to: destinationURL)
            }
            var moved = item
            moved.fileName = destinationFileName
            moved.title = (destinationFileName as NSString).deletingPathExtension
            moved.projectName = project.name
            reloadAll()
            return moved
        } catch {
            lastErrorMessage = "プロジェクトへの格納に失敗しました: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Project Context & Documents (Overview, Current Status, Transcripts, Minutes)

    func readTextFile(at url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func saveTextFile(_ content: String, to url: URL) {
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            lastErrorMessage = "ファイルの保存に失敗しました: \(error.localizedDescription)"
        }
    }

    /// プロジェクト内の書き起こし・議事録一覧を取得する
    func loadDocuments(for project: Project) -> [ProjectDocument] {
        var docs: [ProjectDocument] = []

        // 1. 議事録 (minutes/)
        if let minuteURLs = try? fileManager.contentsOfDirectory(
            at: project.minutesDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            for url in minuteURLs where url.pathExtension.lowercased() == "md" || url.pathExtension.lowercased() == "txt" {
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                docs.append(
                    ProjectDocument(
                        title: url.deletingPathExtension().lastPathComponent,
                        fileName: url.lastPathComponent,
                        fileURL: url,
                        updatedAt: date,
                        category: .minutes
                    )
                )
            }
        }

        // 2. 書き起こし・話者分離 (transcripts/)
        if let transcriptURLs = try? fileManager.contentsOfDirectory(
            at: project.transcriptsDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            for url in transcriptURLs where url.pathExtension.lowercased() == "md" || url.pathExtension.lowercased() == "txt" {
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                let isDiarized = url.lastPathComponent.contains("_diarized")
                docs.append(
                    ProjectDocument(
                        title: url.deletingPathExtension().lastPathComponent,
                        fileName: url.lastPathComponent,
                        fileURL: url,
                        updatedAt: date,
                        category: isDiarized ? .diarizedTranscript : .transcript
                    )
                )
            }
        }

        return docs.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 特定の音声ファイルに対応する生成済みドキュメント（書き起こし・人物別・議事録）があれば返す
    func existingDocumentURL(for item: RecordingItem, project: Project, mode: AIProcessingMode) -> URL {
        let baseName = (item.fileName as NSString).deletingPathExtension
        let targetFileName = "\(baseName)\(mode.outputFileSuffix)"
        switch mode {
        case .transcription, .speakerDiarization:
            return project.transcriptsDirectoryURL.appendingPathComponent(targetFileName)
        case .meetingMinutes:
            return project.minutesDirectoryURL.appendingPathComponent(targetFileName)
        }
    }

    /// AI生成結果をプロジェクトディレクトリ内の適切なフォルダに保存する
    @discardableResult
    func saveAIResult(
        content: String,
        for item: RecordingItem,
        in project: Project,
        mode: AIProcessingMode
    ) -> URL {
        ensureProjectSubdirectories(for: project)
        let targetURL = existingDocumentURL(for: item, project: project, mode: mode)
        saveTextFile(content, to: targetURL)
        return targetURL
    }

    /// 議事録生成のために、プロジェクト内の「概要」「現在の進捗状況」「過去の音声・書き起こし・議事録」を統合したコンテキスト文字列を構築する
    func buildHistoricalContext(for project: Project, excludingAudioFileName: String? = nil) -> String {
        let overview = readTextFile(at: project.overviewURL).trimmingCharacters(in: .whitespacesAndNewlines)
        let currentStatus = readTextFile(at: project.currentStatusURL).trimmingCharacters(in: .whitespacesAndNewlines)
        let audioFiles = loadAudioFiles(for: project)
        let allDocs = loadDocuments(for: project)

        var sections: [String] = []
        sections.append("## 1. プロジェクト概要 (overview.md)\n\(overview.isEmpty ? "（未記入）" : overview)")
        sections.append("## 2. 現在の進捗状況 (current_status.md)\n\(currentStatus.isEmpty ? "（未記入）" : currentStatus)")

        // 過去の音声ファイル一覧
        let pastAudioList = audioFiles
            .filter { $0.fileName != excludingAudioFileName }
            .prefix(10)
            .map { "- \($0.fileName)（録音日時: \($0.formattedDate), 長さ: \($0.formattedDuration)）" }
            .joined(separator: "\n")
        if !pastAudioList.isEmpty {
            sections.append("## 3. プロジェクト内の過去の音声ファイル履歴\n\(pastAudioList)")
        }

        // 過去の議事録（直近3件まで全文または抜粋を参照）
        let pastMinutes = allDocs.filter { $0.category == .minutes }.prefix(3)
        if !pastMinutes.isEmpty {
            var minutesText = "## 4. 過去の議事録（直近の文脈）\n"
            for doc in pastMinutes {
                let body = readTextFile(at: doc.fileURL)
                let clipped = String(body.prefix(4000))
                minutesText += "\n### 📄 \(doc.fileName) (\(doc.formattedDate))\n\(clipped)\n"
            }
            sections.append(minutesText)
        }

        // 過去の書き起こし（直近2件まで参照）
        let pastTranscripts = allDocs
            .filter { $0.category == .transcript || $0.category == .diarizedTranscript }
            .prefix(2)
        if !pastTranscripts.isEmpty {
            var transcriptsText = "## 5. 過去の音声書き起こしログ（抜粋）\n"
            for doc in pastTranscripts {
                let body = readTextFile(at: doc.fileURL)
                let clipped = String(body.prefix(3000))
                transcriptsText += "\n### 🗣️ \(doc.fileName) (\(doc.formattedDate))\n\(clipped)\n"
            }
            sections.append(transcriptsText)
        }

        return sections.joined(separator: "\n\n---\n\n")
    }

    // MARK: - Helpers

    private func audioDuration(for url: URL) -> TimeInterval {
        if let player = try? AVAudioPlayer(contentsOf: url) {
            return player.duration
        }
        return 0
    }
}

