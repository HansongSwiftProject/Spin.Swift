//
//  RxFeedbackTests.swift
//  
//
//  Created by Thibault Wittemberg on 2019-12-31.
//

import RxBlocking
import RxSwift
import Spin_RxSwift
import XCTest

final class RxFeedbackTests: XCTestCase {

    private let disposeBag = DisposeBag()

    func test_output_observes_on_current_executer_when_nilExecuter_is_passed_to_initializer() {
        var feedbackIsCalled = false
        var receivedExecuterName = ""
        let expectedExecuterName = "FEEDBACK_QUEUE_\(UUID().uuidString)"

        // Given: a feedback with no Executer
        let sut = RxFeedback(feedback: { (inputs: Observable<Int>) -> Observable<String> in
            feedbackIsCalled = true
            return inputs.map {
                receivedExecuterName = DispatchQueue.currentLabel
                return "\($0)"
            }
        })

        // Given: an input stream observed on a dedicated Executer
        let inputStreamScheduler = ConcurrentDispatchQueueScheduler(queue: DispatchQueue(label: expectedExecuterName,
                                                                                         qos: .userInitiated))

        let inputStream = Observable<Int>
            .just(1701)
            .observeOn(inputStreamScheduler)

        // When: executing the feedback
        _ = sut.feedbackStream(inputStream).toBlocking().materialize()

        // Then: the feedback is called
        // Then: the feedback happens on the dedicated Executer specified on the inputStream, since no Executer has been
        // given in the Feedback initializer
        XCTAssertTrue(feedbackIsCalled)
        XCTAssertEqual(receivedExecuterName, expectedExecuterName)
    }

    func test_output_observes_on_an_executer_when_one_is_passed_to_initializer() {
        var feedbackIsCalled = false
        var receivedExecuterName = ""
        let expectedExecuterName = "FEEDBACK_QUEUE_\(UUID().uuidString)"

        // Given: a feedback with a dedicated Executer
        let feedbackScheduler = ConcurrentDispatchQueueScheduler(queue: DispatchQueue(label: expectedExecuterName,
                                                                                      qos: .userInitiated))

        let sut = RxFeedback(feedback: { (inputs: Observable<Int>) -> Observable<String> in
            feedbackIsCalled = true
            return inputs.map {
                receivedExecuterName = DispatchQueue.currentLabel
                return "\($0)"
            }
        }, on: feedbackScheduler)

        // Given: an input stream observed on a dedicated Executer
        let inputStreamSchedulerQueueName = "INPUT_STREAM_QUEUE_\(UUID().uuidString)"
        let inputStreamScheduler = ConcurrentDispatchQueueScheduler(queue: DispatchQueue(label: inputStreamSchedulerQueueName,
                                                                                         qos: .userInitiated))

        let inputStream = Observable<Int>
            .just(1701)
            .observeOn(inputStreamScheduler)

        // When: executing the feedback
        _ = sut.feedbackStream(inputStream).toBlocking().materialize()

        // Then: the feedback is called
        // Then: the feedback happens on the dedicated Executer given in the Feedback initializer, not on the one defined on
        // the inputStream
        XCTAssertTrue(feedbackIsCalled)
        XCTAssertEqual(receivedExecuterName, expectedExecuterName)
    }

    func test_make_produces_a_non_cancellable_stream_when_called_with_continueOnNewEvent_strategy() throws {
        // Given: a stream that performs a long operation when given 1 as an input, and an immediate operation otherwise
        let longOperationSchedulerQueueLabel = "LONG_OPERATION_QUEUE_\(UUID().uuidString)"
        let longOperationScheduler = ConcurrentDispatchQueueScheduler(queue: DispatchQueue(label: longOperationSchedulerQueueLabel,
                                                                                           qos: .userInitiated))

        let stream = { (input: Int) -> Observable<String> in
            if input == 1 {
                return Observable<String>.create { (observer) -> Disposable in
                    observer.onNext("\(input)")
                    observer.onCompleted()
                    return Disposables.create()
                }
                .delaySubscription(.seconds(1), scheduler: SerialDispatchQueueScheduler(qos: .userInitiated))
                .subscribeOn(longOperationScheduler)
            }

            return .just("\(input)")
        }

        // Given: this stream being applied a "continueOnNewEvent" strategy
        let sut = RxFeedback.make(from: stream, applying: .continueOnNewEvent)

        // When: feeding this stream with 2 events: 1 and 2
        let received = try sut(.from([1, 2])).toBlocking().toArray()

        // Then: the stream waits for the long operation to end before completing
        XCTAssertEqual(received, ["2", "1"])
    }

    func test_make_produces_a_non_failable_stream_when_called_with_continueOnNewEvent_strategy() throws {
        // Given: a stream that performs a long operation when given 1 as an input, and an immediate operation otherwise
        let stream = { (input: Int) -> Observable<String> in
            if input == 1 {
                return .error(NSError(domain: "feedback", code: 0))
            }

            return .just("\(input)")
        }

        // Given: this stream being applied a "continueOnNewEvent" strategy
        let sut = RxFeedback.make(from: stream, applying: .continueOnNewEvent)

        // When: feeding this stream with 2 events: 1 and 2
        let received = try sut(.from([1, 2])).toBlocking().toArray()

        // Then: the stream waits for the long operation to end before completing
        XCTAssertEqual(received, ["2"])
    }

    func test_make_produces_a_cancellable_stream_when_called_with_cancelOnNewEvent_strategy() throws {
        // Given: a stream that performs a long operation when given 1 as an input, and an immediate operation otherwise
        let longOperationSchedulerQueueLabel = "LONG_OPERATION_QUEUE_\(UUID().uuidString)"
        let longOperationScheduler = ConcurrentDispatchQueueScheduler(queue: DispatchQueue(label: longOperationSchedulerQueueLabel,
                                                                                           qos: .userInitiated))

        let stream = { (input: Int) -> Observable<String> in
            if input == 1 {
                return Observable<String>.create { (observer) -> Disposable in
                    observer.onNext("\(input)")
                    observer.onCompleted()
                    return Disposables.create()
                }
                .delaySubscription(.seconds(1), scheduler: SerialDispatchQueueScheduler(qos: .userInitiated))
                .subscribeOn(longOperationScheduler)
            }

            return .just("\(input)")
        }

        // Given: this stream being applied a "cancelOnNewEvent" strategy
        let sut = RxFeedback.make(from: stream, applying: .cancelOnNewEvent)

        // When: feeding this stream with 2 events: 1 and 2
        let received = try sut(.from([1, 2])).toBlocking().toArray()

        // Then: the stream does not wait for the long operation to end before completing, the first operation is cancelled
        // in favor of the immediate one
        XCTAssertEqual(received, ["2"])
    }

    func test_make_produces_a_non_failable_stream_when_called_with_cancelOnNewEvent_strategy() throws {
        // Given: a stream that performs a long operation when given 1 as an input, and an immediate operation otherwise
        let stream = { (input: Int) -> Observable<String> in
            if input == 1 {
                return .error(NSError(domain: "feedback", code: 0))
            }

            return .just("\(input)")
        }

        // Given: this stream being applied a "continueOnNewEvent" strategy
        let sut = RxFeedback.make(from: stream, applying: .cancelOnNewEvent)

        // When: feeding this stream with 2 events: 1 and 2
        let received = try sut(.from([1, 2])).toBlocking().toArray()

        // Then: the stream waits for the long operation to end before completing
        XCTAssertEqual(received, ["2"])
    }

    func test_initialize_with_two_feedbacks_executes_the_original_feedbackFunctions() {
        // Given: 2 feedbacks based on a Stream<State> -> Stream<Event>
        var feedbackAIsCalled = false
        var feedbackBIsCalled = false

        let feedbackAStream: (Int) -> Observable<Int> = { states -> Observable<Int> in
            feedbackAIsCalled = true
            return .just(0)
        }
        let feedbackBStream: (Int) -> Observable<Int> = { states -> Observable<Int> in
            feedbackBIsCalled = true
            return .just(0)
        }

        let sourceFeedbackA = RxFeedback(feedback: feedbackAStream)
        let sourceFeedbackB = RxFeedback(feedback: feedbackBStream)

        // When: instantiating the feedback with already existing feedbacks
        // When: executing the feedback
        let sut = RxFeedback(feedbacks: sourceFeedbackA, sourceFeedbackB)
        _ = sut.feedbackStream(.just(0)).take(2).toBlocking().materialize()

        // Then: the original feedback streams are preserved
        XCTAssertTrue(feedbackAIsCalled)
        XCTAssertTrue(feedbackBIsCalled)
    }

    func test_initialize_with_three_feedbacks_executes_the_original_feedbackFunctions() {
        // Given: 3 feedbacks based on a Stream<State> -> Stream<Event>
        var feedbackAIsCalled = false
        var feedbackBIsCalled = false
        var feedbackCIsCalled = false

        let feedbackAStream: (Int) -> Observable<Int> = { states -> Observable<Int> in
            feedbackAIsCalled = true
            return .just(0)
        }
        let feedbackBStream: (Int) -> Observable<Int> = { states -> Observable<Int> in
            feedbackBIsCalled = true
            return .just(0)
        }
        let feedbackCStream: (Int) -> Observable<Int> = { states -> Observable<Int> in
            feedbackCIsCalled = true
            return .just(0)
        }

        let sourceFeedbackA = RxFeedback(feedback: feedbackAStream)
        let sourceFeedbackB = RxFeedback(feedback: feedbackBStream)
        let sourceFeedbackC = RxFeedback(feedback: feedbackCStream)

        // When: instantiating the feedback with already existing feedbacks
        // When: executing the feedback
        let sut = RxFeedback(feedbacks: sourceFeedbackA, sourceFeedbackB, sourceFeedbackC)
        _ = sut.feedbackStream(.just(0)).take(3).toBlocking().materialize()

        // Then: the original feedback streams are preserved
        XCTAssertTrue(feedbackAIsCalled)
        XCTAssertTrue(feedbackBIsCalled)
        XCTAssertTrue(feedbackCIsCalled)
    }

    func test_initialize_with_four_feedbacks_executes_the_original_feedbackFunctions() {
        // Given: 4 feedbacks based on a Stream<State> -> Stream<Event>
        var feedbackAIsCalled = false
        var feedbackBIsCalled = false
        var feedbackCIsCalled = false
        var feedbackDIsCalled = false

        let feedbackAStream: (Int) -> Observable<Int> = { states -> Observable<Int> in
            feedbackAIsCalled = true
            return .just(0)
        }
        let feedbackBStream: (Int) -> Observable<Int> = { states -> Observable<Int> in
            feedbackBIsCalled = true
            return .just(0)
        }
        let feedbackCStream: (Int) -> Observable<Int> = { states -> Observable<Int> in
            feedbackCIsCalled = true
            return .just(0)
        }
        let feedbackDStream: (Int) -> Observable<Int> = { states -> Observable<Int> in
            feedbackDIsCalled = true
            return .just(0)
        }

        let sourceFeedbackA = RxFeedback(feedback: feedbackAStream)
        let sourceFeedbackB = RxFeedback(feedback: feedbackBStream)
        let sourceFeedbackC = RxFeedback(feedback: feedbackCStream)
        let sourceFeedbackD = RxFeedback(feedback: feedbackDStream)

        // When: instantiating the feedback with already existing feedbacks
        // When: executing the feedback
        let sut = RxFeedback(feedbacks: sourceFeedbackA, sourceFeedbackB, sourceFeedbackC, sourceFeedbackD)
        _ = sut.feedbackStream(.just(0)).take(4).toBlocking().materialize()

        // Then: the original feedback streams are preserved
        XCTAssertTrue(feedbackAIsCalled)
        XCTAssertTrue(feedbackBIsCalled)
        XCTAssertTrue(feedbackCIsCalled)
        XCTAssertTrue(feedbackDIsCalled)
    }

    func test_initialize_with_five_feedbacks_executes_the_original_feedbackFunctions() {
        // Given: 5 feedbacks based on a Stream<State> -> Stream<Event>
        var feedbackAIsCalled = false
        var feedbackBIsCalled = false
        var feedbackCIsCalled = false
        var feedbackDIsCalled = false
        var feedbackEIsCalled = false

        let feedbackAStream: (Int) -> Observable<Int> = { states -> Observable<Int> in
            feedbackAIsCalled = true
            return .just(0)
        }
        let feedbackBStream: (Int) -> Observable<Int> = { states -> Observable<Int> in
            feedbackBIsCalled = true
            return .just(0)
        }
        let feedbackCStream: (Int) -> Observable<Int> = { states -> Observable<Int> in
            feedbackCIsCalled = true
            return .just(0)
        }
        let feedbackDStream: (Int) -> Observable<Int> = { states -> Observable<Int> in
            feedbackDIsCalled = true
            return .just(0)
        }
        let feedbackEStream: (Int) -> Observable<Int> = { states -> Observable<Int> in
            feedbackEIsCalled = true
            return .just(0)
        }

        let sourceFeedbackA = RxFeedback(feedback: feedbackAStream)
        let sourceFeedbackB = RxFeedback(feedback: feedbackBStream)
        let sourceFeedbackC = RxFeedback(feedback: feedbackCStream)
        let sourceFeedbackD = RxFeedback(feedback: feedbackDStream)
        let sourceFeedbackE = RxFeedback(feedback: feedbackEStream)

        // When: instantiating the feedback with already existing feedbacks
        // When: executing the feedback
        let sut = RxFeedback(feedbacks: sourceFeedbackA, sourceFeedbackB, sourceFeedbackC, sourceFeedbackD, sourceFeedbackE)
        _ = sut.feedbackStream(.just(0)).take(5).toBlocking().materialize()

        // Then: the original feedback streams are preserved
        XCTAssertTrue(feedbackAIsCalled)
        XCTAssertTrue(feedbackBIsCalled)
        XCTAssertTrue(feedbackCIsCalled)
        XCTAssertTrue(feedbackDIsCalled)
        XCTAssertTrue(feedbackEIsCalled)
    }

    func test_initialize_with_an_array_of_feedbacks_executes_the_original_feedbackFunctions() throws {
        let exp = expectation(description: "toto")
        // Given: 5 feedbacks based on a Stream<State> -> Stream<Event>
        var feedbackAIsCalled = false
        var feedbackBIsCalled = false
        var feedbackCIsCalled = false
        var feedbackDIsCalled = false
        var feedbackEIsCalled = false

        let feedbackAStream: (Int) -> Observable<Int> = { states -> Observable<Int> in
            feedbackAIsCalled = true
            return .just(0)
        }
        let feedbackBStream: (Int) -> Observable<Int> = { states -> Observable<Int> in
            feedbackBIsCalled = true
            return .just(0)
        }
        let feedbackCStream: (Int) -> Observable<Int> = { states -> Observable<Int> in
            feedbackCIsCalled = true
            return .just(0)
        }
        let feedbackDStream: (Int) -> Observable<Int> = { states -> Observable<Int> in
            feedbackDIsCalled = true
            return .just(0)
        }
        let feedbackEStream: (Int) -> Observable<Int> = { states -> Observable<Int> in
            feedbackEIsCalled = true
            return .just(0)
        }

        let sourceFeedbackA = RxFeedback(feedback: feedbackAStream)
        let sourceFeedbackB = RxFeedback(feedback: feedbackBStream)
        let sourceFeedbackC = RxFeedback(feedback: feedbackCStream)
        let sourceFeedbackD = RxFeedback(feedback: feedbackDStream)
        let sourceFeedbackE = RxFeedback(feedback: feedbackEStream)

        // When: instantiating the feedback with already existing feedbacks with function builder
        // When: executing the feedback
        let sut = RxFeedback(feedbacks: [sourceFeedbackA,
                                               sourceFeedbackB,
                                               sourceFeedbackC,
                                               sourceFeedbackD,
                                               sourceFeedbackE])
        sut.feedbackStream(.just(0)).take(5).toArray().do(onSuccess: { _ in exp.fulfill() }).subscribe().disposed(by: self.disposeBag)

        waitForExpectations(timeout: 5)

        // Then: the original feedback streams are preserved
        XCTAssertTrue(feedbackAIsCalled)
        XCTAssertTrue(feedbackBIsCalled)
        XCTAssertTrue(feedbackCIsCalled)
        XCTAssertTrue(feedbackDIsCalled)
        XCTAssertTrue(feedbackEIsCalled)
    }
}