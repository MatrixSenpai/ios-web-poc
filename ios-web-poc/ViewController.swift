//
//  ViewController.swift
//  ios-web-poc
//
//  Created by Mason Phillips on 10/20/22.
//

import UIKit
import WebKit
import Combine

class ViewController: UIViewController, WKNavigationDelegate {

    @IBOutlet weak var webView: WKWebView!

    var bag = Set<AnyCancellable>()

    override func viewDidLoad() {
        super.viewDidLoad()

//        let urlRequest = URLRequest(url: URL(string: "https://seatmap.dev.yoop.app/seating/seatingChart")!)
//        webView.load(urlRequest)
//        webView.navigationDelegate = self
//        webView.configuration.userContentController.add(self, name: "seatmapClient")
//
//        webView.publisher(for: \.isLoading, options: [.new])
//            .delay(for: 0.2, scheduler: DispatchQueue.main)
//            .sink { [unowned self] value in
//                guard !value else { return }
//                webView.evaluateJavaScript("window.postMessage({\"name\":\"setMessagePort\", \"params\": {\"webkitHandlerName\": \"seatmapClient\"}})")
//                webView.evaluateJavaScript("window.postMessage(\(configureString))")
//            }
//            .store(in: &bag)
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
        print(message.name, message.body)
    }
}
