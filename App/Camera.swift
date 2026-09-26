import SwiftUI
@preconcurrency import AVFoundation
@preconcurrency import Vision
import CoreML
import Darwin

final class CaptureEngine: NSObject,AVCaptureVideoDataOutputSampleBufferDelegate,@unchecked Sendable {
    let session = AVCaptureSession()
    let queue = DispatchQueue(label:"guide.camera")
    var result: (@Sendable ([Detection],Double,Double,Double,String?) -> Void)?
    private var request: VNCoreMLRequest?
    private var configured=false
    private var lastFrame=0.0
    func start() {
        queue.async { [self] in
            do {
                if !configured {
                    session.beginConfiguration();defer { session.commitConfiguration() }
                    session.sessionPreset = .vga640x480
                    guard let device=AVCaptureDevice.default(.builtInWideAngleCamera,for:.video,position:.back) else { throw CameraError.noCamera }
                    let input=try AVCaptureDeviceInput(device:device)
                    guard session.canAddInput(input) else { throw CameraError.noCamera };session.addInput(input)
                    let output=AVCaptureVideoDataOutput();output.alwaysDiscardsLateVideoFrames=true;output.setSampleBufferDelegate(self,queue:queue)
                    guard session.canAddOutput(output) else { throw CameraError.noCamera };session.addOutput(output);configured=true
                }
                if request == nil, let url=Bundle.main.url(forResource:"vidvipo_yolov8n_2023-05-19",withExtension:"mlmodelc") {
                    let model=try MLModel(contentsOf:url);request=VNCoreMLRequest(model:try VNCoreMLModel(for:model));request?.imageCropAndScaleOption = .scaleFit
                }
                session.startRunning()
            } catch { result?([],0,0,0,error.localizedDescription) }
        }
    }
    func stop() { queue.async { [self] in session.stopRunning() } }
    func captureOutput(_ output:AVCaptureOutput,didOutput sampleBuffer:CMSampleBuffer,from connection:AVCaptureConnection) {
        let now=ProcessInfo.processInfo.systemUptime
        guard now-lastFrame >= 0.15 else { return };lastFrame=now
        guard let request,let pixel=CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp=CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        let captured=timestamp.isFinite && timestamp>0 ? timestamp:now
        let start=ProcessInfo.processInfo.systemUptime
        do {
            // Body mount is portrait, rear lens. Actual orientation/framing needs device evaluation.
            try VNImageRequestHandler(cvPixelBuffer:pixel,orientation:.right).perform([request])
            let finish=ProcessInfo.processInfo.systemUptime
            guard let objects=request.results as? [VNRecognizedObjectObservation] else { result?([],captured,start,finish,"モデルの出力形式に対応できません");return }
            let detections=objects.compactMap { object -> Detection? in
                guard let label=object.labels.first else { return nil }
                let b=object.boundingBox
                return Detection(label:label.identifier,confidence:Double(label.confidence),box:Box(x:b.minX,y:b.minY,width:b.width,height:b.height),capturedAt:captured)
            }
            result?(detections,captured,start,finish,nil)
        } catch { result?([],captured,start,ProcessInfo.processInfo.systemUptime,error.localizedDescription) }
    }
    enum CameraError: LocalizedError { case noCamera;var errorDescription:String? { "背面カメラを使用できません" } }
}
@MainActor final class CameraController: ObservableObject {
    let engine=CaptureEngine()
    @Published var running=false
    @Published var status="カメラ停止中"
    @Published var modelStatus="未導入"
    @Published var labels="検出候補なし"
    @Published var inferenceCount=0
    @Published var inferenceLatency=0.0
    @Published var decisionLatency=0.0
    @Published var notificationCount=0
    @Published var suppressionCount=0
    @Published var frameTime=0.0
    @Published var inferenceStart=0.0
    @Published var inferenceEnd=0.0
    @Published var decisionTime=0.0
    @Published var detections:[Detection]=[]
    @Published var memoryBytes:UInt64=0
    @Published var framesPerSecond=0.0
    @Published var simulatedDetections=false
    private var lastCaptured=0.0
    var filter=NoticeFilter()
    var injectError=false
    var onNotice: ((DetectionNotice)->Void)?
    var onMetric: ((MetricEvent)->Void)?
    private var sessionGeneration=0
    init() {
        UIDevice.current.isBatteryMonitoringEnabled=true
        if Bundle.main.url(forResource:"vidvipo_yolov8n_2023-05-19",withExtension:"mlmodelc") != nil { modelStatus="導入済み・動作確認待ち" }
        Task { @MainActor [modelStatus] in debugLog(.model,modelStatus == "未導入" ? .warning:.info,"Model bundle check",["model":"vidvipo_yolov8n_2023-05-19","status":modelStatus]) }
        engine.result = { [weak self] detections,captured,start,end,error in
            Task { @MainActor in self?.receive(detections,captured:captured,start:start,end:end,error:error) }
        }
    }
    func start() {
        sessionGeneration += 1;let generation=sessionGeneration
        Task {
            let granted:Bool
            if AVCaptureDevice.authorizationStatus(for:.video) == .notDetermined { granted=await AVCaptureDevice.requestAccess(for:.video) }
            else { granted=AVCaptureDevice.authorizationStatus(for:.video) == .authorized }
            guard generation==sessionGeneration else { return }
            guard granted else { status="カメラが許可されていません";debugLog(.permission,.warning,"Camera not authorized");return }
            running=true;simulatedDetections=false;detections=[];lastCaptured=0;status=modelStatus == "未導入" ? "カメラ映像のみ・認識モデル未導入":"カメラ起動中";engine.start()
            debugLog(.camera,.start,"Camera session started",["model":modelStatus,"confidence":String(format:"%.2f",filter.confidence)])
        }
    }
    func stop() {
        if running { debugLog(.camera,.info,"Camera session stopped",["inferences":inferenceCount,"notices":notificationCount]) }
        sessionGeneration += 1;running=false;engine.stop();filter.reset();status="カメラ停止中";labels="検出候補なし";detections=[];framesPerSecond=0
    }
    /// DeveloperMode preview of the box overlay without camera frames. Never passed to the notice filter.
    func showSimulated(_ items:[Detection]) { guard !running else { return };simulatedDetections=true;detections=items }
    private func receive(_ detections:[Detection],captured:Double,start:Double,end:Double,error:String?) {
        guard running else { return }
        if let error=error ?? (injectError ? "模擬認識エラー":nil) { status="認識エラー：\(error)";debugLog(.model,.error,"Inference error",["error":error,"injected":injectError]);stopAfterError();return }
        if inferenceCount == 0 { debugLog(.model,.success,"First inference completed",["ms":Int((end-start)*1000),"objects":detections.count]) }
        if lastCaptured>0,captured>lastCaptured { let fps=1/(captured-lastCaptured);framesPerSecond=framesPerSecond == 0 ? fps:framesPerSecond*0.8+fps*0.2 };lastCaptured=captured
        frameTime=captured;inferenceStart=start;inferenceEnd=end;inferenceCount += 1;inferenceLatency=end-start
        status="端末内で認識中";modelStatus="認識処理実行中"
        self.detections=detections
        labels=Array(Set(detections.prefix(5).map { DetectionLabels.japanese[$0.label] ?? $0.label })).sorted().joined(separator:"、")
        if labels.isEmpty { labels="検出候補なし" }
        decisionTime=ProcessInfo.processInfo.systemUptime;decisionLatency=decisionTime-captured
        onMetric?(MetricEvent(kind:"inference",frame:captured,inferenceStart:start,inferenceEnd:end,decision:decisionTime))
        let notices=filter.process(detections,now:decisionTime)
        notificationCount=filter.notices;suppressionCount=filter.suppressed
        if inferenceCount == 1 || inferenceCount.isMultiple(of:30) {
            var info=task_vm_info_data_t();var size=mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size/MemoryLayout<integer_t>.size)
            let result=withUnsafeMutablePointer(to:&info) { pointer in pointer.withMemoryRebound(to:integer_t.self,capacity:Int(size)) { task_info(mach_task_self_,task_flavor_t(TASK_VM_INFO),$0,&size) } }
            if result == KERN_SUCCESS { memoryBytes=info.phys_footprint }
            #if DEBUG
            print("GUIDE_INFERENCE count=\(inferenceCount) duration_ms=\(Int(inferenceLatency*1000)) objects=\(detections.count) notices=\(notificationCount) suppressed=\(suppressionCount) memory_bytes=\(memoryBytes) thermal=\(ProcessInfo.processInfo.thermalState.rawValue) battery=\(UIDevice.current.batteryLevel)")
            #endif
        }
        if DebugLogger.shared.verboseInference || inferenceCount.isMultiple(of:30) { debugLog(.model,.debug,"Inference",["count":inferenceCount,"ms":Int(inferenceLatency*1000),"objects":detections.count,"top":detections.max { $0.confidence<$1.confidence }.map { "\($0.label) \(String(format:"%.2f",$0.confidence))" },"fps":String(format:"%.1f",framesPerSecond)]) }
        notices.forEach { debugLog(.camera,.info,"Obstacle notice",["label":$0.label]);onMetric?(MetricEvent(kind:"notice",frame:$0.capturedAt,decision:decisionTime));onNotice?($0) }
    }
    private func stopAfterError() { running=false;engine.stop();filter.reset() }
}
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    class Preview: UIView { override class var layerClass:AnyClass { AVCaptureVideoPreviewLayer.self }; var preview:AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer } }
    func makeUIView(context:Context)->Preview { let view=Preview();view.preview.session=session;view.preview.videoGravity = .resizeAspectFill;return view }
    func updateUIView(_ uiView:Preview,context:Context) {}
}
