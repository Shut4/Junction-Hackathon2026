import SwiftUI

/// Road selection, blocked-segment reports and explicit report migration.
extension AppStore {
    func edgeDescription(_ edge: WalkEdge) -> String { "\(edge.name)、\(name(edge.from))から\(name(edge.to))、\(Int(edge.distance.rounded()))メートル、\(blocked.contains(edge.id) ? "通行不可登録あり":"報告なし・安全未確認")" }
    func toggle(_ id: String) { if selected.contains(id) { selected.remove(id) } else { selected.insert(id) };roadCandidates=[];ambiguity=false;selectionMessage="区間全体が登録・除外の対象です" }
    func clearSelection() { selected.removeAll();roadCandidates.removeAll();ambiguity=false;selectionMessage="選択を解除しました" }
    func tapRoad(_ coordinate:Coordinate,radius:Double) -> Report? {
        guard let network else { return nil }
        let result=RoadMatcher(network:network).tap(coordinate,radius:radius)
        roadCandidates=result.candidates;ambiguity=result.ambiguous;selectionMessage=result.message
        debugLog(.map,result.edgeID == nil && !result.ambiguous ? .warning:.info,"Road tap",["radiusM":Int(radius),"selected":result.edgeID,"candidates":result.candidates.count,"ambiguous":result.ambiguous])
        guard let id=result.edgeID else { return nil }
        if let report=reports.first(where: { $0.segmentID == id }) {
            selectionMessage="登録済みの通行禁止区域です。削除する場合は確認してください。"
            return report
        }
        confirmTappedRoad(id)
        return nil
    }
    func confirmTappedRoad(_ id:String) {
        guard let network,edge(id) != nil else { return }
        let next=selected.symmetricDifference([id])
        guard next.isEmpty || RoadMatcher(network:network).connected(next) else { selectionMessage="離れた道路は同時に選択できません。選択を解除してから選び直してください。";return }
        selected=next;ambiguity=false;roadCandidates=[];selectionMessage="選択 \(selected.count)区間。道路区間全体を登録・除外します。再タップで選択解除できます。"
    }
    func confirmRoadCandidate(_ id:String) {
        confirmTappedRoad(id)
    }
    func register(hazard:Hazard,date:Date,text:String) -> Bool {
        guard let network,!selected.isEmpty,!ambiguity,storageError == nil else { notice="対象・候補・保存状態を確認してください";return false }
        guard RoadMatcher(network:network).connected(selected) else { notice=CoreError.disconnectedSelection.localizedDescription;return false }
        let additions=selected.sorted().map { Report(segmentID:$0,hazard:hazard,observedAt:date,explanation:text.isEmpty ? nil:String(text.prefix(120))) }
        let all=reports+additions
        do {
            try activeStore.save(all,network:network)
            reports=all
            debugLog(.report,.success,"Blocked segments saved",["segments":additions.count,"hazard":hazard.rawValue,"total":all.count,"simulated":simulated])
            clearSelection();notice="通行不可を保存しました"
            refreshRequestedRoute()
            return true
        } catch { storageError="保存失敗：\(error.localizedDescription)";debugLog(.storage,.error,"Report save failed",["error":error.localizedDescription]);stopNavigation();notice=storageError;return false }
    }
    func retryRead() {
        guard let network else { return }
        loadReports(from:activeStore,network:network)
        if storageError == nil { notice="報告を読み込みました";refreshRequestedRoute() } else { stopNavigation() }
    }
    func remove(_ id:UUID) {
        guard let network,storageError == nil else { return }
        do { let next=reports.filter { $0.id != id };try activeStore.save(next,network:network);reports=next;debugLog(.report,.info,"Report removed",["remaining":next.count]);refreshRequestedRoute() }
        catch { storageError=error.localizedDescription;debugLog(.storage,.error,"Report removal failed",["error":error.localizedDescription]);stopNavigation() }
    }
    func removeReports(for segmentID:String) {
        guard let network,storageError == nil else { return }
        do {
            let removed=reports.filter { $0.segmentID == segmentID }.count
            let next=reports.filter { $0.segmentID != segmentID }
            try activeStore.save(next,network:network)
            reports=next;selected.remove(segmentID)
            selectionMessage="通行禁止区域を削除しました"
            notice=selectionMessage
            debugLog(.report,.info,"Blocked segment removed",["segment":segmentID,"reports":removed,"remaining":next.count])
            refreshRequestedRoute()
        } catch { storageError=error.localizedDescription;debugLog(.storage,.error,"Blocked segment removal failed",["error":error.localizedDescription]);stopNavigation() }
    }
    func migrationPreview()->(kept:Int,dropped:Int)? {
        guard let network,let preview=try? activeStore.migrationPreview(network:network) else { return nil }
        return (preview.kept.count,preview.dropped.count)
    }
    /// User-confirmed: keeps reports whose segment ID still exists after the road data update. The old file is kept as a backup.
    func migrateReports() {
        guard let network else { return }
        do {
            let preview=try activeStore.migrationPreview(network:network)
            let backup=try activeStore.archive(label:"before-migration")
            try activeStore.save(preview.kept,network:network)
            reports=preview.kept;storageError=nil;storageIncompatible=false
            notice="同じ区間IDの報告\(preview.kept.count)件を引き継ぎました。対応しない\(preview.dropped.count)件は退避ファイルに残っています。"
            debugLog(.storage,.success,"Reports migrated",["kept":preview.kept.count,"dropped":preview.dropped.count,"backup":backup?.lastPathComponent])
            refreshRequestedRoute()
        } catch { notice="引き継げませんでした：\(error.localizedDescription)";debugLog(.storage,.error,"Report migration failed",["error":error.localizedDescription]) }
    }
    func archiveReports() {
        do { let backup=try activeStore.archive(label:"archived");reports=[];storageError=nil;storageIncompatible=false;notice="旧報告を退避しました（削除していません）";debugLog(.storage,.success,"Reports archived",["backup":backup?.lastPathComponent]);refreshRequestedRoute() }
        catch { notice="退避できませんでした：\(error.localizedDescription)";debugLog(.storage,.error,"Report archive failed",["error":error.localizedDescription]) }
    }
}
