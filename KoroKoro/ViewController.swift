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
    let isDebug = true
    
    @IBOutlet private var sceneView: ARSCNView!
    @IBOutlet private var statusLabel: UILabel!
    @IBOutlet private var mainLabel: UILabel! {
        didSet { mainLabel.text = "" }
    }
    @IBOutlet private var subLabel: UILabel! {
        didSet { subLabel.text = "" }
    }
    @IBOutlet private var scoreLabel: UILabel! {
        didSet { scoreLabel.text = "" }
    }
    
    
    private enum Phase {
        case initializing   // 初期化中
        case limited
        case tracking       // トラッキング中
        
        case ready(stage: SCNNode)                  // スタート待機
        case play(stage: SCNNode, score: Int)       // プレイ中
        
        case gameover(stage: SCNNode, score: Int)   // ゲームオーバー
        
        case error(message: String)
        
        var status: String {
            switch self {
            case .initializing: return "ARKit initializing..."
            case .limited: return "ERROR!: limited"
            case .tracking: return "tracking..."
                
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
        
        guard ARWorldTrackingConfiguration.isSupported else { fatalError() }
        
        sceneView.showsStatistics = isDebug
        sceneView.debugOptions = isDebug
            ? [ARSCNDebugOptions.showFeaturePoints, .showPhysicsShapes]
            : []
        
        sceneView.delegate = self
        sceneView.scene.physicsWorld.contactDelegate = self
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
    }
    
    // MARK: - ARSCNViewDelegate
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        print(error)
        phase = .error(message: error.localizedDescription)
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // ARSessionが中断された時に呼ばれる
        // （バックグラウンドに入ってカメラが使えない場合など）
        phase = .error(message: "ARKit Was Interrupted")
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // ARSessionの中断が終わった時に呼ばれる
        print("sessionInterruptionEnded")
    }
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        // トラッキング状況の変化
        print(camera.trackingState)
        
        switch camera.trackingState {
        case .normal:               // トラッキング中
            phase = .tracking
        case .limited(let reason):  // トラッキングが一時的に不可
            switch reason {
            case .initializing:     // 初期化中
                phase = .initializing
            case .excessiveMotion:
                phase = .limited    // 動きが速い
            case .insufficientFeatures:
                phase = .limited    // 特徴点なし
            }
        case .notAvailable:         // そもそも無効
            phase = .error(message: "Tracking Not Available")
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        // 平面が検出された時に呼ばれる
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        
        // ステージを配置
        DispatchQueue.main.async { [weak self] in
            self?.setupStage(node: node, planeAnchor: planeAnchor)
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        // 描画ごとに呼ばれる
        if case let .play(stage, _) = phase {
            // プレイ中ならプレイヤーの当たり判定をカメラ(=デバイス)の位置に追従させる
            let cameras = sceneView.scene.rootNode.childNodes.flatMap { $0.camera == nil ? nil : $0 }
            guard let camera = cameras.first else { fatalError() }

            guard let player = stage.childNode(withName: "player", recursively: true) else { fatalError() }
            // Y軸（縦）は床の高さに固定
            player.worldPosition = SCNVector3Make(camera.worldPosition.x, player.worldPosition.y, camera.worldPosition.z)
        }
    }
    
    // MARK: - SCNPhysicsContactDelegate
    
    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        // 当たり判定が発生した時に呼ばれる
        DispatchQueue.main.async { [weak self] in
            switch (contact.nodeA.name ?? "", contact.nodeB.name ?? "") {
            case ("ng", _), (_, "ng"):
                self?.gameover()
                
            case ("goal", _):
                // スコアを加算してボールを消滅
                self?.addScore()
                contact.nodeB.removeFromParentNode()
                
            case (_, "goal"):
                // スコアを加算してボールを消滅
                self?.addScore()
                contact.nodeA.removeFromParentNode()
                
            default: break
            }
        }
    }
    
    // MARK: - Event
    
    @IBAction func tap(sender: UITapGestureRecognizer) {
        // 画面タップ
        switch phase {
        case .ready, .gameover: start()
        default: return
        }
    }
    
    @IBAction private func tapReset(sender: UIButton) {
        // リセットボタン
        reset()
    }
    
    // MARK: -
    private func reset() {
        // 初期状態にリセットして開始する
        
        // 平面の検出を開始
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal
        sceneView.session.run(configuration, options: [.removeExistingAnchors, .resetTracking])
        
        // ゲーム状況「初期化」
        phase = .initializing
    }
    
    private func setupStage(node: SCNNode, planeAnchor: ARPlaneAnchor) {
        // 平面が検出できたのでステージを設置してスタート待ち
        guard case .tracking = phase else { return }
        
        // ステージを読み込み
        let parent = node.clone()
        let stage = SCNNode()
        stage.name = "stage"
        parent.addChildNode(stage)
        guard let source = SCNScene(named: "stage.scn", inDirectory: "Models.scnassets/stage")?.rootNode else { fatalError() }
        source.childNodes.forEach { stage.addChildNode($0) }
        
        // 床と思われる場所に配置
        stage.position = SCNVector3Make(planeAnchor.center.x, 0, planeAnchor.center.y)
        
        // カメラの位置を取得
        let cameras = sceneView.scene.rootNode.childNodes.flatMap { $0.camera == nil ? nil : $0 }
        guard let camera = cameras.first else { fatalError() }
        // カメラの向きに合わせてステージを回転
        parent.orientation.y = camera.worldOrientation.y
        
        // シーンにステージを追加
        sceneView.scene.rootNode.addChildNode(parent)
        
        // 平面の検出は停止
        let configuration = ARWorldTrackingConfiguration()
        sceneView.session.run(configuration)
        
        // ゲーム状況「スタート待ち」
        phase = .ready(stage: stage)
    }
    
    private func start() {
        let stage: SCNNode
        // プレイ開始
        switch phase {
        case let .ready(node), let .gameover(node, _): stage = node
        default: return
        }
        
        // ゲーム状況「スタート」
        sceneView.scene.physicsWorld.speed = 1
        phase = .play(stage: stage, score: 0)
        
        DispatchQueue.main.async { [weak self] in
            guard let `self` = self else { return }
            self.mainLabel.text = "START"
            // 1秒後にスタート非表示
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let `self` = self else { return }
                self.mainLabel.text = ""
                
                // 1秒後にボール発生開始
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    self?.spawnBall()
                }
            }
        }
    }
    
    private func spawnBall() {
        guard case let .play(stage, _) = phase else { return }
        
        // ボールを読み込み
        let ball = SCNNode()
        ball.name = "ball"
        guard let source = SCNScene(named: "ball.scn", inDirectory: "Models.scnassets/ball")?.rootNode else { fatalError() }
        source.childNodes.forEach { ball.addChildNode($0) }
        ball.position.x = (Float(arc4random()) / Float(UINT32_MAX)) * 4 - 2
        
        // ボールを発生場所に追加
        guard let spawn = stage.childNode(withName: "spawn", recursively: true) else { fatalError() }
        spawn.addChildNode(ball)
        
        // 1.5秒後にボール発生開始
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.spawnBall()
        }
    }
    
    private func addScore() {
        // 無事にボールを避けた場合
        guard case let .play(stage, score) = phase else { return }
        phase = .play(stage: stage, score: score + 1)
    }
    
    private func gameover() {
        // ボールにぶつかった場合
        guard case let .play(stage, score) = phase else { return }

        sceneView.scene.physicsWorld.speed = 0
        phase = .gameover(stage: stage, score: score)
    }
    
    private func updatePhase(old: Phase) {
        print("phase: \(old) => \(phase)")
        
        statusLabel.text = phase.status
        mainLabel.text = ""
        subLabel.text = ""
        scoreLabel.text = ""
        
        switch phase {
        case .initializing:
            subLabel.text = "Plaese wait ..."
        case .ready:
            mainLabel.text = "READY?"
            subLabel.text = "TAP TO START"
        case let .play(_, score):
            scoreLabel.text = "\(score)"
        case let .gameover(_, score):
            mainLabel.text = "GAME OVER"
            subLabel.text = "TAP TO RESTART"
            scoreLabel.text = "\(score)"
        default: break
        }
        
        let removeBalls = { (stage: SCNNode) in
            guard let spawn = stage.childNode(withName: "spawn", recursively: true) else { fatalError() }
            spawn.childNodes.forEach { $0.removeFromParentNode() }
        }
        
        switch old {
        case let .ready(stage), let .play(stage, _):
            switch phase {
            case .play, .gameover: break
            default:
                // ステージを削除
                stage.removeFromParentNode()
                // ボールが残っていれば削除
                removeBalls(stage)
            }
        case let .gameover(stage, _):
            removeBalls(stage)
        default: break
        }
    }
}

