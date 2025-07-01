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
import WebKit

class LicensesViewController: UIViewController, WKNavigationDelegate {
    // MARK: Properties

    var homeURL: URL?

    @IBOutlet private var webView: WKWebView!

    // MARK: Overridden Functions

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        if let path = Bundle.main.path(forResource: "thirdPartyLicenses.html", ofType: "") {
            homeURL = URL(fileURLWithPath: path)
            // swiftlint:disable:next force_unwrapping
            webView.loadFileURL(homeURL!, allowingReadAccessTo: homeURL!)
            webView.navigationDelegate = self
        }
    }

    // MARK: Functions

    func webView(_ _: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, url != homeURL {
            decisionHandler(.cancel)
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        } else {
            decisionHandler(.allow)
        }
    }

    /*
     // MARK: - Navigation

     // In a storyboard-based application, you will often want to do a little preparation before navigation
     override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
         // Get the new view controller using segue.destinationViewController.
         // Pass the selected object to the new view controller.
     }
     */
}
