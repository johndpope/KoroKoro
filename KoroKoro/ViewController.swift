//
//  ViewController.swift
//  KoroKoro
//
//  Created by M.Ike on 2017/07/09.
//  Copyright © 2017年 M.Ike. All rights reserved.
//

import UIKit
import ARKit

class ViewController: UIViewController, ARSCNViewDelegate, SCNPhysicsContactDelegate {
    let isDebug = false
    
    @IBOutlet private var sceneView: ARSCNView!
    @IBOutlet private var statusLabel: UILabel!
    @IBOutlet private var mainLabel: UILabel! {
        didSet { mainLabel.text = "" }
    }
    
    let planeVerticalOffset = Float(0.01)
    
    private enum Phase {
        case initializing   // 初期化中
        case limited    // TODO:
        case tracking       // トラッキング中
        case detection(stage: SCNNode)      // 平面検出
        
        case starting(stage: SCNNode)
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
        sceneView.scene.physicsWorld.contactDelegate = self

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
        
        let stage = makeStage(anchor: planeAnchor)
        node.addChildNode(stage)
        phase = .detection(stage: stage)
        DispatchQueue.main.async { [weak self] in
            self?.waitingStart()
        }
    }
    
    // MARK: -
    private func reset() {
        // ゲームを最初から開始

        // 床の検出を開始
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal
        sceneView.session.run(configuration, options: .resetTracking)
        
        phase = .initializing
    }
    
    private func waitingStart() {
        mainLabel.text = "Ready?"
    }
    
    private func start() {
        guard case let .detection(node) = phase, let parent = node.parent else { return }
        let cameras = sceneView.scene.rootNode.childNodes.flatMap { $0.camera == nil ? nil : $0 }
        guard let camera = cameras.first else { return }
        
        let configuration = ARWorldTrackingConfiguration()
        sceneView.session.run(configuration)

        

        let translation = SCNMatrix4MakeTranslation(0, 0, -3)
        let ball = SCNNode(geometry: SCNBox(width: 0.5, height: 0.5, length: 0.5, chamferRadius: 0.1))
        ball.transform = translation
        camera.addChildNode(ball)
        
        let stage = parent.clone()
        stage.orientation.y = camera.worldOrientation.y
        stage.worldPosition = SCNVector3Make(0, stage.worldPosition.y, 0)
        sceneView.scene.rootNode.addChildNode(stage)
        
//        stage.childNode(withName: "play_area", recursively: true)?.isHidden = true
        
        phase = .starting(stage: stage)
    }
    
    private func updatePhase(old: Phase) {
        print("phase: \(old) => \(phase)")

        switch old {
        case .detection(let node), .starting(let node):
            node.removeFromParentNode()
        default: break
        }
        
        statusLabel.text = phase.status
        mainLabel.text = ""
    }

    
    @IBAction func tap(sender: UITapGestureRecognizer) {
        switch phase {
        case .detection: start()
        case .starting: bbb()
        default: return
        }
    }

    private func bbb() {
        let ball = makeBall()
        let parent = sceneView.scene.rootNode.childNode(withName: "balls", recursively: true)
        parent?.addChildNode(ball)
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let camera = sceneView.scene.rootNode.childNodes.flatMap { $0.camera == nil ? nil : $0 }.first
        
//        print(camera?.eulerAngles)

    }
    
    @IBAction private func tapReset(sender: UIButton) {
        reset()
    }

    // MARK: -
    private func makeStage(anchor: ARPlaneAnchor) -> SCNNode {
        let source = SCNScene(named: "stage.scn", inDirectory: "Models.scnassets/stage")!.rootNode
        let node = SCNNode()
        node.name = "stage"
        source.childNodes.forEach { node.addChildNode($0) }
        node.position = SCNVector3Make(anchor.center.x, planeVerticalOffset, anchor.center.y)
        return node
    }
    
    private func makeBall() -> SCNNode {
        let source = SCNScene(named: "ball.scn", inDirectory: "Models.scnassets/ball")!.rootNode
        let parent = SCNNode()
        source.childNodes.forEach { parent.addChildNode($0) }
        return parent
    }
    
    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        print(contact.nodeA)
        print(contact.nodeB)
    }
}
