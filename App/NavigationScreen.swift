import SwiftUI


/// One full-screen container so switching map ↔ camera does not dismiss/re-present covers.
struct GuidanceContainer:View {
    @EnvironmentObject var store:AppStore
    var body:some View {
        Group { if store.guidanceMode == .camera { CameraScreen() } else { NavigationModeScreen() } }
    }
}

extension RouteProgress {
    var walkingMinutes:Int { max(1,Int((remainingDistance/1.0/60).rounded(.up))) }
}

struct NavigationModeScreen:View {
    @EnvironmentObject var store:AppStore
    @State private var report=false
    @State private var steps=false
    @State private var stop=false
    @State private var bannerHeight:CGFloat=160
    @State private var barHeight:CGFloat=160
    var body:some View {
        GeometryReader { geometry in
            ZStack {
                GuideMap(store:store,mode:.navigation,insets:UIEdgeInsets(top:bannerHeight+geometry.safeAreaInsets.top,left:0,bottom:barHeight+geometry.safeAreaInsets.bottom,right:0)).ignoresSafeArea().accessibilityIdentifier("navigationMap")
                VStack(spacing:10) {
                    InstructionBanner().onGeometryChange(for:CGFloat.self) { $0.size.height } action: { bannerHeight=$0 }
                    Spacer()
                    HStack { Spacer();Button("現在位置に戻る",systemImage:"location.north.circle.fill") { store.focus(.user) }.labelStyle(.iconOnly).font(.largeTitle).foregroundStyle(.blue).frame(width:60,height:60).background(Circle().fill(Color(.systemBackground)).shadow(radius:4)) }
                    bottomBar.onGeometryChange(for:CGFloat.self) { $0.size.height } action: { barHeight=$0 }
                }.padding(.horizontal,12).padding(.vertical,6)
            }
        }
        .sheet(isPresented:$report) { NavigationStack { ReportScreen() } }
        .sheet(isPresented:$steps) { NavigationStack { RouteList().toolbar { ToolbarItem(placement:.confirmationAction) { Button("閉じる") { steps=false } } } } }
        .confirmationDialog("案内・待機音声を停止します",isPresented:$stop,titleVisibility:.visible) { Button("案内を終了",role:.destructive) { store.stopNavigation();store.closeGuidance() };Button("取消",role:.cancel) {} }
    }
    private var bottomBar:some View {
        VStack(spacing:12) {
            HStack(alignment:.firstTextBaseline) {
                if let p=store.progress,store.navigating {
                    VStack(alignment:.leading,spacing:2) {
                        Text(localized("徒歩目安 約{0}分",p.walkingMinutes)).font(.title2.bold()).foregroundStyle(.green)
                        Text(localized("残り約{0} m・{1}",Int(p.remainingDistance.rounded()),store.targetName)).font(.subheadline).foregroundStyle(.secondary)
                    }.accessibilityElement(children:.combine)
                } else { Text(localized(store.navigating ? "位置を確認中":"案内停止中")).font(.title3.bold()) }
                Spacer()
                Button(localized(store.navigating ? "終了":"閉じる")) { if store.navigating { stop=true } else { store.closeGuidance() } }.font(.headline).buttonStyle(.borderedProminent).tint(.red).accessibilityIdentifier("endNavigation")
            }
            HStack(spacing:8) {
                barButton("再読み上げ",symbol:"speaker.wave.2.fill") { store.repeatInstruction() }
                barButton("カメラ案内",symbol:"camera.viewfinder") { store.switchGuidance(to:.camera) }.accessibilityIdentifier("navSwitchCamera")
                barButton("通行不可",symbol:"exclamationmark.triangle.fill") { report=true }
                barButton("経路一覧",symbol:"list.number") { steps=true }
            }
            Button("地図・目的地選択へ",systemImage:"map") { store.closeGuidance() }.font(.subheadline).frame(minHeight:36)
        }
        .padding(14).background(RoundedRectangle(cornerRadius:22).fill(Color(.systemBackground)).shadow(color:.black.opacity(0.2),radius:8,y:-2))
    }
    private func barButton(_ title:String,symbol:String,action:@escaping ()->Void)->some View {
        Button(action:action) { VStack(spacing:4) { Image(systemName:symbol).font(.title3);Text(localized(title)).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7) }.frame(maxWidth:.infinity,minHeight:52) }.buttonStyle(.bordered)
    }
}

/// Next-maneuver banner shared by map and camera guidance.
struct InstructionBanner:View {
    @EnvironmentObject var store:AppStore
    var compact=false
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            if store.navigating,let p=store.progress {
                HStack(spacing:14) {
                    Image(systemName:p.maneuver.symbol).font(.system(size:compact ? 36:48,weight:.bold)).frame(width:compact ? 48:64).accessibilityHidden(true)
                    VStack(alignment:.leading,spacing:2) {
                        Text("\(Int(p.distanceToStepEnd.rounded())) m").font(compact ? .title.bold():.largeTitle.bold())
                        Text(p.maneuver == .arrive ? localized("先で案内の終点"):localized("先の接続点で{0}",localized(p.maneuver.text))).font(.headline)
                        if let step=store.route?.steps[safe:p.stepIndex] { Text(store.stepName(step)).font(.subheadline).opacity(0.9) }
                    }
                    Spacer(minLength:0)
                }.accessibilityElement(children:.combine)
                Text(localized(store.nextInstruction)).font(.callout).opacity(0.95)
            } else {
                Text(localized(store.navigating ? store.nextInstruction:store.route == nil ? "経路が未設定です。目的地を選び、経路を確認して開始してください":store.nextInstruction)).font(.title3.bold())
            }
            if store.matchedEdge == nil { Label(localized(store.positionState),systemImage:"location.slash").font(.subheadline.bold()).padding(.horizontal,10).padding(.vertical,6).background(Capsule().fill(Color.orange)) }
        }
        .foregroundStyle(.white).padding(16).frame(maxWidth:.infinity,alignment:.leading)
        .background(RoundedRectangle(cornerRadius:20).fill(Color(red:0.05,green:0.42,blue:0.28)).shadow(color:.black.opacity(0.25),radius:8,y:3))
        .accessibilityElement(children:.contain).accessibilityIdentifier("instructionBanner")
    }
}

extension Array { subscript(safe index:Int)->Element? { indices.contains(index) ? self[index]:nil } }
