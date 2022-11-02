//
//  WebkitWrapper.swift
//  YoopUI
//
//  Created by Mason Phillips on 10/26/22.
//  Copyright © 2022 enovLAB. All rights reserved.
//

import UIKit
import WebKit
import Combine

/// A method of sending a message to the webview
public struct Message<T: Codable>: Codable {
    public let name: String
    public let params: T

    init(name: String, params: T) {
        self.name = name
        self.params = params
    }

    init?(dictionary: Dictionary<String, Any>) {
        guard
            let name = dictionary["name"] as? String,
            let params = dictionary["params"] as? T
        else { return nil }

        self.name = name
        self.params = params
    }
}

/// Responses used by YoopUI.YUIWebViewWrapper when executing a script
public typealias WebkitResponse = (Any?, Error?)

public protocol YUIWebViewType {
    var webView: WKWebView { get }
    var isWebviewOpaque: Bool { get set }
    var isLoading: Bool { get }
    var isExecuting: Bool { get }

    func reload()
    func showWebView()
    func evaluate(_ script: String, completionHandler: ((WebkitResponse) -> Void)?)
    func execute(_ function: String, with params: String?..., completionHandler: ((WebkitResponse) -> Void)?)
    func post<T: Codable>(message: Message<T>) throws
}

/// A wrapped WKWebkitView with default behavior and exposed interaction
open class YUIWebViewWrapper: UIView, YUIWebViewType {
    /// A tracker for running js calls sent to the browser
    public let operationsQueue = OperationQueue()

    /// The webview this view wraps
    public let webView = WKWebView()

    /// The location the webview is navigating to
    public let mapUrl: URL

    /// Whether the webview should be opaque
    public var isWebviewOpaque: Bool = false {
        didSet { self.layoutSubviews() }
    }
    /// Whether the webview is loading content
    public var isLoading: Bool {
        self._isLoading
    }
    /// Whether the webview is executing javascript in the queue
    public var isExecuting: Bool {
        self._isExecuting
    }

    private let eventPublisher = PassthroughSubject<Dictionary<String, Any>?, Error>()
    private var bag = Set<AnyCancellable>()

    private var _isLoading: Bool = true {
        didSet { suspendQueueIfNeeded() }
    }
    private var _isExecuting: Bool = false {
        didSet { suspendQueueIfNeeded() }
    }

    public init(mapUrl: URL) {
        self.mapUrl = mapUrl

        super.init(frame: .zero)

        operationsQueue.isSuspended = true
        operationsQueue.qualityOfService = .userInteractive
        operationsQueue.maxConcurrentOperationCount = 1

        let source = "function captureLog(msg) { window.webkit.messageHandlers.logHandler.postMessage(msg); } window.console.log = captureLog;"
        let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        webView.configuration.userContentController.addUserScript(script)
        // register the bridge script that listens for the output
        webView.configuration.userContentController.add(self, name: "logHandler")

        webView.configuration.userContentController.add(self, name: "seatmapClient")

        reload()
        suspendQueueIfNeeded()
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        operationsQueue.cancelAllOperations()
        bag.forEach { $0.cancel() }
    }

    // MARK: - Webview Control

    /// Reloads the webview with the currently stored URL
    open func reload() {
        _isLoading = true
        webView.load(URLRequest(url: mapUrl))
    }

    /// Display the webview in its parent, injecting an animation into the webview and transitioning from invisible
    open func showWebView() {
        evaluate(
            """
                var sheet = window.document.styleSheets[0];
                sheet.insertRule('* { transition: background 0.25s ease }', sheet.cssRules.length);
            """
        )
        // TODO(mason): Eventually, move the UIView extensions into YUI lib
        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState],
            animations: { [weak self] in
                self?.webView.alpha = 1
            },
            completion: nil
        )
    }

    // MARK: - Webview Communication

    /// Runs a script in the context of the webview
    ///
    /// - Parameters:
    ///   - script: The script to be run, as a string
    ///   - completionHandler: An optional handler for when the operation completes
    public func evaluate(_ script: String, completionHandler: ((WebkitResponse) -> Void)? = nil) {
        operationsQueue.addOperation(BlockOperation { [weak self] in
            self?._isExecuting = true

            DispatchQueue.main.async {
                self?.webView.evaluateJavaScript(script) {
                    completionHandler?(($0, $1))
                    self?._isExecuting = false
                }
            }
        })
    }

    /// Execute a function in the context of the webview, including params
    ///
    /// - Parameters:
    ///   - function: The name of the function to be called
    ///   - params: The positional parameters to be included
    ///   - completionHandler: An optional handler for when the operation completes
    public func execute(_ function: String, with params: String?..., completionHandler: ((WebkitResponse) -> Void)? = nil) {
        let params = params.map { $0 ?? "null" }.joined(separator: ",")
        let js = "\(function)(\(params))"
        evaluate(js, completionHandler: completionHandler)
    }

    /// Register a subject to listen for messages from the webview. Data will automatically be
    /// decoded, and any decoding errors will need to be handled by the subscriber.
    /// - Parameters:
    ///   - messageName: The message name to listen for
    ///   - subscriber: The subject that will handle incoming messages
    public func register<T>(for messageName: String, subscriber: any Subject<T, Error>) where T: Codable {
        eventPublisher
            .compactMap { $0 }
            .compactMap { Message<T>(dictionary: $0) }
            .filter { $0.name == messageName }
            .map { $0.params }
            .subscribe(subscriber)
            .store(in: &bag)
    }

    /// Send a message to the webview. Use the `Message<T>` struct for the correct structure
    /// - Parameter message: The message to be sent
    public func post<T: Codable>(message: Message<T>) throws {
        let data = try JSONEncoder().encode(message)

        guard let message = String(data: data, encoding: .utf8) else {
            return
        }

        evaluate("window.postMessage(\(message));")
    }

    // MARK: - Helpers

    /// Takes a URL and parses query params that appear after `#`
    ///
    /// Query parameters normally follow `?`, and Apple's URL parsing ignores anything
    /// after a `#`, which is what the internal javascript implementation uses. This workaround
    /// allows us to parse params like `https://example.com/#foo=bar`
    ///
    /// - Parameter originalURL: The original URL to parse
    /// - Returns: Parsed query items, if possible
    public func fragmentQueryParameters(url originalURL: URL?) -> [URLQueryItem]? {
        guard
            let originalURL = originalURL,
            let originalUrlComponents = URLComponents(url: originalURL,
                                                      resolvingAgainstBaseURL: false)
        else { return nil }

        guard
            let url = URL(string: "http://example.com?\(originalUrlComponents.fragment ?? "")")
        else { return nil }

        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    }

    // MARK: - Layout

    open override func layoutSubviews() {
        super.layoutSubviews()

        webView.frame = self.bounds
        webView.alpha = 0
        webView.isOpaque = isOpaque
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.autoresizingMask = [
            .flexibleWidth, .flexibleHeight
        ]
    }

    // MARK: - Private operations

    private func suspendQueueIfNeeded() {
        operationsQueue.isSuspended = isLoading || isExecuting
    }
}

extension YUIWebViewWrapper: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self._isLoading = false
    }
}

extension YUIWebViewWrapper: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if (message.name == "logHandler") {
            print("LOG: \(message.body)")  
        } else {
            print(message.body)
            eventPublisher.send(message.body as? Dictionary<String, Any>)
        }
    }
}

