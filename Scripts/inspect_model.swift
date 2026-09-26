import Foundation
import CoreML
import Vision
import CoreVideo
let url=URL(fileURLWithPath:CommandLine.arguments[1])
let model=try MLModel(contentsOf:url)
print("INPUTS",model.modelDescription.inputDescriptionsByName)
print("OUTPUTS",model.modelDescription.outputDescriptionsByName)
print("METADATA",model.modelDescription.metadata)
var buffer:CVPixelBuffer?
CVPixelBufferCreate(kCFAllocatorDefault,640,640,kCVPixelFormatType_32BGRA,nil,&buffer)
if let buffer {
 CVPixelBufferLockBaseAddress(buffer,[])
 memset(CVPixelBufferGetBaseAddress(buffer),127,CVPixelBufferGetDataSize(buffer))
 CVPixelBufferUnlockBaseAddress(buffer,[])
 let request=VNCoreMLRequest(model:try VNCoreMLModel(for:model));request.imageCropAndScaleOption = .scaleFit
 let start=ProcessInfo.processInfo.systemUptime
 try VNImageRequestHandler(cvPixelBuffer:buffer,orientation:.up).perform([request])
 print("SMOKE_INFERENCE_SECONDS",ProcessInfo.processInfo.systemUptime-start)
 print("RESULT_TYPE",String(describing:type(of:request.results)),"COUNT",request.results?.count ?? 0)
 print("OBJECT_RESULT_CAST",request.results is [VNRecognizedObjectObservation])
}
