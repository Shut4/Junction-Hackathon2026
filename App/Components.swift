import SwiftUI

struct PrimaryButton:View {
    let title:String;let symbol:String;var destructive=false;let action:()->Void
    var body:some View { Button(action:action) { Label(localized(title),systemImage:symbol).font(.headline).frame(maxWidth:.infinity,minHeight:48).padding(.vertical,6) }.buttonStyle(.borderedProminent).tint(destructive ? .red:.blue) }
}


struct RouteSummary:View {
    @EnvironmentObject var store:AppStore
    let route:WalkRoute
    var body:some View { VStack(alignment:.leading,spacing:8) { HStack(alignment:.firstTextBaseline) { Text(localized("徒歩目安 約{0}分",max(1,Int((route.distance/60).rounded(.up))))).font(.title2.bold()).foregroundStyle(.green);Text("\(Int(route.distance.rounded())) m").font(.title3.bold()) } }.accessibilityElement(children:.combine).padding().frame(maxWidth:.infinity,alignment:.leading).background(Color.blue.opacity(0.09),in:RoundedRectangle(cornerRadius:18)) }
}


struct SourceFooter:View {
    var body:some View { Link("道路データ © OpenStreetMap contributors · ODbL",destination:URL(string:"https://www.openstreetmap.org/copyright")!).font(.caption).frame(minHeight:44).accessibilityHint("道路データの出典と利用条件を開きます") }
}
