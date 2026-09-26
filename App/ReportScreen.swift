import SwiftUI

struct ReportScreen:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var listMode=false
    @State private var query=""
    @State private var visibleCount=30
    @State private var hazard=Hazard.other
    @State private var observed=Date()
    @State private var description=""
    @State private var review=false
    var filtered:[WalkEdge] { store.edges.filter { query.isEmpty || store.edgeDescription($0).localizedCaseInsensitiveContains(query) || $0.id.contains(query) } }
    var body:some View { ScrollView { VStack(alignment:.leading,spacing:16) {
        if !listMode {
            Text("地図の道路をタップして選択").font(.headline)
            ZStack(alignment:.topLeading) {
                GuideMap(store:store,mode:.report).frame(height:440).clipShape(RoundedRectangle(cornerRadius:18)).accessibilityIdentifier("reportRoadMap")
                VStack(alignment:.leading,spacing:6) {
                    legend(color:.teal,text:"選択できる道路（\(store.edges.count)区間）")
                    legend(color:.red,text:"選択中・登録済み")
                }.padding(10).background(.regularMaterial,in:RoundedRectangle(cornerRadius:12)).padding(10).accessibilityElement(children:.combine)
            }
            SourceFooter()
            Text("青緑の線が選択できる道路です。線の上をタップすると赤く選択、再タップで解除。ドラッグで地図移動、ピンチで拡大できます。登録は道路区間全体が対象です。歩道と車道を区別していない区間があります。")
            DisclosureGroup("なぞって複数区間を選択") { Toggle("なぞり選択モード",isOn:$store.tracing).accessibilityHint("地図移動を停止して連続する道路をなぞれます") }
        }
        Button(listMode ? "地図で道路をタップして選ぶ":"VoiceOver用の区間一覧を開く") { listMode.toggle();store.tracing=false }.frame(minHeight:48).accessibilityIdentifier("roadListAlternative")
        Text(store.selectionMessage).font(.headline)
        if store.ambiguity {
            Text("タップ位置の道路候補を確認してください。")
            ForEach(store.traceCandidates) { candidate in if let edge=store.edge(candidate.id) { Button(store.edgeDescription(edge)) { store.confirmRoadCandidate(edge.id) }.frame(minHeight:44).accessibilityIdentifier("roadCandidate."+edge.id) } }
        }
        Button("選択解除・やり直し",systemImage:"arrow.counterclockwise") { store.clearSelection() }.frame(minHeight:44)
        Text("選択 \(store.selected.count)区間").font(.title2.bold())
        ForEach(store.edges.filter { store.selected.contains($0.id) }) { edge in Text(store.edgeDescription(edge)).padding().background(Color.red.opacity(0.08),in:RoundedRectangle(cornerRadius:12)) }
        if listMode {
            TextField("道路名・接続点・区間IDを検索",text:$query).textFieldStyle(.roundedBorder)
            LazyVStack(alignment:.leading,spacing:0) { ForEach(Array(filtered.prefix(visibleCount))) { edge in Button { store.toggle(edge.id) } label: {
                HStack(alignment:.top) { Image(systemName:store.selected.contains(edge.id) ? "checkmark.circle.fill":"circle");VStack(alignment:.leading,spacing:4) { Text(edge.name).font(.headline);Text("\(store.name(edge.from)) → \(store.name(edge.to))");Text("\(Int(edge.distance.rounded())) m・\(store.blocked.contains(edge.id) ? "× 通行不可登録あり":"報告なし・安全未確認")").font(.subheadline) } }.frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,12)
            }.accessibilityIdentifier("edge."+edge.id).accessibilityLabel(store.edgeDescription(edge)).accessibilityValue(store.selected.contains(edge.id) ? "選択中":"未選択");Divider() } }
            if filtered.count>visibleCount { Button("次の30区間を表示（全\(filtered.count)区間）") { visibleCount += 30 }.frame(minHeight:48) }
        }
        Picker("危険の種類",selection:$hazard) { ForEach(Hazard.allCases,id:\.self) { Text($0.rawValue).tag($0) } }
        DatePicker("観測時刻",selection:$observed,in:...Date())
        TextField("短い説明（任意・120文字まで）",text:$description,axis:.vertical).textFieldStyle(.roundedBorder).onChange(of:description) { _,value in description=String(value.prefix(120)) }
        PrimaryButton(title:"対象を確認して登録",symbol:"checkmark") { review=true }.disabled(store.selected.isEmpty || store.ambiguity || store.storageError != nil)
        Text("登録はこの端末だけに反映します。古い報告も自動解除しません。").font(.caption)
    }.padding() }.navigationTitle("通行不可登録")
    .toolbar { ToolbarItem(placement:.cancellationAction) { Button("取消") { store.tracing=false;store.clearSelection();dismiss() } } }
    .sheet(isPresented:$review) { NavigationStack { ScrollView { VStack(alignment:.leading,spacing:16) { Text("区間全体を通行不可にします").font(.title.bold());ForEach(store.edges.filter { store.selected.contains($0.id) }) { e in Text(store.edgeDescription(e)) };Text("種類：\(hazard.rawValue)");Text(observed,style:.date);Text(description);PrimaryButton(title:"この範囲を登録",symbol:"checkmark") { if store.register(hazard:hazard,date:observed,text:description) { review=false;store.tracing=false;dismiss() } };Button("戻って修正") { review=false }.frame(minHeight:48) }.padding() }.navigationTitle("登録内容の確認") } }
    .onDisappear { store.tracing=false }
    }
    private func legend(color:Color,text:String)->some View { HStack(spacing:8) { Capsule().fill(color).frame(width:28,height:6).overlay(Capsule().stroke(.white,lineWidth:1));Text(text).font(.caption.bold()) } }
}
