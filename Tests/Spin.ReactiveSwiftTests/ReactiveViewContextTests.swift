//
//  ReactiveViewContextTests.swift
//  
//
//  Created by Thibault Wittemberg on 2020-01-08.
//

import Combine
import ReactiveSwift
import Spin_ReactiveSwift
import XCTest

fileprivate class MockContainer {

    var isRenderCalled = false

    func render(state: String) {
        self.isRenderCalled = true
    }
}

final class ReactiveViewContextTests: XCTestCase {

    private var cancellables = [AnyCancellable]()
    private let disposeBag = CompositeDisposable()

    func test_state_is_updated_when_feeding_the_resulting_feedback_with_an_input_state() throws {
        let exp = expectation(description: "new event")
        exp.expectedFulfillmentCount = 2

        var receivedState = ""

        // Given: a ViewContext (with an external rendering function) and its resulting feedback
        let sut = ReactiveViewContext<String, String>(state: "initial")
        let container = MockContainer()
        sut.render(on: container) { $0.render(state:) }

        // Make sure the render function is called directly after being set on the containe
        XCTAssertTrue(container.isRenderCalled)
        container.isRenderCalled = false
        
        let feedback = sut.toFeedback()

        sut.$state.sink { state in
            receivedState = state
            exp.fulfill()
        }.store(in: &self.cancellables)

        // When: feeding the resulting feedback with a state input stream
        feedback.feedbackStream(SignalProducer<String, Never>(value: "newState")).start().disposed(by: self.disposeBag)

        waitForExpectations(timeout: 5)

        // Then: the state is updated in the ViewContext and the external rendering function is called
        XCTAssertEqual(receivedState, "newState")
        XCTAssertTrue(container.isRenderCalled)
    }

    func test_event_is_output_by_the_feedback_when_sending_a_event_to_the_viewContext() throws {
        let exp = expectation(description: "new event")

        var receivedEvent = ""

        // Given: a ViewContext and its resulting feedback
        let sut = ReactiveViewContext<String, String>(state: "initial")
        let feedback = sut.toFeedback()

        feedback.feedbackStream(SignalProducer<String, Never>(value: "newState")).startWithValues{ event in
            receivedEvent = event
            exp.fulfill()
        }.disposed(by: self.disposeBag)

        // When: sending a event to the viewContext
        sut.emit("newEvent")
        waitForExpectations(timeout: 5)

        // Then: the resulting feedback outputs the event
        XCTAssertEqual(receivedEvent, "newEvent")
    }
}