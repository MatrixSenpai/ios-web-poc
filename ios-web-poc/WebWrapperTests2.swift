//
//  WebWrapperTests.swift
//  YoopUITests
//
//  Created by Mason Phillips on 11/1/22.
//  Copyright © 2022 enovLAB. All rights reserved.
//

import XCTest
import Combine
@testable import ios_web_poc

// A small hack to override reload() and load a file instead
class TestableYUIWebViewWrapper: YUIWebViewWrapper {
    override func reload() {
        super.reload()
        webView.stopLoading()
        webView.loadFileURL(mapUrl, allowingReadAccessTo: mapUrl)
    }
}

final class WebWrapperTests: XCTestCase {
    var webview: TestableYUIWebViewWrapper!

    let responseSubject = CurrentValueSubject<Int, Error>(-1)
    let postSubject = CurrentValueSubject<String, Error>("")

    var bag = Set<AnyCancellable>()

    override func setUpWithError() throws {
        try super.setUpWithError()

        let bundle = Bundle(for: Self.classForCoder())
        let path = bundle.url(forResource: "webview_test", withExtension: "html")!

        webview = TestableYUIWebViewWrapper(mapUrl: path)

        webview.register(for: "response", subscriber: responseSubject)
        webview.register(for: "handled", subscriber: postSubject)

        responseSubject.sink(receiveCompletion: {_ in}) { v in
            print(">>>>> \(v)")
        }.store(in: &bag)
        postSubject.sink(receiveCompletion: { _ in }) { v in
            print(">>>>> \(v)")
        }.store(in: &bag)
    }

    func testWebviewCommunication() throws {
        let postExpectation = XCTestExpectation(description: "Post subject should have correct value (some value)")

        let responseExpectation = XCTestExpectation(description: "Response subject should have correct value (42)")
        responseExpectation.assertForOverFulfill = true

        postSubject
            .dropFirst()
            .sink(receiveCompletion: { _ in }) { value in
                XCTAssertEqual(value, "some value")
                postExpectation.fulfill()
            }
            .store(in: &bag)

        responseSubject
            .dropFirst()
            .sink(receiveCompletion: { _ in }) { value in
                XCTAssertEqual(value, 42)
                responseExpectation.fulfill()
            }
            .store(in: &bag)

        webview.reload()
        webview.webView.publisher(for: \.isLoading)
            .filter { !$0 }
            .sink { _ in
                do {
                    try self.webview.post(message: Message(name: "request", params: ["value": 42]))
                } catch { print(">>>>> \(error)") }
            }
            .store(in: &bag)

        wait(for: [postExpectation, responseExpectation], timeout: 100.0)
    }
}


