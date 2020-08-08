//
//  Feedback.swift
//  
//
//  Created by Thibault Wittemberg on 2019-12-31.
//

import Combine
@testable import SpinCombine
import SpinCommon
import XCTest

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
final class FeedbackTests: XCTestCase {
    private var subscriptions = [AnyCancellable]()

    func test_effect_observes_on_current_executer_when_nilExecuter_is_passed_to_initializer() throws {
        let exp = expectation(description: "Effects")

        var effectIsCalled = false
        var receivedExecuterName = ""
        let expectedExecuterName = "FEEDBACK_QUEUE_\(UUID().uuidString)"

        // Given: a feedback with no Executer
        let nilExecuter: DispatchQueue? = nil
        let sut = ScheduledFeedback(effect: { (inputs: AnyPublisher<Int, Never>) -> AnyPublisher<String, Never> in
            effectIsCalled = true
            return inputs.map {
                receivedExecuterName = DispatchQueue.currentLabel
                return "\($0)"
            }.eraseToAnyPublisher()
        }, on: nilExecuter?.eraseToAnyScheduler())

        // Given: an input stream observed on a dedicated Executer
        let inputStream = Just<Int>(1701)
            .receive(on: DispatchQueue(label: expectedExecuterName, qos: .userInitiated))
            .eraseToAnyPublisher()

        // When: executing the feedback
        sut
            .effect(inputStream)
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in exp.fulfill() })
            .store(in: &self.subscriptions)

        waitForExpectations(timeout: 0.5)

        // Then: the effect is called
        // Then: the effect happens on the dedicated Executer specified in the inputStream, since no Executer has been given
        // in the Feedback initializer
        XCTAssertTrue(effectIsCalled)
        XCTAssertEqual(receivedExecuterName, expectedExecuterName)
    }

    func test_effect_observes_on_an_executer_when_one_is_passed_to_initializer() throws {
        let exp = expectation(description: "Effects")

        var effectIsCalled = false
        var receivedExecuterName = ""
        let expectedExecuterName = "FEEDBACK_QUEUE_\(UUID().uuidString)"

        // Given: a feedback with a dedicated Executer
        let sut = ScheduledFeedback(effect: { (inputs: AnyPublisher<Int, Never>) -> AnyPublisher<String, Never> in
            effectIsCalled = true
            return inputs.map {
                receivedExecuterName = DispatchQueue.currentLabel
                return "\($0)"
            }.eraseToAnyPublisher()
        }, on: DispatchQueue(label: expectedExecuterName, qos: .userInitiated).eraseToAnyScheduler())

        // Given: an input stream observed on a dedicated Executer
        let inputStream = Just<Int>(1701)
            .receive(on: DispatchQueue(label: "FEEDBACK_QUEUE_\(UUID().uuidString)", qos: .userInitiated))
            .eraseToAnyPublisher()

        // When: executing the feedback
        sut.effect(inputStream)
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in exp.fulfill() })
            .store(in: &self.subscriptions)

        waitForExpectations(timeout: 0.5)

        // Then: the effect is called
        // Then: the effect happens on the dedicated Executer given in the Feedback initializer, not on the one defined
        // on the inputStream
        XCTAssertTrue(effectIsCalled)
        XCTAssertEqual(receivedExecuterName, expectedExecuterName)
    }

    func test_init_produces_a_non_cancellable_stream_when_called_with_continueOnNewEvent_strategy() throws {
        let exp = expectation(description: "ContinueOnEvent")
        var receivedElements = [String]()

        // Given: an effect that performs a long operation when given 1 as an input, and an immediate operation otherwise
        func makeLongOperationEffect(outputing: Int) -> AnyPublisher<String, Never> {
            return Future<String, Never> { (observer) in
                sleep(1)
                observer(.success("\(outputing)"))
            }.eraseToAnyPublisher()
        }

        let longOperationQueue = DispatchQueue(label: "FEEDBACK_QUEUE_\(UUID().uuidString)", qos: .background)

        let effect = { (input: Int) -> AnyPublisher<String, Never> in
            if input == 1 {
                return Just<Void>(())
                    .receive(on: longOperationQueue)
                    .flatMap { _ in return makeLongOperationEffect(outputing: input) }
                    .eraseToAnyPublisher()
            }

            return Just<String>("\(input)").eraseToAnyPublisher()
        }

        // Given: this effect being applied a "continueOnNewEvent" strategy
        let sut = Feedback<Int, String>(effect: effect, applying: .continueOnNewState).effect

        // When: feeding this effect with 2 events: 1 and 2
        sut([1, 2].publisher.eraseToAnyPublisher())
            .sink(receiveCompletion: { _ in exp.fulfill() }, receiveValue: { element in receivedElements.append(element) })
            .store(in: &self.subscriptions)

        waitForExpectations(timeout: 5)

        // Then: the stream waits for the long operation to end before completing
        XCTAssertEqual(receivedElements, ["2", "1"])
    }

    func test_init_produces_a_cancellable_stream_when_called_with_cancelOnNewEvent_strategy() throws {
        let exp = expectation(description: "ContinueOnEvent")
        var receivedElements = [String]()

        // Given: an effect that performs a long operation when given 1 as an input, and an immediate operation otherwise
        func makeLongOperationEffect(outputing: Int) -> AnyPublisher<String, Never> {
            return Future<String, Never> { (observer) in
                sleep(1)
                observer(.success("\(outputing)"))
            }.eraseToAnyPublisher()
        }

        let longOperationQueue = DispatchQueue(label: "FEEDBACK_QUEUE_\(UUID().uuidString)", qos: .background)

        let effect = { (input: Int) -> AnyPublisher<String, Never> in
            if input == 1 {
                return Just<Void>(())
                    .receive(on: longOperationQueue)
                    .flatMap { _ in return makeLongOperationEffect(outputing: input) }
                    .eraseToAnyPublisher()
            }

            return Just<String>("\(input)").eraseToAnyPublisher()
        }

        // Given: this effect being applied a "cancelOnNewState" strategy
        let sut = Feedback<Int, String>(effect: effect, applying: .cancelOnNewState).effect

        // When: feeding this stream with 2 events: 1 and 2
        sut([1, 2].publisher.eraseToAnyPublisher())
            .sink(receiveCompletion: { _ in exp.fulfill() }, receiveValue: { element in receivedElements.append(element) })
            .store(in: &self.subscriptions)

        waitForExpectations(timeout: 5)

        // Then: the stream does not wait for the long operation to end before completing, the first operation is cancelled in favor
        // of the immediate one
        XCTAssertEqual(receivedElements, ["2"])
    }

    func test_directEffect_is_used() throws {
        let exp = expectation(description: "Effects")

        var effectIsCalled = false

        // Given: a feedback from a directEffect
        let nilExecuter: DispatchQueue? = nil
        let sut = ScheduledFeedback(directEffect: { (input: Int) -> String in
            effectIsCalled = true
            return "\(input)"
        }, on: nilExecuter?.eraseToAnyScheduler())

        // When: executing the feedback
        let inputStream = Just<Int>(1701).eraseToAnyPublisher()
        sut.effect(inputStream)
            .sink(receiveCompletion: { _ in exp.fulfill() }, receiveValue: { _ in })
            .store(in: &self.subscriptions)

        waitForExpectations(timeout: 0.5)

        // Then: the directEffect is called
        XCTAssertTrue(effectIsCalled)
    }

    func test_effects_are_used() throws {
        let exp = expectation(description: "Effects")
        var effectAIsCalled = false
        var effectBIsCalled = false

        // Given: a feedback from 2 effects
        let effectA = { (inputs: AnyPublisher<Int, Never>) -> AnyPublisher<String, Never> in
            effectAIsCalled = true
            return inputs.map { "\($0)" }.eraseToAnyPublisher()
        }
        let effectB = { (inputs: AnyPublisher<Int, Never>) -> AnyPublisher<String, Never> in
            effectBIsCalled = true
            return inputs.map { "\($0)" }.eraseToAnyPublisher()
        }

        let sut = Feedback(effects: [effectA, effectB])

        // When: executing the feedback
        let inputStream = Just<Int>(1701).eraseToAnyPublisher()
        sut
            .effect(inputStream)
            .sink(receiveCompletion: { _ in exp.fulfill() }, receiveValue: { _ in })
            .store(in: &self.subscriptions)

        waitForExpectations(timeout: 0.5)

        // Then: the effects are called
        XCTAssertTrue(effectAIsCalled)
        XCTAssertTrue(effectBIsCalled)
    }

    func testFeedback_call_gearSideEffect_and_does_only_trigger_a_feedbackEvent_when_attachment_return_not_nil() throws {
        let exp = expectation(description: "Gear")

        let gear = Gear<Int>()
        var numberOfCallsGearSideEffect = 0
        var receivedElements = [String]()

        // Given: a feedback attached to a Gear and triggering en event only of the gear event is 1
        let sut = Feedback<Int, String>(attachedTo: gear, propagating: { gearEvent -> String? in
            numberOfCallsGearSideEffect += 1
            if gearEvent == 1 {
                return "event"
            }

            return nil
        })

        // When: executing the feedback
        let inputStream = Just<Int>(1701).eraseToAnyPublisher()
        sut
            .effect(inputStream)
            .sink(receiveCompletion: { _ in exp.fulfill() }, receiveValue: { element in receivedElements.append(element) })
            .store(in: &self.subscriptions)

        // When: sending 0 and then 1 as gear event
        gear.eventSubject.send(0)
        gear.eventSubject.send(1)
        gear.eventSubject.send(completion: .finished)

        waitForExpectations(timeout: 0.5)

        // Then: the gear dedicated side effect is called twice
        // Then: the only event triggered by the feedback is the one when attachment is not nil
        XCTAssertEqual(numberOfCallsGearSideEffect, 2)
        XCTAssertEqual(receivedElements, ["event"])
    }
}
