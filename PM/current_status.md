# 📊 Current Status

**プロジェクト名**: voice_recorder_application（アプリ名: **ChronoVox**）
**ターゲット端末**: iPhone 12 (Swift / SwiftUI & PWA Webアプリ)
**公開URL (PWA)**: https://gilded-licorice-56aa77.netlify.app

## 🟢 現在のフェーズ
- iOSネイティブ版（`VoiceRecorderApp`）＆ Webアプリ/PWA版（`web/`）の両方実装完了

## 📝 直近のタスク
- [x] コアコンセプト・主要機能フローのヒアリング（[idea_20261028_core_concept.md](../secretary/idea_20261028_core_concept.md)）
- [x] 技術スタック選定：SwiftUI + AVFoundation + ファイルアプリ連携 + Gemini API（[idea_20261028_architecture_and_spec.md](../secretary/idea_20261028_architecture_and_spec.md)）
- [x] アプリ名を **ChronoVox** に改名し、専用アプリアイコン（`AppIcon.png`）を設定
- [x] 6言語（日本語・英語・フランス語・ドイツ語・イタリア語・韓国語）のUI表示切替と、AI文字起こし/議事録の言語設定（`Automatic` または6言語手動指定）を実装
- [x] 7日署名制限なしでずっと無料で使える **Webアプリ（PWA）版（`web/`）** を実装
- [ ] 実機での録音〜振り分け〜多言語AI議事録生成の動作確認
