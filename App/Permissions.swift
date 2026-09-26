import SwiftUI
import UserNotifications
import CoreLocation
import AVFoundation

@MainActor final class TutorialPermissions:ObservableObject {
    @Published var notification="未確認"
    @Published var location="未確認"
    @Published var camera="未確認"
    @Published var requesting=false
    func refresh() async {
        let settings=await UNUserNotificationCenter.current().notificationSettings()
        notification=switch settings.authorizationStatus { case .authorized,.provisional,.ephemeral:"許可済み";case .denied:"許可なし";default:"未確認" }
        location=switch CLLocationManager().authorizationStatus { case .authorizedAlways,.authorizedWhenInUse:"許可済み";case .denied,.restricted:"許可なし";default:"未確認" }
        camera=switch AVCaptureDevice.authorizationStatus(for:.video) { case .authorized:"許可済み";case .denied,.restricted:"許可なし";default:"未確認" }
    }
    func requestNotification() async {
        requesting=true;defer { requesting=false }
        do { _=try await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound]) }
        catch { notification="確認できません：\(error.localizedDescription)";return }
        await refresh()
    }
    func requestCamera() async { requesting=true;_=await AVCaptureDevice.requestAccess(for:.video);requesting=false;await refresh() }
}
struct TutorialScreen:View {
    @EnvironmentObject var store:AppStore
    @AppStorage("tutorialComplete") private var complete=false
    @AppStorage("tutorialStep") private var step=0
    @StateObject private var permissions=TutorialPermissions()
    @Environment(\.scenePhase) private var phase
    var body:some View {
        ScrollView { VStack(alignment:.leading,spacing:24) {
            Text("避難ナビの使い方").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            Text("\(min(step,4)+1) / 5").accessibilityLabel("チュートリアル全5ページ中\(min(step,4)+1)ページ")
            Image(systemName:symbol).font(.system(size:64)).foregroundStyle(.blue).accessibilityHidden(true)
            Text(title).font(.title.bold()).accessibilityAddTraits(.isHeader)
            Text(message).font(.title3)
            if step==1 {
                Label("通知：\(permissions.notification)",systemImage:"bell")
                PrimaryButton(title:"通知の許可を確認",symbol:"bell.badge") { Task { await permissions.requestNotification() } }.disabled(permissions.requesting)
            } else if step==2 {
                Label("位置情報：\(permissions.location)",systemImage:"location")
                PrimaryButton(title:"位置情報の許可を確認",symbol:"location") { store.location.start() }
                Text(store.location.status).font(.subheadline)
            } else if step==3 {
                Label("カメラ：\(permissions.camera)",systemImage:"camera")
                PrimaryButton(title:"カメラの許可を確認",symbol:"camera") { Task { await permissions.requestCamera() } }.disabled(permissions.requesting)
            }
            if (step==1 && permissions.notification=="許可なし") || (step==2 && permissions.location=="許可なし") || (step==3 && permissions.camera=="許可なし") {
                Button("iOS設定を開く") { openAppSettings() }.frame(minHeight:48)
            }
            PrimaryButton(title:step==4 ? "避難先を選ぶ":step==0 ? "次へ":"次へ（後で設定も可能）",symbol:"arrow.right") { if step>=4 { complete=true;step=0 } else { step += 1 } }.accessibilityIdentifier("tutorialNext")
            if step>0 { Button("前の説明に戻る") { step -= 1 }.frame(minHeight:48) }
        }.padding(24) }.background(Color(.systemGroupedBackground))
        .task { await permissions.refresh() }
        .onChange(of:step) { _,_ in Task { await permissions.refresh() } }
        .onChange(of:phase) { _,value in if value == .active { Task { await permissions.refresh() } } }
    }
    var symbol:String { ["figure.walk","bell","location","camera","map"][min(max(step,0),4)] }
    var title:String { ["選んだ場所までの避難を支援","通知の許可","位置情報の許可","カメラの許可","地図とカメラで案内"][min(max(step,0),4)] }
    var message:String { switch step {
        case 1:return "iOSの通知を許可するか確認します。カメラの候補通知と経路の音声はアプリ内で行い、通知の許可がなくても使えます。現在のMVPでは災害情報のプッシュ配信はありません。"
        case 2:return "アプリ使用中の位置情報を、道路との照合と経路案内に使います。位置が不確かなときは案内を保留します。位置履歴は保存・送信しません。"
        case 3:return "背面カメラの映像から障害物候補を端末内で認識します。画像は保存・送信しません。カメラを許可しなくても地図の操作ができます。"
        case 4:return "上部の検索欄に避難先を直接入力し、候補から選択します。地図の長押し・保存済み地点からも選べます。道路接続点と経路を確認して開始すると、カメラ全面表示へ切り替えられます。通行不可登録では地図の道路をタップして選択します。VoiceOver用の区間一覧も用意しています。"
        default:return "視覚障害者が指定した避難先へ向かうための実験用アプリです。この端末で登録した通行不可区間を避けて検索します。まずは同行者のいる管理された環境で使ってください。避難所の開設・受入状況と道路の安全性は確認していません。"
    } }
}
@MainActor func openAppSettings() { if let url=URL(string:UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
