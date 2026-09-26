import SwiftUI

/// Compass-relative HUD arrow. Not anchored to the world; accuracy depends on GPS and the magnetometer.
struct ARDirectionIndicator:View {
    @EnvironmentObject var store:AppStore
    var body:some View {
        let state=guidance
        VStack(spacing:6) {
            if let angle=state.angle {
                Image(systemName:"location.north.fill").font(.system(size:72,weight:.bold)).foregroundStyle(abs(angle)<15 ? Color.green:Color.yellow)
                    .rotationEffect(.degrees(angle)).shadow(color:.black.opacity(0.6),radius:6).animation(.easeOut(duration:0.25),value:angle).accessibilityHidden(true)
            } else { Image(systemName:"questionmark.circle").font(.system(size:48)).foregroundStyle(.white.opacity(0.8)).accessibilityHidden(true) }
            Text(state.text).font(.headline).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
            Button("方向を読み上げ",systemImage:"speaker.wave.2") { store.speech.say(state.spoken) }.font(.subheadline.bold()).buttonStyle(.bordered).tint(.white)
        }
        .foregroundStyle(.white).padding(14).background(RoundedRectangle(cornerRadius:20).fill(.black.opacity(0.45)))
        .accessibilityElement(children:.contain).accessibilityLabel(state.spoken).accessibilityIdentifier("arDirection")
    }
    private var guidance:(angle:Double?,text:String,spoken:String) {
        guard store.navigating,let p=store.progress,let sample=store.location.sample else { return (nil,"経路案内中のみ方向を表示します","経路案内中ではありません") }
        guard store.matchedEdge != nil else { return (nil,"位置を確認中。方向を保留します","位置を確認中のため方向を保留します") }
        guard let heading=store.heading,store.headingReliable else { return (nil,"方位の精度が低いため矢印を表示しません","方位の精度が低いため方向を保留します") }
        let angle=RouteTracker.relativeBearing(from:sample.coordinate,to:p.lookahead,heading:heading)
        let degrees=Int(abs(angle).rounded())
        let direction=abs(angle)<15 ? "正面方向":abs(angle)>150 ? "後ろ方向・約\(degrees)°":"\(angle>0 ? "右":"左")へ約\(degrees)°"
        let text="\(direction)\n次の接続点まで約\(Int(p.distanceToStepEnd.rounded())) m・\(p.maneuver.text)"
        let spoken="進む方向は\(abs(angle)<15 ? "ほぼ正面":abs(angle)>150 ? "後ろ":"\(angle>0 ? "右":"左")に約\(degrees)度")です。方位は概算です。足元と周囲を同行者と確認してください。"
        return (angle,text,spoken)
    }
}

enum DetectionNames {
    static let japanese=DetectionLabels.japanese
    static func color(_ label:String)->Color { label == "person" ? .yellow:japanese[label] != nil ? .orange:.cyan }
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
                    Text("\(DetectionNames.japanese[d.label] ?? d.label) \(d.confidence,specifier:"%.2f")\(d.simulated ? " 模擬":"")").font(.caption.bold().monospacedDigit()).foregroundStyle(.black)
                        .padding(.horizontal,4).padding(.vertical,2).background(color).fixedSize().position(x:rect.minX+40,y:max(10,rect.minY-10))
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct CameraScreen:View {
    @EnvironmentObject var store:AppStore
    @State private var report=false
    @State private var stop=false
    @State private var details=false
    @State private var settings=false
    @Environment(\.dynamicTypeSize) private var textSize
    var body:some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session:store.camera.engine.session).ignoresSafeArea().accessibilityHidden(true)
            if store.developer && store.showBoxes { DetectionOverlay(detections:store.camera.detections,minConfidence:store.boxMinConfidence,showLabels:store.showBoxLabels).ignoresSafeArea() }
            if !store.camera.running && !(store.navigating && store.showARArrow) { Text("カメラ停止中").font(.title.bold()).foregroundStyle(.white) }
            VStack(spacing:8) {
                if store.navigating { InstructionBanner(compact:true) }
                ScrollView { VStack(alignment:.leading,spacing:8) {
                    if !store.navigating { Text(store.route == nil ? "避難先を選び、経路を確認して案内を開始してください":store.nextInstruction).font(.title2.bold()).accessibilityAddTraits(.isHeader) }
                    Text(store.targetName).font(.headline)
                    Text(store.camera.status).accessibilityIdentifier("cameraStatus")
                    Text(store.camera.labels)
                    if details { Text(store.positionState);Text("モデル："+store.camera.modelStatus);Text("画像内の候補です。距離・通行可能性・回避方向は判断しません。") }
                }.frame(maxWidth:.infinity,alignment:.leading).padding() }.frame(maxHeight:textSize.isAccessibilitySize ? 220:(store.navigating ? 110:170)).background(.regularMaterial,in:RoundedRectangle(cornerRadius:18))
                Spacer(minLength:8)
                if store.navigating && store.showARArrow { ARDirectionIndicator() }
                ScrollView { VStack(spacing:10) {
                    PrimaryButton(title:store.camera.running ? "カメラと通知を停止":"カメラと通知を開始",symbol:store.camera.running ? "stop.fill":"camera",destructive:store.camera.running) { if store.camera.running { store.camera.stop();store.speech.stop() } else { store.camera.start() } }
                    PrimaryButton(title:"案内を再読み上げ",symbol:"speaker.wave.2") { store.repeatInstruction() }
                    if store.navigating { Button("地図ナビに切り替え",systemImage:"map.fill") { store.switchGuidance(to:.map) }.frame(minHeight:48).accessibilityIdentifier("switchToMapNavigation") }
                    Button(details ? "状態表示を縮小":"状態表示を展開",systemImage:"info.circle") { details.toggle() }.frame(minHeight:48)
                    Button("通行不可を登録",systemImage:"exclamationmark.triangle") { report=true }.frame(minHeight:48)
                    Button("設定",systemImage:"gearshape") { settings=true }.frame(minHeight:48)
                    Button("案内を停止",role:.destructive) { stop=true }.frame(minHeight:48)
                }.padding() }.accessibilityIdentifier("cameraControls").frame(maxHeight:textSize.isAccessibilitySize ? 300:(store.navigating ? 200:250)).background(.regularMaterial,in:RoundedRectangle(cornerRadius:18))
                Button("地図・避難先選択へ",systemImage:"map") { store.closeGuidance() }.font(.headline).frame(maxWidth:.infinity,minHeight:48).padding(10).background(.regularMaterial,in:RoundedRectangle(cornerRadius:14))
            }.padding(.horizontal,12).padding(.vertical,8)
        }
        .sheet(isPresented:$report) { NavigationStack { ReportScreen() } }
        .sheet(isPresented:$settings) { NavigationStack { SettingsScreen().toolbar { ToolbarItem(placement:.confirmationAction) { Button("完了") { settings=false } } } } }
        .confirmationDialog("案内・カメラ・待機音声を停止します",isPresented:$stop,titleVisibility:.visible) { Button("停止",role:.destructive) { store.camera.stop();store.stopNavigation() };Button("取消",role:.cancel) {} }
    }
}
