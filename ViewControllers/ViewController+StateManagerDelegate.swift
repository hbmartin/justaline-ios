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

import UIKit

extension ViewController: StateManagerDelegate {
    func stateChangeCompleted(_: State) {
        if shouldShowTrackingIndicator() {
            enterTrackingState()
        } else {
            exitTrackingState()
        }
    }

    func attemptPartnerDiscovery() {
        #if JOIN_GLOBAL_ROOM
            pairingManager?.beginGlobalSession(true)
        #else
            pairingManager?.beginPairing()
        #endif
    }

    func anchorDrawingTryAgain() {
//        mode = .DRAW_ANCHOR
    }

    func pairingFinished() {
        uiViewController?.pairButton.accessibilityLabel = NSLocalizedString("content_description_disconnect", comment: "Disconnect")

        mode = .DRAW
        uiViewController?.updatePairButtonState(.connected)
    }

    func pairCancelled() {
        // reset pairing button accessibility to original state
        uiViewController?.configureAccessibility()

        pairingManager?.cancelPairing()

        shouldRetryAnchorResolve = false
        if shouldShowTrackingIndicator() {
            // when cancelling pairing while tracking, we need to act like we came from .DRAW mode, not .PAIR mode
            modeBeforeTracking = .DRAW
            uiViewController?.messagesContainerView.isHidden = true
            uiViewController?.drawingUIHidden(false)
            mode = .TRACKING
        } else {
            mode = .DRAW
        }
        uiViewController?.updatePairButtonState(.unpaired)
    }

    func retryResolvingAnchor() {
        if shouldRetryAnchorResolve {
            pairingManager?.retryResolvingAnchor()
        }
    }

    func onReadyToSetAnchor() {
        pairingManager?.setReadyToSetAnchor()
        //        Analytics.logEvent(AnalyticsKey.val(.tapped_ready_to_set_anchor), parameters: nil)
    }

    func offlineDetected() {
        if mode != .PAIR {
            self.pairCancelled()
            self.clearAllStrokes()
            let alert = UIAlertController(
                title: NSLocalizedString("pair_no_data_connection_title", comment: "No Connection"),
                message: NSLocalizedString("pair_no_data_connection", comment: "Looks like it\' pen and paper"),
                preferredStyle: .alert
            )

            let okAction = UIAlertAction(title: NSLocalizedString("ok", comment: "OK"), style: .default) { _ in
                alert.dismiss(animated: true, completion: nil)
            }
            alert.addAction(okAction)
            self.uiViewController?.present(alert, animated: true, completion: nil)
        }
    }
}
