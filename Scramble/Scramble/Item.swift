//
//  Item.swift
//  Scramble
//
//  Created by Arjen Schwarz on 10/5/2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
