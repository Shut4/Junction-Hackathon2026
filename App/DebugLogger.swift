import SwiftUI
import OSLog

/// Unified developer log. Never record images, coordinates or location history,
/// or free text that identifies where the user is going (search terms, place names, spoken instructions): log counts instead.
@MainActor final class DebugLogger: ObservableObject {
    static let shared=DebugLogger()
    static let capacity=500
    static let fileName="junctionguide_developer_debug_log_v1.json"
    static let url=AppFiles.directory.appending(path:fileName)
    #if DEBUG
    static let persists=true
    #else
    static let persists=false
    #endif
    @Published private(set) var buffer:DebugLogBuffer
    @Published var verboseLocation=false
    @Published var verboseInference=false
    @Published private(set) var saveError:String?
    private var saveTask:Task<Void,Never>?
    private let system=Logger(subsystem:Bundle.main.bundleIdentifier ?? "JunctionGuide",category:"debug")
    private init() { buffer=(Self.persists ? DebugLogBuffer.load(from:Self.url,capacity:Self.capacity):nil) ?? DebugLogBuffer(capacity:Self.capacity) }
    static func operationID()->String { String(UUID().uuidString.prefix(8)) }
    func log(_ category:LogCategory,_ level:LogLevel,_ title:String,_ fields:KeyValuePairs<String,Any?>=[:],direction:LogDirection = .event,operation:String?=nil,fileID:String=#fileID,line:Int=#line,function:String=#function) {
        let entry=DebugLogEntry(category:category,level:level,direction:direction,title:title,fields:fields.map { LogField($0.key,$0.value.map { "\($0)" } ?? "nil") },operationID:operation,source:"\(fileID):\(line)",function:function)
        buffer.append(entry)
        system.log("[\(category.rawValue, privacy:.public)] \(level.rawValue, privacy:.public) \(title, privacy:.public)")
        scheduleSave()
    }
    func clear() { buffer.clear();scheduleSave();log(.developer,.info,"Debug log cleared") }
    func export()->URL? {
        let url=URL.temporaryDirectory.appending(path:"JunctionGuide-debug-log.json")
        do { try buffer.save(to:url);return url } catch { saveError=error.localizedDescription;return nil }
    }
    private func scheduleSave() {
        guard Self.persists,saveTask == nil else { return }
        saveTask=Task { [weak self] in
            try? await Task.sleep(for:.seconds(1))
            guard let self else { return }
            saveTask=nil
            do { try buffer.save(to:Self.url);saveError=nil } catch { saveError=error.localizedDescription }
        }
    }
}
@MainActor func debugLog(_ category:LogCategory,_ level:LogLevel,_ title:String,_ fields:KeyValuePairs<String,Any?>=[:],direction:LogDirection = .event,operation:String?=nil,fileID:String=#fileID,line:Int=#line,function:String=#function) {
    DebugLogger.shared.log(category,level,title,fields,direction:direction,operation:operation,fileID:fileID,line:line,function:function)
}

extension LogLevel {
    var tint:Color { switch self { case .error:return .red;case .warning:return .orange;case .success:return .green;case .cancelled:return .purple;case .request,.response:return .blue;default:return .secondary } }
}
struct DebugLogScreen:View {
    @ObservedObject private var logger=DebugLogger.shared
    @Environment(\.dismiss) private var dismiss
    var modal=false
    @State private var category:LogCategory?
    @State private var level:LogLevel?
    @State private var query=""
    @State private var expanded=Set<UUID>()
    @State private var confirmClear=false
    @State private var export:URL?
    var body:some View {
        let entries=logger.buffer.filtered(category:category,level:level,query:query)
        List {
            Section("統合デバッグログ") {
                VStack(alignment:.leading,spacing:4) {
                    Text("ログ保存").font(.subheadline.bold())
                    Text(DebugLogger.persists ? localized("有効（直近{0}件を再起動後も保持）/ {1}",DebugLogger.capacity,DebugLogger.fileName):localized("無効（メモリ内の直近{0}件のみ）",DebugLogger.capacity)).font(.subheadline).foregroundStyle(.secondary)
                }
                Text("再起動をまたぐ不具合の調査に備え、DEBUGビルドでは直近ログをApplication Supportへ保存します。Releaseビルドでは保存しません。画像・位置座標・位置履歴は記録しません。").font(.footnote).foregroundStyle(.secondary)
                if let error=logger.saveError { Label(localized("保存エラー：{0}",error),systemImage:"exclamationmark.triangle").foregroundStyle(.red) }
                Picker("カテゴリ",selection:$category) { Text("ALL").tag(LogCategory?.none);ForEach(LogCategory.allCases,id:\.self) { Text(localized("{0}（{1}）",$0.rawValue,localized($0.label))).tag(Optional($0)) } }
                Picker("レベル",selection:$level) { Text("ALL").tag(LogLevel?.none);ForEach(LogLevel.allCases,id:\.self) { Text(localized("{0}（{1}）",$0.rawValue,localized($0.label))).tag(Optional($0)) } }
                TextField("タイトル、詳細、Operation IDを検索",text:$query).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("debugLogSearch")
                Text(localized("表示 {0}件・保持 {1}件・上限超過で破棄 {2}件",entries.count,logger.buffer.entries.count,logger.buffer.dropped)).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("debugLogCount")
                if entries.isEmpty { Text("該当するログはありません").foregroundStyle(.secondary) }
                ForEach(entries) { entry in DebugLogRow(entry:entry,expanded:expanded.contains(entry.id)) { if expanded.contains(entry.id) { expanded.remove(entry.id) } else { expanded.insert(entry.id) } } }
            }
        }
        .navigationTitle("DEBUG ログ").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if modal { ToolbarItem(placement:.cancellationAction) { Button("閉じる") { dismiss() } } }
            ToolbarItem(placement:.primaryAction) { Button("ログ消去",role:.destructive) { confirmClear=true } }
            ToolbarItem(placement:.bottomBar) { if let export { ShareLink("JSONを書き出す",item:export) } else { Button("書き出し用JSONを作成") { export=logger.export() } } }
        }
        .confirmationDialog("保持中のデバッグログをすべて消去します",isPresented:$confirmClear,titleVisibility:.visible) { Button("ログ消去",role:.destructive) { logger.clear();expanded=[];export=nil };Button("取消",role:.cancel) {} }
    }
}
struct DebugLogRow:View {
    let entry:DebugLogEntry;let expanded:Bool;let toggle:()->Void
    static let formatter:DateFormatter = { let f=DateFormatter();f.locale=Locale(identifier:Bundle.main.preferredLocalizations.first ?? "ja");f.dateFormat="yyyy/MM/dd HH:mm:ss.SSS";return f }()
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            Button(action:toggle) {
                HStack(alignment:.top) {
                    VStack(alignment:.leading,spacing:4) {
                        Text(localized(entry.title)).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                        Text("\(Self.formatter.string(from:entry.date)) / \(entry.category.rawValue)（\(localized(entry.category.label))）/ \(Text("\(entry.level.rawValue)（\(localized(entry.level.label))）").foregroundStyle(entry.level.tint))").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName:expanded ? "chevron.down":"chevron.right").font(.headline).foregroundStyle(.primary).accessibilityHidden(true)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityValue(localized(expanded ? "展開中":"折りたたみ"))
            if expanded {
                VStack(alignment:.leading,spacing:8) {
                    Grid(alignment:.leading,horizontalSpacing:12,verticalSpacing:6) {
                        row("発生日時",Self.formatter.string(from:entry.date));row("カテゴリ",localized("{0}（{1}）",entry.category.rawValue,localized(entry.category.label)))
                        row("レベル",localized("{0}（{1}）",entry.level.rawValue,localized(entry.level.label)));row("方向",entry.direction.rawValue)
                        if let op=entry.operationID { row("Operation ID",op) }
                    }
                    if !entry.fields.isEmpty {
                        Text("詳細").font(.title3.bold())
                        Text(entry.fields.map { "\($0.key) = \($0.value)" }.joined(separator:"\n")).font(.callout.monospaced()).foregroundStyle(.secondary)
                    }
                    Text("発生元").font(.title3.bold())
                    Text("\(entry.source)\n\(entry.function)").font(.callout.monospaced()).foregroundStyle(.secondary)
                }.textSelection(.enabled).padding(.leading,16)
            }
        }.padding(.vertical,4)
    }
    private func row(_ key:String,_ value:String)->some View { GridRow { Text(localized(key)).font(.subheadline.bold());Text(value).font(.subheadline).foregroundStyle(.secondary) } }
}
