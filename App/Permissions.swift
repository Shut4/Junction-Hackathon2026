import SwiftUI
import UserNotifications
import CoreLocation
import AVFoundation

@MainActor final class TutorialPermissions:NSObject,ObservableObject,@preconcurrency CLLocationManagerDelegate {
    @Published var notification="未確認"
    @Published private(set) var locationAuthorization:CLAuthorizationStatus = .notDetermined
    @Published private(set) var cameraAuthorization:AVAuthorizationStatus = .notDetermined
    @Published private(set) var checked=false
    @Published var requesting=false
    private let locationManager=CLLocationManager()
    var locationAuthorized:Bool { locationAuthorization == .authorizedWhenInUse || locationAuthorization == .authorizedAlways }
    var cameraAuthorized:Bool { cameraAuthorization == .authorized }
    var hasRequiredPermissions:Bool { locationAuthorized && cameraAuthorized }
    var location:String { switch locationAuthorization { case .authorizedAlways,.authorizedWhenInUse:return "許可済み";case .denied,.restricted:return "許可なし";default:return "未確認" } }
    var camera:String { switch cameraAuthorization { case .authorized:return "許可済み";case .denied,.restricted:return "許可なし";default:return "未確認" } }
    override init() { super.init();locationManager.delegate=self;locationAuthorization=locationManager.authorizationStatus;cameraAuthorization=AVCaptureDevice.authorizationStatus(for:.video) }
    func locationManagerDidChangeAuthorization(_ manager:CLLocationManager) { locationAuthorization=manager.authorizationStatus }
    func refresh() async {
        locationAuthorization=locationManager.authorizationStatus
        cameraAuthorization=AVCaptureDevice.authorizationStatus(for:.video)
        let settings=await UNUserNotificationCenter.current().notificationSettings()
        notification=switch settings.authorizationStatus { case .authorized,.provisional,.ephemeral:"許可済み";case .denied:"許可なし";default:"未確認" }
        checked=true
    }
    func requestNotification() async {
        requesting=true;defer { requesting=false }
        do { _=try await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound]) }
        catch { notification=localized("確認できません：{0}",error.localizedDescription);return }
        await refresh()
    }
    func requestLocation() { locationAuthorization=locationManager.authorizationStatus;if locationAuthorization == .notDetermined { locationManager.requestWhenInUseAuthorization() } }
    func requestCamera() async { requesting=true;defer { requesting=false };let granted=await AVCaptureDevice.requestAccess(for:.video);cameraAuthorization=granted ? .authorized:AVCaptureDevice.authorizationStatus(for:.video) }
}
struct TutorialScreen:View {
    @EnvironmentObject var store:AppStore
    @AppStorage("tutorialComplete") private var complete=false
    @AppStorage("tutorialStep") private var step=0
    @ObservedObject var permissions:TutorialPermissions
    var recoveryStep:Int? = nil
    private var page:Int { recoveryStep ?? step }
    private var locationDeniedReason:String { localized("位置情報の許可は経路案内に必要です。iOS設定でこのアプリの位置情報を「使用中のみ許可」にして戻ってください。") }
    private var cameraDeniedReason:String { localized("カメラの許可は障害物候補の検出と通知に必要です。iOS設定でこのアプリのカメラを許可して戻ってください。") }
    var body:some View {
        ScrollView { VStack(alignment:.leading,spacing:24) {
            Text("避難ナビの使い方").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            Text("\(min(page,4)+1) / 5").accessibilityLabel(localized("チュートリアル全5ページ中{0}ページ",min(page,4)+1))
            Image(systemName:symbol).font(.system(size:64)).foregroundStyle(.blue).accessibilityHidden(true)
            Text(localized(title)).font(.title.bold()).accessibilityAddTraits(.isHeader)
            Text(localized(message)).font(.title3)
            if page==1 {
                Label(localized("通知：{0}",localized(permissions.notification)),systemImage:"bell")
                PrimaryButton(title:"通知の許可を確認",symbol:"bell.badge") { Task { await permissions.requestNotification();if step==1 { step=2 } } }.disabled(permissions.requesting)
            } else if page==2 {
                Label(localized("位置情報：{0}",localized(permissions.location)),systemImage:"location")
                PrimaryButton(title:"位置情報の許可を確認",symbol:"location") { permissions.requestLocation();syncPageWithPermissions() }
                if permissions.location=="許可なし" { Text(locationDeniedReason).accessibilityIdentifier("locationPermissionReason") }
            } else if page==3 {
                Label(localized("カメラ：{0}",localized(permissions.camera)),systemImage:"camera")
                PrimaryButton(title:"カメラの許可を確認",symbol:"camera") { Task { await permissions.requestCamera();syncPageWithPermissions() } }.disabled(permissions.requesting)
                if permissions.camera=="許可なし" { Text(cameraDeniedReason).accessibilityIdentifier("cameraPermissionReason") }
            }
            if (page==1 && permissions.notification=="許可なし") || (page==2 && permissions.location=="許可なし") || (page==3 && permissions.camera=="許可なし") {
                Button("iOS設定を開く") { openAppSettings() }.frame(minHeight:48)
            }
            if recoveryStep == nil && page != 2 && page != 3 {
                PrimaryButton(title:page==4 ? "目的地を選ぶ":page==0 ? "次へ":"次へ（後で設定も可能）",symbol:"arrow.right") { if page>=4 { complete=true;step=0 } else { step += 1 } }.accessibilityIdentifier("tutorialNext")
            }
            if recoveryStep == nil && page>0 { Button("前の説明に戻る") { step -= 1 }.frame(minHeight:48) }
        }.padding(24) }.background(Color(.systemGroupedBackground))
        .onChange(of:step) { _,_ in if !complete { syncPageWithPermissions();announcePage() } }
        .onChange(of:recoveryStep) { _,_ in announcePage() }
        .onChange(of:permissions.locationAuthorization) { _,_ in syncPageWithPermissions();if page==2 && permissions.location=="許可なし" { announcePage() } }
        .onChange(of:permissions.cameraAuthorization) { _,_ in syncPageWithPermissions();if page==3 && permissions.camera=="許可なし" { announcePage() } }
        .task { syncPageWithPermissions();announcePage() }
    }
    private func syncPageWithPermissions() {
        guard recoveryStep == nil else { return }
        if step>2 && !permissions.locationAuthorized { step=2;return }
        if step>3 && !permissions.cameraAuthorized { step=3;return }
        if step==2 && permissions.locationAuthorized { store.location.start();step=3 }
        else if step==3 && permissions.cameraAuthorized { step=4 }
    }
    private func announcePage() {
        let detail:String
        if page==2 && permissions.location=="許可なし" { detail=localized("許可なし。{0}",locationDeniedReason) }
        else if page==3 && permissions.camera=="許可なし" { detail=localized("許可なし。{0}",cameraDeniedReason) }
        else { detail=localized(message) }
        UIAccessibility.post(notification:.screenChanged,argument:page==2 || page==3 ? localized("{0}。{1}",localized(title),detail):localized(title))
    }
    var symbol:String { ["figure.walk","bell","location","camera","map"][min(max(page,0),4)] }
    var title:String { ["選んだ場所までの避難を支援","通知の許可","位置情報の許可","カメラの許可","地図とカメラで案内"][min(max(page,0),4)] }
    var message:String { switch page {
        case 1:return "iOSの通知を許可するか確認します。カメラの候補通知と経路の音声はアプリ内で行い、通知の許可がなくても使えます。現在のMVPでは災害情報のプッシュ配信はありません。"
        case 2:return "アプリ使用中の位置情報の許可が必要です。道路との照合と経路案内に使います。許可しない場合は先へ進めません。位置履歴は保存・送信しません。"
        case 3:return "背面カメラの許可が必要です。障害物候補を端末内で検出して通知するために使います。許可しない場合は先へ進めません。画像は保存・送信しません。"
        case 4:return "上部の検索欄に目的地を直接入力し、候補から選択します。地図の長押し・保存済み地点からも選べます。道路接続点と経路を確認して開始すると、カメラ全面表示へ切り替えられます。通行不可登録では地図の道路をタップして選択します。VoiceOver用の区間一覧も用意しています。"
        default:return "視覚障害者が指定した目的地へ向かうための実験用アプリです。この端末で登録した通行不可区間を避けて検索します。まずは同行者のいる管理された環境で使ってください。避難所の開設・受入状況と道路の安全性は確認していません。"
    } }
}
@MainActor func openAppSettings() { if let url=URL(string:UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
