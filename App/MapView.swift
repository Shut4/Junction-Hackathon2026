import SwiftUI
import MapKit

enum GuideMapMode { case explore,report,navigation }

final class GuidePin: MKPointAnnotation {
    enum Kind { case target,endpoint,blocked,simulated,dropped }
    var kind:Kind
    var segmentID:String?
    init(kind:Kind,segmentID:String? = nil) { self.kind=kind;self.segmentID=segmentID;super.init() }
}
/// A plain UIKit boundary prevents MapKit's virtual road/POI accessibility
/// elements from escaping SwiftUI's accessibilityHidden modifier.
final class GuideMapContainer:UIView {
    let map:MKMapView
    var hidesMapElements=false
    var onUserInteraction:(()->Void)?
    override var accessibilityElements:[Any]? {
        get { hidesMapElements ? []:[map] }
        set { }
    }
    // Expose the actual MapKit camera to UI regression tests without adding UI.
    override var accessibilityValue:String? {
        get {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing"),!hidesMapElements {
                return String(map.camera.centerCoordinateDistance)
            }
            #endif
            return super.accessibilityValue
        }
        set { super.accessibilityValue=newValue }
    }
    override func hitTest(_ point:CGPoint,with event:UIEvent?)->UIView? {
        let hit=super.hitTest(point,with:event)
        // Observe real touches before MapKit consumes its private recognizers.
        // This leaves native pinch, double-tap and pan handling unchanged.
        if hit != nil,event?.type == .touches {
            onUserInteraction?()
        }
        return hit
    }
    init(map:MKMapView) {
        self.map=map
        super.init(frame:.zero)
        isAccessibilityElement=false
        addSubview(map);map.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([map.leadingAnchor.constraint(equalTo:leadingAnchor),map.trailingAnchor.constraint(equalTo:trailingAnchor),map.topAnchor.constraint(equalTo:topAnchor),map.bottomAnchor.constraint(equalTo:bottomAnchor)])
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
}
struct GuideMap: UIViewRepresentable {
    @ObservedObject var store: AppStore
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    var mode:GuideMapMode = .explore
    var onDestination: ((Coordinate)->Void)? = nil
    var onBlockedReport: ((Report)->Void)? = nil
    var onTap: (()->Void)? = nil
    /// Keeps Apple's legal label, compass and focused content clear of floating panels.
    var insets=UIEdgeInsets.zero
    func makeCoordinator() -> Coordinator { Coordinator(store:store) }
    func makeUIView(context:Context)->GuideMapContainer {
        let map=MKMapView();map.delegate=context.coordinator;map.showsUserLocation=true;map.showsTraffic=false;map.showsScale=mode != .explore
        map.pointOfInterestFilter = mode == .explore ? .includingAll:.excludingAll;map.isPitchEnabled=false;map.isRotateEnabled=mode == .navigation
        map.preferredConfiguration=MKStandardMapConfiguration(emphasisStyle:mode == .report ? .muted:.default)
        // Home map: POIs are tappable like Google Maps and open the place card.
        map.selectableMapFeatures=mode == .explore ? [.pointsOfInterest,.physicalFeatures,.territories]:[]
        if let b=store.network?.bounds {
            let span=mode == .explore ? MKCoordinateSpan(latitudeDelta:(b.north-b.south)*0.55,longitudeDelta:(b.east-b.west)*0.55):MKCoordinateSpan(latitudeDelta:(b.north-b.south)*0.35,longitudeDelta:(b.east-b.west)*0.35)
            map.setRegion(MKCoordinateRegion(center:CLLocationCoordinate2D(latitude:(b.south+b.north)/2,longitude:(b.west+b.east)/2),span:span),animated:false)
        }
        let press=UILongPressGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.chooseDestination(_:)));press.isEnabled=mode == .explore;map.addGestureRecognizer(press)
        let tap=UITapGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.tapped(_:)));tap.cancelsTouchesInView=false;tap.delegate=context.coordinator;map.addGestureRecognizer(tap)
        context.coordinator.mode=mode
        configureAccessibility(map)
        if mode == .navigation { context.coordinator.following=true }
        let container=GuideMapContainer(map:map)
        container.onUserInteraction = { [weak coordinator=context.coordinator] in coordinator?.routeOverviewActive=false }
        container.hidesMapElements=AccessibilityLayout.voiceOver(voiceOver)
        return container
    }
    private func configureAccessibility(_ map:MKMapView) {
        let accessibleLayout=AccessibilityLayout.voiceOver(voiceOver)
        map.accessibilityElementsHidden=accessibleLayout
        map.isAccessibilityElement=false
        if accessibleLayout {
            map.accessibilityLabel=nil;map.accessibilityHint=nil
            map.accessibilityTraits.remove(.allowsDirectInteraction)
            return
        }
        map.accessibilityLabel=localized(mode == .report ? "通行不可登録の地図。青緑の線が選択できる道路です。道路をタップして選択します。":mode == .navigation ? "ナビの地図。青い線が経路です。":"対応地域の実地図。長押しで目的地を選択できます。目的地は検索欄からも選べます。")
        if mode == .report {
            map.accessibilityHint=localized("道路を選択すると、選択区間数と登録ボタンの状態が更新されます")
            map.accessibilityTraits.insert(.allowsDirectInteraction)
        }
    }
    func updateUIView(_ container:GuideMapContainer,context:Context) {
        let map=container.map
        container.hidesMapElements=AccessibilityLayout.voiceOver(voiceOver)
        configureAccessibility(map)
        let c=context.coordinator
        c.store=store;c.onDestination=onDestination;c.onBlockedReport=onBlockedReport;c.onTap=onTap;c.mode=mode
        // MapKit may adjust its margins while zooming. Compare requested layout
        // values, rather than treating those internal changes as panel changes.
        let insetsChanged=c.requestedInsets != insets
        if insetsChanged { c.requestedInsets=insets;map.layoutMargins=insets }
        guard let network=store.network else { return }
        // The static road-network layer is built once per mode; only small dynamic layers are replaced.
        let baseKey="\(mode)|\(network.id)|\(network.version)"
        if baseKey != c.baseKey {
            c.baseKey=baseKey;c.dynamicKey="";map.removeOverlays(map.overlays);map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) });c.simulatedPin=nil;c.dynamicOverlays=[];c.dynamicPins=[]
            let lines=network.edges.map { MKPolyline(coordinates:$0.shape.map(\.clLocation),count:$0.shape.count) }
            for title in mode == .report ? ["selectableCasing","selectable"]:["walk"] { let multi=MKMultiPolyline(lines);multi.title=title;map.addOverlay(multi,level:.aboveRoads) }
        }
        let dynamicKey="\(store.selected.sorted())|\(store.blocked.sorted())|\(store.routeVersion)|\(store.route != nil)|\(store.destinationID)|\(String(describing:store.destinationCoordinate))|\(String(describing:store.guideEndpointCoordinate))|\(store.inspected?.droppedPin == true ? String(describing:store.inspected?.coordinate):"")"
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
            if mode != .report { for edge in blocked { c.dynamicPins.append(pin(edge.shape[edge.shape.count/2],kind:.blocked,title:localized("× 通行不可登録"),subtitle:localized("{0}・タップして削除",edge.name),segmentID:edge.id,map:map)) } }
            if let target=store.destinationCoordinate { c.dynamicPins.append(pin(target,kind:.target,title:store.targetName,subtitle:localized("選択した目的地・受入状況未確認"),map:map)) }
            if let endpoint=store.confirmedDestinationConnection?.coordinate { c.dynamicPins.append(pin(endpoint,kind:.endpoint,title:localized("道路上の案内終点"),subtitle:localized("ここまでが保存済み道路による案内です"),map:map)) }
            if let dropped=store.inspected,dropped.droppedPin { c.dynamicPins.append(pin(dropped.coordinate,kind:.dropped,title:dropped.name,subtitle:"ドロップしたピン",map:map)) }
        }
        if store.simulated,let sample=store.location.sample {
            if let existing=c.simulatedPin { existing.coordinate=sample.coordinate.clLocation }
            else { c.simulatedPin=pin(sample.coordinate,kind:.simulated,title:localized("模擬位置"),subtitle:localized("実位置ではありません"),map:map) }
        } else if let existing=c.simulatedPin { map.removeAnnotation(existing);c.simulatedPin=nil }
        let focusChanged=c.focusToken != store.mapFocusToken
        if focusChanged {
            c.focusToken=store.mapFocusToken
            c.routeOverviewActive=false
            if let target=store.mapFocus { c.apply(target,map:map,insets:insets) }
        }
        // The destination panel changes height after a route is calculated.
        // Fit again with its measured height so neither endpoint is hidden behind it.
        if insetsChanged,!focusChanged,c.routeOverviewActive,mode == .explore,case .route?=store.mapFocus {
            c.apply(.route,map:map,insets:insets,animated:false)
        }
        if mode == .navigation && c.following { c.follow(map:map) }
    }
    @discardableResult private func add(_ shape:[Coordinate],title:String,map:MKMapView)->MKPolyline { let line=MKPolyline(coordinates:shape.map(\.clLocation),count:shape.count);line.title=title;map.addOverlay(line,level:.aboveRoads);return line }
    @discardableResult private func pin(_ p:Coordinate,kind:GuidePin.Kind,title:String,subtitle:String,segmentID:String? = nil,map:MKMapView)->GuidePin { let pin=GuidePin(kind:kind,segmentID:segmentID);pin.coordinate=p.clLocation;pin.title=title;pin.subtitle=subtitle;map.addAnnotation(pin);return pin }
    @MainActor final class Coordinator:NSObject,MKMapViewDelegate,UIGestureRecognizerDelegate {
        var store:AppStore;var baseKey="";var dynamicKey="";var dynamicOverlays:[any MKOverlay]=[];var dynamicPins:[GuidePin]=[];var onDestination:((Coordinate)->Void)?;var onBlockedReport:((Report)->Void)?;var onTap:(()->Void)?
        var mode:GuideMapMode = .explore;var focusToken=0;var simulatedPin:GuidePin?;var following=false;var lastFollowed:Date?
        var requestedInsets:UIEdgeInsets?
        var routeOverviewActive=false
        init(store:AppStore) { self.store=store }
        func apply(_ focus:MapFocus,map:MKMapView,insets:UIEdgeInsets,animated:Bool=true) {
            // MapKit already includes layoutMargins when fitting overlays.
            // Only add breathing room here; panel insets must not be counted twice.
            let padding=UIEdgeInsets(top:24,left:24,bottom:24,right:24)
            switch focus {
            case .user:
                if mode == .navigation { following=true;lastFollowed=nil;follow(map:map);return }
                if store.simulated,let s=store.location.sample { map.setCenter(s.coordinate.clLocation,animated:true) }
                else if map.userLocation.location != nil { map.setUserTrackingMode(.follow,animated:true) }
                else if let s=store.location.sample { map.setCenter(s.coordinate.clLocation,animated:true) }
            case .route:
                guard mode != .navigation,let route=store.route else { return }
                routeOverviewActive=true
                // Stop a previous current-location follow before fitting the full route.
                map.setUserTrackingMode(.none,animated:false)
                var coordinates=RouteTracker.shape(of:route)
                if let target=store.destinationCoordinate { coordinates.append(target) }
                guard !coordinates.isEmpty else { return }
                let line=MKPolyline(coordinates:coordinates.map(\.clLocation),count:coordinates.count)
                var rect=line.boundingMapRect
                // Keep very short or straight routes from zooming in excessively.
                let minimum=250 * MKMapPointsPerMeterAtLatitude(line.coordinate.latitude)
                rect=rect.insetBy(dx:-max(0,(minimum-rect.width)/2),dy:-max(0,(minimum-rect.height)/2))
                map.setVisibleMapRect(rect,edgePadding:padding,animated:animated)
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
        // MapKit also uses a single-tap recognizer. Both may receive a road tap;
        // pans, pinches and double-tap zoom retain their normal gesture arbitration.
        func gestureRecognizer(_ gestureRecognizer:UIGestureRecognizer,shouldRecognizeSimultaneouslyWith otherGestureRecognizer:UIGestureRecognizer)->Bool {
            guard mode == .report,let tap=otherGestureRecognizer as? UITapGestureRecognizer else { return false }
            return tap.numberOfTapsRequired == 1 && tap.numberOfTouchesRequired == 1
        }
        @objc func tapped(_ sender:UITapGestureRecognizer) {
            guard sender.state == .ended,let map=sender.view as? MKMapView else { return }
            guard mode == .report else {
                // Taps on POIs/pins also reach this recognizer; only treat it as "tap on empty map" if nothing got selected.
                Task { @MainActor [weak self] in try? await Task.sleep(for:.milliseconds(250));if map.selectedAnnotations.isEmpty { self?.onTap?() } }
                return
            }
            // Keep the hit area at 22 screen points, including when zoomed out.
            // Nearby roads remain candidates rather than silently ignoring a visible line.
            let touch=sender.location(in:map),c=map.convert(touch,toCoordinateFrom:map),side=map.convert(CGPoint(x:touch.x+22,y:touch.y),toCoordinateFrom:map)
            let coordinate=Coordinate(c.latitude,c.longitude)
            if let report=store.tapRoad(coordinate,radius:max(6,coordinate.distance(to:Coordinate(side.latitude,side.longitude)))) { onBlockedReport?(report) }
        }
        @objc func chooseDestination(_ sender:UILongPressGestureRecognizer) {
            guard sender.state == .began,let map=sender.view as? MKMapView else { return }
            let c=map.convert(sender.location(in:map),toCoordinateFrom:map);onDestination?(Coordinate(c.latitude,c.longitude))
        }
        func mapView(_ mapView:MKMapView,rendererFor overlay:any MKOverlay)->MKOverlayRenderer {
            if let multi=overlay as? MKMultiPolyline {
                let r=MKMultiPolylineRenderer(multiPolyline:multi);r.lineCap = .round;r.lineJoin = .round
                switch multi.title {
                case "selectableCasing": r.strokeColor = .white;r.lineWidth=7
                case "selectable": r.strokeColor = .systemTeal;r.lineWidth=3.5
                case "blockedCasing": r.strokeColor = .white;r.lineWidth=11
                case "selectedCasing": r.strokeColor = .systemYellow;r.lineWidth=11
                case "blocked": r.strokeColor = .systemOrange;r.lineWidth=6;r.lineDashPattern=[5,5]
                case "selected": r.strokeColor = .systemRed;r.lineWidth=6
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
            else if let pin=annotation as? GuidePin,pin.kind == .blocked,let id=pin.segmentID { store.pendingReportRemoval=store.reports.first(where: { $0.segmentID == id }) }
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
            case .endpoint: view.markerTintColor = .systemBlue;view.glyphImage=UIImage(systemName:"figure.walk.arrival");view.displayPriority = .required
            case .blocked: view.markerTintColor = .systemOrange;view.glyphImage=UIImage(systemName:"xmark");view.displayPriority = .defaultHigh
            case .simulated: view.markerTintColor = .systemPurple;view.glyphImage=UIImage(systemName:"location.fill");view.displayPriority = .required
            case .dropped: view.markerTintColor = .systemRed;view.glyphImage=UIImage(systemName:"mappin");view.displayPriority = .required
            }
            return view
        }
    }
}
extension Coordinate { var clLocation:CLLocationCoordinate2D { CLLocationCoordinate2D(latitude:latitude,longitude:longitude) } }
