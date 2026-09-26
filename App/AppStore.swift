import SwiftUI
import Combine
import CoreLocation

enum GuidanceMode:String { case map,camera }
enum MapFocus:Equatable { case user,route,destination,network,coordinate(Coordinate) }

@MainActor final class AppStore: ObservableObject {
    @Published var network: Network?
    @Published var networkError: String?
    @Published var reports: [Report] = [] { didSet { let ids=Set(reports.map(\.segmentID));if ids != blocked { blocked=ids } } }
    /// Cached: previously recomputed from `reports` on every access, including per-edge loops.
    @Published private(set) var blocked=Set<String>()
    @Published var inspected:InspectedPlace?
    @Published var storageError: String?
    @Published var storageIncompatible = false
    @Published var selected = Set<String>()
    @Published var selectionMessage = "地図の道路をタップして選択してください"
    @Published var traceCandidates: [MatchCandidate] = []
    @Published var ambiguity = false
    @Published var destinationID = ""
    @Published var selectedTarget:Coordinate?
    @Published var targetName="避難先を選択してください"
    @Published var customDestination:Destination?
    @Published var destinationConnections:[DestinationConnection]=[]
    @Published var destinationMessage="避難所の開設・受入状況は確認していません"
    @Published var previewStart = ""
    @Published var route: WalkRoute?
    @Published var navigating = false
    @Published var routeVersion = 0
    @Published var reroutes = 0
    @Published var nextInstruction = "目的地を選んでください"
    @Published var positionState = "位置情報を開始してください"
    @Published var matchedEdge: String?
    @Published var developer = false
    @Published var notice: String?
    @Published var tracing = false
    @Published var trace: [Coordinate] = []
    @Published var simulatedNoticeCount=0
    @Published var guidanceActive=false
    @Published var guidanceMode:GuidanceMode = .map
    @Published private(set) var mapFocus:MapFocus?
    @Published private(set) var mapFocusToken=0
    @Published private(set) var stepIndex = 0
    @Published var simulatedWalkActive=false
    @Published var simulatedWalkSpeed=1.2
    @Published var lastRouteMilliseconds:Double?
    // DeveloperMode camera overlay settings persist between launches.
    @Published var showBoxes:Bool { didSet { UserDefaults.standard.set(showBoxes,forKey:"dev.showBoxes");debugLog(.developer,.info,"BBOX overlay \(showBoxes ? "on":"off")") } }
    @Published var showBoxLabels:Bool { didSet { UserDefaults.standard.set(showBoxLabels,forKey:"dev.showBoxLabels") } }
    @Published var boxMinConfidence:Double { didSet { UserDefaults.standard.set(boxMinConfidence,forKey:"dev.boxMinConfidence") } }
    @Published var showARArrow:Bool { didSet { UserDefaults.standard.set(showARArrow,forKey:"dev.showARArrow") } }
    @Published var headingOffset:Double { didSet { UserDefaults.standard.set(headingOffset,forKey:"dev.headingOffset") } }
    var simulationFilter=NoticeFilter()
    let speech = SpeechController()
    let location = LocationController()
    let camera = CameraController()
    let persistence: ReportStore
    let simulatedPersistence: ReportStore
    private var subscriptions = Set<AnyCancellable>()
    private var arrivalSamples = 0
    private var lastArrivalTimestamp: Date?
    private var lastSpoken = ""
    var versionTaps = 0
    var lastTap: Date?
    private var deviationSamples = 0
    private var lastDeviationTimestamp: Date?
    var simulationTask: Task<Void,Never>?
    var walkTask: Task<Void,Never>?
    var metrics:[MetricEvent]=[]
    var droppedMetrics=0
    var positionResolver=PositionResolver()
    private var lastPositionKey=""
    private(set) var edgeIndex:[String:WalkEdge]=[:]
    private(set) var placeIndex:[String:Place]=[:]
    var edges: [WalkEdge] { network?.edges ?? [] }
    var destinations: [Destination] { network?.destinations ?? [] }
    var currentDestination: Destination? { customDestination ?? destinations.first { $0.id == destinationID } }
    var destinationCoordinate:Coordinate? { selectedTarget ?? currentDestination.flatMap { place($0.nodeID)?.coordinate } }
    var simulated: Bool { location.simulated }
    var activeStore:ReportStore { simulated ? simulatedPersistence:persistence }
    init() {
        let defaults=UserDefaults.standard
        showBoxes=defaults.bool(forKey:"dev.showBoxes");showBoxLabels=defaults.object(forKey:"dev.showBoxLabels") as? Bool ?? true
        boxMinConfidence=defaults.object(forKey:"dev.boxMinConfidence") as? Double ?? 0.3;showARArrow=defaults.object(forKey:"dev.showARArrow") as? Bool ?? true
        headingOffset=defaults.double(forKey:"dev.headingOffset")
        #if DEBUG
        // UI testing only: skips the 7-tap gesture. Never compiled into Release builds.
        if ProcessInfo.processInfo.arguments.contains("--developer-mode") { developer=true }
        #endif
        let directory=AppFiles.directory
        persistence=ReportStore(url:directory.appending(path:"real-reports.json"))
        simulatedPersistence=ReportStore(url:directory.appending(path:"simulation-reports.json"))
        let started=Date()
        do {
            guard let url=Bundle.main.url(forResource:"kokura-network",withExtension:"json") else { throw CoreError.invalidNetwork }
            let data=try JSONDecoder().decode(Network.self,from:Data(contentsOf:url));try data.validate();network=data
            edgeIndex=Dictionary(data.edges.map { ($0.id,$0) },uniquingKeysWith:{ a,_ in a });placeIndex=Dictionary(data.nodes.map { ($0.id,$0) },uniquingKeysWith:{ a,_ in a })
            previewStart=data.destinations.last?.nodeID ?? ""
            debugLog(.storage,.success,"Road network loaded",["version":data.version,"nodes":data.nodes.count,"edges":data.edges.count,"destinations":data.destinations.count,"loadMs":Int(Date().timeIntervalSince(started)*1000)])
            loadReports(from:persistence,network:data)
        } catch { networkError=error.localizedDescription;debugLog(.storage,.error,"Road network failed",["error":error.localizedDescription]) }
        location.$sample.sink { [weak self] _ in Task { @MainActor in self?.updatePosition() } }.store(in:&subscriptions)
        for publisher in [location.objectWillChange.eraseToAnyPublisher(),speech.objectWillChange.eraseToAnyPublisher(),camera.objectWillChange.eraseToAnyPublisher()] {
            publisher.sink { [weak self] _ in self?.objectWillChange.send() }.store(in:&subscriptions)
        }
        Timer.publish(every:1,on:.main,in:.common).autoconnect().sink { [weak self] _ in self?.updatePosition() }.store(in:&subscriptions)
        camera.onNotice = { [weak self] n in guard let self else { return };speech.say(n.text,obstacle:true,capturedAt:n.capturedAt) }
        camera.onMetric = { [weak self] event in self?.record(event) }
        speech.onMetric = { [weak self] event in self?.record(event) }
    }
    func loadReports(from store:ReportStore,network:Network) {
        do { reports=try store.load(network:network);storageError=nil;storageIncompatible=false;debugLog(.storage,.success,"Reports loaded",["count":reports.count,"simulated":store === simulatedPersistence]) }
        catch { storageError=error.localizedDescription;storageIncompatible=(error as? CoreError) == .incompatibleReports;debugLog(.storage,.error,"Reports could not be loaded",["error":error.localizedDescription,"incompatible":storageIncompatible]) }
    }
    func edge(_ id:String)->WalkEdge? { edgeIndex[id] }
    func place(_ id:String)->Place? { placeIndex[id] }
    func name(_ node: String) -> String { place(node)?.name ?? "現在位置" }
    func focus(_ target:MapFocus) { mapFocus=target;mapFocusToken += 1 }
    func focusOn(_ c:CLLocationCoordinate2D) { focus(.coordinate(Coordinate(c.latitude,c.longitude))) }
    // MARK: Destination
    func chooseTarget(_ coordinate:Coordinate,name:String) {
        stopNavigation();destinationID="";customDestination=nil;selectedTarget=coordinate;targetName=name
        guard let network else { destinationMessage="道路データを読み込めません";return }
        destinationConnections=DestinationConnection.candidates(for:coordinate,network:network)
        destinationMessage = !network.bounds.contains(coordinate) ? "選択した避難先は経路案内の対応範囲外です" : destinationConnections.isEmpty ? "近くに保存済み道路の接続点がありません。別の避難先を選択してください" : "案内の終点を下の候補から確認してください。施設入口への接続は未確認です"
        debugLog(.search,.info,"Destination chosen",["inBounds":network.bounds.contains(coordinate),"connectionCandidates":destinationConnections.count])
        focus(.destination)
    }
    func confirmConnection(_ nodeID:String) {
        guard let candidate=destinationConnections.first(where:{$0.nodeID==nodeID}),place(nodeID) != nil else { return }
        stopNavigation();destinationID="chosen-"+nodeID
        customDestination=Destination(id:destinationID,name:targetName,nodeID:nodeID,note:"道路接続点まで案内。選択地点まで約\(Int(candidate.distance.rounded())) m・入口未確認")
        destinationMessage=customDestination!.note
        debugLog(.search,.success,"Road connection confirmed",["node":nodeID,"distanceM":Int(candidate.distance.rounded())])
    }
    func chooseSavedDestination(_ destination:Destination) {
        stopNavigation();customDestination=nil;selectedTarget=nil;destinationConnections=[];destinationID=destination.id;targetName=destination.name;destinationMessage=destination.note
        debugLog(.search,.info,"Saved destination chosen",["id":destination.id]);focus(.destination)
    }
    func clearDestination() {
        stopNavigation();customDestination=nil;selectedTarget=nil;destinationConnections=[];destinationID="";targetName="避難先を選択してください";destinationMessage="避難所の開設・受入状況は確認していません"
    }
    // MARK: Routing and guidance
    func calculate(usePosition:Bool) {
        guard let network,let destination=currentDestination,storageError == nil else { notice="道路・報告・目的地の状態を確認してください";return }
        let operation=DebugLogger.operationID(),started=Date()
        debugLog(.route,.start,"Route search started",["usePosition":usePosition,"destination":destination.nodeID,"blocked":blocked.count],operation:operation)
        let resume=navigating;navigating=false;route=nil
        speech.invalidateRoute();routeVersion += 1;stepIndex=0;arrivalSamples=0;lastSpoken=""
        if usePosition {
            updatePosition()
            guard let sample=location.sample,let edge=matchedEdge else { route=nil;nextInstruction="現在位置の道路を確定できません。案内を保留します。";notice=nextInstruction;debugLog(.route,.cancelled,"Route search held: position not matched",["state":positionState],operation:operation);return }
            route=Router(network:network).route(from:sample.coordinate,on:edge,to:destination.nodeID,blocked:blocked)
        } else { route=Router(network:network).route(from:previewStart,to:destination.nodeID,blocked:blocked) }
        lastRouteMilliseconds=Date().timeIntervalSince(started)*1000
        if let route { debugLog(.route,.success,"Route found",["distanceM":Int(route.distance),"steps":route.steps.count,"routeVersion":routeVersion,"ms":Int(lastRouteMilliseconds ?? 0)],operation:operation);focus(.route) }
        else { nextInstruction="経路がありません。通行不可と対応範囲を確認してください。";notice=nextInstruction;debugLog(.route,.error,"No route",["blocked":blocked.count,"ms":Int(lastRouteMilliseconds ?? 0)],operation:operation) }
        navigating=resume && route != nil
    }
    func startGuidance(_ mode:GuidanceMode) {
        calculate(usePosition:true)
        guard route != nil,matchedEdge != nil else { return }
        navigating=true;guidanceMode=mode;guidanceActive=true
        if mode == .camera { camera.start() }
        debugLog(.navigation,.start,"Guidance started",["mode":mode.rawValue,"distanceM":Int(route?.distance ?? 0),"simulated":simulated])
        updatePosition()
    }
    func openCamera() { guidanceMode = .camera;guidanceActive=true;debugLog(.navigation,.info,"Full camera opened",["navigating":navigating]) }
    func switchGuidance(to mode:GuidanceMode) {
        guidanceMode=mode
        if mode == .camera { if !camera.running { camera.start() } } else { camera.stop() }
        debugLog(.navigation,.info,"Guidance view switched",["mode":mode.rawValue])
    }
    func closeGuidance() { guidanceActive=false;camera.stop();debugLog(.navigation,.info,"Guidance view closed",["navigating":navigating]) }
    func stopNavigation() {
        if navigating { debugLog(.navigation,.cancelled,"Guidance stopped",["stepIndex":stepIndex]) }
        navigating=false;route=nil;speech.stop();lastSpoken="";nextInstruction="案内を停止しました";stepIndex=0;stopSimulatedWalk()
    }
    func repeatInstruction() { speech.say(navigating ? nextInstruction:positionState) }
    func reroute(blockage:Bool) {
        reroutes += 1;debugLog(.route,.warning,"Reroute",["reason":blockage ? "blockage":"deviation","count":reroutes]);calculate(usePosition:true)
        if route != nil { if blockage { speech.say("通行不可のため経路を変更しました") };updatePosition() }
        else { navigating=false;speech.say(nextInstruction) }
    }
    var progress:RouteProgress? {
        guard let route,let sample=location.sample else { return nil }
        return RouteTracker.progress(route:route,stepIndex:stepIndex,position:sample.coordinate)
    }
    /// Compass heading of the top/back of the device including the developer calibration offset.
    var heading:Double? { location.heading.map { ($0.degrees+headingOffset+720).truncatingRemainder(dividingBy:360) } }
    var headingReliable:Bool { guard let h=location.heading else { return false };return h.accuracy >= 0 && h.accuracy <= 25 }
    func updatePosition() {
        guard let network,let sample=location.sample else { matchedEdge=nil;positionState=location.status;if navigating { hold(positionState) };return }
        let verdict=positionResolver.evaluate(sample,network:network)
        switch verdict {
        case .outside: matchedEdge=nil;positionState="対応範囲外です。案内を保留します。"
        case .uncertain(let message): matchedEdge=nil;positionState=message
        case .matched(let id): matchedEdge=id;positionState="\(sample.simulated ? "模擬位置":"実位置")・道路候補を照合。精度約\(Int(sample.accuracy))メートル"
        }
        let key=matchedEdge ?? positionState
        if key != lastPositionKey { lastPositionKey=key;debugLog(.location,matchedEdge == nil ? .warning:.success,matchedEdge == nil ? "Position held":"Position matched to road",["state":positionState,"edge":matchedEdge,"accuracy":Int(sample.accuracy),"simulated":sample.simulated]) }
        guard navigating else { return }
        guard matchedEdge != nil,storageError == nil else { hold(positionState);return }
        guard let route else { hold("経路を確認中です");return }
        if !route.steps.isEmpty && !route.steps.contains(where: { $0.id == matchedEdge }) {
            if lastDeviationTimestamp != sample.timestamp { deviationSamples += 1;lastDeviationTimestamp=sample.timestamp }
            hold("経路との対応を確認中です。立ち止まって確認してください。")
            if deviationSamples >= 3 { deviationSamples=0;reroute(blockage:false) };return
        }
        deviationSamples=0
        if let index=route.steps.enumerated().dropFirst(stepIndex).first(where:{$0.element.id==matchedEdge})?.offset,index<=stepIndex+1,index != stepIndex { stepIndex=index;debugLog(.navigation,.info,"Step advanced (matched)",["step":stepIndex,"of":route.steps.count]) }
        if let end=place(route.destinationID),sample.accuracy <= 8,sample.coordinate.distance(to:end.coordinate) <= 6,stepIndex >= max(0,route.steps.count-1) {
            if lastArrivalTimestamp != sample.timestamp { arrivalSamples += 1;lastArrivalTimestamp=sample.timestamp }
            if arrivalSamples >= 3 { navigating=false;speech.invalidateRoute();stopSimulatedWalk();nextInstruction="避難先の道路接続点付近です。施設入口と受入状況を同行者と確認してください。";speech.say(nextInstruction);debugLog(.navigation,.success,"Arrived near destination connection");return }
        } else { arrivalSamples=0 }
        if route.steps.isEmpty { hold("目的地の実験接続点付近です。同行者と確認してください。");return }
        if stepIndex < route.steps.count-1,let end=place(route.steps[stepIndex].to), sample.accuracy <= 8,sample.coordinate.distance(to:end.coordinate) <= 6 { stepIndex += 1;debugLog(.navigation,.info,"Step advanced (junction reached)",["step":stepIndex,"of":route.steps.count]) }
        let step=route.steps[min(stepIndex,route.steps.count-1)]
        let road=edge(step.id)?.name ?? "歩行区間"
        let distance=place(step.to).map { Int(sample.coordinate.distance(to:$0.coordinate).rounded()) } ?? Int(step.distance)
        let following=stepIndex+1 < route.steps.count ? route.steps[stepIndex+1]:nil
        let turn=matchedEdge == step.id ? TurnGuidance.instruction(current:step,next:following,sample:sample):nil
        nextInstruction=turn.map { "約\(distance)メートル先。"+$0+" \(road)。" } ?? "次は\(name(step.to))です。\(road)の経路を同行者と確認。残り約\(distance)メートル。向きは確認中です。"
        let key2="\(routeVersion):\(stepIndex)"
        if lastSpoken != key2 { lastSpoken=key2;speech.say(nextInstruction) }
    }
    private func hold(_ text:String) { nextInstruction=text;if lastSpoken != text { speech.invalidateRoute();speech.say(text);lastSpoken=text;debugLog(.navigation,.warning,"Guidance held",["reason":text]) } }
    func record(_ event:MetricEvent) { if metrics.count>=2000 { metrics.removeFirst();droppedMetrics += 1 };metrics.append(event) }
    func pause() { debugLog(.lifecycle,.info,"Moved to background: guidance, camera and location stopped",["navigating":navigating]);stopNavigation();camera.stop();location.stop();simulationTask?.cancel();guidanceActive=false }
}
