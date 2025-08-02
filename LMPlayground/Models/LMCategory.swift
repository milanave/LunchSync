//
//  Item.swift
//  LMPlayground
//
//  Created by Bob Sanders on 10/26/24.
//

import Foundation
import SwiftData

@Model
final class LMCategory {
    var id: String
    var name: String
    var descript: String
    var exclude_from_budget: Bool
    var exclude_from_totals: Bool
    
    init(id: String, name: String, descript: String, exclude_from_budget: Bool, exclude_from_totals: Bool) {
        self.id = id
        self.name = name
        self.descript = descript
        self.exclude_from_budget = exclude_from_budget
        self.exclude_from_totals = exclude_from_totals
    }
}

@Model
final class TrnCategory {
    var mcc: String
    var name: String
    var lm_category: LMCategory?
    
    init(mcc: String, name: String, lm_category: LMCategory? = nil) {
        self.mcc = mcc
        self.name = name
        self.lm_category = lm_category
    }
}
