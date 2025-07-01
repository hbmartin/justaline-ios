// swiftlint:disable type_contents_order private_outlet type_body_length file_length
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

import FirebaseAnalytics
import UIKit

protocol InterfaceViewControllerDelegate: AnyObject {
    func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?)
    func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?)
    func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?)
    func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?)

    func recordTapped(sender: UIButton?)
    func undoLastStroke(sender: UIButton?)
    func clearStrokesTapped(sender: UIButton?)
    func strokeSizeChanged(_ radius: Radius)
    func stopRecording()
    func joinButtonTapped(sender: UIButton?)
    func stateViewLoaded(_ stateManager: StateManager)
    func shouldHideTrashButton() -> Bool
    func shouldHideUndoButton() -> Bool
    func beginGlobalSession(_ withPairing: Bool)
    func shouldPresentPairingChooser() -> Bool
    func resetTouches()

    var shouldAutorotate: Bool { get }
}

enum PairButtonState {
    case unpaired
    case connected
    case lost
}

enum TrackingMessageType {
    case looking
    case lookingEscalated
    case anchorLost
}

class TouchView: UIView {
    // MARK: Properties

    weak var touchDelegate: InterfaceViewController?

    // MARK: Overridden Functions

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchDelegate?.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchDelegate?.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let delegate = touchDelegate {
            delegate.touchesEnded(touches, with: event)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchDelegate?.touchesCancelled(touches, with: event)
    }
}

class InterfaceViewController: UIViewController, OverflowViewControllerDelegate, GlobalPairingChooserDelegate, PairingChooserDelegate {
    // MARK: Overridden Properties

    override var shouldAutorotate: Bool {
        if let touchDelegate, touchDelegate.shouldAutorotate == false {
            return false
        }
        return true
    }

    // MARK: Properties

    @IBOutlet var touchView: TouchView!
    @IBOutlet var progressCircle: ProgressView!
    @IBOutlet var recordBackgroundView: UIView!
    @IBOutlet var clearAllButton: UIButton!
    @IBOutlet var pairButton: UIButton!
    @IBOutlet var undoButton: UIButton!
    @IBOutlet var messagesContainerView: UIView!
    @IBOutlet var trackingPromptLabel: UILabel!
    weak var touchDelegate: InterfaceViewControllerDelegate?
    var hasDrawnInSession: Bool = false
    var pairButtonState: PairButtonState = .unpaired
    var recordingTimer: Timer?

    let pairedLabelBlue = UIColor(red: 37 / 255, green: 85 / 255, blue: 255 / 255, alpha: 1.0)
    let pairedLabelBlack = UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.5)

    @IBOutlet private var trackingImage: UIImageView!
    @IBOutlet private var trackingImageCenterConstraint: NSLayoutConstraint!

    @IBOutlet private var recordButton: UIButton!
    @IBOutlet private var recordIconView: UIView!
    @IBOutlet private var chooseSizeButton: UIButton!
    @IBOutlet private var overflowButton: UIButton!
    @IBOutlet private var sizeButtonStackView: UIStackView!
    @IBOutlet private var sizeStackViewBottomConstraint: NSLayoutConstraint!
    @IBOutlet private var recordButtonBottomConstraint: NSLayoutConstraint!
    @IBOutlet private var drawPromptContainer: UIView!
    @IBOutlet private var drawPromptLabel: UILabel!
    @IBOutlet private var trackingPromptContainer: UIView!
    @IBOutlet private var pairedStateLabel: UILabel!
    @IBOutlet private var largeBrushButton: UIButton!
    @IBOutlet private var mediumBrushButton: UIButton!
    @IBOutlet private var smallBrushButton: UIButton!

    // MARK: Overridden Functions

    override func viewDidLoad() {
        super.viewDidLoad()

        touchView.touchDelegate = self

        recordBackgroundView.alpha = 0
        sizeButtonStackView.alpha = 0
        drawPromptContainer.alpha = 0

        // forces hiding of recording ui for global version
        drawingUIHidden(false)

        #if JOIN_GLOBAL_ROOM
            recordButtonBottomConstraint.constant = 0
        #else
            recordButtonBottomConstraint.constant = 20
        #endif

        selectSize(.medium)

        configureAccessibility()
    }

    /*
     // MARK: - Navigation

     // In a storyboard-based application, you will often want to do a little preparation before navigation
     override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
         // Get the new view controller using segue.destinationViewController.
         // Pass the selected object to the new view controller.
     }
     */

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchDelegate?.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchDelegate?.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let delegate = touchDelegate {
            delegate.touchesEnded(touches, with: event)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchDelegate?.touchesCancelled(touches, with: event)
    }

    override func prepare(for segue: UIStoryboardSegue, sender _: Any?) {
        self.touchDelegate?.resetTouches()

        if segue.identifier == "stateMessageSegue" {
            // swiftlint:disable:next force_cast
            self.touchDelegate?.stateViewLoaded(segue.destination as! StateManager)
        }

        if segue.identifier == "overflowSegue" {
            if let overflow = segue.destination as? OverflowViewController {
                overflow.delegate = self
            }
        }

        if segue.identifier == "globalPairingChooserSegue" {
            if let chooser = segue.destination as? GlobalPairingChooser {
                chooser.delegate = self
            }
        }

        if segue.identifier == "pairingChooserSegue" {
            if let chooser = segue.destination as? PairingChooser {
                chooser.delegate = self
            }
        }
    }

    // MARK: Functions

    func configureAccessibility() {
        undoButton.accessibilityLabel = NSLocalizedString("content_description_undo", comment: "Undo")
        overflowButton.accessibilityLabel = NSLocalizedString("menu_overflow", comment: "Options")
        clearAllButton.accessibilityLabel = NSLocalizedString("menu_clear", comment: "Clear Drawing")
        chooseSizeButton.accessibilityLabel = NSLocalizedString("content_description_select_brush", comment: "Choose Brush Size")
        pairButton.accessibilityLabel = NSLocalizedString("content_description_join", comment: "Join a Friend")
        largeBrushButton.accessibilityLabel = NSLocalizedString("content_description_large_brush", comment: "Large Brush")
        mediumBrushButton.accessibilityLabel = NSLocalizedString("content_description_medium_brush", comment: "Medium Brush")
        smallBrushButton.accessibilityLabel = NSLocalizedString("content_description_small_brush", comment: "Small Brush")

        let key = NSAttributedString.Key(
            rawValue: NSAttributedString.Key.accessibilitySpeechIPANotation.rawValue
        )
        let attributedString = NSAttributedString(
            string: NSLocalizedString("content_description_record", comment: "Record"), attributes: [key: "rəˈkɔrd"]
        )

        recordButton.accessibilityAttributedLabel = attributedString
        recordButton.accessibilityHint = NSLocalizedString("content_description_record_accessible", comment: "Tap to record a video for ten seconds.")

        // swiftlint:disable:next legacy_objc_type
        NotificationCenter.default.addObserver(self, selector: #selector(voiceOverStatusChanged), name: NSNotification.Name.STATE_CHANGED, object: nil)

        voiceOverStatusChanged()
    }

    @objc
    func voiceOverStatusChanged() {
        sizeButtonStackView.alpha = (UIAccessibility.isVoiceOverRunning) ? 1 : 0
    }

    func selectSize(_ size: Radius) {
        UIView.animate(withDuration: 0.25) {
            self.sizeButtonStackView.alpha = (UIAccessibility.isVoiceOverRunning) ? 1 : 0
            if self.sizeButtonStackView.alpha == 0 {
                self.sizeStackViewBottomConstraint.constant = 10
            }
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.sizeStackViewBottomConstraint.constant = 18
            switch size {
            case .small:
                self.chooseSizeButton.setImage(UIImage(named: "brushSmall"), for: .normal)

            case .medium:
                self.chooseSizeButton.setImage(UIImage(named: "brushMedium"), for: .normal)

            case .large:
                self.chooseSizeButton.setImage(UIImage(named: "brushLarge"), for: .normal)
            }
            self.touchDelegate?.strokeSizeChanged(size)
        }
    }

    func drawingUIHidden(_ isHidden: Bool) {
        var forceHidden = false
        #if JOIN_GLOBAL_ROOM
            forceHidden = true
        #endif

        // hide record from stage version only
        progressCircle.isHidden = forceHidden ? true : isHidden
        recordBackgroundView.isHidden = forceHidden ? true : isHidden
        recordButton.isHidden = forceHidden ? true : isHidden
        recordIconView.isHidden = forceHidden ? true : isHidden
        touchView.isHidden = isHidden
        overflowButton.isHidden = isHidden
        chooseSizeButton.isHidden = isHidden
        sizeButtonStackView.isHidden = isHidden
        pairButton.isHidden = isHidden

        // trash and undo are dependent on strokes for the visibility
        if let delegate = touchDelegate {
            clearAllButton.isHidden = (isHidden == true) ? true : delegate.shouldHideTrashButton()
            undoButton.isHidden = (isHidden == true) ? true : delegate.shouldHideUndoButton()
        }

        // Pair button label needs to maintain its visibility state across UI hide/show
        if isHidden == true {
            pairedStateLabel.isHidden = true
        } else {
            updatePairButtonState(pairButtonState)
        }
    }

    func showDrawingPrompt(isPaired: Bool = false) {
        if isPaired {
            drawPromptLabel.text = NSLocalizedString("draw_prompt_paired", comment: "Start drawing with your partner")
            touchView.accessibilityLabel = NSLocalizedString("draw_prompt_paired", comment: "Start drawing with your partner")

            drawPromptLabel.isHidden = false
        } else {
            drawPromptLabel.text = NSLocalizedString("draw_prompt", comment: "Press your finger")
            touchView.accessibilityLabel = NSLocalizedString("draw_action_accessible", comment: "Draw")

            drawPromptLabel.isHidden = hasDrawnInSession
        }
        touchView.accessibilityHint = NSLocalizedString("draw_prompt_accessible", comment: "Double-tap and hold your finger and move around")

        UIView.animate(withDuration: 0.25) {
            self.drawPromptContainer.alpha = 1
        }
    }

    func hideDrawingPrompt() {
        UIView.animate(withDuration: 0.25) {
            self.drawPromptContainer.alpha = 0
        }
    }

    func updatePairButtonState(_ pairState: PairButtonState) {
        // only visually change the state label if the pair button is currently showing
        if pairButton.isHidden == false {
            switch pairState {
            case .unpaired:
                pairButton.setImage(UIImage(named: "partner_icon_default"), for: .normal)
                pairedStateLabel.layer.removeAllAnimations()
                pairedStateLabel.isHidden = true
                pairedStateLabel.backgroundColor = pairedLabelBlue
                pairedStateLabel.alpha = 1

            case .connected:
                pairButton.setImage(UIImage(named: "partner_icon_connected"), for: .normal)
                pairedStateLabel.layer.removeAllAnimations()
                pairedStateLabel.isHidden = false
                pairedStateLabel.backgroundColor = pairedLabelBlue
                pairedStateLabel.alpha = 1
                pairedStateLabel.text = NSLocalizedString("partner_icon_connected", comment: "PAIRED")

            case .lost:
                pairButton.setImage(UIImage(named: "partner_icon_lost_partner"), for: .normal)
                pairedStateLabel.isHidden = false
                pairedStateLabel.backgroundColor = pairedLabelBlack
                pairedStateLabel.text = NSLocalizedString("partner_icon_lost_partner", comment: "PARTNER\nLOST")
                UIView.animate(withDuration: 0.25, delay: 3.0, options: .curveLinear) {
                    self.pairedStateLabel.alpha = 0
                    self.pairedStateLabel.isHidden = self.pairButton.isHidden
                } completion: { complete in
                    if complete, self.pairButtonState != .connected {
                        self.pairedStateLabel.isHidden = true
                        self.pairedStateLabel.alpha = 1
                    }
                }
            }
        }
        pairButtonState = pairState
    }

    /// When tracking state is .notavailable or .limited, start tracking animation
    func startTrackingAnimation(_ trackingMessage: TrackingMessageType = .looking) {
        switch trackingMessage {
        case .looking:
            trackingPromptLabel.text = NSLocalizedString("tracking_indicator_text_looking", comment: "Looking for a place for your line")

        case .lookingEscalated:
            trackingPromptLabel.text = NSLocalizedString("tracking_indicator_text_cant_find", comment: "Can\'t find a place for your line")

        case .anchorLost:
            trackingPromptLabel.text = NSLocalizedString("tracking_indicator_text_anchor_not_tracking", comment: "Try going back to where you started.")
        }

//        trackingPromptContainer.alpha = 0
//        trackingPromptContainer.isHidden = false
        trackingPromptLabel.accessibilityLabel = trackingPromptLabel.text

        hideDrawingPrompt()

        // Fade in
        UIView.animate(withDuration: 0.25) {
            self.trackingPromptContainer.alpha = 1
        }

        // Loop right-left tracking animation
        UIView.animate(withDuration: 1.0, delay: 0, options: [.repeat, .curveEaseInOut, .autoreverse], animations: {
            self.trackingImageCenterConstraint.constant = 15

            self.trackingPromptContainer.layoutIfNeeded()
        })
    }

    /// When tracking state is .normal, end tracking animation
    func stopTrackingAnimation() {
        // Fade out
        UIView.animate(withDuration: 0.25) {
            self.trackingPromptContainer.alpha = 0

            // Reset state
        } completion: { _ in
//            self.trackingPromptContainer.isHidden = true
            self.trackingImageCenterConstraint.constant = -15
            self.trackingPromptContainer.layoutIfNeeded()
            self.trackingPromptContainer.layer.removeAllAnimations()
        }
    }

    func recordingWillStart() {
        DispatchQueue.main.async {
            self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false, block: { _ in
                DispatchQueue.main.async {
                    self.touchDelegate?.stopRecording()
                }
            })

            self.recordBackgroundView.alpha = 1
            self.recordBackgroundView.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)

            UIView.animate(withDuration: 0.25) {
                self.recordBackgroundView.transform = .identity
                self.recordIconView.layer.cornerRadius = 0
            } completion: { _ in
                self.progressCircle.play(duration: 10.0)
            }
        }
    }

    func recordingHasEnded() {
        if let timer = recordingTimer {
            timer.invalidate()
        }
        recordingTimer = nil

        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.25) {
                self.recordIconView.layer.cornerRadius = 6
                self.recordBackgroundView.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            }
        }
    }

    func shareButtonTapped(_: UIButton) {
        // swiftlint:disable:next force_unwrapping
        let url = URL(string: NSLocalizedString("share_app_message", comment: "https://g.co/justaline"))!
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        present(activity, animated: true, completion: nil)

        Analytics.logEvent(AnalyticsKey.val(.tapped_share_app), parameters: nil)
    }

    func aboutButtonTapped(_: UIButton) {
        performSegue(withIdentifier: "aboutSegue", sender: nil)
    }

    func shouldBeginGlobalSession(withPairing: Bool) {
        self.touchDelegate?.beginGlobalSession(withPairing)
    }

    func shouldBeginPartnerSession() {
        self.touchDelegate?.joinButtonTapped(sender: nil)
    }

    @IBAction private func recordTapped(_ sender: UIButton) {
        touchDelegate?.recordTapped(sender: sender)
    }

    @IBAction private func undoLastStroke(_ sender: UIButton) {
        touchDelegate?.undoLastStroke(sender: sender)
    }

    @IBAction private func clearAllStrokes(_ sender: UIButton) {
        touchDelegate?.clearStrokesTapped(sender: sender)
    }

    @IBAction private func chooseSizeTapped(_: UIButton) {
        let newAlpha = (sizeButtonStackView.alpha == 0) ? 1 : 0
        UIView.animate(withDuration: 0.25, animations: {
            self.sizeButtonStackView.alpha = CGFloat(newAlpha)
        })
    }

    @IBAction private func smallSizeTapped(_: UIButton) {
        selectSize(.small)
    }

    @IBAction private func mediumSizeTapped(_: UIButton) {
        selectSize(.medium)
    }

    @IBAction private func largeSizeTapped(_: UIButton) {
        selectSize(.large)
    }

    @IBAction private func joinButtonTapped(_ sender: UIButton) {
        #if JOIN_GLOBAL_ROOM
            if let presentChooser = self.touchDelegate?.shouldPresentPairingChooser(), presentChooser == true {
                self.performSegue(withIdentifier: "globalPairingChooserSegue", sender: self)
            } else {
                self.touchDelegate?.joinButtonTapped(sender: sender)
            }
        #else
//        self.touchDelegate?.joinButtonTapped(sender: sender)
            if let presentChooser = self.touchDelegate?.shouldPresentPairingChooser(), presentChooser == true {
                self.performSegue(withIdentifier: "pairingChooserSegue", sender: self)
            } else {
                self.touchDelegate?.joinButtonTapped(sender: sender)
            }
        #endif
    }

    // swiftlint:disable:next no_empty_block
    @IBAction private func unwindAboutSegue(_: UIStoryboardSegue) {}
}
