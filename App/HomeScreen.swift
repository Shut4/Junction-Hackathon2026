import SwiftUI
import MapKit

struct HomeScreen:View {
    @EnvironmentObject var store:AppStore
    @State private var destinations=false
    @State private var report=false
    @State private var settings=false
    @State private var pendingMode:GuidanceMode?
    @State private var expanded=false
    @State private var destinationPanelCollapsed=false
    @State private var destinationPanelContentAtTop=true
    @GestureState(resetTransaction:Transaction(animation:.spring(response:0.35,dampingFraction:0.85))) private var destinationPanelDrag:CGFloat=0
    @State private var panelHeight:CGFloat=180
    @StateObject private var search=DestinationSearch()
    @State private var query=""
    @State private var searchOpen=false
    @FocusState private var searchFocused:Bool
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @AccessibilityFocusState private var accessibilityFocus:HomeFocus?
    private enum HomeFocus:Hashable { case search,destination,settings,report,start }

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
                    .ignoresSafeArea().accessibilityHidden(AccessibilityLayout.voiceOver(voiceOver)).accessibilityIdentifier("homeMap")
                VStack(spacing:10) {
                    searchBar.padding(.horizontal,12)
                    if searchOpen { searchResults.padding(.horizontal,12) } else { savedChips }
                    Spacer(minLength:0)
                    if !searchOpen {
                        floatingButtons.padding(.horizontal,12)
                        if let place=store.inspected { PlaceCard(place:place).padding(.horizontal,12).padding(.bottom,4).onGeometryChange(for:CGFloat.self) { $0.size.height } action: { panelHeight=$0 } }
                        else if store.hasDestination || store.selectedTarget != nil {
                            destinationPanel(maxHeight:min(geometry.size.height*(textSize.isAccessibilitySize ? 0.72:0.58),max(220,geometry.size.height-300))).padding(.horizontal,12)
                        } else { bottomPanel(maxHeight:geometry.size.height*(expanded || textSize.isAccessibilitySize ? 0.62:0.42)).padding(.horizontal,12) }
                    }
                }.padding(.top,4).clipped()
            }
        }
        .accessibilityHidden(store.guidanceActive || settings || report || destinations || pendingMode != nil || store.pendingReportRemoval != nil)
        .overlay(alignment:.top) { CaneConnectionToast(bluetooth:store.cane) }
        .toolbar(.hidden,for:.navigationBar)
        .onChange(of:store.targetName) { _,_ in destinationPanelCollapsed=false;accessibilityFocus = .destination }
        .onChange(of:pendingMode) { _,mode in if mode == nil && !store.guidanceActive { accessibilityFocus = .start } }
        .onChange(of:searchFocused) { _,focused in if focused { searchOpen=true } }
        .task(id:query) { guard searchOpen,query != search.resultsQuery else { return };search.cancel();search.results=[];try? await Task.sleep(for:.milliseconds(300));guard !Task.isCancelled,query != search.resultsQuery else { return };search.suggest(query,network:store.network) }
        .sheet(isPresented:$destinations,onDismiss:{ accessibilityFocus=store.hasDestination ? .destination:.search }) { NavigationStack { DestinationPickerScreen() } }
        .sheet(isPresented:$settings,onDismiss:{ accessibilityFocus = .settings }) { NavigationStack { SettingsScreen().toolbar { ToolbarItem(placement:.confirmationAction) { Button("完了") { settings=false } } } } }
        .sheet(isPresented:$report,onDismiss:{ accessibilityFocus = .report }) { NavigationStack { ReportScreen() } }
        .fullScreenCover(isPresented:$store.guidanceActive,onDismiss:{ accessibilityFocus = .destination }) { GuidanceContainer().environmentObject(store) }
        .confirmationDialog("目的地の入口・受入状況と経路を同行者と確認してください",isPresented:Binding(get:{pendingMode != nil},set:{ if !$0 { pendingMode=nil } }),titleVisibility:.visible,presenting:pendingMode) { mode in
            Button(localized(mode == .map ? "確認してナビを開始":"確認して全面カメラで案内開始")) { store.startGuidance(mode) }
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
                Text(localized("{0}を経路検索の対象に戻します。",store.edge(report.segmentID)?.name ?? localized("選択した道路区間")))
            }
        }
    }
    private var searchBar:some View {
        HStack(spacing:10) {
            if searchOpen { Button("検索を閉じる",systemImage:"chevron.left") { closeSearch() }.labelStyle(.iconOnly).font(.title3.weight(.semibold)).frame(minWidth:44,minHeight:44) }
            else { Image(systemName:"magnifyingglass").font(.title3).foregroundStyle(.secondary).frame(width:28).accessibilityHidden(true) }
            TextField("目的地を入力",text:$query).focused($searchFocused).submitLabel(.search).onSubmit { performSearch() }.font(.title3).accessibilityIdentifier("destinationQuery").accessibilityFocused($accessibilityFocus,equals:.search)
            if searchOpen || !query.isEmpty {
                Button(localized(query.isEmpty ? "検索を閉じる":"入力を消去"),systemImage:"xmark.circle.fill") {
                    if query.isEmpty { closeSearch() }
                    else { query="";search.clear();searchOpen=true;searchFocused=true }
                }
                .labelStyle(.iconOnly).foregroundStyle(.secondary).frame(minWidth:44,minHeight:44).accessibilityIdentifier("searchAction")
            }
            if !searchOpen { Button("設定",systemImage:"gearshape.fill") { settings=true }.accessibilityFocused($accessibilityFocus,equals:.settings).labelStyle(.iconOnly).font(.title3).foregroundStyle(.white).frame(width:44,height:44).background(Circle().fill(Color.blue)) }
        }
        .padding(.leading,14).padding(.trailing,6).padding(.vertical,6)
        .background(Capsule().fill(Color(.systemBackground)).shadow(color:.black.opacity(0.18),radius:8,y:3))
    }
    private var savedChips:some View {
        ScrollView(.horizontal,showsIndicators:false) {
            HStack(spacing:8) {
                ForEach(store.destinations) { d in
                    Button { store.inspected=nil;store.chooseSavedDestination(d);query=localized(d.name) } label: { Label(localized(d.name).replacingOccurrences(of:localized("・実験接続点"),with:""),systemImage:"figure.walk").font(.subheadline.weight(.medium)).padding(.horizontal,14).padding(.vertical,9).background(Capsule().fill(store.destinationID == d.id ? Color.blue.opacity(0.18):Color(.systemBackground)).shadow(color:.black.opacity(0.12),radius:4,y:2)) }
                        .buttonStyle(.plain).accessibilityLabel(localized("{0}を目的地にする",localized(d.name)))
                        .accessibilityValue(localized(store.destinationID == d.id ? "選択中":"未選択"))
                }
            }.padding(.horizontal,14).padding(.vertical,4)
        }.frame(maxWidth:.infinity).accessibilityIdentifier("savedChipsScroll")
    }
    private var searchResults:some View {
        ScrollView { VStack(alignment:.leading,spacing:0) {
            if search.searching { ProgressView("検索中").padding() }
            if !search.results.isEmpty {
                ForEach(Array(search.results.enumerated()),id:\.offset) { i,item in resultRow(title:item.name ?? localized("名称なし"),subtitle:item.address?.fullAddress ?? "",symbol:"mappin.circle.fill",tint:.red) { choose(item) }.accessibilityIdentifier("destinationResult.\(i)") }.id("results-\(search.resultsQuery ?? "")")
            } else {
                ForEach(Array(search.suggestions.prefix(8).enumerated()),id:\.element) { i,c in resultRow(title:c.title,subtitle:c.subtitle,symbol:"magnifyingglass",tint:.secondary) { searchFocused=false;Task { await search.find(c.title,network:store.network,completion:c);if search.results.count==1,let item=search.results.first { choose(item) } } }.accessibilityIdentifier("destinationSuggestion.\(i)") }
                ForEach(store.destinations.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { d in
                    resultRow(title:localized(d.name),subtitle:localized("保存済み・通信なしで選択可能"),symbol:"figure.walk.circle.fill",tint:.green) { store.chooseSavedDestination(d);query=localized(d.name);closeSearch() }.accessibilityLabel(localized(d.name)).accessibilityIdentifier("savedSearch."+d.id)
                }
                if !query.isEmpty { resultRow(title:localized("「{0}」を検索",query),subtitle:"施設名・住所・「緯度, 経度」",symbol:"arrow.up.left.circle",tint:.blue) { performSearch() }.accessibilityIdentifier("destinationSearchButton") }
            }
            Text(localized(search.status)).font(.caption).foregroundStyle(.secondary).padding(12)
            resultRow(title:"保存済み地点・座標から選ぶ",subtitle:"一覧・緯度経度の入力",symbol:"list.bullet.circle",tint:.blue) { searchFocused=false;destinations=true }
        }.padding(.vertical,6) }
        .background(RoundedRectangle(cornerRadius:22).fill(Color(.systemBackground)).shadow(color:.black.opacity(0.15),radius:8,y:3))
        .padding(.bottom,8)
    }
    private func resultRow(title:String,subtitle:String,symbol:String,tint:Color,action:@escaping ()->Void)->some View {
        Button(action:action) {
            HStack(spacing:14) {
                Image(systemName:symbol).font(.title2).foregroundStyle(tint).frame(width:32).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:2) { Text(localized(title)).font(.headline).foregroundStyle(.primary);if !subtitle.isEmpty { Text(localized(subtitle)).font(.subheadline).foregroundStyle(.secondary) } }
                Spacer(minLength:0)
            }.padding(.horizontal,16).padding(.vertical,10).frame(minHeight:52).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private var floatingButtons:some View {
        HStack(alignment:.bottom) {
            if store.developer { Label(localized(store.simulated ? "DEV・模擬位置":"DEV"),systemImage:"hammer.fill").font(.caption.bold()).padding(8).background(Capsule().fill(Color.orange.opacity(0.9))).foregroundStyle(.white) }
            Spacer()
            VStack(spacing:12) {
                circleButton("通行不可を登録",symbol:"exclamationmark.triangle.fill",tint:.orange) { report=true }.accessibilityFocused($accessibilityFocus,equals:.report)
                circleButton("全面カメラで案内",symbol:"camera.fill",tint:.teal) { store.openCamera() }
                circleButton("現在位置を表示",symbol:"location.fill",tint:.blue) { store.location.start();store.focus(.user) }
            }
        }
    }
    private func circleButton(_ title:String,symbol:String,tint:Color,action:@escaping ()->Void)->some View {
        Button(localized(title),systemImage:symbol,action:action).labelStyle(.iconOnly).font(.title2).foregroundStyle(tint).frame(width:56,height:56).background(Circle().fill(Color(.systemBackground)).shadow(color:.black.opacity(0.2),radius:6,y:2))
    }
    private func bottomPanel(maxHeight:CGFloat)->some View {
        VStack(spacing:0) {
            Button { withAnimation(.snappy) { expanded.toggle() } } label: { Capsule().fill(Color.secondary.opacity(0.45)).frame(width:40,height:5).frame(maxWidth:.infinity,minHeight:24) }
                .accessibilityLabel(localized(expanded ? "パネルを縮小":"パネルを展開"))
                .accessibilityValue(localized(expanded ? "展開":"縮小"))
                .accessibilityAdjustableAction { direction in
                    if direction == .increment { expanded=true } else if direction == .decrement { expanded=false }
                }
            ViewThatFits(in:.vertical) { panelContent;ScrollView { panelContent }.scrollBounceBehavior(.basedOnSize) }
                .frame(maxHeight:maxHeight-24,alignment:.top)
        }
        .background(RoundedRectangle(cornerRadius:24).fill(Color(.systemBackground)).shadow(color:.black.opacity(0.2),radius:10,y:-2))
        .onGeometryChange(for:CGFloat.self) { $0.size.height } action: { panelHeight=$0 }
        .padding(.bottom,4)
    }
    private func destinationPanel(maxHeight:CGFloat)->some View {
        let compactHeight=min(180,maxHeight*0.45)
        let restingHeight=destinationPanelCollapsed ? compactHeight:maxHeight
        let travel=maxHeight-compactHeight
        let translation=min(max(destinationPanelDrag,destinationPanelCollapsed ? -travel:0),destinationPanelCollapsed ? 0:travel)
        return VStack(spacing:0) {
            Button { setDestinationPanelCollapsed(!destinationPanelCollapsed) } label: {
                Capsule().fill(Color.secondary.opacity(0.45)).frame(width:40,height:5).frame(maxWidth:.infinity,minHeight:24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(localized("{0}、{1}",store.targetName,localized(destinationPanelCollapsed ? "縮小":"展開")))
            .accessibilityAdjustableAction { direction in
                if direction == .increment { setDestinationPanelCollapsed(false) } else if direction == .decrement { setDestinationPanelCollapsed(true) }
            }
            .accessibilityLabel(destinationPanelCollapsed ? "目的地パネルを展開":"目的地パネルを縮小")
            .accessibilityIdentifier("destinationPanelHandle")
            .simultaneousGesture(destinationPanelGesture(fullHeight:maxHeight,compactHeight:compactHeight,fromHandle:true))
            ScrollView { panelContent }
                .onScrollGeometryChange(for:Bool.self) { $0.contentOffset.y <= -$0.contentInsets.top+1 } action: { _,atTop in destinationPanelContentAtTop=atTop }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDisabled(destinationPanelCollapsed)
                .frame(maxHeight:.infinity,alignment:.top)
                .accessibilityHidden(AccessibilityLayout.voiceOver(voiceOver) && destinationPanelCollapsed)
                .overlay(alignment:.top) {
                    if AccessibilityLayout.voiceOver(voiceOver) && destinationPanelCollapsed { collapsedDestinationSummary }
                }
        }
        // Keep content layout and MapKit insets stable while the finger moves.
        // Only the settled height changes when the gesture ends.
        .frame(height:maxHeight)
        .background(RoundedRectangle(cornerRadius:24).fill(Color(.systemBackground)).shadow(color:.black.opacity(0.2),radius:10,y:-2))
        .offset(y:translation)
        .frame(height:restingHeight,alignment:.top)
        .contentShape(RoundedRectangle(cornerRadius:24))
        .simultaneousGesture(destinationPanelGesture(fullHeight:maxHeight,compactHeight:compactHeight))
        .onGeometryChange(for:CGFloat.self) { $0.size.height } action: { panelHeight=$0 }
        .padding(.bottom,4)
        .accessibilityElement(children:.contain)
        .accessibilityIdentifier("destinationPanel")
    }
    private func destinationPanelGesture(fullHeight:CGFloat,compactHeight:CGFloat,fromHandle:Bool=false)->some Gesture {
        DragGesture(minimumDistance:10)
            .updating($destinationPanelDrag) { value,state,transaction in
                guard abs(value.translation.height)>abs(value.translation.width),fromHandle || destinationPanelCollapsed || (destinationPanelContentAtTop && value.translation.height>0) else { return }
                transaction.animation=nil
                state=value.translation.height
            }
            .onEnded { value in
                guard abs(value.translation.height)>abs(value.translation.width),fromHandle || destinationPanelCollapsed || (destinationPanelContentAtTop && value.translation.height>0) else { return }
                let restingHeight=destinationPanelCollapsed ? compactHeight:fullHeight
                let projectedHeight=restingHeight-value.predictedEndTranslation.height
                withAnimation(.spring(response:0.35,dampingFraction:0.85)) {
                    destinationPanelCollapsed=projectedHeight < (compactHeight+fullHeight)/2
                }
            }
    }
    private var panelContent:some View {
            VStack(alignment:.leading,spacing:12) {
                if store.navigating { navigatingCard }
                if let error=store.storageError {
                    VStack(alignment:.leading,spacing:6) {
                        Label(localized(error),systemImage:"exclamationmark.triangle.fill").font(.subheadline.bold()).foregroundStyle(.red)
                        Button("設定で報告の状態を確認") { settings=true }.buttonStyle(.bordered).accessibilityIdentifier("openStorageSettings")
                    }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.red.opacity(0.1),in:RoundedRectangle(cornerRadius:14))
                }
                Text(localized(store.targetName)).font(.title2.bold()).accessibilityAddTraits(.isHeader).accessibilityFocused($accessibilityFocus,equals:.destination)
                if !store.destinationMessage.isEmpty { Text(localized(store.destinationMessage)).font(.subheadline).foregroundStyle(.secondary) }
                if let route=store.route {
                    RouteSummary(route:route)
                    HStack(spacing:10) {
                        Button { pendingMode = .map } label: { Label("ナビ開始",systemImage:"location.north.line.fill").font(.headline).frame(maxWidth:.infinity,minHeight:50) }.buttonStyle(.borderedProminent).accessibilityIdentifier("startMapNavigation").accessibilityFocused($accessibilityFocus,equals:.start)
                        Button { pendingMode = .camera } label: { Label("カメラ案内",systemImage:"camera.viewfinder").font(.headline).frame(maxWidth:.infinity,minHeight:50) }.buttonStyle(.borderedProminent).tint(.teal).accessibilityIdentifier("startCameraNavigation")
                    }
                } else {
                    PrimaryButton(title:"通行不可を避ける経路を確認",symbol:"arrow.triangle.turn.up.right.diamond") { store.calculate(usePosition:true) }.disabled(!store.hasDestination)
                }
                if let message=store.routeMessage { Text(localized(message)).font(.subheadline).accessibilityIdentifier("routeMessage") }
                if !store.positionState.isEmpty { Text(localized(store.positionState)).font(.subheadline) }
                if store.hasDestination || store.selectedTarget != nil { Button("目的地の選択を解除",systemImage:"xmark.circle") { store.clearDestination();query="" }.frame(minHeight:44) }
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
    private var collapsedDestinationSummary:some View {
        VStack(alignment:.leading,spacing:8) {
            Text(localized(store.targetName)).font(.headline)
            Text("目的地パネルを展開すると、経路と案内の操作を確認できます").font(.subheadline)
        }
        .padding(.horizontal,16).padding(.bottom,12)
        .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .background(Color(.systemBackground))
        .accessibilityElement(children:.combine)
    }
    private func setDestinationPanelCollapsed(_ value:Bool) {
        if AccessibilityLayout.voiceOver(voiceOver) {
            var transaction=Transaction();transaction.disablesAnimations=true
            withTransaction(transaction) { destinationPanelCollapsed=value }
        } else { withAnimation(.spring(response:0.35,dampingFraction:0.85)) { destinationPanelCollapsed=value } }
    }
    func closeSearch() { searchOpen=false;searchFocused=false;search.cancel();accessibilityFocus = .search }
    func performSearch() {
        searchOpen=true;searchFocused=false
        let parts=query.split(separator:",").map { $0.trimmingCharacters(in:.whitespaces) }
        if parts.count==2,let latitude=Double(parts[0]),let longitude=Double(parts[1]) {
            guard latitude.isFinite,longitude.isFinite,abs(latitude)<=90,abs(longitude)<=180 else { store.notice=localized("緯度・経度を確認してください");return }
            store.chooseTarget(Coordinate(latitude,longitude),name:"指定した座標");searchOpen=false;search.clear();return
        }
        Task { await search.find(query,network:store.network) }
    }
    /// Like Google Maps, a chosen search result opens the place card first.
    func choose(_ item:MKMapItem) { store.inspect(item);store.focusOn(item.location.coordinate);searchOpen=false;searchFocused=false;query=item.name ?? query;search.clear() }
}
