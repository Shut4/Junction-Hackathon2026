import SwiftUI

/// DeveloperMode: simulated position/walk, fault injection and metric export. Never active outside DeveloperMode.
extension AppStore {
    func tapVersion() {
        let now=Date();if let lastTap,now.timeIntervalSince(lastTap)>3 { versionTaps=0 };self.lastTap=now;versionTaps += 1
        if versionTaps>=7 { developer=true;versionTaps=0;notice=localized("アプリ内DeveloperModeを有効にしました");debugLog(.developer,.success,"DeveloperMode enabled") }
    }
    func switchSimulation(_ enabled:Bool) {
        stopNavigation();camera.stop();speech.stop();simulationTask?.cancel();positionResolver.reset()
        if enabled,let network {
            let start=network.destinations.first.flatMap { d in network.edges.first { $0.from == d.nodeID || $0.to == d.nodeID } } ?? network.edges.first
            if let e=start { location.useSimulation(Geometry.point(along:e.shape,at:Geometry.length(e.shape)/2).coordinate) }
        }
        else { location.real() }
        retryRead()
    }
    func simulateAtEdge(_ edge:WalkEdge) {
        stopNavigation();positionResolver.reset()
        location.useSimulation(Geometry.point(along:edge.shape,at:Geometry.length(edge.shape)/2).coordinate);retryRead()
        debugLog(.developer,.info,"Simulated position moved to edge",["edge":edge.id])
    }
    func moveSimulation(to coordinate:Coordinate) { guard developer,simulated else { return };location.useSimulation(coordinate) }
    /// Walks the simulated position along the current route. Real GPS is never replaced outside DeveloperMode.
    func startSimulatedWalk() {
        guard developer,simulated,let route else { notice=localized("模擬位置を有効にし、経路を確認してから開始してください");return }
        let shape=RouteTracker.shape(of:route),total=Geometry.length(shape)
        walkTask?.cancel();simulatedWalkActive=true
        debugLog(.developer,.start,"Simulated walk started",["distanceM":Int(total),"speed":simulatedWalkSpeed])
        walkTask=Task { [weak self] in
            var travelled=0.0
            while !Task.isCancelled {
                guard let self else { return }
                let p=Geometry.point(along:shape,at:min(travelled,total))
                location.useSimulation(p.coordinate,course:p.bearing,speed:travelled<total ? simulatedWalkSpeed:0);location.simulateHeading(p.bearing)
                if travelled>=total { break }
                try? await Task.sleep(for:.milliseconds(500));travelled += simulatedWalkSpeed*0.5
            }
            self?.simulatedWalkActive=false
        }
    }
    func stopSimulatedWalk() { if walkTask != nil { walkTask?.cancel();walkTask=nil;simulatedWalkActive=false;debugLog(.developer,.cancelled,"Simulated walk stopped") } }
    func simulateNotice() {
        simulationTask?.cancel();simulationFilter.reset()
        simulationFilter.confidence=camera.filter.confidence;simulationFilter.persistence=camera.filter.persistence;simulationFilter.cooldown=camera.filter.cooldown
        debugLog(.developer,.start,"Simulated pole detection")
        simulationTask=Task { [weak self] in guard let self else { return };let box=Box(x:0.4,y:0.3,width:0.2,height:0.5);let t=ProcessInfo.processInfo.systemUptime
            let simulatedDetection=Detection(label:"pole",confidence:0.9,box:box,capturedAt:t,simulated:true)
            camera.showSimulated([simulatedDetection])
            _=simulationFilter.process([simulatedDetection],now:t)
            try? await Task.sleep(for:.milliseconds(700));guard !Task.isCancelled,developer else { return };let now=ProcessInfo.processInfo.systemUptime
            let notices=simulationFilter.process([Detection(label:"pole",confidence:0.9,box:box,capturedAt:now,simulated:true)],now:now)
            simulatedNoticeCount=simulationFilter.notices
            notices.forEach { record(MetricEvent(kind:"notice",frame:$0.capturedAt,decision:now,simulated:true));speech.say(localized("模擬検出。")+$0.text,obstacle:true,capturedAt:$0.capturedAt) }
        }
    }
    func closeDeveloper() {
        simulationTask?.cancel();simulationTask=nil;simulationFilter.reset();stopSimulatedWalk();camera.stop();camera.injectError=false;camera.filter.reset();speech.stop()
        persistence.failRead=false;persistence.failWrite=false;simulatedPersistence.failRead=false;simulatedPersistence.failWrite=false
        if simulated { switchSimulation(false) };developer=false;debugLog(.developer,.info,"DeveloperMode closed")
    }
    func failSave(_ enabled:Bool) { activeStore.failWrite=enabled;debugLog(.developer,.warning,"Save failure injection \(enabled ? "on":"off")") }
    func failRead(_ enabled:Bool) { activeStore.failRead=enabled;debugLog(.developer,.warning,"Read failure injection \(enabled ? "on":"off")");retryRead() }
    func closeAll() {
        guard developer,simulated,let network else { notice=localized("全閉鎖は模擬領域でのみ実行できます");return }
        let all=network.edges.map { Report(segmentID:$0.id,hazard:.other,observedAt:Date(),explanation:"DeveloperMode全閉鎖") }
        do { try simulatedPersistence.save(all,network:network);reports=all;debugLog(.developer,.warning,"All simulated segments closed",["count":all.count]);if navigating { reroute(blockage:true) } else { calculate(usePosition:false) } } catch { storageError=error.localizedDescription }
    }
    func resetSimulation() { guard let network else { return };do { try simulatedPersistence.save([],network:network);if simulated { reports=[];storageError=nil;stopNavigation() };simulationTask?.cancel();simulationFilter=NoticeFilter();simulatedNoticeCount=0;debugLog(.developer,.info,"Simulation data reset") } catch { notice=error.localizedDescription } }
    func exportLog() -> URL? {
        let value="アプリ 0.4 / \(UIDevice.current.model) / iOS \(UIDevice.current.systemVersion)\n実・模擬: \(simulated ? "模擬":"実")\n道路版: \(network?.version ?? "なし")\n経路版: \(routeVersion) 再検索: \(reroutes)\n推論回数: \(camera.inferenceCount) 通知: \(camera.notificationCount) 抑制: \(camera.suppressionCount)\nフレーム: \(camera.frameTime) 推論開始: \(camera.inferenceStart) 終了: \(camera.inferenceEnd) 通知決定: \(camera.decisionTime)\n推論秒: \(camera.inferenceLatency) 通知決定秒: \(camera.decisionLatency) 発話開始コールバック秒: \(speech.lastStartLatency.map(String.init(describing:)) ?? "未計測")\n熱状態: \(ProcessInfo.processInfo.thermalState.rawValue)\n画像・位置履歴・軌跡は含みません\n"
        let url=URL.temporaryDirectory.appending(path:"JunctionGuide-log.txt")
        do { let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys];let lines=try metrics.map { String(decoding:try encoder.encode($0),as:UTF8.self) }.joined(separator:"\n");try Data((value+"\n保持イベント上限2000・破棄数 \(droppedMetrics)\n"+lines).utf8).write(to:url,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication]);return url } catch { notice=error.localizedDescription;return nil }
    }
}
