//
//  TimeExtension.swift
//  PHP Monitor
//
//  Created by Nico Verbruggen on 29/09/2022.
//  Copyright © 2023 Nico Verbruggen. All rights reserved.
//

import Foundation

extension TimeInterval {
    static func seconds(_ value: Double) -> TimeInterval { value }
    static func minutes(_ value: Double) -> TimeInterval { value * 60 }
    static func hours(_ value: Double) -> TimeInterval { value * 3600 }
    static func days(_ value: Double) -> TimeInterval { value * 86400 }
}

extension Date {
    func adding(_ interval: TimeInterval) -> Date {
        return self.addingTimeInterval(interval)
    }
}
