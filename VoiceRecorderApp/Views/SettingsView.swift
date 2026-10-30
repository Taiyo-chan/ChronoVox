import SwiftUI

/// 設定画面：
/// - アプリ表示言語（日本語 / 英語 / フランス語 / ドイツ語 / イタリア語 / 韓国語）の切替
/// - 文字起こし・AI処理の言語（Automatic または 6言語指定）の切替
/// - Gemini APIキーの設定（Google AI Studio 発行リンク付き）
/// - 議事録生成モデルの選択（Gemini 3.8 Flash / Gemini 4 Argon）
/// - iPhone「ファイル」アプリおよびMac連携の案内
struct SettingsView: View {
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var geminiService: GeminiService
    @EnvironmentObject private var storageManager: ProjectStorageManager

    @State private var isShowingAPIKey = false

    var body: some View {
        let t = localization.t
        NavigationStack {
            Form {
                // MARK: - 1. 言語設定（UI言語 ＆ 文字起こし言語）
                Section {
                    Picker(t.appLanguageLabel, selection: $localization.appLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }

                    Picker(t.defaultTranscriptionLanguageLabel, selection: $localization.transcriptionLanguage) {
                        ForEach(TranscriptionLanguageOption.allCases) { option in
                            Text(option.displayName(in: localization.appLanguage)).tag(option)
                        }
                    }
                } header: {
                    Text(t.languageSectionHeader)
                } footer: {
                    Text(t.languageSectionFooter)
                }

                // MARK: - 2. Gemini API キー設定 & Google AI Studio リンク
                Section {
                    HStack {
                        if isShowingAPIKey {
                            TextField("AIzaSy...", text: $geminiService.apiKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("AIzaSy...", text: $geminiService.apiKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        Button {
                            isShowingAPIKey.toggle()
                        } label: {
                            Image(systemName: isShowingAPIKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Image(systemName: geminiService.hasValidAPIKey ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(geminiService.hasValidAPIKey ? .green : .orange)
                        Text(geminiService.hasValidAPIKey ? t.apiKeyConfiguredText : t.apiKeyMissingText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
                        HStack(spacing: 8) {
                            Image(systemName: "key.fill")
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.getAPIKeyLinkTitle)
                                    .font(.subheadline.weight(.semibold))
                                Text("https://aistudio.google.com/apikey")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text(t.apiKeySectionHeader)
                } footer: {
                    Text(t.apiKeySectionFooter)
                }

                // MARK: - 3. AIモデル設定
                Section {
                    Picker(t.modelPickerLabel, selection: $geminiService.selectedModel) {
                        ForEach(GeminiService.ReasoningModel.allCases) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                } header: {
                    Text(t.modelSectionHeader)
                } footer: {
                    Text(t.modelSectionFooter)
                }

                // MARK: - 4. ファイルアプリ・Mac連携案内
                Section(t.filesIntegrationSectionHeader) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(t.filesIntegrationTitle, systemImage: "folder.badge.person.crop")
                            .font(.subheadline.weight(.bold))
                        Text(t.filesIntegrationBody)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("• overview.md")
                            Text("• current_status.md")
                            Text("• audio/ (.m4a)")
                            Text("• transcripts/ (.md)")
                            Text("• minutes/ (.md)")
                        }
                        .font(.caption.monospaced())
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(t.tabSettings)
        }
    }
}
