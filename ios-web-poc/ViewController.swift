//
//  ViewController.swift
//  ios-web-poc
//
//  Created by Mason Phillips on 10/20/22.
//

import UIKit
import WebKit

func delay(_ delay: Double = 1, closure: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + delay) {
        closure()
    }
}

class ViewController: UIViewController, WKNavigationDelegate {

    @IBOutlet weak var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()

        // Load in an html file written locally
//        let htmlFile = Bundle.main.url(forResource: "test-file", withExtension: "html")!
//        webView.loadFileURL(htmlFile, allowingReadAccessTo: htmlFile)
//        let request = URLRequest(url: htmlFile)
//        webView.load(request)

        var urlRequest = URLRequest(url: URL(string: "http://yoop-web-av-seatmap-3.oak.dev.yoop.app/seating/seatingChart")!)
        webView.load(urlRequest)
        webView.navigationDelegate = self
        webView.configuration.userContentController.add(self, name: "seatmapClient")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        delay(0.5) {
            webView.evaluateJavaScript("window.postMessage({\"name\":\"setMessagePort\", \"params\": {\"webkitHandlerName\": \"seatmapClient\"}})")
            webView.evaluateJavaScript("window.postMessage(\(configureString))")
        }

    }
}

struct Callback {
    var name: String

    struct Param {
        var name: String
    }
}

extension ViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "seatmapClient" {
            print("Button tapped: \(message.body)")
        }
    }
}
