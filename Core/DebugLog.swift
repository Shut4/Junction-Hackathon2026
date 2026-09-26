import Foundation

public enum LogCategory: String, Codable, CaseIterable, Sendable {
    case location="LOCATION",route="ROUTE",navigation="NAVIGATION",camera="CAMERA",model="MODEL",speech="SPEECH"
    case report="REPORT",storage="STORAGE",search="SEARCH",map="MAP",permission="PERMISSION",lifecycle="LIFECYCLE",developer="DEVELOPER"
    public var label:String { switch self {
        case .location:return "位置情報・方位";case .route:return "経路探索";case .navigation:return "経路案内";case .camera:return "カメラ"
        case .model:return "認識モデル";case .speech:return "音声";case .report:return "通行不可報告";case .storage:return "保存・読込"
        case .search:return "目的地検索";case .map:return "地図操作";case .permission:return "端末権限";case .lifecycle:return "アプリ状態";case .developer:return "DeveloperMode"
    } }
}
public enum LogLevel: String, Codable, CaseIterable, Sendable {
    case debug="DEBUG",info="INFO",start="START",request="REQUEST",response="RESPONSE",success="SUCCESS",warning="WARNING",error="ERROR",cancelled="CANCELLED"
    public var label:String { switch self {
        case .debug:return "詳細";case .info:return "通常情報";case .start:return "処理開始";case .request:return "要求開始";case .response:return "応答受信"
        case .success:return "正常完了";case .warning:return "注意";case .error:return "エラー";case .cancelled:return "利用者または処理によりキャンセル"
    } }
}
public enum LogDirection: String, Codable, CaseIterable, Sendable { case event="EVENT",outgoing="OUTGOING",incoming="INCOMING",state="STATE" }
public struct LogField: Codable, Hashable, Sendable {
    public var key:String;public var value:String
    public init(_ key:String,_ value:String) { self.key=key;self.value=value }
}
public struct DebugLogEntry: Codable, Identifiable, Sendable {
    public var id:UUID;public var date:Date;public var category:LogCategory;public var level:LogLevel;public var direction:LogDirection
    public var title:String;public var fields:[LogField];public var operationID:String?;public var source:String;public var function:String
    public init(date:Date=Date(),category:LogCategory,level:LogLevel,direction:LogDirection = .event,title:String,fields:[LogField]=[],operationID:String?=nil,source:String,function:String) {
        id=UUID();self.date=date;self.category=category;self.level=level;self.direction=direction;self.title=title;self.fields=fields;self.operationID=operationID;self.source=source;self.function=function
    }
    public func matches(_ query:String)->Bool {
        let q=query.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(q) || (operationID?.localizedCaseInsensitiveContains(q) ?? false) || fields.contains { $0.key.localizedCaseInsensitiveContains(q) || $0.value.localizedCaseInsensitiveContains(q) }
    }
}
/// Bounded developer log. Callers must not put images or location history into fields.
public struct DebugLogBuffer: Codable, Sendable {
    public var schema=1
    public private(set) var capacity:Int
    public private(set) var dropped=0
    public private(set) var entries:[DebugLogEntry]=[]
    public init(capacity:Int) { self.capacity=max(1,capacity) }
    public mutating func append(_ entry:DebugLogEntry) {
        entries.append(entry)
        if entries.count>capacity { dropped += entries.count-capacity;entries.removeFirst(entries.count-capacity) }
    }
    public mutating func clear() { entries.removeAll();dropped=0 }
    public func filtered(category:LogCategory?=nil,level:LogLevel?=nil,query:String="")->[DebugLogEntry] {
        entries.reversed().filter { (category == nil || $0.category == category) && (level == nil || $0.level == level) && $0.matches(query) }
    }
    public static func load(from url:URL,capacity:Int)->DebugLogBuffer? {
        guard let data=try? Data(contentsOf:url),var buffer=try? JSONDecoder().decode(DebugLogBuffer.self,from:data),buffer.schema==1 else { return nil }
        buffer.capacity=max(1,capacity)
        if buffer.entries.count>buffer.capacity { buffer.dropped += buffer.entries.count-buffer.capacity;buffer.entries.removeFirst(buffer.entries.count-buffer.capacity) }
        return buffer
    }
    public func save(to url:URL) throws {
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try encoder.encode(self).write(to:url,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
    }
}
