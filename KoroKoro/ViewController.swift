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
    let isDebug = true
    
    @IBOutlet private var sceneView: ARSCNView!
    @IBOutlet private var statusLabel: UILabel!
    @IBOutlet private var mainLabel: UILabel! {
        didSet { mainLabel.text = "" }
    }

    private var planes = [ARPlaneAnchor: SCNNode]()
    
    let planeVerticalOffset = Float(0.01)
    
    private enum Phase {
        case initializing   // 初期化中
        case limited    // TODO:
        case tracking       // トラッキング中
        case detection(SCNNode)      // 平面検出
        
        case starting
        case playing

        case error(message: String)
        
        var status: String {
            switch self {
            case .initializing: return "ARKit initializing..."
            case .limited: return "ERROR!: limited"
            case .tracking: return "tracking..."
            case .detection: return "detection plane"
                
            case .error(let message): return "ERROR!: \(message)"
            default: return ""
            }
        }
    }
    
    private var phase = Phase.initializing {
        didSet {
            DispatchQueue.main.async { [weak self] in
                self?.updatePhase(old: oldValue)
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        guard ARWorldTrackingConfiguration.isSupported else {
            fatalError()
        }

        sceneView.showsStatistics = isDebug
        sceneView.debugOptions = isDebug
            ? [ARSCNDebugOptions.showFeaturePoints, .showPhysicsShapes]
            : []
        sceneView.delegate = self

        //sceneView.automaticallyUpdatesLighting = true
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        reset()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // TODO: !!!
        sceneView.session.pause()
    }
    
    // MARK: - ARSCNViewDelegate
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        print(error)
        phase = .error(message: error.localizedDescription)
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        print("sessionWasInterrupted")
        phase = .error(message: "ARKit Was Interrupted")
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
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
    
    // 床検出用
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        
        switch phase {
        case .tracking, .detection: break
        default: return
        }
        
        let floor = makeFloor(anchor: planeAnchor)
        node.addChildNode(floor)
        planes[planeAnchor] = floor
        phase = .detection(floor)
        DispatchQueue.main.async { [weak self] in
            self?.waitingStart()
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        guard let parent = planes[planeAnchor], parent == node else { return }
        parent.position = SCNVector3Make(planeAnchor.center.x, planeVerticalOffset, planeAnchor.center.y)
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        planes.removeValue(forKey: planeAnchor)
        if planes.count == 0 {
            phase = .tracking
        } else {
            print(planes.count)
        }
    }
    
    // MARK: -
    private func reset() {
        // ゲームを最初から開始

        // 床の検出を開始
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal
        sceneView.session.run(configuration, options: .removeExistingAnchors)
        
        planes = [:]
        phase = .initializing
    }
    
    private func waitingStart() {
        mainLabel.text = "Ready?"
    }
    
    private func start() {
        guard case let .detection(node) = phase,
            let parent = node.parent else {
                return
        }
        
        phase = .starting

        let configuration = ARWorldTrackingConfiguration()
        sceneView.session.run(configuration)

        
        let camera = sceneView.scene.rootNode.childNodes.flatMap { $0.camera == nil ? nil : $0 }.first!

        let translation = SCNMatrix4MakeTranslation(0, 0, -3)
        let ball = SCNNode(geometry: SCNBox(width: 0.5, height: 0.5, length: 0.5, chamferRadius: 0.1))
        ball.transform = translation
        camera.addChildNode(ball)
        
        let a = parent.clone()
        a.orientation.y = camera.worldOrientation.y

        //        a.localRotate(by: camera.worldOrientation)//, aroundTarget: SCNVector3Make(0, 1, 0))
        sceneView.scene.rootNode.addChildNode(a)

        
        
        //        sceneView.scene.physicsWorld.speed = 1

    }
    
    private func updatePhase(old: Phase) {
        print("phase: \(old) => \(phase)")

        if case let .detection(node) = old {
            node.removeFromParentNode()
        }
        
        statusLabel.text = phase.status
        mainLabel.text = ""
    }

    
    @IBAction func tap(sender: UITapGestureRecognizer) {
        switch phase {
        case .detection: start()
        default: return
        }
    }

    @IBAction func _tap() {
        
        let results = sceneView.hitTest(CGPoint(x: 0.5, y: 0.5),
                                        types: [.existingPlane])
        results.forEach {
            guard let anchor = $0.anchor as? ARPlaneAnchor else { return }
            let plane = planes[anchor]
            print(plane?.name ?? "?")
        }

        
        
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
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let camera = sceneView.scene.rootNode.childNodes.flatMap { $0.camera == nil ? nil : $0 }.first
        
        print(camera?.eulerAngles)

    }
    
    @IBAction private func tapReset(sender: UIButton) {
        reset()
    }

    // MARK: -
    private func makeFloor(anchor: ARPlaneAnchor) -> SCNNode {
        let source = SCNScene(named: "floor.scn", inDirectory: "Models.scnassets/floor")!.rootNode
        let node = SCNNode()
        source.childNodes.forEach { node.addChildNode($0) }
        
        let debug = node.childNode(withName: "debug", recursively: true)
        debug?.isHidden = !isDebug
        
        sceneView.scene.physicsWorld.speed = 0
        
        node.position = SCNVector3Make(anchor.center.x, planeVerticalOffset, anchor.center.y)
        return node
    }
    
    private func makeBall() -> SCNNode {
        let source = SCNScene(named: "ball.scn", inDirectory: "Models.scnassets/ball")!.rootNode
        let parent = SCNNode()
        source.childNodes.forEach { parent.addChildNode($0) }
        return parent
    }
    
    private func makeStage() -> SCNNode {
        let source = SCNScene(named: "stage.scn", inDirectory: "Models.scnassets/stage")!.rootNode
        let parent = SCNNode()
        source.childNodes.forEach { parent.addChildNode($0) }
        return parent
    }
}
