import SwiftUI

/// The 3D ground arrow (`GroundArrowView`) carries the direction; this only exposes it to VoiceOver as one short phrase.
/// No visible card, no heading-accuracy text and no read-aloud button: direction changes are spoken automatically.
struct ARDirectionIndicator:View {
    @EnvironmentObject var store:AppStore
    var body:some View {
        let angle=store.cameraAngle
        Color.clear.frame(height:1)
            .accessibilityElement().accessibilityLabel(angle.map { localized("進む方向、{0}",DirectionBucket.of($0).phrase) } ?? localized("進む方向を確認中")).accessibilityIdentifier("arDirection")
    }
}

enum DetectionNames {
    static let japanese=DetectionLabels.japanese
    static func color(_ label:String,overrides:[String:SceneTier]=[:])->Color {
        switch SceneCatalog.tier(label,overrides:overrides) { case .hazard?: .orange; case .landmark?: .cyan; case .context?: .gray; case .off?: .white.opacity(0.4); case nil: .white }
    }
}

/// Colour and symbol per speech priority, shared by the on-screen surroundings list.
enum SceneStyle {
    static func color(_ p:SpeechPriority)->Color { switch p { case .critical: .red; case .high: .orange; case .normal: .blue; case .low: .gray } }
    static func symbol(_ p:SpeechPriority)->String { switch p { case .critical: "exclamationmark.octagon.fill"; case .high: "exclamationmark.triangle.fill"; case .normal: "mappin.circle.fill"; case .low: "info.circle.fill" } }
}

/// "Surroundings": head-level warning, walkable ground and detected objects, most useful first.
/// VoiceOver reads it as one element (all items, in the same order) and is told it changes often.
struct SceneList:View {
    let items:[SceneItem];let limit:Int
    var body:some View {
        VStack(alignment:.leading,spacing:3) {
            if items.isEmpty { Text("周囲の検出なし").font(.subheadline) }
            ForEach(Array(items.prefix(limit).enumerated()),id:\.offset) { _,item in
                Label(item.text,systemImage:SceneStyle.symbol(item.priority)).font(item.priority >= .high ? .subheadline.bold():.subheadline)
                    .padding(.horizontal,8).padding(.vertical,3).background(SceneStyle.color(item.priority).opacity(item.priority == .low ? 0.6:0.9),in:Capsule())
            }
        }
        .accessibilityElement(children:.ignore).accessibilityLabel(items.isEmpty ? "周囲の検出なし":"周囲。"+items.map(\.text).joined())
        .accessibilityAddTraits(.updatesFrequently).accessibilityIdentifier("sceneList")
    }
}

/// Model bounding boxes on the aspect-filled preview. Assumes the 640×480 buffer rotated to portrait (3:4).
struct DetectionOverlay:View {
    let detections:[Detection];let minConfidence:Double;let showLabels:Bool
    var body:some View {
        GeometryReader { geometry in
            let size=geometry.size,scale=max(size.width/3,size.height/4),w=3*scale,h=4*scale,ox=(size.width-w)/2,oy=(size.height-h)/2
            ForEach(Array(detections.filter { $0.confidence>=minConfidence }.enumerated()),id:\.offset) { _,d in
                let rect=CGRect(x:ox+d.box.x*w,y:oy+(1-d.box.y-d.box.height)*h,width:d.box.width*w,height:d.box.height*h)
                let color=DetectionNames.color(d.label)
                Rectangle().stroke(color,lineWidth:3).frame(width:rect.width,height:rect.height).position(x:rect.midX,y:rect.midY)
                if showLabels {
                    Text(localized("{0} {1}{2}",localized(DetectionNames.japanese[d.label] ?? d.label),String(format:"%.2f",d.confidence),d.simulated ? localized(" 模擬"):"")) .font(.caption.bold().monospacedDigit()).foregroundStyle(.black)
                        .padding(.horizontal,4).padding(.vertical,2).background(color).fixedSize().position(x:rect.minX+40,y:max(10,rect.minY-10))
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Detected objects marked on the preview like the reference design: a ringed dot at the object with its name below.
/// Visual only (VoiceOver gets the same information from the top bar).
struct SceneMarkers:View {
    let detections:[Detection];let minConfidence:Double;var tiers:[String:SceneTier]=[:]
    var body:some View {
        GeometryReader { geometry in
            // Same aspect-fill mapping as `DetectionOverlay`: the 3:4 portrait frame fills the screen.
            let size=geometry.size,scale=max(size.width/3,size.height/4),w=3*scale,h=4*scale,ox=(size.width-w)/2,oy=(size.height-h)/2
            ForEach(Array(detections.filter { $0.confidence>=minConfidence && (SceneCatalog.tier($0.label,overrides:tiers) ?? .off) != .off }.prefix(8).enumerated()),id:\.offset) { _,d in
                let x=ox+(d.box.x+d.box.width/2)*w,y=oy+(1-d.box.y-d.box.height/2)*h
                VStack(spacing:6) {
                    Circle().fill(.white).frame(width:26,height:26).overlay(Circle().fill(.black).frame(width:14,height:14))
                    Text(DetectionNames.japanese[d.label] ?? d.label).font(.title2.weight(.semibold)).foregroundStyle(.white).shadow(color:.black.opacity(0.8),radius:3)
                }.fixedSize().position(x:x,y:y+18)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Colour of the top bar and the round buttons: the most urgent item decides it (yellow when nothing needs attention).
enum SceneBarStyle {
    static let calm=Color(red:0.92,green:0.73,blue:0.29)
    static func color(_ p:SpeechPriority?)->Color {
        switch p { case .critical?: Color(red:0.89,green:0.36,blue:0.25); case .high?: Color(red:0.93,green:0.52,blue:0.18); case .normal?: Color(red:0.20,green:0.47,blue:0.85); default: calm }
    }
}

struct CameraScreen:View {
    @EnvironmentObject var store:AppStore
    @State private var report=false
    @State private var stop=false
    @State private var details=false
    @State private var settings=false
    var body:some View {
        let items=store.sceneItems,top=items.first(where: { $0.priority > .low })
        let tint=SceneBarStyle.color(top?.priority)
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session:store.camera.engine.session).ignoresSafeArea().accessibilityHidden(true)
            if store.developer && store.showBoxes { DetectionOverlay(detections:store.camera.detections,minConfidence:store.boxMinConfidence,showLabels:store.showBoxLabels).ignoresSafeArea() }
            SceneMarkers(detections:store.camera.detections,minConfidence:store.noticeTuning.confidence,tiers:store.noticeTuning.tiers).ignoresSafeArea()
            if store.navigating && store.showARArrow,let angle=store.cameraAngle {
                GroundArrowView(angle:angle,cameraHeight:store.arrowCameraHeight,distance:store.arrowDistance,fieldOfView:store.camera.verticalFieldOfView).ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
            }
            if !store.camera.running && !(store.navigating && store.showARArrow) { stoppedHint }
            VStack(spacing:0) {
                topBar(top:top,items:items,tint:tint)
                if details { detailsCard(items).padding(.horizontal,12).padding(.top,8) }
                Spacer(minLength:8)
                if store.navigating && store.showARArrow { ARDirectionIndicator() }
                HStack {
                    roundButton(store.navigating ? "地図ナビに切り替え":"地図へ戻る",symbol:"map.fill",tint:tint,id:store.navigating ? "switchToMapNavigation":"cameraBack") {
                        if store.navigating { store.switchGuidance(to:.map) } else { store.closeGuidance() }
                    }
                    Spacer()
                    Menu {
                        Button("周囲を読み上げ",systemImage:"speaker.wave.2") { store.speakSurroundingsNow() }
                        Button(details ? "詳細を隠す":"詳細を表示",systemImage:"info.circle") { details.toggle() }
                        Button("通行不可を登録",systemImage:"exclamationmark.triangle") { report=true }
                        Button("設定",systemImage:"gearshape") { settings=true }
                        if store.navigating { Button("地図へ戻る",systemImage:"chevron.left") { store.closeGuidance() } }
                        Button("案内を停止",systemImage:"xmark.octagon",role:.destructive) { stop=true }
                    } label: { roundLabel(symbol:"line.3.horizontal",tint:tint) }.accessibilityLabel("メニュー").accessibilityIdentifier("cameraMenu")
                }.padding(.horizontal,24).padding(.bottom,8).accessibilityElement(children:.contain).accessibilityIdentifier("cameraControls")
            }
        }
        .animation(.easeOut(duration:0.2),value:top?.priority)
        // Spoken direction cues for the arrow, only while this screen is shown.
        .task { store.directionAnnouncer.reset();while !Task.isCancelled { store.announceDirection();try? await Task.sleep(for:.milliseconds(500)) } }
        .sheet(isPresented:$report) { NavigationStack { ReportScreen() } }
        .sheet(isPresented:$settings) { NavigationStack { SettingsScreen().toolbar { ToolbarItem(placement:.confirmationAction) { Button("完了") { settings=false } } } } }
        .confirmationDialog("案内・カメラ・待機音声を停止します",isPresented:$stop,titleVisibility:.visible) { Button("停止",role:.destructive) { store.camera.stop();store.stopNavigation() };Button("取消",role:.cancel) {} }
    }
    /// Full-width coloured bar: the single most important thing in large type, the route step below it while navigating.
    /// Tapping it reads the surroundings aloud; VoiceOver reads it first, with the other items as its value.
    private func topBar(top:SceneItem?,items:[SceneItem],tint:Color)->some View {
        let title=top.map { $0.text.trimmingCharacters(in:CharacterSet(charactersIn:"。")) } ?? (store.camera.running ? "障害物なし":store.camera.status)
        return VStack(alignment:.leading,spacing:6) {
            Text(title).font(.system(size:40,weight:.bold)).minimumScaleFactor(0.5).lineLimit(2)
            if store.navigating { Text(store.nextInstruction).font(.title3.weight(.semibold)).lineLimit(2).opacity(0.95) }
        }
        .foregroundStyle(.white).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,24).padding(.top,12).padding(.bottom,22)
        // The coloured shape runs up under the status bar, like the reference design.
        .background { UnevenRoundedRectangle(bottomLeadingRadius:22,bottomTrailingRadius:22).fill(tint).ignoresSafeArea(edges:.top) }
        .contentShape(Rectangle()).onTapGesture { store.speakSurroundingsNow() }
        .accessibilityElement(children:.ignore).accessibilityLabel(title)
        .accessibilityValue([store.navigating ? store.nextInstruction:nil,items.count > 1 ? "ほかに、"+items.dropFirst().map(\.text).joined():nil].compactMap { $0 }.joined(separator:" "))
        .accessibilityHint("ダブルタップで周囲を読み上げます").accessibilityAddTraits([.isHeader,.updatesFrequently,.isButton])
        .accessibilityAction { store.speakSurroundingsNow() }.accessibilitySortPriority(10).accessibilityIdentifier("sceneBar")
    }
    private func detailsCard(_ items:[SceneItem])->some View {
        VStack(alignment:.leading,spacing:4) {
            SceneList(items:items,limit:6)
            if !store.camera.running || store.camera.modelStatus == "未導入" { Text(store.camera.status).font(.subheadline).accessibilityIdentifier("cameraStatus") }
            Text(store.positionState).font(.subheadline);Text("モデル："+store.camera.modelStatus).font(.subheadline)
            Text("距離・歩ける範囲は2つのカメラの深度からの概算です。足元と周囲を同行者と確認してください。").font(.caption)
        }.frame(maxWidth:.infinity,alignment:.leading).padding(12).foregroundStyle(.white).background(.black.opacity(0.55),in:RoundedRectangle(cornerRadius:16))
    }
    private func roundLabel(symbol:String,tint:Color)->some View {
        Image(systemName:symbol).font(.system(size:34,weight:.semibold)).foregroundStyle(.white).frame(width:76,height:76).background(Circle().fill(tint)).shadow(color:.black.opacity(0.25),radius:6,y:3)
    }
    private func roundButton(_ title:String,symbol:String,tint:Color,id:String,action:@escaping ()->Void)->some View {
        Button(action:action) { roundLabel(symbol:symbol,tint:tint) }.buttonStyle(.plain).accessibilityLabel(title).accessibilityIdentifier(id)
    }
    private var stoppedHint:some View {
        VStack(spacing:8) {
            // The reason itself is in the top bar.
            Image(systemName:"video.slash").font(.largeTitle)
            Text("カメラは画面を開くと自動で起動します。起動しない場合は地図へ戻り、もう一度カメラボタンを押してください").font(.subheadline)
        }.foregroundStyle(.white).multilineTextAlignment(.center).padding(.horizontal,24).accessibilityHidden(true)
    }
}
