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

protocol PairingChooserDelegate: AnyObject {
    func shouldBeginPartnerSession()
}

class PairingChooser: UIViewController {
    // MARK: Properties

    weak var delegate: PairingChooserDelegate?
    var offscreenContainerPosition: CGFloat = 0

    @IBOutlet private var overlayButton: UIButton!
    @IBOutlet private var buttonContainer: UIView!
    @IBOutlet private var joinButton: UIButton!
    @IBOutlet private var pairButton: UIButton!
    @IBOutlet private var cancelButton: UIButton!

    // MARK: Overridden Functions

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        offscreenContainerPosition = buttonContainer.frame.size.height
        pairButton.setTitle(NSLocalizedString("draw_with_partner", comment: "Draw with a partner"), for: .normal)
        cancelButton.setTitle(NSLocalizedString("cancel", comment: "Cancel"), for: .normal)
        print(offscreenContainerPosition)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        buttonContainer.transform = CGAffineTransform(translationX: 0, y: offscreenContainerPosition)
        UIView.animate(withDuration: 0.25) {
            self.buttonContainer.transform = .identity
        } completion: { _ in
            UIAccessibility.post(notification: UIAccessibility.Notification.layoutChanged, argument: self.pairButton)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIView.animate(withDuration: 0.35) {
            self.buttonContainer.transform = CGAffineTransform(translationX: 0, y: self.offscreenContainerPosition)
        }
    }

    // MARK: Functions

    @IBAction private func pairButtonTapped(_ _: UIButton) {
        self.dismiss(animated: true, completion: {
            self.delegate?.shouldBeginPartnerSession()
        })
    }

    @IBAction private func cancelTapped(_ _: UIButton) {
        self.dismiss(animated: true, completion: nil)
    }
}
