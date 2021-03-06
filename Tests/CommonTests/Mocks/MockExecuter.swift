//
//  MockExecuter.swift
//  
//
//  Created by Thibault Wittemberg on 2019-12-29.
//

import SpinCommon
import Foundation

struct MockExecuter: ExecuterDefinition, Equatable {
    typealias Executer = MockExecuter
    var id = UUID().uuidString

    static func defaultSpinExecuter() -> Executer {
        MockExecuter(id: "defaultExecuter")
    }
}
