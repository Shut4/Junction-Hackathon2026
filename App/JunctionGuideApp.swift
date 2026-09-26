import SwiftUI


@main struct JunctionGuideApp: App {
    @StateObject private var store=AppStore()
    @Environment(\.scenePhase) private var phase
    init() {
        #if DEBUG
        // UI testing resets only tutorial progress, never real reports or system permissions.
        if ProcessInfo.processInfo.arguments.contains("--reset-tutorial") {
            UserDefaults.standard.removeObject(forKey:"tutorialComplete")
            UserDefaults.standard.removeObject(forKey:"tutorialStep")
        }
        #endif
    }
    var body:some Scene { WindowGroup { RootView().environmentObject(store).onChange(of:phase) { _,new in if new == .background { store.pause() } else if new == .active { debugLog(.lifecycle,.info,"Scene active") } }
        .task { debugLog(.lifecycle,.start,"App launched",["version":Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String,"build":Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String,"device":UIDevice.current.model,"iOS":UIDevice.current.systemVersion]) } } }
}

struct RootView:View {
    @EnvironmentObject var store:AppStore
    @AppStorage("tutorialComplete") private var tutorialComplete=false
    var body:some View {
        Group {
            if tutorialComplete { NavigationStack { HomeScreen() } }
            else { TutorialScreen() }
        }.tint(.blue)
        .onChange(of:store.notice) { _,message in if let message { NoticePresenter.show(message) { store.notice=nil } } }
    }
}

/// Presents on the top-most controller so an open sheet (e.g. DeveloperMode) is not dismissed by a root-level alert.
@MainActor enum NoticePresenter {
    static func show(_ message:String,onClose:@escaping ()->Void) {
        guard let scene=UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,var top=scene.keyWindow?.rootViewController else { return }
        while let next=top.presentedViewController,!next.isBeingDismissed { top=next }
        if let existing=top as? UIAlertController { existing.message=message;return }
        let alert=UIAlertController(title:"状態",message:message,preferredStyle:.alert)
        alert.addAction(UIAlertAction(title:"閉じる",style:.cancel) { _ in onClose() })
        top.present(alert,animated:true)
    }
}
