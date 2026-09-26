import SwiftUI
import MapKit

enum GuideMapMode { case explore,report,navigation }

final class GuidePin: MKPointAnnotation {
    enum Kind { case target,saved,blocked,simulated,dropped }
    var kind:Kind
    init(kind:Kind) { self.kind=kind;super.init() }
}
struct GuideMap: UIViewRepresentable {
    @ObservedObject var store: AppStore
    var mode:GuideMapMode = .explore
    var onDestination: ((Coordinate)->Void)? = nil
    var onTap: (()->Void)? = nil
    /// Keeps Apple's legal label, compass and focused content clear of floating panels.
    var insets=UIEdgeInsets.zero
    func makeCoordinator() -> Coordinator { Coordinator(store:store) }
    func makeUIView(context:Context)->MKMapView {
        let map=MKMapView();map.delegate=context.coordinator;map.showsUserLocation=true;map.showsTraffic=false;map.showsScale=mode != .explore
        map.pointOfInterestFilter = mode == .explore ? .includingAll:.excludingAll;map.isPitchEnabled=false;map.isRotateEnabled=mode == .navigation
        map.preferredConfiguration=MKStandardMapConfiguration(emphasisStyle:mode == .report ? .muted:.default)
        // Home map: POIs are tappable like Google Maps and open the place card.
        map.selectableMapFeatures=mode == .explore ? [.pointsOfInterest,.physicalFeatures,.territories]:[]
        if let b=store.network?.bounds {
            let span=mode == .explore ? MKCoordinateSpan(latitudeDelta:(b.north-b.south)*0.55,longitudeDelta:(b.east-b.west)*0.55):MKCoordinateSpan(latitudeDelta:(b.north-b.south)*0.35,longitudeDelta:(b.east-b.west)*0.35)
            map.setRegion(MKCoordinateRegion(center:CLLocationCoordinate2D(latitude:(b.south+b.north)/2,longitude:(b.west+b.east)/2),span:span),animated:false)
        }
        let gesture=UIPanGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.pan(_:)));gesture.isEnabled=false;map.addGestureRecognizer(gesture);context.coordinator.gesture=gesture
        let press=UILongPressGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.chooseDestination(_:)));press.isEnabled=mode == .explore;map.addGestureRecognizer(press)
        let tap=UITapGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.tapped(_:)));tap.cancelsTouchesInView=false;map.addGestureRecognizer(tap);context.coordinator.tapGesture=tap
        context.coordinator.mode=mode
        map.accessibilityLabel=mode == .report ? "通行不可登録の地図。青緑の線が選択できる道路です。区間一覧でも選択できます。":mode == .navigation ? "ナビの地図。青い線が経路です。":"対応地域の実地図。長押しで避難先を選択できます。避難先は検索欄と保存済み地点からも選べます。"
        if mode == .navigation { context.coordinator.following=true }
        return map
    }
    func updateUIView(_ map:MKMapView,context:Context) {
        let c=context.coordinator
        c.store=store;c.onDestination=onDestination;c.onTap=onTap;c.mode=mode
        if map.layoutMargins != insets { map.layoutMargins=insets }
        map.isScrollEnabled = !store.tracing;map.isZoomEnabled = !store.tracing;c.gesture?.isEnabled=store.tracing
        c.tapGesture?.isEnabled = !store.tracing
        guard let network=store.network else { return }
        // Static layer (network, boundary, saved pins) is built once per mode; only small dynamic layers are replaced.
        let baseKey="\(mode)|\(network.id)|\(network.version)"
        if baseKey != c.baseKey {
            c.baseKey=baseKey;c.dynamicKey="";map.removeOverlays(map.overlays);map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) });c.simulatedPin=nil;c.dynamicOverlays=[];c.dynamicPins=[]
            let b=network.bounds
            add([Coordinate(b.south,b.west),Coordinate(b.south,b.east),Coordinate(b.north,b.east),Coordinate(b.north,b.west),Coordinate(b.south,b.west)],title:"boundary",map:map)
            let lines=network.edges.map { MKPolyline(coordinates:$0.shape.map(\.clLocation),count:$0.shape.count) }
            for title in mode == .report ? ["selectableCasing","selectable"]:["walk"] { let multi=MKMultiPolyline(lines);multi.title=title;map.addOverlay(multi,level:.aboveRoads) }
            if mode != .navigation { for d in network.destinations { if let p=store.place(d.nodeID) { pin(p.coordinate,kind:.saved,title:d.name,subtitle:"実験接続点・入口未確認",map:map) } } }
        }
        let dynamicKey="\(store.selected.sorted())|\(store.blocked.sorted())|\(store.routeVersion)|\(store.route != nil)|\(store.destinationID)|\(String(describing:store.destinationCoordinate))|\(store.inspected?.droppedPin == true ? String(describing:store.inspected?.coordinate):"")"
        if dynamicKey != c.dynamicKey {
            c.dynamicKey=dynamicKey;map.removeOverlays(c.dynamicOverlays);map.removeAnnotations(c.dynamicPins);c.dynamicOverlays=[];c.dynamicPins=[]
            if let route=store.route {
                // The off-road approach is drawn dashed: it is a straight line, not a mapped road.
                var roads=route;if let first=roads.steps.first,first.isApproach { roads.steps.removeFirst();c.dynamicOverlays.append(add(first.shape,title:"approach",map:map)) }
                let shape=RouteTracker.shape(of:roads);c.dynamicOverlays += [add(shape,title:"routeCasing",map:map),add(shape,title:"route",map:map)]
            }
            let blocked=network.edges.filter { store.blocked.contains($0.id) },selected=network.edges.filter { store.selected.contains($0.id) }
            for (edges,name) in [(blocked,"blocked"),(selected,"selected")] where !edges.isEmpty {
                let lines=edges.map { MKPolyline(coordinates:$0.shape.map(\.clLocation),count:$0.shape.count) }
                for title in [name+"Casing",name] { let multi=MKMultiPolyline(lines);multi.title=title;map.addOverlay(multi,level:.aboveRoads);c.dynamicOverlays.append(multi) }
            }
            if mode != .report { for edge in blocked { c.dynamicPins.append(pin(edge.shape[edge.shape.count/2],kind:.blocked,title:"× 通行不可登録",subtitle:edge.name,map:map)) } }
            if let target=store.destinationCoordinate { c.dynamicPins.append(pin(target,kind:.target,title:store.targetName,subtitle:"選択した避難先・受入状況未確認",map:map)) }
            if let dropped=store.inspected,dropped.droppedPin { c.dynamicPins.append(pin(dropped.coordinate,kind:.dropped,title:dropped.name,subtitle:"ドロップしたピン",map:map)) }
        }
        if store.simulated,let sample=store.location.sample {
            if let existing=c.simulatedPin { existing.coordinate=sample.coordinate.clLocation }
            else { c.simulatedPin=pin(sample.coordinate,kind:.simulated,title:"模擬位置",subtitle:"実位置ではありません",map:map) }
        } else if let existing=c.simulatedPin { map.removeAnnotation(existing);c.simulatedPin=nil }
        if c.focusToken != store.mapFocusToken { c.focusToken=store.mapFocusToken;if let target=store.mapFocus { c.apply(target,map:map,insets:insets) } }
        if mode == .navigation && c.following { c.follow(map:map) }
    }
    @discardableResult private func add(_ shape:[Coordinate],title:String,map:MKMapView)->MKPolyline { let line=MKPolyline(coordinates:shape.map(\.clLocation),count:shape.count);line.title=title;map.addOverlay(line,level:.aboveRoads);return line }
    @discardableResult private func pin(_ p:Coordinate,kind:GuidePin.Kind,title:String,subtitle:String,map:MKMapView)->GuidePin { let pin=GuidePin(kind:kind);pin.coordinate=p.clLocation;pin.title=title;pin.subtitle=subtitle;map.addAnnotation(pin);return pin }
    @MainActor final class Coordinator:NSObject,MKMapViewDelegate {
        var store:AppStore;var baseKey="";var dynamicKey="";var dynamicOverlays:[any MKOverlay]=[];var dynamicPins:[GuidePin]=[];var gesture:UIPanGestureRecognizer?;var tapGesture:UITapGestureRecognizer?;var points:[Coordinate]=[];var onDestination:((Coordinate)->Void)?;var onTap:(()->Void)?
        var mode:GuideMapMode = .explore;var focusToken=0;var simulatedPin:GuidePin?;var following=false;var lastFollowed:Date?
        init(store:AppStore) { self.store=store }
        func apply(_ focus:MapFocus,map:MKMapView,insets:UIEdgeInsets) {
            let padding=UIEdgeInsets(top:insets.top+40,left:40,bottom:insets.bottom+40,right:40)
            switch focus {
            case .user:
                if mode == .navigation { following=true;lastFollowed=nil;follow(map:map);return }
                if store.simulated,let s=store.location.sample { map.setCenter(s.coordinate.clLocation,animated:true) }
                else if map.userLocation.location != nil { map.setUserTrackingMode(.follow,animated:true) }
                else if let s=store.location.sample { map.setCenter(s.coordinate.clLocation,animated:true) }
            case .route:
                guard mode != .navigation,let route=store.route else { return }
                let shape=RouteTracker.shape(of:route).map(\.clLocation)
                map.setVisibleMapRect(MKPolyline(coordinates:shape,count:shape.count).boundingMapRect,edgePadding:padding,animated:true)
            case .destination:
                if let t=store.destinationCoordinate { map.setRegion(MKCoordinateRegion(center:t.clLocation,latitudinalMeters:700,longitudinalMeters:700),animated:true) }
            case .coordinate(let c):
                map.setRegion(MKCoordinateRegion(center:c.clLocation,latitudinalMeters:600,longitudinalMeters:600),animated:true)
            case .network:
                if let b=store.network?.bounds { let r=MKPolyline(coordinates:[Coordinate(b.south,b.west).clLocation,Coordinate(b.north,b.east).clLocation],count:2).boundingMapRect;map.setVisibleMapRect(r,edgePadding:padding,animated:true) }
            }
        }
        /// Navigation camera: heading-up around the (real or simulated) position.
        func follow(map:MKMapView) {
            if !store.simulated && map.userLocation.location != nil {
                if map.userTrackingMode != .followWithHeading { map.setUserTrackingMode(.followWithHeading,animated:true) }
                return
            }
            guard let sample=store.location.sample,lastFollowed != sample.timestamp else { return }
            lastFollowed=sample.timestamp
            map.setCamera(MKMapCamera(lookingAtCenter:sample.coordinate.clLocation,fromDistance:350,pitch:0,heading:store.heading ?? map.camera.heading),animated:true)
        }
        func mapView(_ mapView:MKMapView,didChange mode:MKUserTrackingMode,animated:Bool) {
            if self.mode == .navigation && mode == .none && !store.simulated { following=false }
        }
        func mapView(_ mapView:MKMapView,regionWillChangeAnimated animated:Bool) {
            guard self.mode == .navigation,store.simulated else { return }
            // A user drag pauses simulated following until the recentre button is used.
            if mapView.subviews.first?.gestureRecognizers?.contains(where:{ $0.state == .began || $0.state == .changed }) == true { following=false }
        }
        @objc func tapped(_ sender:UITapGestureRecognizer) {
            guard sender.state == .ended,let map=sender.view as? MKMapView else { return }
            guard mode == .report else {
                // Taps on POIs/pins also reach this recognizer; only treat it as "tap on empty map" if nothing got selected.
                Task { @MainActor [weak self] in try? await Task.sleep(for:.milliseconds(250));if map.selectedAnnotations.isEmpty { self?.onTap?() } }
                return
            }
            // ~22pt touch tolerance, clamped to 6–30 m so short roads next to each other remain distinguishable.
            let touch=sender.location(in:map),c=map.convert(touch,toCoordinateFrom:map),side=map.convert(CGPoint(x:touch.x+22,y:touch.y),toCoordinateFrom:map)
            let coordinate=Coordinate(c.latitude,c.longitude)
            store.tapRoad(coordinate,radius:max(6,min(30,coordinate.distance(to:Coordinate(side.latitude,side.longitude)))))
        }
        @objc func chooseDestination(_ sender:UILongPressGestureRecognizer) {
            guard sender.state == .began,!store.tracing,let map=sender.view as? MKMapView else { return }
            let c=map.convert(sender.location(in:map),toCoordinateFrom:map);onDestination?(Coordinate(c.latitude,c.longitude))
        }
        @objc func pan(_ sender:UIPanGestureRecognizer) {
            guard let map=sender.view as? MKMapView else { return }
            let touch=sender.location(in:map),coordinate=map.convert(touch,toCoordinateFrom:map)
            let p=Coordinate(coordinate.latitude,coordinate.longitude)
            if sender.state == .began { points=[p] }
            else if sender.state == .changed { if points.last?.distance(to:p) ?? 10 > 1 { points.append(p) } }
            else if sender.state == .ended {
                points.append(p);let side=map.convert(CGPoint(x:touch.x+18,y:touch.y),toCoordinateFrom:map)
                store.finishTrace(points,radius:max(4,min(25,p.distance(to:Coordinate(side.latitude,side.longitude)))))
            } else if sender.state == .cancelled { points=[];store.selectionMessage="なぞり操作を取り消しました" }
        }
        func mapView(_ mapView:MKMapView,rendererFor overlay:any MKOverlay)->MKOverlayRenderer {
            if let multi=overlay as? MKMultiPolyline {
                let r=MKMultiPolylineRenderer(multiPolyline:multi);r.lineCap = .round;r.lineJoin = .round
                switch multi.title {
                case "selectableCasing": r.strokeColor = .white;r.lineWidth=7
                case "selectable": r.strokeColor = .systemTeal;r.lineWidth=3.5
                case "blockedCasing": r.strokeColor = .white;r.lineWidth=11
                case "selectedCasing": r.strokeColor = .systemYellow;r.lineWidth=11
                case "blocked","selected": r.strokeColor = .systemRed;r.lineWidth=6
                default: r.strokeColor = UIColor.systemGray.withAlphaComponent(mode == .navigation ? 0.35:0.55);r.lineWidth=mode == .navigation ? 1:1.5
                }
                return r
            }
            guard let line=overlay as? MKPolyline else { return MKOverlayRenderer(overlay:overlay) }
            let renderer=MKPolylineRenderer(polyline:line)
            switch line.title {
            case "routeCasing": renderer.strokeColor = .white;renderer.lineWidth=11
            case "route": renderer.strokeColor = .systemBlue;renderer.lineWidth=7
            case "approach": renderer.strokeColor = .systemBlue;renderer.lineWidth=5;renderer.lineDashPattern=[2,10]
            default: renderer.strokeColor = .systemIndigo;renderer.lineWidth=2;renderer.lineDashPattern=[5,5]
            }
            renderer.lineCap = .round;renderer.lineJoin = .round
            return renderer
        }
        func mapView(_ mapView:MKMapView,didSelect annotation:any MKAnnotation) {
            guard mode == .explore else { return }
            if let feature=annotation as? MKMapFeatureAnnotation { store.inspect(feature:feature) }
            else if let pin=annotation as? GuidePin,pin.kind == .saved,let d=store.destinations.first(where:{ $0.name == pin.title }) { store.inspect(saved:d) }
        }
        func mapView(_ mapView:MKMapView,didDeselect annotation:any MKAnnotation) {
            guard mode == .explore,mapView.selectedAnnotations.isEmpty else { return }
            Task { @MainActor [weak self] in try? await Task.sleep(for:.milliseconds(300));if mapView.selectedAnnotations.isEmpty,self?.store.inspected?.droppedPin == false { self?.store.inspected=nil } }
        }
        func mapView(_ mapView:MKMapView,viewFor annotation:any MKAnnotation)->MKAnnotationView? {
            guard let pin=annotation as? GuidePin else { return nil }
            let view=mapView.dequeueReusableAnnotationView(withIdentifier:"guide") as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation:pin,reuseIdentifier:"guide")
            view.annotation=pin;view.canShowCallout=mode != .explore || pin.kind == .blocked
            switch pin.kind {
            case .target: view.markerTintColor = .systemRed;view.glyphImage=UIImage(systemName:"mappin");view.displayPriority = .required
            case .saved: view.markerTintColor = .systemGreen;view.glyphImage=UIImage(systemName:"figure.walk");view.displayPriority = .defaultHigh
            case .blocked: view.markerTintColor = .systemOrange;view.glyphImage=UIImage(systemName:"xmark");view.displayPriority = .defaultHigh
            case .simulated: view.markerTintColor = .systemPurple;view.glyphImage=UIImage(systemName:"location.fill");view.displayPriority = .required
            case .dropped: view.markerTintColor = .systemRed;view.glyphImage=UIImage(systemName:"mappin");view.displayPriority = .required
            }
            return view
        }
    }
}
extension Coordinate { var clLocation:CLLocationCoordinate2D { CLLocationCoordinate2D(latitude:latitude,longitude:longitude) } }
