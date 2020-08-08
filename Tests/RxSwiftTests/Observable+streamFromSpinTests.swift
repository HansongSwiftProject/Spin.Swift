//
//  File.swift
//  
//
//  Created by Thibault Wittemberg on 2020-02-07.
//

import RxBlocking
import RxRelay
import RxSwift
import SpinCommon
import SpinRxSwift
import XCTest

final class Observable_streamFromSpinTests: XCTestCase {
    private let disposeBag = DisposeBag()

    func test_initialState_is_the_first_state_given_to_the_effects() {
        // Given: 2 feedbacks and 1 reducer assembled in a Spin with an initialState
        let initialState = "initialState"
        var receivedStateInEffectA = [String]()
        var receivedStateInEffectB = [String]()

        let feedbackA = Feedback<String, String>(effect: { states in
            states.map { state -> String in
                receivedStateInEffectA.append(state)
                return "event"
            }
        })
        let feedbackB = Feedback<String, String>(effect: { states in
            states.map { state -> String in
                receivedStateInEffectB.append(state)
                return "event"
            }
        })
        let reducer = Reducer<String, String>({ state, _ in
            return "newState"
        })

        let spin = Spin<String, String>(initialState: initialState) {
            feedbackA
            feedbackB
            reducer
        }

        // When: producing/subscribing to a stream based on the RxSpin
        _ = Observable<String>
            .stream(from: spin)
            .take(1)
            .toBlocking()
            .materialize()

        // Then: the feedback's effects receive the initial state
        XCTAssertEqual(receivedStateInEffectA[0], initialState)
        XCTAssertEqual(receivedStateInEffectB[0], initialState)
    }

    func test_initialState_is_the_state_given_to_the_reducer() {
        // Given: 1 feedback and 1 reducer assembled in a Spin with an initialState
        let initialState = "initialState"
        var receivedInitialStateInReducer = ""

        let feedbackA = Feedback<String, String>(effect: { states in
            states.map { state -> String in
                return "event"
            }
        })

        let reducer = Reducer<String, String>({ state, _ in
            receivedInitialStateInReducer = state
            return "newState"
        })

        let spin = Spin<String, String>(initialState: initialState) {
            feedbackA
            reducer
        }

        // When: producing/subscribing to a stream based on the Spin
        _ = Observable
            .stream(from: spin)
            .take(1)
            .toBlocking()
            .materialize()

        // Then: the reducer receives the initial state
        XCTAssertEqual(receivedInitialStateInReducer, initialState)
    }

    func test_stream_outputs_no_error_and_complete_when_effect_fails() {
        // Given: an effect that outputs an Error and a reducer
        let initialState = "initialState"
        var reduceIsCalled = false

        let feedback = Feedback(effect: { (inputs: Observable<String>) -> Observable<String> in
            return .error(NSError(domain: "feedback", code: 0))
        })

        let reducer = Reducer<String, String>({ state, _ in
            reduceIsCalled = false
            return "newState"
        })

        let spin = Spin<String, String>(initialState: initialState) {
            feedback
            reducer
        }

        // When: producing/subscribing to a stream based on the Spin
        let events = Observable
            .stream(from: spin)
            .take(1)
            .toBlocking()
            .materialize()

        // Then: the reduce is not performed
        // Then: the feedback loop completes with no error
        XCTAssertFalse(reduceIsCalled)
        XCTAssertEqual(events, MaterializedSequenceResult<String>.completed(elements: []))
    }
}
