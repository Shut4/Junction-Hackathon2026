import SwiftUI
import Combine
import CoreBluetooth
import UIKit

enum CaneConnectionState: Equatable {
    case idle, preparing, searching, connecting, checking, connected, failed
    var title:String {
        switch self {
        case .idle: "未接続"
        case .preparing: "Bluetoothを準備中"
        case .searching: "白杖を検索中"
        case .connecting: "接続中"
        case .checking: "通信を確認中"
        case .connected: "接続済み"
        case .failed: "接続できていません"
        }
    }
    var busy:Bool { [.preparing,.searching,.connecting,.checking].contains(self) }
    var symbol:String {
        switch self {
        case .connected: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        case .idle: "antenna.radiowaves.left.and.right.slash"
        default: "antenna.radiowaves.left.and.right"
        }
    }
    var color:Color {
        switch self { case .connected: .green;case .failed: .orange;case .idle: .secondary;default: .blue }
    }
}

struct CaneConnectionNotice:Identifiable {
    let id=UUID()
    let state:CaneConnectionState
    let title:String
    let detail:String
}

/// Main-queue CoreBluetooth central. No background drive; the firmware must also enforce TTL.
@MainActor final class CaneBluetooth: NSObject, ObservableObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    static let service=CBUUID(string:"77D6F146-E62C-4ED3-BAAA-6C1526D79D28")
    static let commandID=CBUUID(string:"BC6B696D-E8D3-4566-9730-EA6B057EE324")
    static let statusID=CBUUID(string:"D9B72442-A4CC-4E98-9352-CED78C12B22F")
    @Published private(set) var message="白杖を接続すると、障害物の注意・危険を振動で知らせます。"
    @Published private(set) var connectionState:CaneConnectionState = .idle
    @Published private(set) var deviceName:String?
    @Published private(set) var connectionNotice:CaneConnectionNotice?
    private var noticeTask:Task<Void,Never>?
    var onConnectionNotice:((String)->Void)?
    func dismissNotice() { noticeTask?.cancel();noticeTask=nil;connectionNotice=nil }
    private func showNotice(state:CaneConnectionState,title:String,detail:String) {
        dismissNotice()
        let notice=CaneConnectionNotice(state:state,title:title,detail:detail)
        connectionNotice=notice
        noticeTask=Task { [weak self] in
            do { try await Task.sleep(for:.seconds(5)) } catch { return }
            guard let self,connectionNotice?.id == notice.id else { return }
            connectionNotice=nil;noticeTask=nil
        }
    }
    var isConnected:Bool { connectionState == .connected }
    private func transition(to next:CaneConnectionState) {
        guard connectionState != next else { return }
        connectionState=next
        guard UIApplication.shared.applicationState == .active else { return }
        if next == .connected {
            showNotice(state:.connected,title:"白杖に接続しました",detail:deviceName ?? "XIAO")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onConnectionNotice?(localized("白杖に接続しました。機器からの応答を確認しました。"))
        } else if next == .failed {
            showNotice(state:.failed,title:"白杖を接続できていません",detail:message)
            onConnectionNotice?(localized(message))
        }
    }
    @Published private(set) var devices:[CBPeripheral]=[]
    @Published private(set) var ready=false
    @Published private(set) var active=false
    @Published private(set) var received:CaneStatus?
    @Published private(set) var lastReceived:Date?
    var source:(()->CaneCommand)?
    private var central:CBCentralManager?
    private var peripheral:CBPeripheral?
    private var command:CBCharacteristic?
    private var status:CBCharacteristic?
    private var timer:AnyCancellable?
    private var sequence:UInt16=0
    private var writingSince:Double?
    private var phaseStarted=0.0
    private var lastStatusTime=0.0
    private var manual:(CaneCommand,Double)?

    func scan() {
        disconnect(announce:false);active=true;devices=[];message="白杖の電源を入れ、iPhoneの近くに置いてください。";transition(to:.preparing)
        if central == nil { central=CBCentralManager(delegate:self,queue:.main) } else { beginScan() }
    }
    private func beginScan() {
        guard active,let central else { return }
        guard central.state == .poweredOn else { updatePower();return }
        message="見つかった白杖を選んで接続してください。";transition(to:.searching);phaseStarted=ProcessInfo.processInfo.systemUptime
        central.scanForPeripherals(withServices:[Self.service]);startTimer()
    }
    func connect(_ device:CBPeripheral) {
        guard active,connectionState == .searching,central?.state == .poweredOn,peripheral == nil else { return }
        central?.stopScan();peripheral=device;device.delegate=self;deviceName=device.name ?? "XIAO";message="白杖に接続しています。そのままお待ちください。";transition(to:.connecting)
        phaseStarted=ProcessInfo.processInfo.systemUptime;central?.connect(device)
    }
    func disconnect(announce:Bool = true) {
        let wasConnected=isConnected
        dismissNotice()
        active=false;central?.stopScan();timer?.cancel();timer=nil
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral=nil;command=nil;status=nil;ready=false;writingSince=nil;manual=nil;received=nil;lastReceived=nil;deviceName=nil;message="白杖を接続すると、障害物の注意・危険を振動で知らせます。"
        transition(to:.idle)
        if announce,wasConnected,UIApplication.shared.applicationState == .active {
            showNotice(state:.idle,title:"白杖の接続を解除しました",detail:"再接続は設定画面から行えます。")
            onConnectionNotice?(localized("白杖の接続を解除しました。"))
        }
    }
    func test(_ state:CaneState) {
        guard isConnected else { return }
        manual=(CaneCommand(state:state,manual:true),ProcessInfo.processInfo.systemUptime+1)
        sendLatest()
    }
    func invalidateDetection() { manual=nil;sendLatest(forceUnavailable:true) }
    private func fail(_ text:String) {
        let wasConnected=isConnected
        disconnect(announce:false)
        message=wasConnected ? localized("白杖との接続が切れました。{0}",localized(text)):text
        transition(to:.failed)
    }
    private func startTimer() {
        timer?.cancel()
        timer=Timer.publish(every:0.25,on:.main,in:.common).autoconnect().sink { [weak self] _ in self?.tick() }
    }
    private func tick() {
        let now=ProcessInfo.processInfo.systemUptime
        if !ready {
            if now-phaseStarted > 15 { fail("検索・接続がタイムアウトしました。再検索してください") }
            return
        }
        if let start=writingSince,now-start > 2 { fail("送信応答がありません。再接続してください");return }
        if now-lastStatusTime > 3 { fail("XIAOの状態通知が途絶えました。再接続してください");return }
        sendLatest()
    }
    /// While a write is in flight, no packet queue is created. The next send samples current input.
    func sendLatest(forceUnavailable:Bool = false) {
        guard ready,writingSince == nil,let peripheral,let command else { return }
        let now=ProcessInfo.processInfo.systemUptime
        let value:CaneCommand
        if forceUnavailable { value=CaneCommand() }
        else if let (test,until)=manual,now < until { value=test }
        else if manual != nil { manual=nil;value=CaneCommand() }
        else { value=source?() ?? CaneCommand() }
        let data=value.data(sequence:sequence);sequence &+= 1;writingSince=now
        peripheral.writeValue(data,for:command,type:.withResponse)
    }
    private func updatePower() {
        guard let central else { return }
        switch central.state {
        case .poweredOn: break
        case .poweredOff: fail("Bluetoothがオフです")
        case .unauthorized: fail("Bluetoothが許可されていません。iOSの設定を確認してください")
        case .unsupported: fail("この端末はBLEに対応していません")
        default: message="Bluetoothの準備中"
        }
    }
    func centralManagerDidUpdateState(_ central:CBCentralManager) {
        if central.state == .poweredOn,active,peripheral == nil { beginScan() } else { updatePower() }
    }
    func centralManager(_ central:CBCentralManager,didDiscover peripheral:CBPeripheral,advertisementData:[String:Any],rssi RSSI:NSNumber) {
        guard active,self.peripheral == nil else { return }
        if !devices.contains(where:{$0.identifier == peripheral.identifier}) { devices.append(peripheral) }
    }
    func centralManager(_ central:CBCentralManager,didConnect peripheral:CBPeripheral) {
        guard self.peripheral === peripheral,active else { central.cancelPeripheralConnection(peripheral);return }
        message="白杖からの応答を確認しています。";transition(to:.checking);peripheral.discoverServices([Self.service])
    }
    func centralManager(_ central:CBCentralManager,didFailToConnect peripheral:CBPeripheral,error:Error?) {
        guard self.peripheral === peripheral else { return };fail("XIAOに接続できませんでした")
    }
    func centralManager(_ central:CBCentralManager,didDisconnectPeripheral peripheral:CBPeripheral,error:Error?) {
        guard self.peripheral === peripheral else { return };fail("XIAOとの接続が切れました。再検索してください")
    }
    func peripheral(_ peripheral:CBPeripheral,didDiscoverServices error:Error?) {
        guard self.peripheral === peripheral else { return }
        guard error == nil,let service=peripheral.services?.first(where:{$0.uuid == Self.service}) else { fail("対応するBLEサービスがありません");return }
        peripheral.discoverCharacteristics([Self.commandID,Self.statusID],for:service)
    }
    func peripheral(_ peripheral:CBPeripheral,didDiscoverCharacteristicsFor service:CBService,error:Error?) {
        guard self.peripheral === peripheral else { return }
        guard error == nil,let c=service.characteristics?.first(where:{$0.uuid == Self.commandID}),c.properties.contains(.write),
              let s=service.characteristics?.first(where:{$0.uuid == Self.statusID}),s.properties.contains(.read),s.properties.contains(.notify) else { fail("BLEの通信仕様が一致しません");return }
        command=c;status=s;peripheral.setNotifyValue(true,for:s)
    }
    func peripheral(_ peripheral:CBPeripheral,didUpdateNotificationStateFor characteristic:CBCharacteristic,error:Error?) {
        guard self.peripheral === peripheral,characteristic === status else { return }
        guard error == nil,characteristic.isNotifying else { fail("状態通知を有効にできません");return }
        sequence=0;ready=true;lastStatusTime=ProcessInfo.processInfo.systemUptime;message="白杖からの応答を確認しています。"
        sendLatest(forceUnavailable:true);peripheral.readValue(for:characteristic)
    }
    func peripheral(_ peripheral:CBPeripheral,didUpdateValueFor characteristic:CBCharacteristic,error:Error?) {
        guard self.peripheral === peripheral,characteristic === status else { return }
        guard error == nil,let data=characteristic.value,let value=CaneStatus(data:data) else { fail("XIAOから不正な状態データを受信しました");return }
        received=value;lastReceived=Date();lastStatusTime=ProcessInfo.processInfo.systemUptime
        message="機器からの応答を受信しました。振動テストで動作を確認できます。"
        transition(to:.connected)
    }
    func peripheral(_ peripheral:CBPeripheral,didWriteValueFor characteristic:CBCharacteristic,error:Error?) {
        guard self.peripheral === peripheral,characteristic === command else { return }
        writingSince=nil
        if error != nil { fail("XIAOへの送信に失敗しました") }
    }
    func peripheral(_ peripheral:CBPeripheral,didModifyServices invalidatedServices:[CBService]) {
        guard self.peripheral === peripheral else { return };fail("XIAOのサービスが変更されました。再接続してください")
    }
}

/// Visible only for five seconds after a connection event; no persistent map/camera badge.
struct CaneConnectionToast:View {
    @ObservedObject var bluetooth:CaneBluetooth
    var body:some View {
        if let notice=bluetooth.connectionNotice {
            HStack(alignment:.top,spacing:12) {
                Image(systemName:notice.state.symbol).font(.title2).foregroundStyle(notice.state.color).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:4) {
                    Text(localized(notice.title)).font(.headline)
                    Text(localized(notice.detail)).font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,alignment:.leading).accessibilityElement(children:.combine)
                Button("閉じる",systemImage:"xmark") { bluetooth.dismissNotice() }
                    .labelStyle(.iconOnly).frame(minWidth:44,minHeight:44).accessibilityIdentifier("dismissCaneNotice")
            }
            .padding(12).background(.regularMaterial,in:RoundedRectangle(cornerRadius:18))
            .overlay(RoundedRectangle(cornerRadius:18).stroke(notice.state.color.opacity(0.5),lineWidth:1))
            .shadow(color:.black.opacity(0.15),radius:8,y:4)
            .padding(.horizontal,12).padding(.top,8)
            .accessibilityIdentifier("caneConnectionNotice")
        }
    }
}

struct CaneBluetoothSection:View {
    @ObservedObject var bluetooth:CaneBluetooth
    var showDiagnostics=false
    var body:some View {
        Section("白杖 Bluetooth") {
            VStack(alignment:.leading,spacing:12) {
                HStack(alignment:.top,spacing:12) {
                    Image(systemName:bluetooth.connectionState.symbol)
                        .font(.system(size:32,weight:.semibold)).foregroundStyle(bluetooth.connectionState.color).accessibilityHidden(true)
                    VStack(alignment:.leading,spacing:4) {
                        Text(localized(bluetooth.connectionState.title)).font(.title2.bold()).accessibilityIdentifier("caneConnectionStatus")
                        if let name=bluetooth.deviceName { Text(name).font(.headline).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength:0)
                    if bluetooth.connectionState.busy { ProgressView().accessibilityLabel("接続処理中") }
                }
                Text(localized(bluetooth.message)).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                if bluetooth.isConnected {
                    Label("白杖からの応答を受信済み",systemImage:"checkmark.shield.fill").font(.subheadline.bold()).foregroundStyle(.green)
                }
            }.padding(.vertical,8)
            if bluetooth.active {
                Button(localized(bluetooth.isConnected ? "白杖の接続を解除":"検索・接続をキャンセル"),role:.destructive) { bluetooth.disconnect() }
                    .frame(minHeight:44).accessibilityIdentifier("disconnectCane")
            } else {
                Button { bluetooth.scan() } label: {
                    Label(localized(bluetooth.connectionState == .failed ? "もう一度白杖を検索":"白杖を検索して接続"),systemImage:"antenna.radiowaves.left.and.right")
                        .font(.headline).frame(maxWidth:.infinity,minHeight:44)
                }.buttonStyle(.borderedProminent).accessibilityIdentifier("scanCane")
                if bluetooth.connectionState == .failed {
                    Button("iOSのBluetooth権限設定を開く",systemImage:"gearshape") { openAppSettings() }.frame(minHeight:44)
                }
            }
            if bluetooth.connectionState == .searching {
                if bluetooth.devices.isEmpty {
                    Label("白杖を探しています。電源と距離を確認してください。",systemImage:"magnifyingglass").foregroundStyle(.secondary)
                }
                ForEach(bluetooth.devices,id:\.identifier) { device in
                    Button { bluetooth.connect(device) } label: {
                        HStack(spacing:12) {
                            Image(systemName:"antenna.radiowaves.left.and.right").font(.title2)
                            VStack(alignment:.leading,spacing:4) {
                                Text(device.name ?? "XIAO").font(.headline)
                                Text(localized("機器ID：{0}",String(device.identifier.uuidString.prefix(8)))).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength:0)
                            Text("接続").font(.headline)
                        }.frame(minHeight:52)
                    }.accessibilityIdentifier("connectCane."+device.identifier.uuidString)
                }
            }
        }
        if bluetooth.isConnected {
            Section("振動を確認") {
                Text("白杖を手に持ち、注意と危険のリズムを確認してください。").font(.subheadline)
                Button { bluetooth.test(.caution) } label: { Label("注意の振動を試す（単発）",systemImage:"waveform.path") }.frame(minHeight:44)
                Button { bluetooth.test(.danger) } label: { Label("危険の振動を試す（3連続）",systemImage:"waveform") }.frame(minHeight:44)
                Button("テストを終了",systemImage:"stop.circle") { bluetooth.test(.unavailable) }.frame(minHeight:44)
                Text("各テストは1秒で終了し、自動送信へ戻ります。実際に振動したかは白杖で確認してください。").font(.caption).foregroundStyle(.secondary)
            }
            if let value=bluetooth.received,value.errors != 0 {
                Section("白杖の状態") {
                    Label(localized(value.errors & 1 != 0 ? "白杖側で通信の期限切れを検出しました。振動テストで応答を確認してください。":"白杖側で指示の受信エラーを検出しました。"),systemImage:"exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
        }
        if showDiagnostics,let value=bluetooth.received {
            Section("通信の詳細・DeveloperMode") {
                Text("XIAO受信状態：\(value.state.title) / sequence \(value.sequence)")
                Text("TTL切れ：\(value.errors & 1 != 0 ? "あり":"なし")・不正パケット：\(value.errors & 2 != 0 ? "あり":"なし")")
                if let date=bluetooth.lastReceived { Text("最終受信：\(date.formatted(date:.omitted,time:.standard))") }
            }
        }
        Section {
            Text("頭の高さの障害物を検知できるカメラ案内中に、注意・危険を白杖へ送ります。接続済みでも、検知不能時は振動を停止します。背景移行時は接続を解除します。").font(.caption).foregroundStyle(.secondary)
        }
    }
}
