// Copyright 2018 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import ARCoreCloudAnchors
import ARKit
import ReplayKit
import SceneKit
import UIKit

enum ViewMode {
    case DRAW
    case PAIR
    case TRACKING
}

class ViewController: UIViewController {
    // MARK: Properties

    /// store current touch location in view
    var touchPoint: CGPoint = .zero

    /// SCNNode floating in front of camera the distance drawing begins
    var hitNode: SCNNode?

    /// array of strokes a user has drawn in current session
    var strokes = [Stroke]()

    /// array of strokes a user has drawn in current session
    var partnerStrokes: [String: Stroke] = .init()

    /// Anchor created for pairing flow to host via cloud anchors
    var sharedAnchor: ARAnchor?

    var shouldRetryAnchorResolve = false

    /// Currently selected stroke size
    var strokeSize: Radius = .small

    /// After 3 seconds of tracking changes trackingMessage to escalated value
    var trackingMessageTimer: Timer?

    /// When session returns from interruption, hold time to limit relocalization
    var resumeFromInterruptionTimer: Timer?

    /// When in limited tracking mode, hold previous mode to return to
    var modeBeforeTracking: ViewMode?

    /// Most situations we show the looking message, but when relocalizing and currently paired, show anchorLost type
    var trackingMessage: TrackingMessageType = .looking

    /// capture first time establish tracking
    var hasInitialTracking = false

    var mode: ViewMode = .DRAW {
        didSet {
            switch mode {
            case .DRAW:
                // make sure we are not coming out of tracking, and that we are in a paired state
                if modeBeforeTracking != .DRAW, let isPaired = pairingManager?.isPairingOrPaired, isPaired == true {
                    uiViewController?.showDrawingPrompt(isPaired: true)
                } else if !strokes.isEmpty {
                    uiViewController?.hideDrawingPrompt()
                } else {
                    uiViewController?.showDrawingPrompt()
                }

                uiViewController?.drawingUIHidden(false)
                uiViewController?.stopTrackingAnimation()
                uiViewController?.messagesContainerView?.isHidden = true
                stateManager?.fullBackground.isHidden = true
                setStrokeVisibility(isHidden: false)
                UIAccessibility.post(notification: UIAccessibility.Notification.layoutChanged, argument: uiViewController?.touchView)

                #if DEBUG
                    sceneView.debugOptions = [ARSCNDebugOptions.showWorldOrigin]
                #else
                    sceneView.debugOptions = []
                #endif

            case .PAIR:
                uiViewController?.hideDrawingPrompt()
                uiViewController?.drawingUIHidden(true)
                uiViewController?.stopTrackingAnimation()
                uiViewController?.messagesContainerView?.isHidden = false
                stateManager?.fullBackground.isHidden = false
                setStrokeVisibility(isHidden: false)
                UIAccessibility.post(notification: UIAccessibility.Notification.screenChanged, argument: stateManager?.centerMessageLabel)

                #if DEBUG
                    sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints, ARSCNDebugOptions.showWorldOrigin]
                #else
                    sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints]
                #endif

            case .TRACKING:
                uiViewController?.hideDrawingPrompt()
                uiViewController?.startTrackingAnimation(trackingMessage)

                // hiding fullBackground hides everything except close button
                stateManager?.fullBackground.isHidden = true
                setStrokeVisibility(isHidden: true)
                uiViewController?.touchView.isHidden = true
                UIAccessibility.post(notification: UIAccessibility.Notification.layoutChanged, argument: uiViewController?.trackingPromptLabel)
            }

            // if we're tracking and the mode changes, update our previous mode state
            if modeBeforeTracking != nil, mode != .TRACKING {
                print("Updating mode to return to after tracking: \(mode)")
                modeBeforeTracking = mode
            }
        }
    }

    // MARK: Managers

    /// Coordinates all aspects of sharing
    var pairingManager: PairingManager?

    var stateManager: StateManager?

    // MARK: UI

    /// window with UI elements to keep them out of screen recording
    var uiWindow: UIWindow?

    /// view controller for ui elements
    var uiViewController: InterfaceViewController?

    // Video

    /// ReplayKit shared screen recorder
    var screenRecorder: RPScreenRecorder?

    /// writes CMSampleBuffer for screen recording
    var assetWriter: AVAssetWriter?

    /// holds asset writer settings for media
    var assetWriterInput: AVAssetWriterInput?

    /// temporary bool for toggling recording state
    var isRecording: Bool = false

    // swiftlint:disable:next private_outlet type_contents_order
    @IBOutlet var sceneView: ARSCNView!

    private var appDidBecomeActiveObserver: NSObjectProtocol?

    // MARK: Overridden Functions

    // MARK: - View State

    override func viewDidLoad() {
        super.viewDidLoad()

        pairingManager = PairingManager()
        pairingManager?.delegate = self

        // Set the view's delegate
        sceneView.delegate = self

        // Show statistics such as fps and timing information
//        sceneView.showsStatistics = true
//        sceneView.debugOptions = [ARSCNDebugOptions.showWorldOrigin]

        // Create a new scene
        let scene = SCNScene()

        // Set the scene to the view
        sceneView.scene = scene

        hitNode = SCNNode()
        // swiftlint:disable:next force_unwrapping
        hitNode!.position = SCNVector3Make(0, 0, -0.17)
        // swiftlint:disable:next force_unwrapping
        sceneView.pointOfView?.addChildNode(hitNode!)

        setupUI()
        screenRecorder = RPScreenRecorder.shared()
        screenRecorder?.isMicrophoneEnabled = true

        appDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil
        ) { _ in
            self.touchPoint = .zero
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        configureARSession()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        #if JOIN_GLOBAL_ROOM
            let globalRoomBase = GLOBAL_ROOM_ROOT + "/global_room"
            let alert = UIAlertController(title: "Global room session", message: "Please Choose Your Session", preferredStyle: .actionSheet)
            alert.addAction(UIAlertAction(title: "0 Sandbox A", style: .default, handler: { _ in
                self.pairingManager?.setGlobalRoomName(globalRoomBase + "_0")
                alert.dismiss(animated: true, completion: nil)
            }))
            alert.addAction(UIAlertAction(title: "1 Sandbox B", style: .default, handler: { _ in
                self.pairingManager?.setGlobalRoomName(globalRoomBase + "_1")
                alert.dismiss(animated: true, completion: nil)
            }))
            alert.addAction(UIAlertAction(title: "2 Dev", style: .default, handler: { _ in
                self.pairingManager?.setGlobalRoomName(globalRoomBase + "_2")
                alert.dismiss(animated: true, completion: nil)
            }))
            alert.addAction(UIAlertAction(title: "3 QA", style: .default, handler: { _ in
                self.pairingManager?.setGlobalRoomName(globalRoomBase + "_3")
                alert.dismiss(animated: true, completion: nil)
            }))
            self.uiViewController?.present(alert, animated: true, completion: nil)
        #endif
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Pause the view's session
        sceneView.session.pause()
    }

    // swiftlint:disable:next type_contents_order
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
        resetTouches()
    }

    // swiftlint:disable:next type_contents_order
    override func viewWillTransition(to _: CGSize, with _: UIViewControllerTransitionCoordinator) {
        touchPoint = .zero
    }

    // MARK: Lifecycle

    deinit {
        // Remove the observer
        if let observer = appDidBecomeActiveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: Functions

    // MARK: - View Configuration

    func configureARSession(runOptions: ARSession.RunOptions = []) {
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
//        configuration.isAutoFocusEnabled = false

        #if DEBUG
            sceneView.debugOptions = [ARSCNDebugOptions.showWorldOrigin]
        #endif

        // Run the view's session
        sceneView.session.run(configuration, options: runOptions)
        sceneView.session.delegate = self
    }

    /// Add new UIWindow with interface elements that forward touch events via the InterfaceViewControllerDelegate protocol
    func setupUI() {
        uiWindow = UIWindow(frame: UIScreen.main.bounds)
        let uiStoryboard = UIStoryboard(name: "UI", bundle: nil)
        uiViewController = uiStoryboard.instantiateInitialViewController() as? InterfaceViewController
        uiViewController?.touchDelegate = self
        uiWindow?.rootViewController = uiViewController

        uiWindow?.makeKeyAndVisible()
    }

    // MARK: - Stroke Code

    /// Places anchor on hitNode plane at point
    func makeAnchor(at point: CGPoint) -> ARAnchor? {
        guard let hitNode else {
            return nil
        }

        let projectedOrigin = sceneView.projectPoint(hitNode.worldPosition)
        let offset = sceneView.unprojectPoint(SCNVector3Make(Float(point.x), Float(point.y), projectedOrigin.z))

        var blankTransform = matrix_float4x4(1)
//        var transform = hitNode.simdWorldTransform
        blankTransform.columns.3.x = offset.x
        blankTransform.columns.3.y = offset.y
        blankTransform.columns.3.z = offset.z

        return ARAnchor(transform: blankTransform)
    }

    /// Updates stroke with new SCNVector3 point, and regenerates line geometry
    func updateLine(for stroke: Stroke) {
        guard stroke.points.last != nil, let strokeNode = stroke.node else {
            return
        }

        let offset = unprojectedPosition(for: stroke, at: touchPoint)
        let newPoint = strokeNode.convertPosition(offset, from: sceneView.scene.rootNode)

        stroke.lineWidth = strokeSize.rawValue
        if stroke.add(point: newPoint) {
            pairingManager?.updateStroke(stroke)
            updateGeometry(stroke)
        }
    }

    func updateGeometry(_ stroke: Stroke) {
        if stroke.positionsVec3.count > 4 {
            let vectors = stroke.positionsVec3
            let sides = stroke.mSide
            let width = stroke.mLineWidth
            let lengths = stroke.mLength
            let totalLength = (stroke.drawnLocally) ? stroke.totalLength : stroke.animatedLength
            let line = LineGeometry(
                vectors: vectors,
                sides: sides,
                width: width,
                lengths: lengths,
                endCapPosition: totalLength
            )

            stroke.node?.geometry = line
            uiViewController?.hasDrawnInSession = true
            uiViewController?.hideDrawingPrompt()
        }
    }

    // Stroke Helper Methods
    func unprojectedPosition(for _: Stroke, at touch: CGPoint) -> SCNVector3 {
        guard let hitNode = self.hitNode else {
            return SCNVector3Zero
        }

        let projectedOrigin = sceneView.projectPoint(hitNode.worldPosition)
        // Offset
        return sceneView.unprojectPoint(SCNVector3Make(Float(touch.x), Float(touch.y), projectedOrigin.z))
    }

    /// Checks user's strokes for match, then partner's strokes
    func getStroke(for anchor: ARAnchor) -> Stroke? {
        var matchStrokeArray = strokes.filter { stroke -> Bool in
            return stroke.anchor == anchor
        }

        if matchStrokeArray.isEmpty {
            for (_, stroke) in partnerStrokes where stroke.anchor == anchor {
                matchStrokeArray.append(stroke)
            }
        }

        return matchStrokeArray.first
    }

    /// Checks user's strokes for match, then partner's strokes
    func getStroke(for node: SCNNode) -> Stroke? {
        var matchStrokeArray = strokes.filter { stroke -> Bool in
            return stroke.node == node
        }

        if matchStrokeArray.isEmpty {
            for (_, stroke) in partnerStrokes where stroke.node == node {
                matchStrokeArray.append(stroke)
            }
        }

        return matchStrokeArray.first
    }

    func setStrokeVisibility(isHidden: Bool) {
        strokes.forEach { stroke in
            stroke.node?.isHidden = isHidden
        }
        partnerStrokes.forEach { _, partnerStroke in
            partnerStroke.node?.isHidden = isHidden
        }
    }
}
