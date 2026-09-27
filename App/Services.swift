import SwiftUI
import CoreLocation
import AVFoundation

@MainActor final class SpeechController: NSObject, ObservableObject, @preconcurrency AVSpeechSynthesizerDelegate {
    @Published var pending = 0
    @Published var status = "待機中"
    @Published var lastStartLatency: Double?
    private let synth = AVSpeechSynthesizer()
    private var queue = SpeechQueue()
    private var active: SpeechJob?
    var onMetric:((MetricEvent)->Void)?
    override init() { super.init(); synth.delegate = self }
    /// With VoiceOver on, messages go through VoiceOver announcements (so two voices never overlap) with VoiceOver's
    /// own priority: critical/high interrupt, normal queue, low is dropped while VoiceOver is busy.
    private var voiceOverLast:[String:Double]=[:]
    func invalidateRoute() {
        queue.invalidateRoute()
        if active?.route == true { synth.stopSpeaking(at:.immediate) }
        pending = queue.count
    }
    func stop() { queue.stop();pending=0;synth.stopSpeaking(at:.immediate);status="停止" }
    /// Legacy form: obstacle = high priority, otherwise a route message (dropped when the route changes).
    func say(_ text: String, obstacle: Bool = false, capturedAt: Double? = nil, ttl: Double? = nil) {
        say(text,priority:obstacle ? .high:.normal,route:!obstacle,capturedAt:capturedAt,ttl:ttl ?? (obstacle ? 2:nil))
    }
    func say(_ text: String, priority: SpeechPriority, route: Bool = false, capturedAt: Double? = nil, ttl: Double? = nil) {
        if UIAccessibility.isVoiceOverRunning { announce(text,priority:priority);return }
        guard active?.text != text else { return }
        guard queue.enqueue(text,priority:priority,route:route,capturedAt:capturedAt,ttl:ttl) else { debugLog(.speech,.debug,"Speech duplicate suppressed",["characters":text.count]);return };pending=queue.count
        // More urgent hazards cut off whatever is being said; equal priority waits its turn.
        if let current=active,priority >= .high,priority > current.priority { synth.stopSpeaking(at:.immediate) }
        if active == nil { playNext() }
    }
    private func announce(_ text:String,priority:SpeechPriority) {
        let now=ProcessInfo.processInfo.systemUptime
        guard now-voiceOverLast[text,default: -.infinity] >= 2 else { return };voiceOverLast[text]=now
        if voiceOverLast.count > 50 { voiceOverLast=voiceOverLast.filter { now-$0.value < 10 } }
        let level:UIAccessibilityPriority = priority >= .high ? .high:priority == .normal ? .default:.low
        UIAccessibility.post(notification:.announcement,argument:NSAttributedString(string:text,attributes:[.accessibilitySpeechAnnouncementPriority:level,.accessibilitySpeechQueueAnnouncement:priority < .high]))
        status="VoiceOverで読み上げ";debugLog(.speech,.info,"VoiceOver announcement",["priority":"\(priority)","characters":text.count])
    }
    private func playNext() {
        while let item=queue.next() {
            pending=queue.count
            active=item
            do { try AVAudioSession.sharedInstance().setCategory(.playback,mode:.spokenAudio,options:[.duckOthers]); try AVAudioSession.sharedInstance().setActive(true) } catch { status="音声出力を開始できません";debugLog(.speech,.error,"Audio session activation failed",["error":error.localizedDescription]);active=nil;continue }
            let utterance = AVSpeechUtterance(string:item.text);utterance.voice=AVSpeechSynthesisVoice(language:"ja-JP");utterance.rate=0.48;synth.speak(utterance);return
        }
        status="待機中";try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,didStart utterance:AVSpeechUtterance) {
        status="発話中"
        onMetric?(MetricEvent(kind:"speechStartCallback",frame:active?.detectionTime,speechStart:ProcessInfo.processInfo.systemUptime,simulated:utterance.speechString.hasPrefix("模擬")))
        if let time=active?.detectionTime { lastStartLatency=ProcessInfo.processInfo.systemUptime-time }
        debugLog(.speech,.info,"Speech started",["characters":utterance.speechString.count,"priority":active.map { "\($0.priority)" } ?? "none","pending":pending,"detectionLatencyMs":lastStartLatency.map { Int($0*1000) }])
        #if DEBUG
        print("GUIDE_SPEECH_START priority=\(active?.priority.rawValue ?? -1) detection_latency_ms=\(lastStartLatency.map { Int($0*1000) } ?? -1)")
        #endif
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,didFinish utterance:AVSpeechUtterance) { active=nil;playNext() }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,didCancel utterance:AVSpeechUtterance) { debugLog(.speech,.cancelled,"Speech cancelled");active=nil;playNext() }
}

/// Plays `Earcon` sounds through its own audio engine, mixed with speech. Stops the engine when idle to save power.
@MainActor final class EarconPlayer {
    static let shared=EarconPlayer()
    /// User setting for hazard warning beeps. Hazard vibration is unaffected.
    var hazardEnabled=true
    /// DeveloperMode tuning of pitch, length, volume, the critical rhythm and vibration.
    var tuning=FeedbackTuning()
    private let engine=AVAudioEngine()
    private let node=AVAudioPlayerNode()
    private let format=AVAudioFormat(standardFormatWithSampleRate:44_100,channels:2)!
    private var pending=0
    private init() { engine.attach(node);engine.connect(node,to:engine.mainMixerNode,format:format) }
    func play(_ earcon:Earcon) {
        guard hazardEnabled else { return }
        let pcm=earcon.samples(sampleRate:format.sampleRate,tuning:tuning)
        guard !pcm.left.isEmpty,let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(pcm.left.count)),let channels=buffer.floatChannelData else { return }
        buffer.frameLength=AVAudioFrameCount(pcm.left.count)
        pcm.left.withUnsafeBufferPointer { channels[0].update(from:$0.baseAddress!,count:pcm.left.count) }
        pcm.right.withUnsafeBufferPointer { channels[1].update(from:$0.baseAddress!,count:pcm.right.count) }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback,mode:.spokenAudio,options:[.duckOthers,.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            if !engine.isRunning { try engine.start() }
        } catch { debugLog(.speech,.error,"Earcon audio failed",["error":error.localizedDescription]);return }
        // A new cue replaces a queued one: stale beeps must not trail behind.
        if node.isPlaying && pending > 0 { node.stop();pending=0 }
        pending += 1
        node.scheduleBuffer(buffer) { [weak self] in Task { @MainActor in self?.finished() } }
        node.play()
    }
    private func finished() {
        pending=max(0,pending-1)
        guard pending == 0 else { return }
        Task { @MainActor in try? await Task.sleep(for:.seconds(2));if pending == 0 && engine.isRunning { node.stop();engine.stop() } }
    }
}

/// Hazards only: sharp beeps, with vibration for high and critical (critical = three strong pulses and three beeps, one every
/// `criticalInterval` s; high = warning buzz and two beeps; normal = one short beep, no vibration).
/// Navigation never beeps or vibrates, so the user can tell the two apart before any words.
@MainActor enum AlertFeedback {
    static func hazard(_ priority:SpeechPriority) {
        let t=EarconPlayer.shared.tuning
        switch priority {
        case .critical where t.vibrateCritical:
            let heavy=UIImpactFeedbackGenerator(style:.heavy);heavy.prepare();heavy.impactOccurred(intensity:1)
            Task { @MainActor in for _ in 0..<max(0,t.criticalCount-1) { try? await Task.sleep(for:.seconds(t.criticalInterval));heavy.impactOccurred(intensity:1) } }
        case .high where t.vibrateHigh: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .normal where t.vibrateNormal: UIImpactFeedbackGenerator(style:.light).impactOccurred()
        case .low: return
        default: break
        }
        EarconPlayer.shared.play(.hazard(priority))
    }
}

struct HeadingSample { var degrees:Double;var accuracy:Double;var timestamp:Date;var simulated:Bool }

@MainActor final class LocationController: NSObject,ObservableObject,@preconcurrency CLLocationManagerDelegate {
    @Published var sample: LocationSample?
    @Published var heading: HeadingSample?
    @Published var status = "位置情報を開始していません"
    private let manager = CLLocationManager()
    private var simulationClock: Task<Void,Never>?
    private var lastAccuracyBucket = -1
    var simulated = false
    var authorization:String { switch manager.authorizationStatus { case .authorizedWhenInUse:return "使用中のみ許可";case .authorizedAlways:return "常に許可";case .denied:return "拒否";case .restricted:return "制限";default:return "未確認" } }
    var headingAvailable:Bool { CLLocationManager.headingAvailable() }
    override init() { super.init();manager.delegate=self;manager.desiredAccuracy=kCLLocationAccuracyBest;manager.distanceFilter=kCLDistanceFilterNone;manager.pausesLocationUpdatesAutomatically=false;manager.headingFilter=3;manager.headingOrientation = .portrait }
    func start() {
        guard !simulated else { return }
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization();debugLog(.permission,.request,"Location authorization requested",direction:.outgoing) }
        else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { status="位置情報が許可されていません";debugLog(.permission,.warning,"Location not authorized",["status":authorization]) }
        else {
            manager.startUpdatingLocation();if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
            status="位置を取得中";debugLog(.location,.start,"Location updates started",["heading":CLLocationManager.headingAvailable() ? "available":"unavailable"])
        }
    }
    func stop() {
        manager.stopUpdatingLocation();manager.stopUpdatingHeading();simulationClock?.cancel();simulationClock=nil
        sample=nil;heading=nil;status="位置情報を停止しました";lastAccuracyBucket = -1;debugLog(.location,.info,"Location updates stopped")
    }
    /// Simulated samples are re-stamped every second, like a stationary receiver, so continuity checks can pass.
    func useSimulation(_ coordinate: Coordinate,course:Double = -1,speed:Double = -1) {
        if !simulated { debugLog(.developer,.info,"Simulated location enabled") }
        simulated=true;manager.stopUpdatingLocation();manager.stopUpdatingHeading()
        sample=LocationSample(coordinate:coordinate,accuracy:3,timestamp:Date(),simulated:true,course:course,courseAccuracy:course>=0 ? 5:-1,speed:speed);status="模擬位置"
        if heading == nil || heading?.simulated == false { heading=HeadingSample(degrees:max(0,course),accuracy:5,timestamp:Date(),simulated:true) }
        if simulationClock == nil {
            simulationClock=Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for:.seconds(1))
                    guard let self else { return }
                    guard simulated,var s=sample else { continue }
                    s.timestamp=Date();sample=s
                }
            }
        }
    }
    func simulateHeading(_ degrees:Double) { guard simulated else { return };heading=HeadingSample(degrees:(degrees.truncatingRemainder(dividingBy:360)+360).truncatingRemainder(dividingBy:360),accuracy:5,timestamp:Date(),simulated:true) }
    func real() { simulated=false;simulationClock?.cancel();simulationClock=nil;sample=nil;heading=nil;debugLog(.developer,.info,"Simulated location disabled");start() }
    func locationManagerDidChangeAuthorization(_ manager:CLLocationManager) {
        debugLog(.permission,.response,"Location authorization changed",["status":authorization],direction:.incoming)
        if !simulated && manager.authorizationStatus != .notDetermined { start() }
    }
    func locationManager(_ manager:CLLocationManager,didUpdateLocations locations:[CLLocation]) {
        guard !simulated, let l=locations.last else { return }
        let first=sample == nil
        sample=LocationSample(coordinate:Coordinate(l.coordinate.latitude,l.coordinate.longitude),accuracy:l.horizontalAccuracy,timestamp:l.timestamp,course:l.course,courseAccuracy:l.courseAccuracy,speed:l.speed);status="実位置を受信"
        // Coordinates are deliberately not logged.
        let bucket=l.horizontalAccuracy<0 ? -2:l.horizontalAccuracy<=10 ? 0:l.horizontalAccuracy<=20 ? 1:2
        if first { debugLog(.location,.success,"First location fix",["accuracy":Int(l.horizontalAccuracy)]) }
        else if bucket != lastAccuracyBucket { debugLog(.location,bucket>=2 ? .warning:.info,"Location accuracy changed",["accuracy":Int(l.horizontalAccuracy),"band":["≤10m","≤20m",">20m"][max(0,min(2,bucket))]]) }
        else if DebugLogger.shared.verboseLocation { debugLog(.location,.debug,"Location sample",["accuracy":Int(l.horizontalAccuracy),"speed":String(format:"%.1f",l.speed),"course":Int(l.course),"courseAccuracy":Int(l.courseAccuracy),"ageMs":Int(-l.timestamp.timeIntervalSinceNow*1000)]) }
        lastAccuracyBucket=bucket
    }
    func locationManager(_ manager:CLLocationManager,didUpdateHeading newHeading:CLHeading) {
        guard !simulated else { return }
        let degrees=newHeading.trueHeading>=0 ? newHeading.trueHeading:newHeading.magneticHeading
        let firstOrDegraded=heading == nil || (newHeading.headingAccuracy<0) != ((heading?.accuracy ?? 0)<0)
        heading=HeadingSample(degrees:degrees,accuracy:newHeading.headingAccuracy,timestamp:newHeading.timestamp,simulated:false)
        if firstOrDegraded { debugLog(.location,newHeading.headingAccuracy<0 ? .warning:.info,"Heading state",["accuracy":Int(newHeading.headingAccuracy),"reference":newHeading.trueHeading>=0 ? "true":"magnetic"]) }
    }
    func locationManager(_ manager:CLLocationManager,didFailWithError error:Error) { sample=nil;status="位置を取得できません：\(error.localizedDescription)";debugLog(.location,.error,"Location error",["error":error.localizedDescription]) }
}
