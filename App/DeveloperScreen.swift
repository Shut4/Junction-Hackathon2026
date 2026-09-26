import SwiftUI

struct DeveloperScreen:View {
    @EnvironmentObject var store:AppStore
    @ObservedObject private var logger=DebugLogger.shared
    @State private var saveFailure=false
    @State private var readFailure=false
    @State private var reset=false
    @State private var export:URL?
    @State private var showLog=false
    var body:some View { Form {
        Section("統合デバッグログ") {
            NavigationLink { DebugLogScreen() } label: { LabeledContent("ログを表示",value:"\(logger.buffer.entries.count)件") }.accessibilityIdentifier("openDebugLog")
            let errors=logger.buffer.entries.filter { $0.level == .error }.count,warnings=logger.buffer.entries.filter { $0.level == .warning }.count
            LabeledContent("エラー / 注意",value:"\(errors) / \(warnings)")
            if let last=logger.buffer.entries.last { LabeledContent("最新",value:last.title) }
            Text(DebugLogger.persists ? "保存：有効（直近\(DebugLogger.capacity)件を再起動後も保持）":"保存：無効（Release）").font(.caption)
            Toggle("位置更新を毎回記録（座標は記録しない）",isOn:$logger.verboseLocation)
            Toggle("推論を毎回記録（通常は30回ごと）",isOn:$logger.verboseInference)
        }
        Section("状態ダッシュボード") {
            LabeledContent("位置の権限",value:store.location.authorization)
            LabeledContent("位置",value:store.location.sample.map { "\($0.simulated ? "模擬":"実")・精度\(Int($0.accuracy))m・\(Int(Date().timeIntervalSince($0.timestamp)))秒前" } ?? "なし")
            LabeledContent("方位",value:store.location.heading.map { "\(Int(($0.degrees).rounded()))°・精度\(Int($0.accuracy))°\($0.simulated ? "・模擬":"")" } ?? (store.location.headingAvailable ? "未取得":"非対応"))
            LabeledContent("道路照合",value:store.matchedEdge == nil ? "保留":"確定")
            LabeledContent("道路データ",value:"\(store.network?.nodes.count ?? 0)地点・\(store.edges.count)区間")
            LabeledContent("経路",value:store.route.map { "\($0.steps.count)区間・\(Int($0.distance))m・計算\(Int(store.lastRouteMilliseconds ?? 0))ms" } ?? "なし")
            if let p=store.progress { LabeledContent("進捗",value:"区間\(p.stepIndex+1)・残り\(Int(p.remainingDistance))m・\(p.maneuver.text)・経路から\(Int(p.offRouteDistance))m") }
            LabeledContent("案内",value:store.navigating ? "案内中（\(store.guidanceMode == .map ? "地図":"カメラ")）":"停止")
            LabeledContent("カメラ",value:store.camera.running ? String(format:"%.1f fps・推論%.0fms",store.camera.framesPerSecond,store.camera.inferenceLatency*1000):"停止")
            LabeledContent("深度",value:store.camera.depthStatus)
            LabeledContent("頭の高さの障害物",value:store.camera.headLevel.map { String(format:"%@ 前方%.2fm・横%.2fm・高さ%.2fm・%d点",$0.stage == .danger ? "危険":"注意",$0.distance,$0.lateral,$0.height,$0.count) } ?? "なし")
            LabeledContent("音声",value:"\(store.speech.status)・待機\(store.speech.pending)")
            LabeledContent("報告",value:"\(store.reports.count)件・\(store.simulated ? "模擬領域":"実領域")")
            LabeledContent("熱状態 / 電池",value:"\(ProcessInfo.processInfo.thermalState.rawValue) / \(UIDevice.current.batteryLevel>=0 ? String(format:"%.0f%%",UIDevice.current.batteryLevel*100):"取得不可")")
        }
        Section("ARカメラ表示") {
            Toggle("学習モデルのBBOXを表示",isOn:$store.showBoxes).accessibilityIdentifier("toggleBoxes")
            Toggle("BBOXにクラス名・信頼度を表示",isOn:$store.showBoxLabels).disabled(!store.showBoxes)
            Slider(value:$store.boxMinConfidence,in:0.05...0.95) { Text("BBOX表示の最低信頼度") };Text("BBOX表示の最低信頼度 \(store.boxMinConfidence,specifier:"%.2f")（音声通知の閾値とは別）").font(.caption)
            Text("現在の検出 \(store.camera.detections.count)件\(store.camera.simulatedDetections ? "（模擬）":"")").font(.caption)
            Toggle("AR方向矢印を表示",isOn:$store.showARArrow)
            Slider(value:$store.headingOffset,in:-45...45,step:1) { Text("方位補正") };Text("方位補正 \(Int(store.headingOffset))°（端末の装着角のずれを補正）").font(.caption)
            Slider(value:$store.arrowCameraHeight,in:0.8...1.8,step:0.05) { Text("カメラの高さ") };Text("カメラの高さ \(store.arrowCameraHeight,specifier:"%.2f") m（3D矢印の路面位置合わせ）").font(.caption)
            Slider(value:$store.arrowDistance,in:1.5...6,step:0.5) { Text("矢印までの距離") };Text("矢印までの距離 \(store.arrowDistance,specifier:"%.1f") m").font(.caption)
            if store.simulated {
                Slider(value:Binding(get:{ store.location.heading?.degrees ?? 0 },set:{ store.location.simulateHeading($0) }),in:0...359,step:1) { Text("模擬方位") }
                Text("模擬方位 \(Int(store.location.heading?.degrees ?? 0))°").font(.caption)
            }
            Text("BBOXはDeveloperModeでのみ全面カメラに重ねます。矢印は方位と位置からの概算で、端末の傾きに合わせて仮想の路面に描きます。路面検出・世界座標への固定はしません。").font(.caption)
        }
        Section("頭の高さの障害物（深度）") {
            LabeledContent("深度",value:store.camera.depthStatus)
            tune("進行方向の幅（片側） corridorHalfWidth",\.corridorHalfWidth,0.2...1.0,0.05,"m")
            tune("最小距離 minDistance",\.minDistance,0.1...1.0,0.05,"m")
            tune("最大距離 maxDistance",\.maxDistance,1.0...4.0,0.1,"m")
            tune("高さの下限（床から） minHeight",\.minHeight,0.5...1.6,0.05,"m")
            tune("高さの上限（床から） maxHeight",\.maxHeight,1.4...2.5,0.05,"m")
            tune("危険とみなす距離 dangerDistance",\.dangerDistance,0.5...2.0,0.1,"m")
            Stepper("必要な点の数 minPoints \(store.headLevelConfig.minPoints)",value:$store.headLevelConfig.minPoints,in:3...60)
            Stepper("読み上げまでの連続検出 persistence \(store.headLevelTiming.persistence)回",value:$store.headLevelTiming.persistence,in:1...6)
            Slider(value:$store.headLevelTiming.cooldown,in:1...15,step:0.5) { Text("同じ段階の再読み上げ間隔 cooldown") };Text("同じ段階の再読み上げ間隔 cooldown \(store.headLevelTiming.cooldown,specifier:"%.1f") 秒").font(.caption)
            Slider(value:$store.headLevelTiming.clearAfter,in:0.2...3,step:0.1) { Text("解消とみなすまで clearAfter") };Text("解消とみなすまで clearAfter \(store.headLevelTiming.clearAfter,specifier:"%.1f") 秒").font(.caption)
            Button("既定値に戻す") { store.resetHeadLevelTuning() }
            Text("危険／注意は dangerDistance で切り替わります（それ以内が危険）。変数は Core/HeadLevel.swift の HeadLevelConfig・HeadLevelTiming。床を推定できない場合は「カメラの高さ」（arrowCameraHeight）を使います。判定は約0.2秒ごとです。").font(.caption)
        }
        Section("実験位置") {
            Toggle("模擬位置・模擬報告",isOn:Binding(get:{store.simulated},set:{store.switchSimulation($0)})).accessibilityIdentifier("toggleSimulation")
            if store.simulated {
                Picker("模擬出発区間",selection:Binding(get:{store.matchedEdge ?? ""},set:{if let e=store.edge($0) { store.simulateAtEdge(e) }})) { Text("区間を選択").tag("");ForEach(store.edges.filter { $0.name != "名称未登録の歩行区間" && $0.name != "名称未登録の道路" }.prefix(200)) { Text(store.edgeDescription($0)).tag($0.id) } }
                HStack { Button("北へ5m") { move(0.000045,0) };Button("南へ5m") { move(-0.000045,0) } }
                HStack { Button("西へ5m") { move(0,-0.000054) };Button("東へ5m") { move(0,0.000054) } }
                Button(store.simulatedWalkActive ? "経路の模擬歩行を停止":"経路に沿って模擬歩行") { if store.simulatedWalkActive { store.stopSimulatedWalk() } else { store.startSimulatedWalk() } }.disabled(store.route == nil).accessibilityIdentifier("simulatedWalk")
                Slider(value:$store.simulatedWalkSpeed,in:0.5...5,step:0.1) { Text("模擬歩行速度") };Text("模擬歩行 \(store.simulatedWalkSpeed,specifier:"%.1f") m/秒").font(.caption)
            }
            Text(store.positionState);Text("道路候補：\(store.matchedEdge ?? "未確定")")
        }
        Section("道路・経路") { Text("版：\(store.network?.version ?? "なし")");Text("軌跡 \(store.trace.count)点・候補 \(store.traceCandidates.count)・確定 \(store.selected.count)・曖昧 \(store.ambiguity ? "あり":"なし")");Text("経路版 \(store.routeVersion)・再検索 \(store.reroutes)");Button("地図を対応範囲全体に移動") { store.focus(.network) };Button("模擬領域の全区間を閉鎖") { store.closeAll() }.disabled(!store.simulated) }
        Section("認識・通知") {
            Text("指定モデル：\(DetectionModel.name)");Text("ファイル記述：640×640 / confidence・coordinates / 39クラス。端末内での推論状態は下に表示")
            Text(store.camera.modelStatus)
            Slider(value:Binding(get:{store.camera.filter.confidence},set:{store.camera.filter.confidence=$0}),in:0.3...0.95) { Text("信頼度閾値") };Text("通知の信頼度閾値 \(store.camera.filter.confidence,specifier:"%.2f")")
            Slider(value:Binding(get:{store.camera.filter.persistence},set:{store.camera.filter.persistence=$0}),in:0.2...2) { Text("継続秒") };Text("継続 \(store.camera.filter.persistence,specifier:"%.1f")秒")
            Slider(value:Binding(get:{store.camera.filter.cooldown},set:{store.camera.filter.cooldown=$0}),in:3...30) { Text("通知間隔秒") };Text("通知間隔 \(store.camera.filter.cooldown,specifier:"%.0f")秒")
            Button("ポールの模擬継続検出（BBOXにも表示）") { store.simulateNotice() }
            Text("模擬通知 \(store.simulatedNoticeCount)回（実認識の計測とは別）")
            Toggle("認識エラー注入",isOn:Binding(get:{store.camera.injectError},set:{store.camera.injectError=$0}))
            Text("推論 \(store.camera.inferenceCount)・通知 \(store.camera.notificationCount)・抑制 \(store.camera.suppressionCount)").accessibilityIdentifier("metricInference")
            Text("推論 \(store.camera.inferenceLatency,specifier:"%.3f")秒・通知決定 \(store.camera.decisionLatency,specifier:"%.3f")秒・\(store.camera.framesPerSecond,specifier:"%.1f") fps")
            Text("メモリ \(Double(store.camera.memoryBytes)/1_048_576,specifier:"%.1f") MB")
            ForEach(Array(store.camera.detections.prefix(5).enumerated()),id:\.offset) { _,d in Text("\(d.label) 信頼度\(d.confidence,specifier:"%.2f")・画像内枠 x\(d.box.x,specifier:"%.2f") y\(d.box.y,specifier:"%.2f") w\(d.box.width,specifier:"%.2f") h\(d.box.height,specifier:"%.2f")・取得\(d.capturedAt,specifier:"%.3f")") }
            Text("発話開始コールバック遅延：\(store.speech.lastStartLatency.map { String(format:"%.3f秒",$0) } ?? "未計測")。耳への到達時刻ではありません。")
        }
        Section("エラー注入・計測") {
            Toggle("保存失敗を注入",isOn:$saveFailure).onChange(of:saveFailure) { _,v in store.failSave(v) }
            Toggle("読み込み失敗を注入",isOn:$readFailure).onChange(of:readFailure) { _,v in store.failRead(v) }
            Text("\(UIDevice.current.model) / iOS \(UIDevice.current.systemVersion)")
            Button("ローカル計測ログを作成") { export=store.exportLog() }
            if let export { ShareLink("計測ログを書き出す",item:export) }
            Button("模擬報告と模擬検出をリセット",role:.destructive) { reset=true }
            Text("実道路報告はリセット対象に含みません。画像・位置履歴は保存しません。")
        }
        Section { Button("DeveloperModeを終了") { store.closeDeveloper() } }
    }.navigationTitle("DeveloperMode")
        .toolbar { ToolbarItem(placement:.primaryAction) { Button("ログ",systemImage:"list.bullet.rectangle") { showLog=true } } }
        .sheet(isPresented:$showLog) { NavigationStack { DebugLogScreen(modal:true) } }
        .confirmationDialog("模擬報告と模擬検出だけをリセットします",isPresented:$reset,titleVisibility:.visible) { Button("模擬データをリセット",role:.destructive) { store.resetSimulation() };Button("取消",role:.cancel) {} }
    }
    /// Slider for one `HeadLevelConfig` distance (Float) with its current value.
    private func tune(_ title:String,_ key:WritableKeyPath<HeadLevelConfig,Float>,_ range:ClosedRange<Double>,_ step:Double,_ unit:String)->some View {
        VStack(alignment:.leading,spacing:2) {
            Slider(value:Binding(get:{ Double(store.headLevelConfig[keyPath:key]) },set:{ store.headLevelConfig[keyPath:key]=Float($0) }),in:range,step:step) { Text(title) }
            Text("\(title) \(store.headLevelConfig[keyPath:key],specifier:"%.2f") \(unit)").font(.caption)
        }
    }
    private func move(_ lat:Double,_ lon:Double) { if let p=store.location.sample { store.moveSimulation(to:Coordinate(p.coordinate.latitude+lat,p.coordinate.longitude+lon)) } }
}
