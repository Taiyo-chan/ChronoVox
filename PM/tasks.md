# 📋 Tasks

## TODO
- [ ] Xcode で `VoiceRecorderApp.xcodeproj` を開き、Signing & Capabilities でご自身の Apple ID (Team) を設定して iPhone 12 実機にインストールする
- [ ] アプリ内「設定」タブで Gemini API キーを入力し、実機で録音〜振り分け〜文脈付き議事録生成をテストする
- [ ] 実際に使ってみて気になったUI・プロンプト・追加機能をブラッシュアップする

## In Progress
- [ ] iPhone 12 実機での動作確認・フィードバック収集

## Done
- [x] プロジェクト管理用フォルダ群（PM, secretary, .agents）の作成
- [x] コア機能要件のヒアリングとアイデアメモ作成（[idea_20261028_core_concept.md](../secretary/idea_20261028_core_concept.md)）
- [x] 技術スタックとアーキテクチャ設計の作成（[idea_20261028_architecture_and_spec.md](../secretary/idea_20261028_architecture_and_spec.md)）
- [x] SwiftUI プロジェクト（`VoiceRecorderApp`）一式の実装・コンパイル検証完了
  - 録音画面（大型ストップウォッチ・リアルタイム波形・赤ボタン・連続録音・区切って次へ）
  - 録音終了後のトリアージ画面（試聴・15秒スキップ・削除・既存/新規プロジェクトへの格納）
  - プロジェクト管理画面（`overview.md` / `current_status.md` 編集・ファイルアプリ連携）
  - Gemini Interactions API 連携（①書き起こし ②人物ごとに書き起こし ③過去文脈を踏まえた議事録生成＆進捗自動更新）
- [x] アプリ名を **ChronoVox** に改名・アプリアイコン作成・Google AI Studio APIキー発行リンク追加
- [x] 6言語ローカライズ（日本語・英語・フランス語・ドイツ語・イタリア語・韓国語）および文字起こし言語指定（`Automatic` + 6言語）の実装
- [x] Webアプリ / PWA版（`web/`）の実装完了（IndexedDB永続化・ホーム画面追加アイコン対応・6言語対応）
- [x] Netlify へのデプロイ・HTTPS公開完了（https://gilded-licorice-56aa77.netlify.app）
