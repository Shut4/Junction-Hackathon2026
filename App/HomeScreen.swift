import SwiftUI
import MapKit

struct HomeScreen:View {
    @EnvironmentObject var store:AppStore
    @State private var destinations=false
    @State private var report=false
    @State private var settings=false
    @State private var pendingMode:GuidanceMode?
    @State private var details=false
    @State private var expanded=false
    @State private var panelHeight:CGFloat=180
    @StateObject private var search=DestinationSearch()
    @State private var query=""
    @State private var searchOpen=false
    @FocusState private var searchFocused:Bool
    @Environment(\.dynamicTypeSize) private var textSize
    private var reportRemovalDialogIsPresented:Binding<Bool> {
        Binding(
            get: { store.pendingReportRemoval != nil },
            set: { if !$0 { store.pendingReportRemoval = nil } }
        )
    }
    var body:some View {
        GeometryReader { geometry in
            ZStack(alignment:.top) {
                GuideMap(store:store,mode:.explore,onDestination:{ store.inspectDroppedPin($0) },onTap:{ searchFocused=false;if query.isEmpty { searchOpen=false };store.inspected=nil },insets:UIEdgeInsets(top:geometry.safeAreaInsets.top+(searchOpen ? 0:118),left:0,bottom:searchOpen ? 0:panelHeight+geometry.safeAreaInsets.bottom,right:0))
                    .ignoresSafeArea().accessibilityIdentifier("homeMap")
                VStack(spacing:10) {
                    searchBar
                    if searchOpen { searchResults } else { savedChips }
                    Spacer(minLength:0)
                    if !searchOpen {
                        floatingButtons
                        if let place=store.inspected { PlaceCard(place:place).padding(.bottom,4).onGeometryChange(for:CGFloat.self) { $0.size.height } action: { panelHeight=$0 } }
                        else { bottomPanel(maxHeight:geometry.size.height*(expanded || textSize.isAccessibilitySize ? 0.62:0.42)) }
                    }
                }.padding(.horizontal,12).padding(.top,4)
            }
        }
        .toolbar(.hidden,for:.navigationBar)
        .onChange(of:searchFocused) { _,focused in if focused { searchOpen=true } }
        .task(id:query) { guard searchOpen,query != search.resultsQuery else { return };search.cancel();search.results=[];try? await Task.sleep(for:.milliseconds(300));guard !Task.isCancelled,query != search.resultsQuery else { return };search.suggest(query,network:store.network) }
        .sheet(isPresented:$destinations) { NavigationStack { DestinationPickerScreen() } }
        .sheet(isPresented:$settings) { NavigationStack { SettingsScreen().toolbar { ToolbarItem(placement:.confirmationAction) { Button("完了") { settings=false } } } } }
        .sheet(isPresented:$report) { NavigationStack { ReportScreen() } }
        .fullScreenCover(isPresented:$store.guidanceActive) { GuidanceContainer().environmentObject(store) }
        .confirmationDialog("避難先の入口・受入状況と経路を同行者と確認してください",isPresented:Binding(get:{pendingMode != nil},set:{ if !$0 { pendingMode=nil } }),titleVisibility:.visible,presenting:pendingMode) { mode in
            Button(mode == .map ? "確認してナビを開始":"確認して全面カメラで案内開始") { store.startGuidance(mode) }
            Button("取消",role:.cancel) {}
        }
        .confirmationDialog("この通行禁止区域を削除しますか？",isPresented:reportRemovalDialogIsPresented,titleVisibility:.visible) {
            Button("通行禁止区域を削除",role:.destructive) {
                if let report = store.pendingReportRemoval { store.remove(report.id) }
                store.pendingReportRemoval = nil
            }
            Button("キャンセル",role:.cancel) { store.pendingReportRemoval=nil }
        } message: {
            if let report = store.pendingReportRemoval {
                Text("\(store.edge(report.segmentID)?.name ?? "選択した道路区間")を経路検索の対象に戻します。")
            }
        }
    }
    private var searchBar:some View {
        HStack(spacing:10) {
            if searchOpen { Button("検索を閉じる",systemImage:"chevron.left") { closeSearch() }.labelStyle(.iconOnly).font(.title3.weight(.semibold)).frame(minWidth:44,minHeight:44) }
            else { Image(systemName:"magnifyingglass").font(.title3).foregroundStyle(.secondary).frame(width:28).accessibilityHidden(true) }
            TextField("目的地を入力",text:$query).focused($searchFocused).submitLabel(.search).onSubmit { performSearch() }.font(.title3).accessibilityIdentifier("destinationQuery")
            if searchOpen || !query.isEmpty {
                Button(query.isEmpty ? "検索を閉じる":"入力を消去",systemImage:"xmark.circle.fill") {
                    if query.isEmpty { closeSearch() }
                    else { query="";search.clear();searchOpen=true;searchFocused=true }
                }
                .labelStyle(.iconOnly).foregroundStyle(.secondary).frame(minWidth:44,minHeight:44).accessibilityIdentifier("searchAction")
            }
            if !searchOpen { Button("設定",systemImage:"gearshape.fill") { settings=true }.labelStyle(.iconOnly).font(.title3).foregroundStyle(.white).frame(width:44,height:44).background(Circle().fill(Color.blue)) }
        }
        .padding(.leading,14).padding(.trailing,6).padding(.vertical,6)
        .background(Capsule().fill(Color(.systemBackground)).shadow(color:.black.opacity(0.18),radius:8,y:3))
    }
    private var savedChips:some View {
        ScrollView(.horizontal,showsIndicators:false) {
            HStack(spacing:8) {
                ForEach(store.destinations) { d in
                    Button { store.inspected=nil;store.chooseSavedDestination(d);query=d.name } label: { Label(d.name.replacingOccurrences(of:"・実験接続点",with:""),systemImage:"figure.walk").font(.subheadline.weight(.medium)).padding(.horizontal,14).padding(.vertical,9).background(Capsule().fill(store.destinationID == d.id ? Color.blue.opacity(0.18):Color(.systemBackground)).shadow(color:.black.opacity(0.12),radius:4,y:2)) }
                        .buttonStyle(.plain).accessibilityLabel("\(d.name)を避難先にする")
                }
            }.padding(.horizontal,2).padding(.vertical,4)
        }
    }
    private var searchResults:some View {
        ScrollView { VStack(alignment:.leading,spacing:0) {
            if search.searching { ProgressView("検索中").padding() }
            if !search.results.isEmpty {
                ForEach(Array(search.results.enumerated()),id:\.offset) { i,item in resultRow(title:item.name ?? "名称なし",subtitle:item.address?.fullAddress ?? "",symbol:"mappin.circle.fill",tint:.red) { choose(item) }.accessibilityIdentifier("destinationResult.\(i)") }.id("results-\(search.resultsQuery ?? "")")
            } else {
                ForEach(Array(search.suggestions.prefix(8).enumerated()),id:\.element) { i,c in resultRow(title:c.title,subtitle:c.subtitle,symbol:"magnifyingglass",tint:.secondary) { searchFocused=false;Task { await search.find(c.title,network:store.network,completion:c);if search.results.count==1,let item=search.results.first { choose(item) } } }.accessibilityIdentifier("destinationSuggestion.\(i)") }
                ForEach(store.destinations.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { d in
                    resultRow(title:d.name,subtitle:"保存済み・通信なしで選択可能",symbol:"figure.walk.circle.fill",tint:.green) { store.chooseSavedDestination(d);query=d.name;closeSearch() }.accessibilityLabel(d.name)
                }
                if !query.isEmpty { resultRow(title:"「\(query)」を検索",subtitle:"施設名・住所・「緯度, 経度」",symbol:"arrow.up.left.circle",tint:.blue) { performSearch() }.accessibilityIdentifier("destinationSearchButton") }
            }
            Text(search.status).font(.caption).foregroundStyle(.secondary).padding(12)
            resultRow(title:"保存済み地点・座標から選ぶ",subtitle:"一覧・緯度経度の入力",symbol:"list.bullet.circle",tint:.blue) { searchFocused=false;destinations=true }
        }.padding(.vertical,6) }
        .background(RoundedRectangle(cornerRadius:22).fill(Color(.systemBackground)).shadow(color:.black.opacity(0.15),radius:8,y:3))
        .padding(.bottom,8)
    }
    private func resultRow(title:String,subtitle:String,symbol:String,tint:Color,action:@escaping ()->Void)->some View {
        Button(action:action) {
            HStack(spacing:14) {
                Image(systemName:symbol).font(.title2).foregroundStyle(tint).frame(width:32).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:2) { Text(title).font(.headline).foregroundStyle(.primary);if !subtitle.isEmpty { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) } }
                Spacer(minLength:0)
            }.padding(.horizontal,16).padding(.vertical,10).frame(minHeight:52).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private var floatingButtons:some View {
        HStack(alignment:.bottom) {
            if store.developer { Label(store.simulated ? "DEV・模擬位置":"DEV",systemImage:"hammer.fill").font(.caption.bold()).padding(8).background(Capsule().fill(Color.orange.opacity(0.9))).foregroundStyle(.white) }
            Spacer()
            VStack(spacing:12) {
                circleButton("通行不可を登録",symbol:"exclamationmark.triangle.fill",tint:.orange) { report=true }
                circleButton("全面カメラで案内",symbol:"camera.fill",tint:.teal) { store.openCamera() }
                circleButton("現在位置を表示",symbol:"location.fill",tint:.blue) { store.location.start();store.focus(.user) }
            }
        }
    }
    private func circleButton(_ title:String,symbol:String,tint:Color,action:@escaping ()->Void)->some View {
        Button(title,systemImage:symbol,action:action).labelStyle(.iconOnly).font(.title2).foregroundStyle(tint).frame(width:56,height:56).background(Circle().fill(Color(.systemBackground)).shadow(color:.black.opacity(0.2),radius:6,y:2))
    }
    private func bottomPanel(maxHeight:CGFloat)->some View {
        VStack(spacing:0) {
            Button { withAnimation(.snappy) { expanded.toggle() } } label: { Capsule().fill(Color.secondary.opacity(0.45)).frame(width:40,height:5).frame(maxWidth:.infinity,minHeight:24) }
                .accessibilityLabel(expanded ? "パネルを縮小":"パネルを展開")
            ViewThatFits(in:.vertical) { panelContent;ScrollView { panelContent }.scrollBounceBehavior(.basedOnSize) }
                .frame(maxHeight:maxHeight-24,alignment:.top)
        }
        .background(RoundedRectangle(cornerRadius:24).fill(Color(.systemBackground)).shadow(color:.black.opacity(0.2),radius:10,y:-2))
        .onGeometryChange(for:CGFloat.self) { $0.size.height } action: { panelHeight=$0 }
        .padding(.bottom,4)
    }
    private var panelContent:some View {
            VStack(alignment:.leading,spacing:12) {
                if store.navigating { navigatingCard }
                if let error=store.storageError {
                    VStack(alignment:.leading,spacing:6) {
                        Label(error,systemImage:"exclamationmark.triangle.fill").font(.subheadline.bold()).foregroundStyle(.red)
                        if store.storageIncompatible { Text("道路データを更新したため、以前の報告を確認するまで経路案内を保留しています。").font(.caption) }
                        Button(store.storageIncompatible ? "設定で報告の引き継ぎを確認":"設定で報告の状態を確認") { settings=true }.buttonStyle(.bordered).accessibilityIdentifier("openStorageSettings")
                    }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.red.opacity(0.1),in:RoundedRectangle(cornerRadius:14))
                }
                Text(store.targetName).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Text(store.destinationMessage).font(.subheadline).foregroundStyle(.secondary)
                if !store.destinationConnections.isEmpty && store.customDestination==nil {
                    Text("案内の終点を確認").font(.headline)
                    ForEach(Array(store.destinationConnections.prefix(expanded ? 5:3))) { c in Button { store.confirmConnection(c.nodeID) } label: { Label("\(store.name(c.nodeID))・選択地点から約\(Int(c.distance.rounded())) m",systemImage:"point.topleft.down.to.point.bottomright.curvepath").frame(maxWidth:.infinity,minHeight:44,alignment:.leading) }.buttonStyle(.bordered) }
                    Text("道路接続点から入口までの経路は未確認です。近い候補が正しい入口とは限りません。").font(.caption)
                }
                if let route=store.route {
                    RouteSummary(route:route)
                    HStack(spacing:10) {
                        Button { pendingMode = .map } label: { Label("ナビ開始",systemImage:"location.north.line.fill").font(.headline).frame(maxWidth:.infinity,minHeight:50) }.buttonStyle(.borderedProminent).accessibilityIdentifier("startMapNavigation")
                        Button { pendingMode = .camera } label: { Label("カメラ案内",systemImage:"camera.viewfinder").font(.headline).frame(maxWidth:.infinity,minHeight:50) }.buttonStyle(.borderedProminent).tint(.teal).accessibilityIdentifier("startCameraNavigation")
                    }
                    NavigationLink("順序付きの経路を確認") { RouteList() }.frame(minHeight:44)
                } else {
                    PrimaryButton(title:"通行不可を避ける経路を確認",symbol:"arrow.triangle.turn.up.right.diamond") { store.calculate(usePosition:true) }.disabled(store.currentDestination==nil)
                }
                if let message=store.routeMessage { Text(message).font(.subheadline).accessibilityIdentifier("routeMessage") }
                Text(store.positionState).font(.subheadline)
                if store.currentDestination != nil || store.selectedTarget != nil { Button("避難先の選択を解除",systemImage:"xmark.circle") { store.clearDestination();query="" }.frame(minHeight:44) }
                Button(details ? "状態の詳細を閉じる":"位置・道路・保存の状態を確認",systemImage:"info.circle") { details.toggle() }.frame(minHeight:44)
                if details { StateCard() }
                Text("長押しで避難先を選択。青：経路、赤と×：通行不可登録、緑：保存済み地点").font(.caption).foregroundStyle(.secondary)
                SourceFooter()
            }.padding(.horizontal,16).padding(.bottom,12).frame(maxWidth:.infinity,alignment:.leading)
    }
    private var navigatingCard:some View {
        VStack(alignment:.leading,spacing:8) {
            Label("案内中",systemImage:"location.north.line.fill").font(.headline).foregroundStyle(.blue)
            Text(store.nextInstruction).font(.body)
            HStack {
                Button("ナビを表示") { store.switchGuidance(to:.map);store.guidanceActive=true }.buttonStyle(.borderedProminent)
                Button("カメラ案内") { store.switchGuidance(to:.camera);store.guidanceActive=true }.buttonStyle(.bordered)
                Button("停止",role:.destructive) { store.stopNavigation() }.buttonStyle(.bordered)
            }
        }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.blue.opacity(0.08),in:RoundedRectangle(cornerRadius:16))
    }
    func closeSearch() { searchOpen=false;searchFocused=false;search.cancel() }
    func performSearch() {
        searchOpen=true;searchFocused=false
        let parts=query.split(separator:",").map { $0.trimmingCharacters(in:.whitespaces) }
        if parts.count==2,let latitude=Double(parts[0]),let longitude=Double(parts[1]) {
            guard latitude.isFinite,longitude.isFinite,abs(latitude)<=90,abs(longitude)<=180 else { store.notice="緯度・経度を確認してください";return }
            store.chooseTarget(Coordinate(latitude,longitude),name:"指定した座標");searchOpen=false;search.clear();return
        }
        Task { await search.find(query,network:store.network) }
    }
    /// Like Google Maps, a chosen search result opens the place card first.
    func choose(_ item:MKMapItem) { store.inspect(item);store.focusOn(item.location.coordinate);searchOpen=false;searchFocused=false;query=item.name ?? query;search.clear() }
}
