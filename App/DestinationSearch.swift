import SwiftUI
import MapKit


@MainActor final class DestinationSearch:NSObject,ObservableObject,@preconcurrency MKLocalSearchCompleterDelegate {
    @Published var results:[MKMapItem]=[]
    @Published var status=localized("名称・住所を入力してください")
    @Published var searching=false
    @Published var suggestions:[MKLocalSearchCompletion]=[]
    /// Query the current results belong to; suggestion refreshes must not wipe results for the same text.
    private(set) var resultsQuery:String?
    private var completer:MKLocalSearchCompleter?
    private var search:MKLocalSearch?
    private var generation=0
    func suggest(_ fragment:String,network:Network?) {
        completer?.cancel();suggestions=[]
        guard !fragment.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { completer=nil;return }
        let source=MKLocalSearchCompleter();source.delegate=self;source.resultTypes=[.address,.pointOfInterest,.query]
        if let b=network?.bounds { source.region=MKCoordinateRegion(center:CLLocationCoordinate2D(latitude:(b.south+b.north)/2,longitude:(b.west+b.east)/2),span:MKCoordinateSpan(latitudeDelta:0.04,longitudeDelta:0.04)) }
        completer=source;source.queryFragment=fragment
    }
    func completerDidUpdateResults(_ source:MKLocalSearchCompleter) { guard source===completer else { return };suggestions=source.results }
    func completer(_ source:MKLocalSearchCompleter,didFailWithError error:Error) { guard source===completer else { return };suggestions=[];status=localized("候補を取得できません。通信を確認するか保存済み地点を選んでください");debugLog(.search,.error,"Completion failed",["error":error.localizedDescription],direction:.incoming) }
    func find(_ query:String,network:Network?,completion:MKLocalSearchCompletion?=nil) async {
        generation += 1;let token=generation;search?.cancel();results=[]
        guard !query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { status=localized("名称・住所を入力してください");searching=false;return }
        let request=completion.map { MKLocalSearch.Request(completion:$0) } ?? MKLocalSearch.Request();if completion==nil { request.naturalLanguageQuery=query }
        if let b=network?.bounds { request.region=MKCoordinateRegion(center:CLLocationCoordinate2D(latitude:(b.south+b.north)/2,longitude:(b.west+b.east)/2),span:MKCoordinateSpan(latitudeDelta:0.04,longitudeDelta:0.04)) }
        let operation=MKLocalSearch(request:request);search=operation;searching=true;status=localized("検索中")
        let op=DebugLogger.operationID(),started=Date()
        debugLog(.search,.request,"MKLocalSearch request",["queryLength":query.count,"fromCompletion":completion != nil],direction:.outgoing,operation:op)
        do { let response=try await operation.start();guard token==generation else { debugLog(.search,.cancelled,"Superseded search response",operation:op);return };results=response.mapItems;resultsQuery=query;status=results.isEmpty ? localized("検索結果がありません"):localized("{0}件。避難所の受入状況は未確認です",results.count)
            debugLog(.search,.response,"MKLocalSearch response",["results":results.count,"ms":Int(Date().timeIntervalSince(started)*1000)],direction:.incoming,operation:op) }
        catch { guard token==generation else { return };status=localized("検索できません。通信を確認するか、保存済み地点・座標・地図から選択してください");debugLog(.search,.error,"MKLocalSearch failed",["error":error.localizedDescription],direction:.incoming,operation:op) }
        if token==generation { searching=false }
    }
    func cancel() { generation += 1;search?.cancel();completer?.cancel();completer=nil;suggestions=[];searching=false }
    func clear() { cancel();results=[];resultsQuery=nil;status=localized("名称・住所を入力してください") }
}

struct DestinationPickerScreen:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var search=DestinationSearch()
    @State private var query=""
    @State private var latitude=""
    @State private var longitude=""
    var body:some View { List {
        Section("目的地を検索") {
            TextField("施設名・住所を入力",text:$query).submitLabel(.search).onSubmit { performSearch() }.accessibilityIdentifier("destinationQuery")
            Button("検索",systemImage:"magnifyingglass") { performSearch() }.disabled(search.searching).accessibilityIdentifier("destinationSearchButton")
            Text(localized(search.status)).font(.subheadline)
            ForEach(Array(search.results.enumerated()),id:\.offset) { index,item in Button { let c=item.location.coordinate;store.chooseTarget(Coordinate(c.latitude,c.longitude),name:item.name ?? localized("選択した目的地"));dismiss() } label: { VStack(alignment:.leading) { Text(item.name ?? localized("名称なし")).font(.headline);Text(item.address?.fullAddress ?? "").font(.subheadline) } }.frame(minHeight:48).accessibilityIdentifier("destinationResult.\(index)") }
        }
        Section("保存済み地点（通信なしでも選択可能）") { ForEach(store.destinations) { d in Button(localized(d.name)) { store.chooseSavedDestination(d);dismiss() }.frame(minHeight:48) } }
        Section("座標で選ぶ") {
            TextField("緯度（例：33.885）",text:$latitude).keyboardType(.numbersAndPunctuation)
            TextField("経度（例：130.880）",text:$longitude).keyboardType(.numbersAndPunctuation)
            Button("この座標を目的地にする") {
                guard let lat=Double(latitude),let lon=Double(longitude),lat.isFinite,lon.isFinite,abs(lat)<=90,abs(lon)<=180 else { store.notice=localized("緯度・経度を確認してください");return }
                store.chooseTarget(Coordinate(lat,lon),name:localized("指定した座標"));dismiss()
            }.frame(minHeight:48)
        }
        Section { Text("任意の場所を選択できます。通行不可を除外した経路案内は、選択中の対応地域に保存された歩行ネットワーク内で提供します。検索には通信が必要です。施設の開設・受入状況を同行者と確認してください。") }
    }.navigationTitle("目的地を選ぶ").toolbar { ToolbarItem(placement:.cancellationAction) { Button("閉じる") { dismiss() } } }.onDisappear { search.cancel() } }
    func performSearch() { Task { await search.find(query,network:store.network) } }
}
