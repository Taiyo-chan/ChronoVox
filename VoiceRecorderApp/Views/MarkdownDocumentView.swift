import SwiftUI

/// 生成された書き起こしや議事録（Markdownファイル）を閲覧・編集・共有する画面
struct MarkdownDocumentView: View {
    let title: String
    let fileURL: URL
    let categoryBadge: String

    @EnvironmentObject private var storageManager: ProjectStorageManager
    @State private var content: String = ""
    @State private var savedConfirmation: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(categoryBadge)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.accentColor)

                Text(fileURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if savedConfirmation {
                    Label("保存済み", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            TextEditor(text: $content)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: content) {
                    Image(systemName: "square.and.arrow.up")
                }

                Button("保存") {
                    storageManager.saveTextFile(content, to: fileURL)
                    withAnimation {
                        savedConfirmation = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            savedConfirmation = false
                        }
                    }
                }
            }
        }
        .onAppear {
            content = storageManager.readTextFile(at: fileURL)
        }
    }
}

