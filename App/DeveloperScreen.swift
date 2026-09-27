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
            LabeledContent("歩ける範囲",value:store.camera.walkable.map { w in
                [w.blockedAhead.map { String(format:"正面%.1fm障害物",$0) },w.dropAhead.map { String(format:"正面%.1fm下り段差",$0) },w.passSide.map { "\($0.japanese)へ回避可" },
                 w.left.map { String(format:"左端%.2fm",$0.distance) },w.right.map { String(format:"右端%.2fm",$0.distance) },w.groundSeen ? "床あり":"床なし"].compactMap { $0 }.joined(separator:"・") } ?? "なし")
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
            tune("危険とみなす距離 dangerDistance",\.dangerDistance,0.5...3.0,0.1,"m")
            Stepper("必要な点の数 minPoints \(store.headLevelConfig.minPoints)",value:$store.headLevelConfig.minPoints,in:3...60)
            Stepper("読み上げまでの連続検出 persistence \(store.headLevelTiming.persistence)回",value:$store.headLevelTiming.persistence,in:1...6)
            Slider(value:$store.headLevelTiming.cooldown,in:1...15,step:0.5) { Text("同じ段階の再読み上げ間隔 cooldown") };Text("同じ段階の再読み上げ間隔 cooldown \(store.headLevelTiming.cooldown,specifier:"%.1f") 秒").font(.caption)
            Slider(value:$store.headLevelTiming.clearAfter,in:0.2...3,step:0.1) { Text("解消とみなすまで clearAfter") };Text("解消とみなすまで clearAfter \(store.headLevelTiming.clearAfter,specifier:"%.1f") 秒").font(.caption)
            Button("既定値に戻す") { store.resetHeadLevelTuning() }
            Text("危険／注意は dangerDistance で切り替わります（それ以内が危険）。変数は Core/HeadLevel.swift の HeadLevelConfig・HeadLevelTiming。床を推定できない場合は「カメラの高さ」（arrowCameraHeight）を使います。判定は約0.2秒ごとです。").font(.caption)
        }
        Section("歩ける範囲（深度）") {
            LabeledContent("判定",value:store.camera.walkable.map { w in [w.blockedAhead.map { String(format:"正面%.1fm障害物",$0) },w.dropAhead.map { String(format:"正面%.1fm段差",$0) },w.passSide.map { "\($0.japanese)へ回避可" },w.width.map { String(format:"幅%.2fm",$0) }].compactMap { $0 }.joined(separator:"・") } ?? "なし")
            dialF("対象の最小前方距離 nearest",$store.walkableConfig.nearest,0.2...1.5,0.1,"m")
            dialF("対象の最大前方距離 farthest",$store.walkableConfig.farthest,1.5...4,0.1,"m")
            dialF("対象の左右幅（片側） halfWidth",$store.walkableConfig.halfWidth,0.8...2,0.1,"m")
            dialF("障害物とみなす高さ obstacleHeight",$store.walkableConfig.obstacleHeight,0.05...0.4,0.01,"m")
            dialF("床とみなす高さの幅 groundTolerance",$store.walkableConfig.groundTolerance,0.03...0.2,0.01,"m")
            dialF("段差とみなす低さ dropHeight",$store.walkableConfig.dropHeight,0.05...0.3,0.01,"m")
            Stepper("帯ごとに必要な点の数 minPoints \(store.walkableConfig.minPoints)",value:$store.walkableConfig.minPoints,in:1...20)
            dialF("自分の進路の幅（片側） corridorHalf",$store.walkableConfig.corridorHalf,0.15...0.6,0.05,"m")
            dialF("避けるのに必要な幅 passWidth",$store.walkableConfig.passWidth,0.3...1.2,0.05,"m")
            dialF("「道が狭い」とする幅 narrowWidth",$store.walkableConfig.narrowWidth,0.5...1.5,0.05,"m")
            dialF("端に近いとする距離 edgeNear",$store.walkableConfig.edgeNear,0.15...0.8,0.05,"m")
            dialF("障害物を知らせる距離 blockedDistance",$store.walkableTiming.blockedDistance,0.5...3,0.1,"m")
            dialF("「目の前」とみなす距離 criticalDistance",$store.walkableTiming.criticalDistance,0.3...3,0.1,"m")
            dialF("段差を知らせる距離 dropDistance",$store.walkableTiming.dropDistance,0.5...3,0.1,"m")
            Stepper("読み上げまでの連続検出 persistence \(store.walkableTiming.persistence)回",value:$store.walkableTiming.persistence,in:1...6)
            dial("緊急の繰り返し間隔 repeatCritical",$store.walkableTiming.repeatCritical,1...10,0.5,"秒")
            dial("高の繰り返し間隔 repeatHigh",$store.walkableTiming.repeatHigh,2...20,1,"秒")
            dial("通常の繰り返し間隔 repeatNormal",$store.walkableTiming.repeatNormal,4...40,1,"秒")
            Button("周囲の読み上げ・歩ける範囲を既定値に戻す") { store.resetSceneTuning() }
            Text("WalkableConfig・WalkableTiming（Core/Walkable.swift）。認識・通知の NoticeTuning も上のボタンで戻ります。").font(.caption)
        }
        Section("危険度の距離（緊急・高・通常）") {
            Text("物体（危険の分類）").font(.subheadline.bold())
            dial("緊急：この距離以内 criticalDistance",$store.noticeTuning.criticalDistance,0.5...5,0.1,"m")
            dial("知らせ始める距離（遠い物は読まない） announceDistance",$store.noticeTuning.announceDistance,1...10,0.5,"m")
            Text("人・車などは下の「ラベルごとの危険度」で「読まない」が既定です。").font(.caption)
            Text("歩ける範囲").font(.subheadline.bold())
            dialF("緊急：この距離以内 criticalDistance",$store.walkableTiming.criticalDistance,0.3...3,0.1,"m")
            dialF("高：障害物をこの距離以内で知らせる blockedDistance",$store.walkableTiming.blockedDistance,0.5...4,0.1,"m")
            dialF("高：段差をこの距離以内で知らせる dropDistance",$store.walkableTiming.dropDistance,0.5...4,0.1,"m")
            dialF("判定する前方の最大距離 farthest",$store.walkableConfig.farthest,1.5...4,0.1,"m")
            dialF("通常：端までの横の距離 edgeNear",$store.walkableConfig.edgeNear,0.15...0.8,0.05,"m")
            dialF("通常：「道が狭い」とする幅 narrowWidth",$store.walkableConfig.narrowWidth,0.5...1.5,0.05,"m")
            Text("頭上の障害物").font(.subheadline.bold())
            tune("緊急：この距離以内 dangerDistance",\.dangerDistance,0.5...3.0,0.1,"m")
            tune("知らせ始める距離 maxDistance",\.maxDistance,1.0...4.0,0.1,"m")
            tune("ブザーが鳴り続ける距離（0で無効） buzzerDistance",\.buzzerDistance,0...2.0,0.1,"m")
            dial("ブザーの高さ buzzerFrequency",$store.feedbackTuning.buzzerFrequency,300...2000,20,"Hz")
            Text("緊急＝警告音3回＋強い振動・赤、高＝警告音2回＋警告の振動・橙、通常＝警告音1回・振動なし・青。頭上の障害物が buzzerDistance 以内にある間はブザーが鳴り続ける（危険の警告音がオフなら鳴らない）。歩ける範囲は farthest より先は見ないため、blockedDistance・dropDistance は farthest 以下で効きます。深度で距離がわからない物体は「高」。").font(.caption)
        }
        Section("ラベルごとの危険度（NoticeTuning.tiers）") {
            ForEach(SceneCatalog.classes.keys.sorted { a,b in
                let ta=SceneCatalog.tier(a,overrides:store.noticeTuning.tiers)!,tb=SceneCatalog.tier(b,overrides:store.noticeTuning.tiers)!
                return ta != tb ? ta > tb:a < b
            },id:\.self) { label in
                Picker(selection:Binding(get:{ SceneCatalog.tier(label,overrides:store.noticeTuning.tiers)! },set:{ store.setTier($0,for:label) })) {
                    ForEach([SceneTier.hazard,.landmark,.context,.off],id:\.self) { Text($0.japanese).tag($0) }
                } label: {
                    VStack(alignment:.leading) {
                        Text("\(SceneCatalog.classes[label]!.name) \(label)")
                        if store.noticeTuning.tiers[label] != nil { Text("変更済み（既定：\(SceneCatalog.classes[label]!.tier.japanese)）").font(.caption).foregroundStyle(.orange) }
                    }
                }
            }
            Button("危険度を既定値に戻す") { store.noticeTuning.tiers=[:] }
            Text("危険＝警告音・振動・高頻度、目印＝音声のみ・中頻度、周辺＝設定で有効時のみ・低頻度、読まない＝読み上げ・目印表示なし。変更は読み上げ・画面の周囲一覧・目印にすぐ反映され、保存されます。").font(.caption)
        }
        Section("効果音・振動・カメラ案内") {
            Toggle("危険の警告音 hazardSounds",isOn:$store.hazardSounds)
            dial("「直進です。」の間隔 straightInterval（0で読まない）",$store.straightInterval,0...30,1,"秒")
            Toggle("頭の高さの障害物 headLevelWarnings",isOn:$store.headLevelWarnings)
            Toggle("歩ける範囲・段差 walkableWarnings",isOn:$store.walkableWarnings)
            Toggle("周辺の目印も読み上げ speakSurroundings",isOn:$store.speakSurroundings)
            Toggle("矢印の方向を読み上げ speakDirection",isOn:$store.speakDirection)
            dial("緊急の音・振動の間隔 criticalInterval",$store.feedbackTuning.criticalInterval,0.2...1.5,0.05,"秒")
            Stepper("緊急の回数 criticalCount \(store.feedbackTuning.criticalCount)回",value:$store.feedbackTuning.criticalCount,in:1...6)
            dial("警告音の高さ hazardFrequency",$store.feedbackTuning.hazardFrequency,400...2400,20,"Hz")
            dial("警告音の長さ beepDuration",$store.feedbackTuning.beepDuration,0.03...0.25,0.01,"秒")
            dial("高（2回）の間隔 highGap",$store.feedbackTuning.highGap,0.02...0.5,0.01,"秒")
            dial("通常（1回）の高さ normalFrequency",$store.feedbackTuning.normalFrequency,400...2400,20,"Hz")
            dialF("警告音の音量 hazardVolume",$store.feedbackTuning.hazardVolume,0.05...1,0.05,"")
            Toggle("緊急の振動 vibrateCritical",isOn:$store.feedbackTuning.vibrateCritical)
            Toggle("高の振動 vibrateHigh",isOn:$store.feedbackTuning.vibrateHigh)
            Toggle("通常の振動 vibrateNormal",isOn:$store.feedbackTuning.vibrateNormal)
            HStack {
                Button("緊急") { AlertFeedback.hazard(.critical) };Button("高") { AlertFeedback.hazard(.high) };Button("通常") { AlertFeedback.hazard(.normal) }
            }.buttonStyle(.bordered)
            Button("効果音・振動を既定値に戻す") { store.feedbackTuning=FeedbackTuning() }
            Text("FeedbackTuning（Core/Earcon.swift）。上の3つのボタンで今の設定を試せます。警告音のオン／オフは設定画面と共通です。道案内は音声のみ（警告音・振動なし）。").font(.caption)
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
        Section("道路・経路") { Text("版：\(store.network?.version ?? "なし")");Text("候補 \(store.roadCandidates.count)・確定 \(store.selected.count)・曖昧 \(store.ambiguity ? "あり":"なし")");Text("経路版 \(store.routeVersion)・再検索 \(store.reroutes)");Button("地図を対応範囲全体に移動") { store.focus(.network) };Button("模擬領域の全区間を閉鎖") { store.closeAll() }.disabled(!store.simulated) }
        Section("認識・通知") {
            Text("指定モデル：\(DetectionModel.name)");Text("ファイル記述：640×640 / confidence・coordinates / 39クラス。端末内での推論状態は下に表示")
            Text(store.camera.modelStatus)
            dial("通知の信頼度閾値 confidence",$store.noticeTuning.confidence,0.3...0.95,0.05,"")
            dial("読み上げまでの継続 persistence",$store.noticeTuning.persistence,0.2...2,0.1,"秒")
            dial("基本の通知間隔 cooldown",$store.noticeTuning.cooldown,3...30,1,"秒")
            dial("危険の間隔倍率 hazardCooldown",$store.noticeTuning.hazardCooldown,0.5...3,0.1,"倍")
            dial("目印の間隔倍率 landmarkCooldown",$store.noticeTuning.landmarkCooldown,0.5...6,0.5,"倍")
            dial("周辺の間隔倍率 contextCooldown",$store.noticeTuning.contextCooldown,1...12,0.5,"倍")
            dial("危険の繰り返し間隔 hazardRepeat",$store.noticeTuning.hazardRepeat,3...30,1,"秒")
            dial("「目の前」とみなす距離 criticalDistance",$store.noticeTuning.criticalDistance,0.5...3,0.1,"m")
            Text("NoticeTuning（Core/Detection.swift）。間隔は cooldown × 倍率。criticalDistance 以内の危険は緊急（強い3連続の振動・赤）になり「目の前／すぐ左／すぐ右」と読みます。").font(.caption)
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
    /// Slider with its current value; `title` includes the variable name.
    private func dial(_ title:String,_ value:Binding<Double>,_ range:ClosedRange<Double>,_ step:Double,_ unit:String)->some View {
        VStack(alignment:.leading,spacing:2) {
            Slider(value:value,in:range,step:step) { Text(title) }
            Text("\(title) \(value.wrappedValue,specifier:"%.2f") \(unit)").font(.caption)
        }
    }
    private func dialF(_ title:String,_ value:Binding<Float>,_ range:ClosedRange<Double>,_ step:Double,_ unit:String)->some View {
        dial(title,Binding(get:{ Double(value.wrappedValue) },set:{ value.wrappedValue=Float($0) }),range,step,unit)
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
