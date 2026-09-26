import SwiftUI

struct SettingsScreen:View {
    @EnvironmentObject var store:AppStore
    @State private var deleteReport:Report?
    @AppStorage("tutorialComplete") private var tutorialComplete=false
    @AppStorage("tutorialStep") private var tutorialStep=0
    var body:some View { List {
        Section("使い方・権限") { Button("チュートリアルを確認") { tutorialStep=0;tutorialComplete=false;store.pause() };Button("iOSの権限設定を開く") { openAppSettings() };Text("位置情報とカメラの許可はアプリの利用に必要です。通知は任意で、許可しなくてもアプリ内音声は使えます。") }
        Section("カメラ案内") { Toggle("矢印の方向を音声で案内",isOn:$store.speakDirection).accessibilityIdentifier("toggleSpeakDirection");Text("カメラ案内中、進む方向（正面・左右・後ろ）が変わると読み上げます。方位は概算です。").font(.caption)
            Toggle("頭の高さの障害物を知らせる",isOn:$store.headLevelWarnings).accessibilityIdentifier("toggleHeadLevel");Text("カメラ案内中、白杖が届かない胸・頭の高さ（約1〜2m）で前方2m以内の物を、2つのカメラの深度から検出し、音声と振動で知らせます。暗い場所・ガラス・模様のない壁では検出できないことがあります。").font(.caption) }
        if store.storageIncompatible { MigrationSection() }
        Section("状態") { Text(store.location.status);Text("モデル：\(store.camera.modelStatus)");Text(store.speech.status);Text(store.storageError ?? "報告の読み込み完了");Button("報告を再読み込み") { store.retryRead() };Button("位置取得を開始") { store.location.start() };Text("アプリは前景で実験します。背景移行時は案内とカメラを停止します。") }
        Section("対応地域") {
            Toggle("現在地から自動選択",isOn:Binding(get:{store.automaticNetworkSelection},set:{store.setAutomaticNetworkSelection($0)}))
            Picker("使用する地域",selection:Binding(get:{store.network?.id ?? ""},set:{store.selectNetwork($0)})) { ForEach(store.networks,id:\.id) { Text($0.name).tag($0.id) } }
            Text("自動選択が有効な場合、現在地が別の対応地域に入ると切り替わります。地域を手動選択すると自動選択はオフになります。地域をまたぐ経路案内には対応していません。").font(.caption)
        }
        Section("道路データ") { Text(store.network?.name ?? "読込失敗");Text(store.network?.source ?? "読込失敗");Text("版：\(store.network?.version ?? "不明")");Text("歩行区間 \(store.edges.count)・現地未確認");SourceFooter() }
        Section("保存済み報告") { if store.reports.isEmpty && store.storageError == nil { Text("登録報告なし・安全確認済みではありません") };ForEach(store.reports) { r in VStack(alignment:.leading) { Text(store.edge(r.segmentID)?.name ?? "対応区間不明");Text(r.hazard.rawValue);Text(r.observedAt,style:.date);Text(r.explanation ?? "");Button("この報告を解除",role:.destructive) { deleteReport=r }.accessibilityIdentifier("removeReport."+r.segmentID) } } }
        if store.developer { Section { NavigationLink("DeveloperModeを開く") { DeveloperScreen() };Button("DeveloperModeを終了") { store.closeDeveloper() } } }
        Section { Button { store.tapVersion() } label: { Text("バージョン情報 0.4").font(.footnote).foregroundStyle(.secondary).frame(minHeight:44) }.accessibilityLabel("バージョン情報 0.4").accessibilityIdentifier("versionInfo").accessibilityHint("3秒以内の間隔で7回操作するとアプリ内DeveloperModeを有効にします") }
    }.navigationTitle("設定")
    .confirmationDialog("選んだ報告を解除し、経路検索でこの区間を再び候補に含めます。同じ区間に他の報告があれば除外を継続します。",isPresented:Binding(get:{deleteReport != nil},set:{if !$0 {deleteReport=nil}}),titleVisibility:.visible) { Button("この報告を解除",role:.destructive) { if let r=deleteReport { store.remove(r.id) };deleteReport=nil };Button("取消",role:.cancel) { deleteReport=nil } }
    }
}

struct MigrationSection:View {
    @EnvironmentObject var store:AppStore
    @State private var migrate=false
    @State private var archive=false
    var body:some View {
        Section("道路データ更新後の報告") {
            Text("保存済み報告は以前の道路データ版で作成されています。案内は保留中です。報告は自動で削除・変換しません。").font(.subheadline)
            if let p=store.migrationPreview() { Text("同じ区間IDが存在する報告 \(p.kept)件・対応しない報告 \(p.dropped)件") }
            Button("同じ区間IDの報告だけ引き継ぐ") { migrate=true }
            Button("旧報告を退避して新しい道路版で開始") { archive=true }
            Text("どちらも元ファイルを退避ファイルとして残します。対応しない報告は現地で再登録してください。").font(.caption)
        }
        .confirmationDialog("同じ区間IDの報告だけを新しい道路版へ引き継ぎます。元ファイルは退避します。",isPresented:$migrate,titleVisibility:.visible) { Button("引き継ぐ") { store.migrateReports() };Button("取消",role:.cancel) {} }
        .confirmationDialog("旧報告を退避ファイルへ移し、報告なしの状態で開始します。削除はしません。",isPresented:$archive,titleVisibility:.visible) { Button("退避して開始",role:.destructive) { store.archiveReports() };Button("取消",role:.cancel) {} }
    }
}
