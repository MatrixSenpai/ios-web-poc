//
//  ViewController.swift
//  ios-web-poc
//
//  Created by Mason Phillips on 10/20/22.
//

import UIKit
import WebKit

class ViewController: UIViewController {

    @IBOutlet weak var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()

        // Load in an html file written locally
        let htmlFile = Bundle.main.url(forResource: "test-file", withExtension: "html")!
        webView.loadFileURL(htmlFile, allowingReadAccessTo: htmlFile)
        let request = URLRequest(url: htmlFile)
        webView.load(request)

        webView.configuration.userContentController.add(self, name: "ios_buttonTapped")
    }
}

extension ViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "ios_buttonTapped" {
            print("Button tapped: \(message.body)")
        }
    }
}
