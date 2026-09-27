import SwiftUI
@preconcurrency import MapKit

/// A place the user tapped on the home map (POI, dropped pin or search result), shown as a Google Maps–style card.
struct InspectedPlace:Identifiable {
    let id=UUID()
    var name:String
    var category:String?
    var address:String?
    var coordinate:Coordinate
    var mapItem:MKMapItem?
    var droppedPin=false
    var loading=false
}
enum PlaceCategory {
    static func name(_ category:MKPointOfInterestCategory?)->String? {
        guard let category else { return nil }
        let names:[MKPointOfInterestCategory:String]=[.airport:"空港",.amusementPark:"遊園地",.aquarium:"水族館",.atm:"ATM",.bakery:"パン屋",.bank:"銀行",.beach:"ビーチ",.brewery:"醸造所",.cafe:"カフェ",.campground:"キャンプ場",.carRental:"レンタカー",.evCharger:"EV充電",.fireStation:"消防署",.fitnessCenter:"フィットネス",.foodMarket:"食料品店",.gasStation:"ガソリンスタンド",.hospital:"病院",.hotel:"ホテル",.laundry:"コインランドリー",.library:"図書館",.marina:"マリーナ",.movieTheater:"映画館",.museum:"博物館・美術館",.nationalPark:"国立公園",.nightlife:"ナイトライフ",.park:"公園",.parking:"駐車場",.pharmacy:"薬局",.police:"警察",.postOffice:"郵便局",.publicTransport:"公共交通機関",.restaurant:"レストラン",.restroom:"トイレ",.school:"学校",.stadium:"スタジアム",.store:"店舗",.theater:"劇場",.university:"大学",.winery:"ワイナリー",.zoo:"動物園",.castle:"城",.landmark:"ランドマーク",.conventionCenter:"会議場",.musicVenue:"音楽会場",.fortress:"要塞"]
        return names[category] ?? "施設"
    }
}
extension AppStore {
    func inspect(_ item:MKMapItem,fallbackName:String?=nil) {
        let c=item.location.coordinate
        inspected=InspectedPlace(name:item.name ?? fallbackName ?? "名称なし",category:PlaceCategory.name(item.pointOfInterestCategory),address:item.address?.fullAddress,coordinate:Coordinate(c.latitude,c.longitude),mapItem:item)
        debugLog(.map,.info,"Place inspected",["category":inspected?.category,"inBounds":network?.bounds.contains(Coordinate(c.latitude,c.longitude))])
    }
    func inspect(feature:MKMapFeatureAnnotation) {
        let c=feature.coordinate
        inspected=InspectedPlace(name:feature.title ?? "施設",category:PlaceCategory.name(feature.pointOfInterestCategory),coordinate:Coordinate(c.latitude,c.longitude),loading:true)
        let op=DebugLogger.operationID(),id=inspected?.id
        debugLog(.map,.request,"Map feature detail request",direction:.outgoing,operation:op)
        Task {
            do {
                let item=try await MKMapItemRequest(mapFeatureAnnotation:feature).mapItem
                guard inspected?.id == id else { return }
                inspect(item,fallbackName:feature.title);debugLog(.map,.response,"Map feature detail received",direction:.incoming,operation:op)
            } catch {
                guard inspected?.id == id else { return }
                inspected?.loading=false;debugLog(.map,.error,"Map feature detail failed",["error":error.localizedDescription],direction:.incoming,operation:op)
            }
        }
    }
    func inspectDroppedPin(_ coordinate:Coordinate) {
        inspected=InspectedPlace(name:"ドロップしたピン",category:String(format:"%.5f, %.5f",coordinate.latitude,coordinate.longitude),coordinate:coordinate,droppedPin:true,loading:true)
        let id=inspected?.id
        debugLog(.map,.info,"Pin dropped")
        Task {
            guard let request=MKReverseGeocodingRequest(location:CLLocation(latitude:coordinate.latitude,longitude:coordinate.longitude)) else { inspected?.loading=false;return }
            let items=try? await request.mapItems
            guard inspected?.id == id else { return }
            inspected?.loading=false
            if let item=items?.first { inspected?.address=item.address?.fullAddress;inspected?.mapItem=item }
        }
    }
    /// Choosing a place always goes through the existing road-connection confirmation.
    func useInspectedAsDestination(calculateRoute:Bool) {
        guard let place=inspected else { return }
        inspected=nil
        chooseTarget(place.coordinate,name:place.droppedPin ? (place.address ?? "地図で選んだ目的地"):place.name)
        if calculateRoute,let first=destinationConnections.first,destinationConnections.count==1 { confirmConnection(first.nodeID);calculate(usePosition:true) }
    }
}
struct PlaceCard:View {
    @EnvironmentObject var store:AppStore
    let place:InspectedPlace
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Capsule().fill(Color.secondary.opacity(0.45)).frame(width:40,height:5).frame(maxWidth:.infinity).accessibilityHidden(true)
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:4) {
                    Text(place.name).font(.title2.bold()).accessibilityAddTraits(.isHeader).accessibilityIdentifier("placeName")
                    if let category=place.category { Text(category).font(.subheadline).foregroundStyle(.secondary) }
                    Text(detailLine).font(.subheadline).foregroundStyle(inBounds ? Color.green:Color.orange)
                }
                Spacer()
                Button("閉じる",systemImage:"xmark") { store.inspected=nil }.labelStyle(.iconOnly).font(.headline).foregroundStyle(.secondary).frame(width:36,height:36).background(Circle().fill(Color(.tertiarySystemFill))).accessibilityIdentifier("closePlace")
            }
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:8) {
                    Button { store.useInspectedAsDestination(calculateRoute:true) } label: { Label("経路",systemImage:"arrow.triangle.turn.up.right.diamond.fill").font(.headline).padding(.horizontal,16).frame(minHeight:44) }
                        .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).disabled(!inBounds).accessibilityIdentifier("placeRoute")
                    Button { store.useInspectedAsDestination(calculateRoute:false) } label: { Label("目的地にする",systemImage:"mappin.and.ellipse").font(.headline).padding(.horizontal,12).frame(minHeight:44) }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule).accessibilityIdentifier("placeSetDestination")
                    if let phone=place.mapItem?.phoneNumber,let url=URL(string:"tel:"+phone.filter { $0.isNumber || $0 == "+" }) { Link(destination:url) { Label("電話",systemImage:"phone.fill").padding(.horizontal,12).frame(minHeight:44) }.buttonStyle(.bordered).buttonBorderShape(.capsule) }
                    if let url=place.mapItem?.url { Link(destination:url) { Label("Webサイト",systemImage:"globe").padding(.horizontal,12).frame(minHeight:44) }.buttonStyle(.bordered).buttonBorderShape(.capsule) }
                    ShareLink(item:shareText) { Label("共有",systemImage:"square.and.arrow.up").padding(.horizontal,12).frame(minHeight:44) }.buttonStyle(.bordered).buttonBorderShape(.capsule)
                    if let item=place.mapItem { Button { item.openInMaps() } label: { Label("マップで開く",systemImage:"map").padding(.horizontal,12).frame(minHeight:44) }.buttonStyle(.bordered).buttonBorderShape(.capsule) }
                }
            }
            if place.loading { ProgressView("詳細を取得中").font(.caption) }
            if let address=place.address { Label(address,systemImage:"mappin.circle").font(.subheadline) }
            Text(inBounds ? "「経路」は選択中の地域の保存済み道路網の接続点までです。施設の開設・受入状況と入口は未確認です。":"保存済み道路網の範囲外のため表示のみです。経路案内はできません。").font(.caption).foregroundStyle(.secondary)
        }
        .padding(16).frame(maxWidth:.infinity,alignment:.leading)
        .background(RoundedRectangle(cornerRadius:24).fill(Color(.systemBackground)).shadow(color:.black.opacity(0.2),radius:10,y:-2))
        .accessibilityElement(children:.contain).accessibilityIdentifier("placeCard")
    }
    private var inBounds:Bool { store.network?.bounds.contains(place.coordinate) ?? false }
    private var detailLine:String {
        let distance=store.location.sample.map { Int($0.coordinate.distance(to:place.coordinate).rounded()) }
        let d=distance.map { $0>=1000 ? String(format:"約%.1f km",Double($0)/1000):"約\($0) m" }
        return [d.map { "現在地から\($0)" },inBounds ? "経路案内の対応範囲内":"対応範囲外"].compactMap { $0 }.joined(separator:"・")
    }
    private var shareText:String { "\(place.name)\n\(place.address ?? "")\nhttps://maps.apple.com/?ll=\(place.coordinate.latitude),\(place.coordinate.longitude)&q=\(place.name.addingPercentEncoding(withAllowedCharacters:.urlQueryAllowed) ?? "")" }
}
