import SwiftUI

struct ReportScreen:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var roadPicker=false
    @AccessibilityFocusState private var accessibilityFocus:ReportFocus?
    private enum ReportFocus:Hashable { case roads,register,review }
    private var accessibleRoadSelection:Bool { AccessibilityLayout.voiceOver(voiceOver) }
    @State private var hazard=Hazard.other
    @State private var observed=Date()
    @State private var description=""
    @State private var review=false
    @State private var showInstructions=false
    @State private var showOptionalDetails=false
    @State private var showSelectedDetails=false
    @State private var reportToDelete:Report?
    private var deleteDialogIsPresented:Binding<Bool> {
        Binding(get:{ reportToDelete != nil },set:{ if !$0 { reportToDelete=nil } })
    }
    private var canReview:Bool { !store.selected.isEmpty && !store.ambiguity && store.storageError == nil }
    private var disabledReason:String {
        if store.selected.isEmpty { return localized("道路が選択されていません") }
        if store.ambiguity { return localized("道路候補を1つ選んでください") }
        if store.storageError != nil { return localized("保存状態を確認してください") }
        return ""
    }

    var body:some View { ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                stepTitle(number:1,title:"道路を選ぶ")
                Text("地図上の道路をタップしてください。もう一度タップすると選択を解除できます。")
                    .font(.subheadline)

                if accessibleRoadSelection {
                    Button("道路を一覧から選ぶ",systemImage:"list.bullet") { roadPicker=true }
                        .frame(minHeight:48)
                        .accessibilityHint("現在地に近い道路を確認し、ダブルタップで区間ごとに選択・解除できます")
                        .accessibilityIdentifier("accessibleRoadPicker")
                        .accessibilityFocused($accessibilityFocus,equals:.roads)
                }
                ZStack(alignment:.topLeading) {
                    GuideMap(store:store,mode:.report,onBlockedReport:{ reportToDelete=$0 })
                        .frame(height:360)
                        .clipShape(RoundedRectangle(cornerRadius:18))
                        .accessibilityIdentifier("reportRoadMap")
                    VStack(alignment:.leading,spacing:8) {
                        legend(symbol:"line.diagonal",color:.teal,text:"選択できる道路")
                        legend(symbol:"checkmark.circle.fill",color:.red,text:"選択中")
                        legend(symbol:"xmark.circle.fill",color:.orange,text:"登録済み")
                    }
                    .padding(10)
                    .background(.regularMaterial,in:RoundedRectangle(cornerRadius:12))
                    .padding(10)
                    .accessibilityElement(children:.combine)
                    .allowsHitTesting(false)
                }

                .accessibilityHidden(accessibleRoadSelection)

                DisclosureGroup("詳しい操作方法",isExpanded:$showInstructions) {
                    Text("地図はドラッグで移動、ピンチで拡大できます。登録は道路区間全体が対象です。登録済みの道路をタップすると、削除の確認を表示します。")
                        .font(.subheadline)
                        .padding(.top,8)
                }

                selectionStatus
                if store.ambiguity { candidatePicker.id("reportRoadCandidates") }

                stepTitle(number:2,title:"内容を確認")
                Picker("危険の種類",selection:$hazard) {
                    ForEach(Hazard.allCases,id:\.self) { Text(localized($0.rawValue)).tag($0) }
                }

                DisclosureGroup("観測時刻・説明",isExpanded:$showOptionalDetails) {
                    VStack(alignment:.leading,spacing:16) {
                        DatePicker("観測時刻",selection:$observed,in:...Date())
                        TextField("短い説明（任意・120文字まで）",text:$description,axis:.vertical)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of:description) { _,value in description=String(value.prefix(120)) }
                    }
                    .padding(.top,12)
                }
            }
            .padding()
            .padding(.bottom,112)
        }
        .onChange(of:store.selectionMessage) { _,message in
            if UIAccessibility.isVoiceOverRunning { UIAccessibility.post(notification:.announcement,argument:message) }
        }
        .navigationTitle("通行不可登録")
        .safeAreaInset(edge:.bottom) {
            registrationBar { withAnimation { proxy.scrollTo("reportRoadCandidates",anchor:.center) } }
        }
        .toolbar { ToolbarItem(placement:.cancellationAction) { Button("戻る") { store.clearSelection();dismiss() } } }
        .sheet(isPresented:$review,onDismiss:{ accessibilityFocus = .register }) { reviewSheet }
        .sheet(isPresented:$roadPicker,onDismiss:{ accessibilityFocus = .roads }) { NavigationStack { AccessibleRoadPicker() } }
        .confirmationDialog("この通行禁止区域を削除しますか？",isPresented:deleteDialogIsPresented,titleVisibility:.visible) {
            Button("通行禁止区域を削除",role:.destructive) {
                if let report=reportToDelete { store.removeReports(for:report.segmentID) }
                reportToDelete=nil
            }
            Button("キャンセル",role:.cancel) { reportToDelete=nil }
        } message: {
            if let report=reportToDelete { Text(localized("{0}を経路検索の対象に戻します。",store.edge(report.segmentID)?.name ?? localized("選択した道路区間"))) }
        }
    } }

    private var selectionStatus:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(alignment:.firstTextBaseline) {
                Label(localized("選択 {0}区間",store.selected.count),systemImage:store.selected.isEmpty ? "circle":"checkmark.circle.fill")
                    .font(.title3.bold())
                Spacer()
                if !store.selected.isEmpty { Button("選択解除") { store.clearSelection() } }
            }
            Text(localized(store.selectionMessage))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("selectionMessage")
            if !store.selected.isEmpty {
                DisclosureGroup("選択した道路を確認",isExpanded:$showSelectedDetails) {
                    VStack(alignment:.leading,spacing:8) {
                        ForEach(store.edges.filter { store.selected.contains($0.id) }) { edge in
                            Label(edge.name,systemImage:"checkmark")
                                .accessibilityLabel(store.edgeDescription(edge))
                        }
                    }
                    .padding(.top,8)
                }
            }
        }
        .padding()
        .frame(maxWidth:.infinity,alignment:.leading)
        .background(Color.blue.opacity(0.08),in:RoundedRectangle(cornerRadius:16))
        .accessibilityElement(children:.contain)
        .accessibilityIdentifier("reportSelectionStatus")
    }

    private var candidatePicker:some View {
        VStack(alignment:.leading,spacing:10) {
            Text("近くに複数の道路があります").font(.headline)
            Text("対象の道路を1つ選んでください。").font(.subheadline)
            ForEach(store.roadCandidates) { candidate in
                if let edge=store.edge(candidate.id) {
                    Button {
                        if let report=store.reports.first(where: { $0.segmentID == edge.id }) { reportToDelete=report }
                        else { store.confirmRoadCandidate(edge.id) }
                    } label: {
                        HStack {
                            VStack(alignment:.leading,spacing:4) {
                                Text(edge.name).font(.headline)
                                Text(localized("約{0} m",Int(edge.distance.rounded()))).font(.subheadline)
                            }
                            Spacer()
                            Image(systemName:"chevron.right")
                        }
                        .frame(maxWidth:.infinity,alignment:.leading)
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight:44)
                    .accessibilityIdentifier("roadCandidate."+edge.id)
                    .accessibilityLabel(store.edgeDescription(edge))
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1),in:RoundedRectangle(cornerRadius:16))
    }

    private func registrationBar(showCandidates:@escaping()->Void)->some View {
        VStack(alignment:.leading,spacing:8) {
            Text(localized(store.selectionMessage))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .accessibilityIdentifier("reportTapFeedback")
            if store.ambiguity {
                Button("道路候補を確認",action:showCandidates)
                    .frame(minHeight:44)
            }
            if !canReview {
                Label(disabledReason,systemImage:"info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("registrationDisabledReason")
            }
            PrimaryButton(title:"対象を確認して登録",symbol:"checkmark") { review=true }
                .disabled(!canReview)
                .accessibilityFocused($accessibilityFocus,equals:.register)
                .accessibilityHint(canReview ? localized("選択した道路と入力内容の確認画面を開きます"):disabledReason)
        }
        .padding(.horizontal)
        .padding(.top,10)
        .padding(.bottom,8)
        .background(.bar)
    }

    private var reviewSheet:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    Text("区間全体を通行不可にします").font(.title.bold())
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($accessibilityFocus,equals:.review)
                        .task { accessibilityFocus = .review }
                    Text(localized("通行不可にする道路：{0}区間",store.selected.count))
                        .font(.headline)
                        .accessibilityIdentifier("reportReviewSegmentCount")
                    Text(localized("種類：{0}",localized(hazard.rawValue)))
                    Text(observed,style:.date)
                    if !description.isEmpty { Text(description) }
                    PrimaryButton(title:"この範囲を登録",symbol:"checkmark") {
                        if store.register(hazard:hazard,date:observed,text:description) { review=false;dismiss() }
                    }
                    Button("戻って修正") { review=false }.frame(minHeight:48)
                }
                .padding()
            }
            .navigationTitle("登録内容の確認")
        }
    }

    private func stepTitle(number:Int,title:String)->some View {
        HStack(spacing:10) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width:30,height:30)
                .background(Color.accentColor,in:Circle())
            Text(localized(title)).font(.title2.bold())
        }
        .accessibilityElement(children:.combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func legend(symbol:String,color:Color,text:String)->some View {
        Label { Text(localized(text)).font(.caption.bold()) } icon: { Image(systemName:symbol).foregroundStyle(color) }
    }
}

/// A deliberate, searchable selection screen; native map roads never enter the VoiceOver focus order.
private struct AccessibleRoadPicker:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query=""
    @State private var ordered:[WalkEdge]=[]
    @State private var distances:[String:Double]=[:]
    @State private var visibleCount=30
    @State private var reportToDelete:Report?
    private var filtered:[WalkEdge] { ordered.filter { query.isEmpty || store.edgeDescription($0).localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query) } }
    var body:some View {
        List {
            Section {
                Text(localized("選択 {0}区間",store.selected.count)).accessibilityAddTraits(.isHeader)
                if distances.isEmpty { Text("位置情報がないため、道路データの順に表示しています") }
                else { Text("現在地に近い順に表示しています。道路の位置と対象区間を確認してください。") }
            }
            ForEach(Array(filtered.prefix(visibleCount))) { edge in roadRow(edge) }
            if filtered.isEmpty { Text("一致する道路がありません。検索語を変更してください。") }
            if filtered.count>visibleCount { Button("次の30区間を表示") { visibleCount += 30 }.frame(minHeight:48) }
        }
        .navigationTitle("道路を選ぶ")
        .searchable(text:$query,prompt:"道路名・区間IDを検索")
        .onChange(of:query) { _,_ in visibleCount=30 }
        .toolbar { ToolbarItem(placement:.confirmationAction) { Button("完了") { dismiss() }.accessibilityIdentifier("finishAccessibleRoadSelection") } }
        .task { loadRoads() }
        .confirmationDialog("この通行禁止区域を削除しますか？",isPresented:Binding(get:{reportToDelete != nil},set:{if !$0 {reportToDelete=nil}}),titleVisibility:.visible) {
            Button("通行禁止区域を削除",role:.destructive) { if let report=reportToDelete { store.removeReports(for:report.segmentID) };reportToDelete=nil }
            Button("キャンセル",role:.cancel) { reportToDelete=nil }
        }
    }
    private func roadRow(_ edge:WalkEdge)->some View {
                Button {
                    if let report=store.reports.first(where:{$0.segmentID==edge.id}) { reportToDelete=report }
                    else { store.confirmTappedRoad(edge.id) }
                } label: {
                    VStack(alignment:.leading,spacing:6) {
                        Label(edge.name,systemImage:store.selected.contains(edge.id) ? "checkmark.circle.fill":"circle")
                        Text(store.edgeDescription(edge)).font(.subheadline)
                        if let distance=distances[edge.id] { Text(localized("現在地から約{0} m",Int(distance.rounded()))).font(.subheadline) }
                    }
                }
                .accessibilityLabel(store.edgeDescription(edge))
                .accessibilityValue(localized(store.blocked.contains(edge.id) ? "通行不可登録あり":store.selected.contains(edge.id) ? "選択中":"未選択"))
                .accessibilityHint(store.blocked.contains(edge.id) ? "ダブルタップで登録解除の確認を開きます":"ダブルタップで選択・解除します")
                .accessibilityIdentifier("accessibleRoad."+edge.id)
    }
    private func loadRoads() {
            if let point=store.location.sample?.coordinate {
                var ranked:[(edge:WalkEdge,distance:Double)]=[]
                for edge in store.edges { ranked.append((edge,Geometry.project(point,onto:edge.shape).distance)) }
                ranked.sort { left,right in
                    if left.distance == right.distance { return left.edge.id < right.edge.id }
                    return left.distance < right.distance
                }
                ordered=ranked.map { $0.edge }
                for item in ranked { distances[item.edge.id]=item.distance }
            } else { ordered=store.edges }
        }

}
