import Foundation

/// アプリの表示言語（6言語対応：日本語・英語・フランス語・ドイツ語・イタリア語・韓国語）
enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case japanese = "ja"
    case english = "en"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case korean = "ko"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .japanese: return "🇯🇵 日本語 (Japanese)"
        case .english:  return "🇺🇸 English"
        case .french:   return "🇫🇷 Français"
        case .german:   return "🇩🇪 Deutsch"
        case .italian:  return "🇮🇹 Italiano"
        case .korean:   return "🇰🇷 한국어 (Korean)"
        }
    }

    var shortName: String {
        switch self {
        case .japanese: return "日本語"
        case .english:  return "English"
        case .french:   return "Français"
        case .german:   return "Deutsch"
        case .italian:  return "Italiano"
        case .korean:   return "한국어"
        }
    }

    /// Gemini 3.5 Transcribe 用の BCP-47 言語コード
    var bcp47Code: String {
        switch self {
        case .japanese: return "ja-JP"
        case .english:  return "en-US"
        case .french:   return "fr-FR"
        case .german:   return "de-DE"
        case .italian:  return "it-IT"
        case .korean:   return "ko-KR"
        }
    }

    /// AIプロンプト内で出力言語を指定するための英語名
    var promptLanguageName: String {
        switch self {
        case .japanese: return "Japanese (日本語)"
        case .english:  return "English"
        case .french:   return "French (Français)"
        case .german:   return "German (Deutsch)"
        case .italian:  return "Italian (Italiano)"
        case .korean:   return "Korean (한국어)"
        }
    }
}

/// 音声の文字起こし・話者分離・議事録作成時の言語設定（Automatic または 6言語から手動指定）
enum TranscriptionLanguageOption: String, CaseIterable, Identifiable, Codable {
    case automatic = "auto"
    case japanese = "ja"
    case english = "en"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case korean = "ko"

    var id: String { rawValue }

    var specificLanguage: AppLanguage? {
        AppLanguage(rawValue: rawValue)
    }

    /// Gemini 3.5 Transcribe の `language_codes` に渡す配列（Automatic の場合は空配列 `[]`）
    var bcp47Codes: [String] {
        if let lang = specificLanguage {
            return [lang.bcp47Code]
        }
        return []
    }

    func displayName(in uiLang: AppLanguage) -> String {
        switch self {
        case .automatic:
            switch uiLang {
            case .japanese: return "🌐 Automatic（自動検出）"
            case .english:  return "🌐 Automatic (Auto-detect)"
            case .french:   return "🌐 Automatique (Détection auto)"
            case .german:   return "🌐 Automatisch (Auto-Erkennung)"
            case .italian:  return "🌐 Automatico (Rilevamento auto)"
            case .korean:   return "🌐 Automatic (자동 감지)"
            }
        case .japanese: return "🇯🇵 日本語 (ja-JP)"
        case .english:  return "🇺🇸 English (en-US)"
        case .french:   return "🇫🇷 Français (fr-FR)"
        case .german:   return "🇩🇪 Deutsch (de-DE)"
        case .italian:  return "🇮🇹 Italiano (it-IT)"
        case .korean:   return "🇰🇷 한국어 (ko-KR)"
        }
    }
}

/// アプリ全体の言語設定を保持・公開する環境オブジェクト
@MainActor
final class LocalizationManager: ObservableObject {
    @Published var appLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(appLanguage.rawValue, forKey: Self.appLanguageKey)
        }
    }

    @Published var transcriptionLanguage: TranscriptionLanguageOption {
        didSet {
            UserDefaults.standard.set(transcriptionLanguage.rawValue, forKey: Self.transcriptionLanguageKey)
        }
    }

    private static let appLanguageKey = "CHRONOVOX_APP_LANGUAGE"
    private static let transcriptionLanguageKey = "CHRONOVOX_TRANSCRIPTION_LANGUAGE"

    init() {
        let savedAppLang = UserDefaults.standard.string(forKey: Self.appLanguageKey) ?? AppLanguage.japanese.rawValue
        self.appLanguage = AppLanguage(rawValue: savedAppLang) ?? .japanese

        let savedTransLang = UserDefaults.standard.string(forKey: Self.transcriptionLanguageKey) ?? TranscriptionLanguageOption.automatic.rawValue
        self.transcriptionLanguage = TranscriptionLanguageOption(rawValue: savedTransLang) ?? .automatic
    }

    var t: AppStrings {
        AppStrings(lang: appLanguage)
    }
}

/// 6言語すべてのUIテキスト・説明文を提供するローカライズ辞書
struct AppStrings {
    let lang: AppLanguage

    private func pick(
        ja: String,
        en: String,
        fr: String,
        de: String,
        it: String,
        ko: String
    ) -> String {
        switch lang {
        case .japanese: return ja
        case .english:  return en
        case .french:   return fr
        case .german:   return de
        case .italian:  return it
        case .korean:   return ko
        }
    }

    // MARK: - App & Tabs
    var appTitle: String { "ChronoVox" }

    var tabRecord: String {
        pick(ja: "録音", en: "Record", fr: "Enregistrer", de: "Aufnahme", it: "Registra", ko: "녹음")
    }
    var tabTriage: String {
        pick(ja: "振り分け", en: "Triage", fr: "Trier", de: "Sortieren", it: "Smista", ko: "분류")
    }
    var tabProjects: String {
        pick(ja: "プロジェクト", en: "Projects", fr: "Projets", de: "Projekte", it: "Progetti", ko: "프로젝트")
    }
    var tabSettings: String {
        pick(ja: "設定", en: "Settings", fr: "Réglages", de: "Einstellungen", it: "Impostazioni", ko: "설정")
    }

    // MARK: - RecorderView
    var standbyBadge: String {
        pick(
            ja: "STANDBY（赤いボタンで録音開始）",
            en: "STANDBY (Tap Red Button to Record)",
            fr: "PRÊT (Appuyez sur le bouton rouge)",
            de: "BEREIT (Roten Knopf drücken)",
            it: "PRONTO (Tocca il pulsante rosso)",
            ko: "대기 중 (빨간 버튼을 눌러 녹음 시작)"
        )
    }

    func standbySessionBadge(count: Int) -> String {
        pick(
            ja: "連続録音待機中（セッション内 \(count)件）",
            en: "Session Standby (\(count) clip(s) recorded)",
            fr: "En attente (\(count) fichier(s) en session)",
            de: "Sitzung bereit (\(count) Aufnahme(n))",
            it: "In attesa (\(count) file nella sessione)",
            ko: "연속 녹음 대기 중 (세션 내 \(count)개)"
        )
    }

    func recordingBadge(take: Int) -> String {
        pick(
            ja: "REC 録音中（テイク #\(take)）",
            en: "REC Recording (Take #\(take))",
            fr: "REC Enregistrement (Prise #\(take))",
            de: "REC Aufnahme läuft (Take #\(take))",
            it: "REC Registrazione (Take #\(take))",
            ko: "REC 녹음 중 (테이크 #\(take))"
        )
    }

    var pausedBadge: String {
        pick(
            ja: "PAUSED 一時停止中",
            en: "PAUSED",
            fr: "EN PAUSE",
            de: "PAUSIERT",
            it: "IN PAUSA",
            ko: "PAUSED 일시정지됨"
        )
    }

    var pauseButton: String {
        pick(ja: "一時停止", en: "Pause", fr: "Pause", de: "Pause", it: "Pausa", ko: "일시정지")
    }
    var resumeButton: String {
        pick(ja: "再開", en: "Resume", fr: "Reprendre", de: "Weiter", it: "Riprendi", ko: "재개")
    }
    var startRecordingButton: String {
        pick(ja: "録音開始", en: "Start", fr: "Démarrer", de: "Start", it: "Avvia", ko: "녹음 시작")
    }
    var finishClipButton: String {
        pick(ja: "この録音を完了", en: "Finish Clip", fr: "Terminer", de: "Beenden", it: "Termina clip", ko: "현재 녹음 완료")
    }
    var splitNextButton: String {
        pick(ja: "区切って次へ", en: "Split & Next", fr: "Suivant", de: "Nächster Clip", it: "Dividi e seg.", ko: "분할 후 다음 녹음")
    }
    var continuousHint: String {
        pick(
            ja: "💡 赤いボタンを押すと続けて次の音声ファイルを録音できます",
            en: "💡 Tap the red button again to record the next audio file in this session",
            fr: "💡 Appuyez sur le bouton rouge pour enregistrer le fichier suivant",
            de: "💡 Drücken Sie den roten Knopf erneut für die nächste Aufnahme",
            it: "💡 Tocca il pulsante rosso per registrare il file successivo",
            ko: "💡 빨간 버튼을 누르면 이어서 다음 음성 파일을 녹음할 수 있습니다"
        )
    }

    func unassignedHeader(count: Int) -> String {
        pick(
            ja: "録音済み・未振り分けファイル (\(count)件)",
            en: "Unassigned Recordings (\(count))",
            fr: "Enregistrements non classés (\(count))",
            de: "Nicht zugeordnete Aufnahmen (\(count))",
            it: "Registrazioni non assegnate (\(count))",
            ko: "녹음 완료 · 미분류 파일 (\(count)개)"
        )
    }

    var finishSessionAndTriageButton: String {
        pick(
            ja: "一連の録音を終了して整理へ",
            en: "Finish Session & Organize",
            fr: "Terminer et organiser",
            de: "Sitzung beenden & sortieren",
            it: "Termina e organizza",
            ko: "연속 녹음 종료 및 정리하기"
        )
    }

    var emptyRecordingsTitle: String {
        pick(
            ja: "赤いボタンを押して録音を開始してください",
            en: "Tap the red button to start recording",
            fr: "Appuyez sur le bouton rouge pour commencer",
            de: "Roten Knopf drücken, um die Aufnahme zu starten",
            it: "Tocca il pulsante rosso per iniziare a registrare",
            ko: "빨간 버튼을 눌러 녹음을 시작하세요"
        )
    }

    var emptyRecordingsSubtitle: String {
        pick(
            ja: "複数の音声ファイルを連続して録りためたあと、\nまとめて削除やプロジェクトフォルダへの振り分けができます。",
            en: "Record multiple audio clips back-to-back, then delete unwanted takes or assign them into project directories.",
            fr: "Enregistrez plusieurs fichiers à la suite, puis supprimez-les ou classez-les dans vos dossiers de projet.",
            de: "Nehmen Sie mehrere Audiodateien nacheinander auf und ordnen Sie sie anschließend Ihren Projektordnern zu.",
            it: "Registra più file audio in sequenza, poi eliminali o spostali nelle cartelle di progetto.",
            ko: "여러 음성 파일을 연속으로 녹음한 뒤, 삭제하거나 프로젝트 폴더로 한꺼번에 분류할 수 있습니다."
        )
    }

    var assignShortButton: String {
        pick(ja: "格納", en: "Assign", fr: "Classer", de: "Zuordnen", it: "Assegna", ko: "저장")
    }
    var deleteButton: String {
        pick(ja: "削除", en: "Delete", fr: "Supprimer", de: "Löschen", it: "Elimina", ko: "삭제")
    }
    var closeButton: String {
        pick(ja: "閉じる", en: "Close", fr: "Fermer", de: "Schließen", it: "Chiudi", ko: "닫기")
    }
    var cancelButton: String {
        pick(ja: "キャンセル", en: "Cancel", fr: "Annuler", de: "Abbrechen", it: "Annulla", ko: "취소")
    }
    var saveButton: String {
        pick(ja: "保存", en: "Save", fr: "Enregistrer", de: "Speichern", it: "Salva", ko: "저장")
    }
    var shareButton: String {
        pick(ja: "共有", en: "Share", fr: "Partager", de: "Teilen", it: "Condividi", ko: "공유")
    }

    // MARK: - SessionTriageView
    var triageNavTitle: String {
        pick(
            ja: "録音ファイルの整理・格納",
            en: "Organize Recordings",
            fr: "Organiser les enregistrements",
            de: "Aufnahmen sortieren",
            it: "Organizza registrazioni",
            ko: "녹음 파일 정리 및 저장"
        )
    }

    var batchAssignTitle: String {
        pick(
            ja: "一括プロジェクト格納",
            en: "Batch Move to Project",
            fr: "Déplacement groupé",
            de: "Alle einem Projekt zuordnen",
            it: "Sposta tutto nel progetto",
            ko: "프로젝트 일괄 저장"
        )
    }

    func batchAssignSubtitle(count: Int) -> String {
        pick(
            ja: "全\(count)件の音声ファイルをまとめて1つのプロジェクトへ移動できます",
            en: "Move all \(count) audio file(s) into a project directory at once",
            fr: "Déplacer les \(count) fichier(s) audio vers un projet en une fois",
            de: "Alle \(count) Audiodatei(en) gleichzeitig in ein Projekt verschieben",
            it: "Sposta tutti i \(count) file audio in un progetto contemporaneamente",
            ko: "전체 \(count)개의 음성 파일을 하나의 프로젝트로 한 번에 이동합니다"
        )
    }

    var batchAssignButton: String {
        pick(ja: "一括格納", en: "Move All", fr: "Tout classer", de: "Alle bewegen", it: "Sposta tutti", ko: "일괄 저장")
    }

    var triageFooterDescription: String {
        pick(
            ja: "各音声ファイルを試聴し、不要なものは「削除」、必要なものは格納先の「プロジェクトディレクトリ」を選択してください。格納後に書き起こしや文脈付き議事録を作成できます。",
            en: "Preview each recording, delete unwanted clips, or move them into a Project Directory. Once stored, you can generate transcripts, speaker diarization, and context-aware meeting minutes.",
            fr: "Écoutez chaque fichier, supprimez les prises inutiles ou déplacez-les dans un dossier de projet pour générer des transcriptions et comptes rendus contextualisés.",
            de: "Hören Sie Aufnahmen an, löschen Sie unnötige Clips oder verschieben Sie sie in ein Projektverzeichnis für Transkription und kontextbasierte Protokolle.",
            it: "Ascolta ogni file, elimina quelli inutili o spostali in una cartella di progetto per generare trascrizioni e verbali basati sul contesto.",
            ko: "각 음성 파일을 들어보고 불필요한 파일은 삭제하거나 프로젝트 디렉토리를 지정해 저장하세요. 저장 후 텍스트 변환 및 맥락 기반 회의록을 생성할 수 있습니다."
        )
    }

    var selectProjectToStore: String {
        pick(
            ja: "プロジェクトを指定して格納",
            en: "Assign to Project",
            fr: "Assigner au projet",
            de: "Projekt zuordnen",
            it: "Assegna al progetto",
            ko: "프로젝트 지정 및 저장"
        )
    }

    var createNewProjectAndStore: String {
        pick(
            ja: "＋ 新規プロジェクトを作成して格納...",
            en: "+ Create New Project & Store...",
            fr: "+ Nouveau projet et classer...",
            de: "+ Neues Projekt erstellen & speichern...",
            it: "+ Crea nuovo progetto e salva...",
            ko: "+ 새 프로젝트 생성 후 저장..."
        )
    }

    var allTriageDoneTitle: String {
        pick(
            ja: "すべての録音ファイルの整理が完了しました！",
            en: "All recordings have been organized!",
            fr: "Tous les enregistrements sont classés !",
            de: "Alle Aufnahmen wurden sortiert!",
            it: "Tutte le registrazioni sono state organizzate!",
            ko: "모든 녹음 파일 정리가 완료되었습니다!"
        )
    }

    var allTriageDoneSubtitle: String {
        pick(
            ja: "「プロジェクト」タブから各ディレクトリを開き、\n書き起こし・人物別書き起こし・文脈付き議事録を作成できます。",
            en: "Open any directory in the Projects tab to run transcription, speaker diarization, or context-aware meeting minutes.",
            fr: "Ouvrez un dossier dans l'onglet Projets pour lancer la transcription ou créer un compte rendu contextualisé.",
            de: "Öffnen Sie ein Projekt im Tab „Projekte“, um Transkriptionen oder kontextbezogene Protokolle zu erstellen.",
            it: "Apri una cartella nella scheda Progetti per avviare la trascrizione o creare verbali con contesto.",
            ko: "'프로젝트' 탭에서 폴더를 열고 텍스트 변환, 화자 분리, 맥락 기반 회의록을 생성할 수 있습니다."
        )
    }

    // MARK: - Projects & ProjectDetailView
    var newProjectButton: String {
        pick(ja: "新規プロジェクト", en: "New Project", fr: "Nouveau projet", de: "Neues Projekt", it: "Nuovo progetto", ko: "새 프로젝트")
    }

    var projectsFooterDescription: String {
        pick(
            ja: "各フォルダには overview.md（概要）、current_status.md（進捗状況）、audio/（音声）、transcripts/（書き起こし）、minutes/（議事録）が格納されます。iPhoneの「ファイル」アプリからも直接閲覧・編集できます。",
            en: "Each directory contains overview.md, current_status.md, audio/, transcripts/, and minutes/. Accessible directly from the iOS Files app.",
            fr: "Chaque dossier contient overview.md, current_status.md, audio/, transcripts/ et minutes/. Accessible via l'app Fichiers d'iOS.",
            de: "Jeder Ordner enthält overview.md, current_status.md, audio/, transcripts/ und minutes/. Direkt über die iOS-Dateien-App zugänglich.",
            it: "Ogni cartella contiene overview.md, current_status.md, audio/, transcripts/ e minutes/. Accessibile dall'app File di iOS.",
            ko: "각 폴더에는 overview.md(개요), current_status.md(진행 상황), audio/(음성), transcripts/(변환록), minutes/(회의록)가 저장되며 iPhone '파일' 앱에서도 직접 편집할 수 있습니다."
        )
    }

    var sectionAudioAndAI: String {
        pick(ja: "音声 & AI生成", en: "Audio & AI", fr: "Audio & IA", de: "Audio & KI", it: "Audio & IA", ko: "음성 & AI")
    }
    var sectionDocuments: String {
        pick(ja: "議事録・履歴", en: "Minutes & Logs", fr: "Historique", de: "Protokolle", it: "Verbali & Log", ko: "회의록 · 기록")
    }
    var sectionContext: String {
        pick(ja: "概要・進捗(文脈)", en: "Context", fr: "Contexte", de: "Kontext", it: "Contesto", ko: "개요 · 진행(맥락)")
    }

    // MARK: - AIProcessingMode Localized Titles & Subtitles
    func modeTitle(_ mode: AIProcessingMode) -> String {
        switch mode {
        case .transcription:
            return pick(
                ja: "書き起こし",
                en: "Transcription",
                fr: "Transcription",
                de: "Transkription",
                it: "Trascrizione",
                ko: "텍스트 변환 (전사)"
            )
        case .speakerDiarization:
            return pick(
                ja: "人物ごとに書き起こし",
                en: "Speaker-Separated Transcription",
                fr: "Transcription par interlocuteur",
                de: "Transkription nach Sprechern",
                it: "Trascrizione per interlocutore",
                ko: "화자별 텍스트 변환"
            )
        case .meetingMinutes:
            return pick(
                ja: "議事録（要約）を作る",
                en: "Context-Aware Meeting Minutes",
                fr: "Compte rendu contextualisé",
                de: "Kontextbasiertes Protokoll erstellen",
                it: "Crea verbale con contesto",
                ko: "회의록(요약) 작성"
            )
        }
    }

    func modeSubtitle(_ mode: AIProcessingMode) -> String {
        switch mode {
        case .transcription:
            return pick(
                ja: "フィラーを除去し、読みやすく整形した全文書き起こしを作成します",
                en: "Generates a clean, readable full transcript with filler words removed",
                fr: "Génère une transcription complète et fluide sans hésitations",
                de: "Erstellt ein bereinigtes, gut lesbares Volltranskript ohne Füllwörter",
                it: "Genera una trascrizione completa e leggibile rimuovendo le esitazioni",
                ko: "추임새를 제거하고 읽기 쉽게 정리된 전체 텍스트 변환본을 생성합니다"
            )
        case .speakerDiarization:
            return pick(
                ja: "発言者を識別し、誰が何を話したか人物ごとに分けて書き起こします",
                en: "Identifies distinct speakers and attributes each spoken segment by person",
                fr: "Identifie les interlocuteurs et sépare les prises de parole par personne",
                de: "Erkennt verschiedene Sprecher und ordnet jede Aussage der jeweiligen Person zu",
                it: "Identifica i diversi interlocutori e suddivide gli interventi per persona",
                ko: "발언자를 식별하여 누가 어떤 말을 했는지 인물별로 나누어 기록합니다"
            )
        case .meetingMinutes:
            return pick(
                ja: "プロジェクトの概要・進捗状況・過去の記録を踏まえた文脈付き議事録を作成します",
                en: "Creates meeting minutes referencing project overview, current status, and past recordings",
                fr: "Crée un compte rendu en tenant compte de la vue d'ensemble, de l'avancement et de l'historique du projet",
                de: "Erstellt ein Protokoll unter Berücksichtigung von Projektübersicht, Fortschritt und bisherigen Aufnahmen",
                it: "Crea un verbale basato su panoramica del progetto, stato di avanzamento e registrazioni passate",
                ko: "프로젝트 개요, 진행 상황, 과거 기록의 맥락을 반영한 회의록을 작성합니다"
            )
        }
    }

    var selectAIActionHeader: String {
        pick(
            ja: "実行する処理を選択",
            en: "Select AI Processing Mode",
            fr: "Choisir le traitement IA",
            de: "KI-Verarbeitungsmodus wählen",
            it: "Seleziona modalità IA",
            ko: "실행할 AI 작업 선택"
        )
    }

    var audioLanguagePickerLabel: String {
        pick(
            ja: "音声・出力の言語設定",
            en: "Audio & Output Language",
            fr: "Langue audio et de sortie",
            de: "Audio- & Ausgabesprache",
            it: "Lingua audio e output",
            ko: "음성 인식 및 출력 언어"
        )
    }

    // MARK: - SettingsView
    var languageSectionHeader: String {
        pick(
            ja: "言語設定 (Language)",
            en: "Language Settings",
            fr: "Paramètres de langue",
            de: "Spracheinstellungen",
            it: "Impostazioni lingua",
            ko: "언어 설정 (Language)"
        )
    }

    var appLanguageLabel: String {
        pick(
            ja: "アプリの表示言語",
            en: "App Display Language",
            fr: "Langue de l'application",
            de: "App-Anzeigesprache",
            it: "Lingua dell'app",
            ko: "앱 표시 언어"
        )
    }

    var defaultTranscriptionLanguageLabel: String {
        pick(
            ja: "文字起こし・AI処理の言語",
            en: "Transcription & AI Language",
            fr: "Langue de transcription / IA",
            de: "Transkriptions- & KI-Sprache",
            it: "Lingua trascrizione / IA",
            ko: "텍스트 변환 · AI 처리 언어"
        )
    }

    var languageSectionFooter: String {
        pick(
            ja: "アプリ内の説明・UI表示言語と、文字起こし・議事録生成時の認識言語を設定できます。「Automatic（自動検出）」以外に特定の言語（日本語・英語・フランス語・ドイツ語・イタリア語・韓国語）を明示的に指定することも可能です。",
            en: "Configure both the app UI language and the target language for speech transcription & minutes. Choose 'Automatic' or explicitly lock to Japanese, English, French, German, Italian, or Korean.",
            fr: "Configurez la langue de l'interface et celle de la transcription IA. Choisissez « Automatique » ou sélectionnez explicitement le japonais, l'anglais, le français, l'allemand, l'italien ou le coréen.",
            de: "Legen Sie die App-Sprache sowie die Sprache für Transkription und Protokolle fest. Wählen Sie „Automatisch“ oder gezielt Japanisch, Englisch, Französisch, Deutsch, Italienisch oder Koreanisch.",
            it: "Configura la lingua dell'interfaccia e quella per trascrizione e verbali IA. Scegli 'Automatico' oppure imposta giapponese, inglese, francese, tedesco, italiano o coreano.",
            ko: "앱 인터페이스 언어와 음성 변환·회의록 생성 언어를 설정합니다. 'Automatic(자동 감지)' 외에 한국어, 일본어, 영어, 프랑스어, 독일어, 이탈리아어를 직접 지정할 수 있습니다."
        )
    }

    var apiKeySectionHeader: String {
        pick(
            ja: "Gemini API キー設定",
            en: "Gemini API Key",
            fr: "Clé API Gemini",
            de: "Gemini API-Schlüssel",
            it: "Chiave API Gemini",
            ko: "Gemini API 키 설정"
        )
    }

    var apiKeyConfiguredText: String {
        pick(
            ja: "APIキー設定済み",
            en: "API Key Configured",
            fr: "Clé API configurée",
            de: "API-Schlüssel gespeichert",
            it: "Chiave API configurata",
            ko: "API 키 설정됨"
        )
    }

    var apiKeyMissingText: String {
        pick(
            ja: "APIキーを入力してください",
            en: "Please enter your Gemini API Key",
            fr: "Veuillez saisir votre clé API Gemini",
            de: "Bitte Gemini API-Schlüssel eingeben",
            it: "Inserisci la tua chiave API Gemini",
            ko: "Gemini API 키를 입력해 주세요"
        )
    }

    var getAPIKeyLinkTitle: String {
        pick(
            ja: "Google AI Studio で APIキーを発行・取得する",
            en: "Get a Gemini API Key from Google AI Studio",
            fr: "Obtenir une clé API sur Google AI Studio",
            de: "API-Schlüssel in Google AI Studio erstellen",
            it: "Ottieni una chiave API da Google AI Studio",
            ko: "Google AI Studio에서 API 키 발급받기"
        )
    }

    var apiKeySectionFooter: String {
        pick(
            ja: "Google AI Studio で発行した Gemini API キーを入力してください。端末内の UserDefaults に安全に保存されます。",
            en: "Enter the Gemini API key issued from Google AI Studio. Stored locally on your device.",
            fr: "Saisissez votre clé API Gemini issue de Google AI Studio. Stockée localement sur votre appareil.",
            de: "Geben Sie Ihren Gemini API-Schlüssel aus Google AI Studio ein. Er wird lokal auf Ihrem Gerät gespeichert.",
            it: "Inserisci la chiave API Gemini ottenuta da Google AI Studio. Viene salvata localmente sul dispositivo.",
            ko: "Google AI Studio에서 발급받은 Gemini API 키를 입력하세요. 기기 내부에 안전하게 저장됩니다."
        )
    }

    var modelSectionHeader: String {
        pick(
            ja: "AIモデル設定",
            en: "AI Model Configuration",
            fr: "Configuration du modèle IA",
            de: "KI-Modell-Konfiguration",
            it: "Configurazione modello IA",
            ko: "AI 모델 설정"
        )
    }

    var modelPickerLabel: String {
        pick(
            ja: "推論・議事録モデル",
            en: "Reasoning & Minutes Model",
            fr: "Modèle de raisonnement",
            de: "Protokoll- & Analysemodell",
            it: "Modello di ragionamento",
            ko: "추론 · 회의록 모델"
        )
    }

    var modelSectionFooter: String {
        pick(
            ja: "音声の書き起こし・話者分離には `gemini-3.5-transcribe`、プロジェクト文脈を踏まえた議事録生成には選択したモデル（`gemini-3.8-flash` または `gemini-4-argon`）が使用されます。",
            en: "Uses `gemini-3.5-transcribe` for speech-to-text & speaker diarization, and your selected model (`gemini-3.8-flash` or `gemini-4-argon`) for context-aware meeting minutes.",
            fr: "Utilise `gemini-3.5-transcribe` pour la transcription et le modèle sélectionné (`gemini-3.8-flash` ou `gemini-4-argon`) pour les comptes rendus contextualisés.",
            de: "Verwendet `gemini-3.5-transcribe` für die Spracherkennung und das gewählte Modell (`gemini-3.8-flash` oder `gemini-4-argon`) für kontextbasierte Protokolle.",
            it: "Usa `gemini-3.5-transcribe` per la trascrizione e il modello selezionato (`gemini-3.8-flash` o `gemini-4-argon`) per i verbali basati sul contesto.",
            ko: "음성 전사 및 화자 분리에는 `gemini-3.5-transcribe`가 사용되며, 맥락 기반 회의록 생성에는 선택한 모델(`gemini-3.8-flash` 또는 `gemini-4-argon`)이 사용됩니다."
        )
    }

    var filesIntegrationSectionHeader: String {
        pick(
            ja: "「ファイル」アプリ・Mac連携について",
            en: "iOS Files App & Mac Integration",
            fr: "Intégration App Fichiers & Mac",
            de: "iOS Dateien-App & Mac-Integration",
            it: "Integrazione App File & Mac",
            ko: "'파일' 앱 및 Mac 연동 안내"
        )
    }

    var filesIntegrationTitle: String {
        pick(
            ja: "iPhoneの「ファイル」アプリから直接アクセス可能",
            en: "Direct Access via iPhone Files App",
            fr: "Accès direct via l'app Fichiers sur iPhone",
            de: "Direkter Zugriff über die iPhone Dateien-App",
            it: "Accesso diretto tramite l'app File su iPhone",
            ko: "iPhone '파일' 앱에서 직접 접근 가능"
        )
    }

    var filesIntegrationBody: String {
        pick(
            ja: "「ファイル」アプリ ＞「このiPhone内」＞「ChronoVox」＞「Projects」を開くと、各プロジェクトフォルダ内の以下のファイルを直接確認・編集・Macと共有できます。",
            en: "Open the Files app > On My iPhone > ChronoVox > Projects to view, edit, or share project folders and Markdown files directly with your Mac.",
            fr: "Ouvrez l'app Fichiers > Sur mon iPhone > ChronoVox > Projects pour consulter, modifier ou partager directement vos dossiers et fichiers Markdown avec votre Mac.",
            de: "Öffnen Sie Dateien > Auf meinem iPhone > ChronoVox > Projects, um Projektordner und Markdown-Dateien direkt einzusehen, zu bearbeiten oder mit dem Mac zu teilen.",
            it: "Apri l'app File > Su iPhone > ChronoVox > Projects per visualizzare, modificare o condividere direttamente le cartelle di progetto e i file Markdown con il Mac.",
            ko: "'파일' 앱 > '나의 iPhone' > 'ChronoVox' > 'Projects'를 열면 각 프로젝트 폴더 내의 파일을 직접 확인·편집하거나 Mac과 공유할 수 있습니다."
        )
    }
}

