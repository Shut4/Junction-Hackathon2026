import SwiftUI
import SceneKit
import CoreMotion

/// A 3D arrow drawn on a virtual ground plane over the camera preview. The virtual camera copies the phone's tilt/roll
/// (CoreMotion gravity) and the rear camera's field of view, so the arrow appears to lie on the road ahead.
/// It shows direction only: no surface detection and no world anchoring. Heading accuracy is as for the HUD arrow.
struct GroundArrowView:UIViewRepresentable {
    /// Signed angle to the route (positive = right), from `RouteTracker.relativeBearing`.
    let angle:Double
    let cameraHeight:Double
    let distance:Double
    let fieldOfView:Double
    func makeCoordinator()->Coordinator { Coordinator() }
    func makeUIView(context:Context)->SCNView {
        let view=SCNView(frame:.zero,options:nil)
        view.backgroundColor = .clear;view.scene=context.coordinator.scene;view.pointOfView=context.coordinator.camera
        view.antialiasingMode = .multisampling4X;view.preferredFramesPerSecond=30;view.isPlaying=true
        view.isUserInteractionEnabled=false;view.isAccessibilityElement=false;view.accessibilityElementsHidden=true
        context.coordinator.startMotion();return view
    }
    func updateUIView(_ view:SCNView,context:Context) { context.coordinator.update(angle:angle,height:cameraHeight,distance:distance,fieldOfView:fieldOfView) }
    static func dismantleUIView(_ view:SCNView,coordinator:Coordinator) { coordinator.stopMotion() }

    @MainActor final class Coordinator {
        let scene=SCNScene()
        let camera=SCNNode()
        private let pivot=SCNNode()
        private let arrow=SCNNode()
        private let material=SCNMaterial()
        private let motion=CMMotionManager()
        private var height=1.3
        private var bucket:DirectionBucket?
        init() {
            let lens=SCNCamera();lens.projectionDirection = .vertical;lens.zNear=0.05;lens.zFar=50;camera.camera=lens;camera.position=SCNVector3(0,height,0)
            scene.rootNode.addChildNode(camera)
            material.lightingModel = .physicallyBased;material.roughness.contents=0.35;material.metalness.contents=0.05
            let body=SCNShape(path:Self.arrowPath(),extrusionDepth:0.1);body.chamferRadius=0.03;body.materials=[material]
            // Path points along +Y and is extruded along Z; lay it flat so it points along -Z (forward) and stands on y=0.
            let mesh=SCNNode(geometry:body);mesh.eulerAngles.x = -.pi/2;mesh.position.y=0.05
            arrow.addChildNode(mesh);pivot.addChildNode(arrow);scene.rootNode.addChildNode(pivot)
            // Gentle forward drift so the direction of travel reads at a glance.
            let drift=SCNAction.sequence([.moveBy(x:0,y:0,z:-0.35,duration:0.9),.moveBy(x:0,y:0,z:0.35,duration:0.9)]);drift.timingMode = .easeInEaseOut
            arrow.runAction(.repeatForever(drift))
            // Invisible ground that only receives the arrow's shadow, so it looks placed on the road.
            let floorMaterial=SCNMaterial();floorMaterial.lightingModel = .shadowOnly
            let floor=SCNNode(geometry:SCNPlane(width:20,height:20));floor.geometry?.materials=[floorMaterial];floor.eulerAngles.x = -.pi/2
            scene.rootNode.addChildNode(floor)
            let sun=SCNLight();sun.type = .directional;sun.intensity=1100;sun.castsShadow=true;sun.shadowMode = .deferred;sun.shadowColor=UIColor.black.withAlphaComponent(0.45);sun.shadowRadius=6;sun.shadowSampleCount=8
            sun.orthographicScale=6;sun.automaticallyAdjustsShadowProjection=true
            let sunNode=SCNNode();sunNode.light=sun;sunNode.eulerAngles=SCNVector3(-1.1,0.5,0);scene.rootNode.addChildNode(sunNode)
            let fill=SCNLight();fill.type = .ambient;fill.intensity=450;let fillNode=SCNNode();fillNode.light=fill;scene.rootNode.addChildNode(fillNode)
        }
        /// Arrow outline in metres: 0.34 m shaft, 0.8 m head, 1.6 m long, pointing +Y and centred on its middle.
        private static func arrowPath()->UIBezierPath {
            let p=UIBezierPath()
            p.move(to:CGPoint(x:0,y:0.8));p.addLine(to:CGPoint(x:0.4,y:0.2));p.addLine(to:CGPoint(x:0.17,y:0.2));p.addLine(to:CGPoint(x:0.17,y:-0.8))
            p.addLine(to:CGPoint(x:-0.17,y:-0.8));p.addLine(to:CGPoint(x:-0.17,y:0.2));p.addLine(to:CGPoint(x:-0.4,y:0.2));p.close();return p
        }
        func update(angle:Double,height:Double,distance:Double,fieldOfView:Double) {
            self.height=height;camera.camera?.fieldOfView=fieldOfView
            // The arrow always sits straight ahead of the wearer and turns toward the route, so GPS drift never pushes it off the road.
            pivot.position=SCNVector3(0,0,-Float(distance))
            SCNTransaction.begin();SCNTransaction.animationDuration=0.25
            pivot.eulerAngles.y = -Float(angle * .pi/180)
            let next=DirectionBucket.of(angle,keeping:bucket)
            if next != bucket { bucket=next;material.diffuse.contents=next == .ahead ? UIColor.systemGreen:UIColor.systemYellow;material.emission.contents=(next == .ahead ? UIColor.systemGreen:UIColor.systemYellow).withAlphaComponent(0.25) }
            SCNTransaction.commit()
            if !motion.isDeviceMotionActive { apply(tilt:0,roll:0) }
        }
        func startMotion() {
            guard motion.isDeviceMotionAvailable else { apply(tilt:0,roll:0);return }
            motion.deviceMotionUpdateInterval=1/30
            motion.startDeviceMotionUpdates(to:.main) { [weak self] data,_ in
                guard let g=data?.gravity else { return }
                MainActor.assumeIsolated { let pose=CameraPose.from(gravityX:g.x,y:g.y,z:g.z);self?.apply(tilt:pose.tilt,roll:pose.roll) }
            }
        }
        func stopMotion() { motion.stopDeviceMotionUpdates() }
        /// Tilt above the horizon is clamped to level, which keeps the arrow near the bottom of the screen instead of losing it.
        private func apply(tilt:Double,roll:Double) {
            let pitch=simd_quatf(angle:-Float(max(0,tilt)),axis:SIMD3(1,0,0)),spin=simd_quatf(angle:Float(roll),axis:SIMD3(0,0,1))
            camera.simdOrientation=pitch*spin;camera.position=SCNVector3(0,Float(height),0)
        }
    }
}
