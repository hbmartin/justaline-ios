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

import ARCore

extension ViewController: PairingManagerDelegate {
    func cloudAnchorResolved(_ anchor: GARAnchor) {
        print("World Origin Updated")
        shouldRetryAnchorResolve = false
        if !isTracking() {
            exitTrackingState()
        }
        sceneView.session.setWorldOrigin(relativeTransform: anchor.transform)
    }

    func createAnchor() {
        print("createAnchor")
        if let anchor = makeAnchor(at: view.center) {
            sharedAnchor = anchor
            pairingManager?.setAnchor(anchor)

            mode = .PAIR
        } else {
            print("ViewController:createAnchor: There was a problem creating a shared anchor")
        }
    }

    func anchorWasReset() {
        print("anchorWasReset")
        uiViewController?.updatePairButtonState(.unpaired)
        let alert = UIAlertController(
            title: NSLocalizedString("drawing_session_ended_title", comment: "Session Reset"),
            message: NSLocalizedString("drawing_session_ended_message", comment: "The drawing session has been reset"),
            preferredStyle: .alert
        )

        let okAction = UIAlertAction(title: NSLocalizedString("ok", comment: "OK"), style: .default) { _ in
            alert.dismiss(animated: true, completion: nil)
        }
        alert.addAction(okAction)
        uiViewController?.present(alert, animated: true, completion: nil)
    }

    func localStrokeRemoved(_ stroke: Stroke) {
        if let localAnchor = stroke.anchor {
            sceneView.session.remove(anchor: localAnchor)
            print("Local stroke removed: \(String(describing: stroke))")
        }
    }

    func addPartnerStroke(_ stroke: Stroke, key: String) {
        // coordinate system for ARKit is relative to anchor
        stroke.prepareLine()
        partnerStrokes[key] = stroke
        print("Partner stroke added: \(stroke)")

        guard let anchor = stroke.anchor else {
            print("ViewController:addPartnerStroke: Could not add stroke anchor")
            return
        }

        sceneView.session.add(anchor: anchor)
    }

    func partnerStrokeUpdated(_ stroke: Stroke, id key: String) {
        if partnerStrokes[key] == nil {
            addPartnerStroke(stroke, key: key)
        } else {
            partnerStrokes[key]?.points = stroke.points
            partnerStrokes[key]?.prepareLine()
        }
    }

    func partnerJoined(isHost _: Bool) {
        print("ViewController: partnerJoined")
        uiViewController?.updatePairButtonState(.connected)
    }

    func partnerLost() {
        uiViewController?.updatePairButtonState(.lost)
    }

    func partnerStrokeRemoved(id key: String) {
        if let partnerAnchor = partnerStrokes[key]?.anchor {
            sceneView.session.remove(anchor: partnerAnchor)
            print("Partner stroke removed: \(String(describing: partnerStrokes[key]))")
        }
    }

    func isTracking() -> Bool {
        mode == .TRACKING
    }
}
