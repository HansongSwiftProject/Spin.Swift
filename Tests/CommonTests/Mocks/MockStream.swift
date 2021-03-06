//
//  MockStream.swift
//  
//
//  Created by Thibault Wittemberg on 2019-12-29.
//

import SpinCommon

protocol CanBeEmpty {
    static var toEmpty: Self { get }
}

class MockStream<Event: CanBeEmpty> {
    var value: Event

    init(value: Event) {
        self.value = value
    }

    func flatMap<Output>(_ function: (Event) -> MockStream<Output>) -> MockStream<Output> {
        return function(self.value)
    }

    func map<Output>(_ function: (Event) -> Output) -> MockStream<Output> {
        return MockStream<Output>(value: function(self.value))
    }

    static func empty() -> MockStream<Event> {
        return MockStream<Event>(value: Event.toEmpty)
    }
}

extension MockStream: ReactiveStream {
    static func emptyStream() -> Self {
        return MockStream.empty() as! Self
    }

    typealias Value = Event
    typealias Subscription = MockLifecycle

    func consume() -> Subscription {
        return MockLifecycle()
    }
}
