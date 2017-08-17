//
//  ViewController.swift
//  KoroKoro
//
//  Created by M.Ike on 2017/07/09.
//  Copyright © 2017年 M.Ike. All rights reserved.
//

import UIKit
import ARKit

class ViewController: UIViewController, ARSCNViewDelegate {
    @IBOutlet private var sceneView: ARSCNView!
    @IBOutlet private var statusLabel: UILabel!
    
    let planeVerticalOffset = Float(0.01)  // The occlusion plane should be placed 1 cm below the actual
    // plane to avoid z-fighting etc.

    private let configuration: ARWorldTrackingConfiguration = {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal
        return configuration
    }()
    
    private enum Phase {
        case initializing   // 初期化中
        case limited    // TODO:
        case tracking       // トラッキング中
        case detection(parentNode: SCNNode)      // 平面検出
        
        
        case starting
        case playing

        case error(message: String)
        
        var status: String {
            switch self {
            case .initializing: return "ARKit initializing..."
            case .limited: return "検出不可"
            case .tracking: return "tracking..."
            case .detection: return "床候補"
                
            case .error(let message): return "error: \(message)"
            default:
                return ""
            }
        }
    }
    
    private var phase = Phase.initializing {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let `self` = self else { return }
                
                if case let .detection(parentNode) = oldValue {
                    parentNode.removeFromParentNode()
                }
                
                self.statusLabel.text = self.phase.status
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        guard ARWorldTrackingConfiguration.isSupported else {
            fatalError()
        }

        sceneView.showsStatistics = true
        sceneView.debugOptions = ARSCNDebugOptions.showFeaturePoints
//        sceneView.automaticallyUpdatesLighting = true
        sceneView.delegate = self
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        sceneView.session.run(configuration)
        
        phase = .initializing
        
//        let f = sceneView.session.currentFrame
//        print(f)
//        sceneView.session.run(configuration, options: .resetTracking)
//        sceneView.session.run(configuration, options: .removeExistingAnchors)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
//        sceneView.session.pause()
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        print(error)
        phase = .error(message: error.localizedDescription)
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        //viewWillDisappearでpause()しない場合
        print("sessionWasInterrupted")
        phase = .error(message: "ARKit Was Interrupted")
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        //viewWillDisappearでpause()しない場合で復活した場合
        print("sessionInterruptionEnded")
    }
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        // トラッキング状況の変化
        print(camera.trackingState)
        switch camera.trackingState {
        case .normal:
            phase = .tracking
        case .limited(let reason):
            switch reason {
            case .initializing:
                phase = .initializing
            case .excessiveMotion:
                phase = .limited    // 動きが速い
            case .insufficientFeatures:
                phase = .limited    // 特徴点なし
            }
        case .notAvailable:
            phase = .error(message: "Tracking Not Available")
        }
    }
    
    private func addFloor(node: SCNNode, planeAnchor: ARPlaneAnchor) {
        switch phase {
        case .tracking:            // 新規床検出
            print("add tracking")
        case let .detection(parentNode):            // 追加検出
            print("add detection")
            guard node.worldPosition.y < parentNode.worldPosition.y else { return }
        default: return
        }
        
        print("add")
        let source = SCNScene(named: "floor.scn", inDirectory: "Models.scnassets/floor")!.rootNode
        let floor = SCNNode()
        source.childNodes.forEach { floor.addChildNode($0) }
        floor.position = SCNVector3Make(0, planeVerticalOffset, 0)
        node.addChildNode(floor)
        
        phase = .detection(parentNode: node)
    }
    
    // 床検出用
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        DispatchQueue.main.async { [weak self] in
            self?.addFloor(node: node, planeAnchor: planeAnchor)
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        print("didUpdate")
        // 更新
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        guard case let .detection(parentNode) = phase, node.isEqual(parentNode) else { return }
        guard let floor = node.childNodes.first else { return }

        print("didUpdate")
//        floor.position = SCNVector3Make(planeAnchor.center.x, planeVerticalOffset, planeAnchor.center.z)

//        DispatchQueue.main.async { [weak self] in
//            guard let `self` = self else { return }
//
//            let frame = self.sceneView.session.currentFrame!
//            let t = frame.camera.transform
//            let a = SCNVector3Make(t.columns.3.x, t.columns.3.y, t.columns.3.z - 2)
//
//
//            self.statusLabel.text = "\(a)"
//        }

    }
    
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        // マージ
        print("didRemove")
    }
    
    @IBAction func tap() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            
            //                let source = SCNScene(named: "ball.scn", inDirectory: "Models.scnassets/ball")!.rootNode
            //                let parent = SCNNode()
            //                source.childNodes.forEach { parent.addChildNode($0) }
            //                parent.position = SCNVector3Make(planeAnchor.center.x, planeVerticalOffset, planeAnchor.center.z)
            //                self.sceneView.scene.rootNode.addChildNode(parent)
//            if case let .detection(parentNode) = self.phase {
//                let a = parentNode.childNode(withName: "ball", recursively: true)!
//                a.isHidden = false
//            }
        }

        let source = SCNScene(named: "ball.scn", inDirectory: "Models.scnassets/ball")!.rootNode
        let parent = SCNNode()
        source.childNodes.forEach { parent.addChildNode($0) }
        
        if let currentFrame = sceneView.session.currentFrame {
            
            // Create a transform with a translation of 0.2 meters in front of the camera
//            var translation = matrix_identity_float4x4
//            translation.columns.3.z = -0.2
//            let transform = simd_mul(currentFrame.camera.transform, translation)
            let translation = SCNMatrix4MakeTranslation(0, 0, -5)
            let transform = SCNMatrix4Mult(translation, SCNMatrix4(currentFrame.camera.transform))

            // Add a new anchor to the session
//            let anchor = ARAnchor(transform: transform)
//            sceneView.session.add(anchor: anchor)
            
            parent.transform = transform
            sceneView.scene.rootNode.addChildNode(parent)
        }
//        let frame = sceneView.session.currentFrame!
//        let t = frame.camera.transform
//
//        let a = SCNVector3Make(t.columns.3.x, t.columns.3.y, t.columns.3.z)
//        parent.position = a
//
//        let aaa = CGPoint(x: 0.5, y: 0.5)
//
//        let planeHitTestResults = sceneView.session.currentFrame?.hitTest(aaa, types: [.existingPlaneUsingExtent, .estimatedHorizontalPlane])
//        if let result = planeHitTestResults?.first {
//
//            let planeHitTestPosition = SCNVector3.positionFromTransform(result.worldTransform)
//            let planeAnchor = result.anchor
//
//            // Return immediately - this is the best possible outcome.
//            print(planeAnchor)
//
//        }


    }
}

extension SCNNode {
    
    func setUniformScale(_ scale: Float) {
        self.scale = SCNVector3Make(scale, scale, scale)
    }
    
    func renderOnTop() {
        self.renderingOrder = 2
        if let geom = self.geometry {
            for material in geom.materials {
                material.readsFromDepthBuffer = false
            }
        }
        for child in self.childNodes {
            child.renderOnTop()
        }
    }
}

// MARK: - SCNVector3 extensions

extension SCNVector3 {
    
    init(_ vec: vector_float3) {
        self.x = vec.x
        self.y = vec.y
        self.z = vec.z
    }
    
    func length() -> Float {
        return sqrtf(x * x + y * y + z * z)
    }
    
    mutating func setLength(_ length: Float) {
        self.normalize()
        self *= length
    }
    
    mutating func setMaximumLength(_ maxLength: Float) {
        if self.length() <= maxLength {
            return
        } else {
            self.normalize()
            self *= maxLength
        }
    }
    
    mutating func normalize() {
        self = self.normalized()
    }
    
    func normalized() -> SCNVector3 {
        if self.length() == 0 {
            return self
        }
        
        return self / self.length()
    }
    
    static func positionFromTransform(_ transform: matrix_float4x4) -> SCNVector3 {
        return SCNVector3Make(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
    }
    
    func friendlyString() -> String {
        return "(\(String(format: "%.2f", x)), \(String(format: "%.2f", y)), \(String(format: "%.2f", z)))"
    }
    
    func dot(_ vec: SCNVector3) -> Float {
        return (self.x * vec.x) + (self.y * vec.y) + (self.z * vec.z)
    }
    
    func cross(_ vec: SCNVector3) -> SCNVector3 {
        return SCNVector3(self.y * vec.z - self.z * vec.y, self.z * vec.x - self.x * vec.z, self.x * vec.y - self.y * vec.x)
    }
}

public let SCNVector3One: SCNVector3 = SCNVector3(1.0, 1.0, 1.0)

func SCNVector3Uniform(_ value: Float) -> SCNVector3 {
    return SCNVector3Make(value, value, value)
}

func SCNVector3Uniform(_ value: CGFloat) -> SCNVector3 {
    return SCNVector3Make(Float(value), Float(value), Float(value))
}

func + (left: SCNVector3, right: SCNVector3) -> SCNVector3 {
    return SCNVector3Make(left.x + right.x, left.y + right.y, left.z + right.z)
}

func - (left: SCNVector3, right: SCNVector3) -> SCNVector3 {
    return SCNVector3Make(left.x - right.x, left.y - right.y, left.z - right.z)
}

func += (left: inout SCNVector3, right: SCNVector3) {
    left = left + right
}

func -= (left: inout SCNVector3, right: SCNVector3) {
    left = left - right
}

func / (left: SCNVector3, right: Float) -> SCNVector3 {
    return SCNVector3Make(left.x / right, left.y / right, left.z / right)
}

func * (left: SCNVector3, right: Float) -> SCNVector3 {
    return SCNVector3Make(left.x * right, left.y * right, left.z * right)
}

func /= (left: inout SCNVector3, right: Float) {
    left = left / right
}

func *= (left: inout SCNVector3, right: Float) {
    left = left * right
}

