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
import ReplayKit

extension ViewController: RPScreenRecorderDelegate {
    func screenRecorderDidChangeAvailability(_ screenRecorder: RPScreenRecorder) {
        if screenRecorder.isAvailable == false {
            let alert = UIAlertController(title: "Screen Recording Failed", message: "Screen Recorder is no longer available.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Ok", style: .default, handler: { _ in
                self.dismiss(animated: true, completion: nil)
            }))
            self.present(self, animated: true, completion: nil)
        }
    }
}

extension ViewController: RPPreviewViewControllerDelegate {
    func previewController(_ previewController: RPPreviewViewController, didFinishWithActivityTypes activityTypes: Set<String>) {
        if activityTypes.contains(UIActivity.ActivityType.saveToCameraRoll.rawValue) {
            Analytics.logEvent(AnalyticsKey.val(.tapped_save), parameters: nil)
        } else if activityTypes.contains(UIActivity.ActivityType.postToVimeo.rawValue)
                    || activityTypes.contains(UIActivity.ActivityType.postToFlickr.rawValue)
                    || activityTypes.contains(UIActivity.ActivityType.postToWeibo.rawValue)
                    || activityTypes.contains(UIActivity.ActivityType.postToTwitter.rawValue)
                    || activityTypes.contains(UIActivity.ActivityType.postToFacebook.rawValue)
                    || activityTypes.contains(UIActivity.ActivityType.mail.rawValue)
                    || activityTypes.contains(UIActivity.ActivityType.message.rawValue) {
            Analytics.logEvent(AnalyticsKey.val(.tapped_share_recording), parameters: nil)
        }

        uiViewController?.progressCircle.reset()
        uiViewController?.recordBackgroundView.alpha = 0

        previewController.dismiss(animated: true) {
            self.uiWindow?.isHidden = false
        }
    }
}
