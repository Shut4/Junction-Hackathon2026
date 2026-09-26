import SwiftUI

struct PrimaryButton:View {
    let title:String;let symbol:String;var destructive=false;let action:()->Void
    var body:some View { Button(action:action) { Label(title,systemImage:symbol).font(.headline).frame(maxWidth:.infinity,minHeight:48).padding(.vertical,6) }.buttonStyle(.borderedProminent).tint(destructive ? .red:.blue) }
}

struct StateCard:View {
    @EnvironmentObject var store:AppStore
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Label(store.simulated ? "模擬位置・模擬報告":"同行者付き実験",systemImage:store.simulated ? "testtube.2":"person.2").font(.headline)
            Text(store.positionState)
            if let error=store.networkError { Label(error,systemImage:"exclamationmark.triangle") }
            if let error=store.storageError { Label(error,systemImage:"exclamationmark.triangle").foregroundStyle(.red) }
            Text("道路・接続は現地未確認。報告がない区間も安全確認済みではありません。").font(.subheadline)
        }.padding().frame(maxWidth:.infinity,alignment:.leading).background(.thinMaterial,in:RoundedRectangle(cornerRadius:18))
    }
}

struct RouteSummary:View {
    @EnvironmentObject var store:AppStore
    let route:WalkRoute
    var body:some View { VStack(alignment:.leading,spacing:8) { HStack(alignment:.firstTextBaseline) { Text("徒歩目安 約\(max(1,Int((route.distance/60).rounded(.up))))分").font(.title2.bold()).foregroundStyle(.green);Text("\(Int(route.distance.rounded())) m").font(.title3.bold()) };Text("\(route.steps.count)区間・通行不可登録\(store.blocked.count)区間を除外して検索");Text("毎分60mで計算。歩道の現状・施設入口・到着時刻は未確認").font(.caption) }.accessibilityElement(children:.combine).padding().frame(maxWidth:.infinity,alignment:.leading).background(Color.blue.opacity(0.09),in:RoundedRectangle(cornerRadius:18)) }
}

struct RouteList:View {
    @EnvironmentObject var store:AppStore
    var body:some View { List { if let route=store.route { Section { RouteSummary(route:route) };ForEach(Array(route.steps.enumerated()),id:\.offset) { index,step in VStack(alignment:.leading,spacing:6) { Text("\(index+1). \(store.edge(step.id)?.name ?? "歩行区間")").font(.headline);Text("\(store.name(step.from)) → \(store.name(step.to))");Text("約\(Int(step.distance)) m・現地未確認").font(.subheadline) } } } else { Text("経路未検索") } }.navigationTitle("経路一覧") }
}

struct SourceFooter:View {
    var body:some View { Link("道路データ © OpenStreetMap contributors · ODbL",destination:URL(string:"https://www.openstreetmap.org/copyright")!).font(.caption).frame(minHeight:44).accessibilityHint("道路データの出典と利用条件を開きます") }
}
