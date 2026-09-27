import SwiftUI
@preconcurrency import AVFoundation
@preconcurrency import Vision
import CoreML
import CoreMotion
import simd
import Darwin

/// The bundled Core ML model name, set once in Info.plist (JGDetectionModel) and shared with Scripts/install_model.sh and Scripts/create_project.py.
enum DetectionModel { static let name=Bundle.main.object(forInfoDictionaryKey:"JGDetectionModel") as? String ?? "" }
final class CaptureEngine: NSObject,AVCaptureVideoDataOutputSampleBufferDelegate,AVCaptureDepthDataOutputDelegate,@unchecked Sendable {
    let session = AVCaptureSession()
    let queue = DispatchQueue(label:"guide.camera")
    var result: (@Sendable ([Detection],Double,Double,Double,String?) -> Void)?
    private var request: VNCoreMLRequest?
    private var configured=false
    private var lastFrame=0.0
    /// Chest/head-height obstacle check from the dual-camera depth stream (no LiDAR needed). Runs on its own queue.
    var headLevel: (@Sendable (HeadLevelResult?,String) -> Void)?
    private let depthQueue=DispatchQueue(label:"guide.depth")
    private let motion=CMMotionManager()
    private var lastDepth=0.0
    private var cameraHeight:Float=1.3
    private var headLevelConfig=HeadLevelConfig()
    private(set) var device:AVCaptureDevice?
    func setCameraHeight(_ height:Double) { depthQueue.async { [self] in cameraHeight=Float(height) } }
    func setHeadLevelConfig(_ config:HeadLevelConfig) { depthQueue.async { [self] in headLevelConfig=config } }
    func start() {
        queue.async { [self] in
            do {
                if !configured {
                    session.beginConfiguration();defer { session.commitConfiguration() }
                    session.sessionPreset = .vga640x480
                    // Dual wide (wide + ultra wide) gives stereo depth on non-Pro iPhones; fall back to the plain wide camera.
                    guard let device=AVCaptureDevice.default(.builtInDualWideCamera,for:.video,position:.back) ?? AVCaptureDevice.default(.builtInWideAngleCamera,for:.video,position:.back) else { throw CameraError.noCamera }
                    self.device=device
                    let input=try AVCaptureDeviceInput(device:device)
                    guard session.canAddInput(input) else { throw CameraError.noCamera };session.addInput(input)
                    let output=AVCaptureVideoDataOutput();output.alwaysDiscardsLateVideoFrames=true;output.setSampleBufferDelegate(self,queue:queue)
                    guard session.canAddOutput(output) else { throw CameraError.noCamera };session.addOutput(output);configured=true
                    configureDepth(device)
                }
                if request == nil, let url=Bundle.main.url(forResource:DetectionModel.name,withExtension:"mlmodelc") {
                    let model=try MLModel(contentsOf:url);request=VNCoreMLRequest(model:try VNCoreMLModel(for:model));request?.imageCropAndScaleOption = .scaleFit
                }
                if motion.isDeviceMotionAvailable && !motion.isDeviceMotionActive { motion.deviceMotionUpdateInterval=1/30;motion.startDeviceMotionUpdates() }
                session.startRunning()
            } catch { result?([],0,0,0,error.localizedDescription) }
        }
    }
    func stop() { queue.async { [self] in session.stopRunning();motion.stopDeviceMotionUpdates() } }
    /// Picks a small 4:3 video format that also delivers depth, and adds a depth output. Leaves the VGA preset when unsupported.
    private func configureDepth(_ device:AVCaptureDevice) {
        let formats=device.formats.filter { !$0.supportedDepthDataFormats.isEmpty }.filter { let d=CMVideoFormatDescriptionGetDimensions($0.formatDescription);return d.width*3 == d.height*4 && d.width >= 640 }
        guard let format=formats.min(by: { CMVideoFormatDescriptionGetDimensions($0.formatDescription).width < CMVideoFormatDescriptionGetDimensions($1.formatDescription).width }),
              let depthFormat=format.supportedDepthDataFormats.filter({ CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_DepthFloat32 || CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_DepthFloat16 }).max(by: { CMVideoFormatDescriptionGetDimensions($0.formatDescription).width < CMVideoFormatDescriptionGetDimensions($1.formatDescription).width }) else {
            headLevel?(nil,"深度非対応のカメラです");return
        }
        let depth=AVCaptureDepthDataOutput();depth.isFilteringEnabled=true;depth.alwaysDiscardsLateDepthData=true
        guard session.canAddOutput(depth) else { headLevel?(nil,"深度出力を追加できません");return }
        session.addOutput(depth);depth.setDelegate(self,callbackQueue:depthQueue)
        do { try device.lockForConfiguration();device.activeFormat=format;device.activeDepthDataFormat=depthFormat;device.unlockForConfiguration() }
        catch { headLevel?(nil,"深度の設定に失敗しました");return }
        let v=CMVideoFormatDescriptionGetDimensions(format.formatDescription),d=CMVideoFormatDescriptionGetDimensions(depthFormat.formatDescription)
        headLevel?(nil,localized("深度 {0}×{1}・映像 {2}×{3}",d.width,d.height,v.width,v.height))
    }
    func depthDataOutput(_ output:AVCaptureDepthDataOutput,didOutput depthData:AVDepthData,timestamp:CMTime,connection:AVCaptureConnection) {
        let now=ProcessInfo.processInfo.systemUptime
        guard now-lastDepth >= 0.2 else { return };lastDepth=now
        guard let g=motion.deviceMotion?.gravity else { headLevel?(nil,"端末の傾きを取得できません");return }
        let depth=depthData.converting(toDepthDataType:kCVPixelFormatType_DepthFloat32),map=depth.depthDataMap
        CVPixelBufferLockBaseAddress(map,.readOnly);defer { CVPixelBufferUnlockBaseAddress(map,.readOnly) }
        guard let base=CVPixelBufferGetBaseAddress(map) else { return }
        let width=CVPixelBufferGetWidth(map),height=CVPixelBufferGetHeight(map),row=CVPixelBufferGetBytesPerRow(map)
        // Intrinsics from calibration (scaled to the depth map), else from the field of view.
        var fx:Float,fy:Float,cx:Float,cy:Float
        if let c=depth.cameraCalibrationData {
            let k=c.intrinsicMatrix,ref=c.intrinsicMatrixReferenceDimensions,sx=Float(width)/Float(ref.width),sy=Float(height)/Float(ref.height)
            fx=k.columns.0.x*sx;fy=k.columns.1.y*sy;cx=k.columns.2.x*sx;cy=k.columns.2.y*sy
        } else {
            let fov=Float(device?.activeFormat.videoFieldOfView ?? 70) * .pi/180
            fx=Float(width)/2/tan(fov/2);fy=fx;cx=Float(width)/2;cy=Float(height)/2
        }
        let step=max(1,width/80)
        var points:[SIMD3<Float>]=[];points.reserveCapacity((width/step)*(height/step))
        for v in stride(from:0,to:height,by:step) {
            let line=base.advanced(by:v*row).assumingMemoryBound(to:Float32.self)
            for u in stride(from:0,to:width,by:step) {
                let z=line[u]
                guard z.isFinite,z>0.2,z<5 else { continue }
                points.append(HeadLevelGeometry.devicePoint(u:Float(u),v:Float(v),depth:z,fx:fx,fy:fy,cx:cx,cy:cy))
            }
        }
        let result=HeadLevelGeometry.evaluate(points:points,gravity:SIMD3(Float(g.x),Float(g.y),Float(g.z)),cameraHeight:cameraHeight,config:headLevelConfig)
        headLevel?(result,localized("深度 {0}点・床{1} {2}m",points.count,localized(result.floorMeasured ? "推定":"仮定"),String(format:"%.2f",-result.floor)))
    }
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
    @Published var headLevel:HeadLevelHit?
    @Published var depthStatus="深度未開始"
    var onHeadLevel: ((HeadLevelHit?,Double)->Void)?
    private var sessionGeneration=0
    /// Field of view of the sensor's long side in degrees. The portrait aspect-fill preview shows that side as the full screen height.
    /// Uses the camera actually in the session (the dual wide virtual camera when depth is on) and its zoom.
    var verticalFieldOfView:Double {
        guard let device=engine.device ?? AVCaptureDevice.default(.builtInWideAngleCamera,for:.video,position:.back) else { return 65 }
        let half=Double(device.activeFormat.videoFieldOfView)/2 * .pi/180
        return 2*atan(tan(half)/Double(device.videoZoomFactor)) * 180 / .pi
    }
    init() {
        UIDevice.current.isBatteryMonitoringEnabled=true
        if Bundle.main.url(forResource:DetectionModel.name,withExtension:"mlmodelc") != nil { modelStatus="導入済み・動作確認待ち" }
        Task { @MainActor [modelStatus] in debugLog(.model,modelStatus == "未導入" ? .warning:.info,"Model bundle check",["model":DetectionModel.name,"status":modelStatus]) }
        engine.result = { [weak self] detections,captured,start,end,error in
            Task { @MainActor in self?.receive(detections,captured:captured,start:start,end:end,error:error) }
        }
        engine.headLevel = { [weak self] result,status in
            Task { @MainActor in
                guard let self else { return }
                self.depthStatus=status
                guard self.running,let result else { return }
                self.headLevel=result.hit;self.onHeadLevel?(result.hit,ProcessInfo.processInfo.systemUptime)
            }
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
        sessionGeneration += 1;running=false;engine.stop();filter.reset();status="カメラ停止中";labels="検出候補なし";detections=[];framesPerSecond=0;headLevel=nil
    }
    /// DeveloperMode preview of the box overlay without camera frames. Never passed to the notice filter.
    func showSimulated(_ items:[Detection]) { guard !running else { return };simulatedDetections=true;detections=items }
    private func receive(_ detections:[Detection],captured:Double,start:Double,end:Double,error:String?) {
        guard running else { return }
        if let error=error ?? (injectError ? localized("模擬認識エラー"):nil) { status=localized("認識エラー：{0}",localized(error));debugLog(.model,.error,"Inference error",["error":error,"injected":injectError]);stopAfterError();return }
        if inferenceCount == 0 { debugLog(.model,.success,"First inference completed",["ms":Int((end-start)*1000),"objects":detections.count]) }
        if lastCaptured>0,captured>lastCaptured { let fps=1/(captured-lastCaptured);framesPerSecond=framesPerSecond == 0 ? fps:framesPerSecond*0.8+fps*0.2 };lastCaptured=captured
        frameTime=captured;inferenceStart=start;inferenceEnd=end;inferenceCount += 1;inferenceLatency=end-start
        status="端末内で認識中";modelStatus="認識処理実行中"
        self.detections=detections
        labels=Array(Set(detections.prefix(5).map { localized(DetectionLabels.japanese[$0.label] ?? $0.label) })).sorted().joined(separator:localized("、"))
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
