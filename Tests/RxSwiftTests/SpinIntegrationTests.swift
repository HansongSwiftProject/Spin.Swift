////
////  SpinIntegrationTests.swift
////  
////
////  Created by Thibault Wittemberg on 2019-12-31.
////

import RxSwift
import SpinRxSwift
import SpinCommon
import XCTest

fileprivate enum StringAction {
    case append(String)
}

final class SpinIntegrationTests: XCTestCase {

    private let disposeBag = DisposeBag()

    func test_multiple_feedbacks_produces_incremental_states_while_executed_on_default_executer() throws {
        var receivedStatesInEffects = [String]()

        // Given: an initial state, feedbacks and a reducer
        var counterA = 0
        let effectA = { (state: String) -> Observable<StringAction> in
            guard state == "initialState" || state.dropLast().last == "c" else { return .empty() }
            counterA += 1
            let counter = counterA
            return .just(.append("_a\(counter)"))
        }

        var counterB = 0
        let effectB = { (state: String) -> Observable<StringAction> in
            guard state.dropLast().last == "a" else { return .empty() }
            counterB += 1
            let counter = counterB
            return .just(.append("_b\(counter)"))
        }

        var counterC = 0
        let effectC = { (state: String) -> Observable<StringAction> in
            guard state.dropLast().last == "b" else { return .empty() }
            counterC += 1
            let counter = counterC
            return .just(.append("_c\(counter)"))
        }

        let spyEffect = { (state: String) -> Observable<StringAction> in
            receivedStatesInEffects.append(state)
            return .empty()
        }

        let reducerFunction = { (state: String, action: StringAction) -> String in
            switch action {
            case .append(let suffix):
                return state+suffix
            }
        }

        // When: spinning the feedbacks and the reducer on the default executer
        let spin = Spinner
            .initialState("initialState")
            .feedback(Feedback(effect: effectA))
            .feedback(Feedback(effect: effectB))
            .feedback(Feedback(effect: effectC))
            .feedback(Feedback(effect: spyEffect))
            .reducer(Reducer(reducerFunction))

        _ = Observable<String>.stream(from: spin)
            .take(6)
            .toBlocking()
            .materialize()

        // Then: the states is constructed incrementally
        XCTAssertEqual(receivedStatesInEffects, ["initialState",
                                                 "initialState_a1",
                                                 "initialState_a1_b1",
                                                 "initialState_a1_b1_c1",
                                                 "initialState_a1_b1_c1_a2",
                                                 "initialState_a1_b1_c1_a2_b2",
                                                 "initialState_a1_b1_c1_a2_b2_c2"])
    }

    func test_multiple_feedbacks_produces_incremental_states_while_executed_on_default_executer_using_declarative_syntax() throws {
        var receivedStatesInEffects = [String]()

        // Given: an initial state, feedbacks and a reducer
        var counterA = 0
        let effectA = { (state: String) -> Observable<StringAction> in
            guard state == "initialState" || state.dropLast().last == "c" else { return .empty() }
            counterA += 1
            let counter = counterA
            return .just(.append("_a\(counter)"))
        }

        var counterB = 0
        let effectB = { (state: String) -> Observable<StringAction> in
            guard state.dropLast().last == "a" else { return .empty() }
            counterB += 1
            let counter = counterB
            return .just(.append("_b\(counter)"))
        }

        var counterC = 0
        let effectC = { (state: String) -> Observable<StringAction> in
            guard state.dropLast().last == "b" else { return .empty() }
            counterC += 1
            let counter = counterC
            return .just(.append("_c\(counter)"))
        }

        let spyEffect = { (state: String) -> Observable<StringAction> in
            receivedStatesInEffects.append(state)
            return .empty()
        }

        let reducerFunction = { (state: String, action: StringAction) -> String in
            switch action {
            case .append(let suffix):
                return state+suffix
            }
        }

        let spin = Spin<String, StringAction>(initialState: "initialState") {
            Feedback(effect: effectA)
            Feedback(effect: effectB)
            Feedback(effect: effectC)
            Feedback(effect: spyEffect)
            Reducer(reducerFunction)
        }

        // When: spinning the feedbacks and the reducer on the default executer
        _ = Observable<String>.stream(from: spin)
            .take(6)
            .toBlocking()
            .materialize()

        // Then: the states is constructed incrementally
        XCTAssertEqual(receivedStatesInEffects, ["initialState",
                                                 "initialState_a1",
                                                 "initialState_a1_b1",
                                                 "initialState_a1_b1_c1",
                                                 "initialState_a1_b1_c1_a2",
                                                 "initialState_a1_b1_c1_a2_b2",
                                                 "initialState_a1_b1_c1_a2_b2_c2"])
    }

    func test_reducer_and_feedback_are_executed_on_specified_executers() {
        let exp = expectation(description: "Scheduling")

        let expectedReducerQueueLabel = "SPIN_QUEUE_\(UUID())"
        let expectedFeedback1QueueLabel = "FEEDBACK1_QUEUE_\(UUID())"
        let expectedFeedback2QueueLabel = "FEEDBACK2_QUEUE_\(UUID())"

        var receivedReducerQueueLabel = ""
        var receivedFeedback1QueueLabel = ""
        var receivedFeedback2QueueLabel = ""

        let spinScheduler = SerialDispatchQueueScheduler(queue: DispatchQueue(label: expectedReducerQueueLabel), internalSerialQueueName: expectedReducerQueueLabel)
        let feedback1Scheduler = SerialDispatchQueueScheduler(queue: DispatchQueue(label: expectedFeedback1QueueLabel), internalSerialQueueName: expectedFeedback1QueueLabel)
        let feedback2Scheduler = SerialDispatchQueueScheduler(queue: DispatchQueue(label: expectedFeedback2QueueLabel), internalSerialQueueName: expectedFeedback2QueueLabel)

        let spyReducer: (String, String) -> String = { _, _ in
            receivedReducerQueueLabel = DispatchQueue.currentLabel
            return ""
        }

        let spyFeedback1: (Observable<String>) -> Observable<String> = { states in
            states.map {
                receivedFeedback1QueueLabel = DispatchQueue.currentLabel
                return $0
            }
        }

        let spyFeedback2: (Observable<String>) -> Observable<String> = { states in
            states.map {
                receivedFeedback2QueueLabel = DispatchQueue.currentLabel
                return $0
            }
        }

        let sut = Spin<String, String>(initialState: "initialState", executeOn: spinScheduler) {
            Feedback<String, String>(effect: spyFeedback1).execute(on: feedback1Scheduler)
            Feedback<String, String>(effect: spyFeedback2).execute(on: feedback2Scheduler)
            Reducer<String, String>(spyReducer)
        }

        Observable
            .stream(from: sut)
            .take(1)
            .do(onCompleted: { exp.fulfill() })
            .subscribe()
            .disposed(by: self.disposeBag)

        waitForExpectations(timeout: 0.5)

        XCTAssertEqual(receivedFeedback1QueueLabel, expectedFeedback1QueueLabel)
        XCTAssertEqual(receivedFeedback2QueueLabel, expectedFeedback2QueueLabel)
        XCTAssertEqual(receivedReducerQueueLabel, expectedReducerQueueLabel)
    }
}

extension SpinIntegrationTests {
    ////////////////////////////////////////////////////////////////
    // CHECK AUTHORIZATION SPIN
    ///////////////////////////////////////////////////////////////

    // events:    checkAuthorization                 revokeUser
    //                   ↓                               ↓
    // states:   initial -> AuthorizationShouldBeChecked -> userHasBeenRevoked

    private enum CheckAuthorizationSpinState: Equatable {
        case initial
        case authorizationShouldBeChecked
        case userHasBeenRevoked
    }

    private enum CheckAuthorizationSpinEvent {
        case checkAuthorization
        case revokeUser
    }

    ////////////////////////////////////////////////////////////////
    // FETCH FEATURE FEEDBACKLOOP
    ///////////////////////////////////////////////////////////////

    // events:   userIsNotAuthorized
    //                  ↓
    // states:  initial -> unauthorized

    private enum FetchFeatureSpinState: Equatable {
        case initial
        case unauthorized
    }

    private enum FetchFeatureSpinEvent {
        case userIsNotAuthorized
    }

    ////////////////////////////////////////////////////////////////
    // Gear
    ///////////////////////////////////////////////////////////////

    private enum GearEvent {
        case authorizedIssueDetected
    }

    func testAttach_trigger_checkAuthorizationSpin_when_fetchFeatureSpin_trigger_gear() {
        let exp1 = expectation(description: "Check Spin is initialized")
        let exp2 = expectation(description: "Gear")

        var receivedCheckAuthorization = [CheckAuthorizationSpinState]()
        var receivedFeatureStates = [FetchFeatureSpinState]()

        // Given: 2 independents spins and a shared gear
        let gear = Gear<GearEvent>()
        let fetchFeatureSpin = self.makeFetchFeatureSpin(attachedTo: gear)
        let checkAuthorizationSpin = self.makeCheckAuthorizationSpin(attachedTo: gear)

        let spyEffectFeatureSpin = { (state: FetchFeatureSpinState) -> Observable<FetchFeatureSpinEvent> in
            receivedFeatureStates.append(state)
            return .empty()
        }
        fetchFeatureSpin.effects.append(Feedback<FetchFeatureSpinState, FetchFeatureSpinEvent>(effect: spyEffectFeatureSpin).effect)

        let spyEffectCheckAuthorizationSpin = { (state: CheckAuthorizationSpinState) -> Observable<CheckAuthorizationSpinEvent> in
            receivedCheckAuthorization.append(state)
            if state == .initial {
                exp1.fulfill()
            }
            if state == .userHasBeenRevoked {
                exp2.fulfill()
            }
            return .empty()
        }
        checkAuthorizationSpin.effects.append(Feedback<CheckAuthorizationSpinState, CheckAuthorizationSpinEvent>(effect: spyEffectCheckAuthorizationSpin).effect)

        // When: executing the 2 spins
        Observable
            .stream(from: checkAuthorizationSpin)
            .subscribe()
            .disposed(by: self.disposeBag)

        wait(for: [exp1], timeout: 0.5)

        Observable
            .stream(from:fetchFeatureSpin)
            .subscribe()
            .disposed(by: self.disposeBag)

        wait(for: [exp2], timeout: 0.5)

        // Then: the stream of states produced by the spins are the expected one thanks to the propagation of the gear
        XCTAssertEqual(receivedFeatureStates[0], .initial)
        XCTAssertEqual(receivedFeatureStates[1], .unauthorized)
        XCTAssertEqual(receivedCheckAuthorization[0], .initial)
        XCTAssertEqual(receivedCheckAuthorization[1], .authorizationShouldBeChecked)
        XCTAssertEqual(receivedCheckAuthorization[2], .userHasBeenRevoked)
    }
}

private extension SpinIntegrationTests {
    private func makeCheckAuthorizationSpin(attachedTo gear: Gear<GearEvent>) -> Spin<CheckAuthorizationSpinState, CheckAuthorizationSpinEvent> {
        let checkAuthorizationSpinReducer: (CheckAuthorizationSpinState, CheckAuthorizationSpinEvent) -> CheckAuthorizationSpinState = { state, event in
            switch (state, event) {
            case (.initial, .checkAuthorization):
                return .authorizationShouldBeChecked
            case (.authorizationShouldBeChecked, .revokeUser):
                return .userHasBeenRevoked
            default:
                return state
            }
        }

        let checkAuthorizationSideEffect: (CheckAuthorizationSpinState) -> Observable<CheckAuthorizationSpinEvent> = { state in
            guard state == .authorizationShouldBeChecked else { return .empty() }
            return Observable<CheckAuthorizationSpinEvent>.just(.revokeUser)
        }

        let attachedCheckAuthorizationFeedback = Feedback<CheckAuthorizationSpinState, CheckAuthorizationSpinEvent>(attachedTo: gear,
                                                                                                                    propagating: { (event: GearEvent) in
                                                                                                                        if event == .authorizedIssueDetected {
                                                                                                                            return CheckAuthorizationSpinEvent.checkAuthorization
                                                                                                                        }
                                                                                                                        return nil
        })

        let spin = Spin<CheckAuthorizationSpinState, CheckAuthorizationSpinEvent>(initialState: .initial) {
            Feedback<CheckAuthorizationSpinState, CheckAuthorizationSpinEvent>(effect: checkAuthorizationSideEffect)
            attachedCheckAuthorizationFeedback
            Reducer(checkAuthorizationSpinReducer)
        }

        return spin
    }

    private func makeFetchFeatureSpin(attachedTo gear: Gear<GearEvent>) -> Spin<FetchFeatureSpinState, FetchFeatureSpinEvent> {
        let fetchFeatureSpinReducer: (FetchFeatureSpinState, FetchFeatureSpinEvent) -> FetchFeatureSpinState = { state, event in
            switch (state, event) {
            case (.initial, .userIsNotAuthorized):
                return .unauthorized
            default:
                return state
            }
        }

        let fetchFeatureSideEffect: (FetchFeatureSpinState) -> Observable<FetchFeatureSpinEvent> = { state in
            guard state == .initial else { return .empty() }
            return Observable<FetchFeatureSpinEvent>.just(.userIsNotAuthorized)
        }

        let attachedFetchFeatureFeedback = Feedback<FetchFeatureSpinState, FetchFeatureSpinEvent>(attachedTo: gear,
                                                                                                  propagating: { (state: FetchFeatureSpinState) -> GearEvent? in
                                                                                                    if state == .unauthorized {
                                                                                                        return GearEvent.authorizedIssueDetected
                                                                                                    }
                                                                                                    return nil
        })

        let spin = Spin<FetchFeatureSpinState, FetchFeatureSpinEvent>(initialState: .initial) {
            Feedback<FetchFeatureSpinState, FetchFeatureSpinEvent>(effect: fetchFeatureSideEffect)
            attachedFetchFeatureFeedback
            Reducer(fetchFeatureSpinReducer)
        }

        return spin
    }
}
