//
//  Item.swift
//  LMPlayground
//
//  Created by Bob Sanders on 10/26/24.
//
/*
 Each time a unique MCC code is received from Apple Wallet, create a local TrnCategory
 The user will select LunchMoney categories (as LMCategory objects) to assign to each one
 */
import Foundation
import SwiftData

struct CategoryMapping: Codable {
    var mcc: String
    var name: String
    var lm_id: String
    var lm_name: String
    var lm_descript: String
    var exclude_from_budget: Bool
    var exclude_from_totals: Bool
}

@Model
final class LMCategory {
    var id: String = ""
    var name: String = ""
    var descript: String = ""
    var exclude_from_budget: Bool = false
    var exclude_from_totals: Bool = false
    @Relationship(inverse: \TrnCategory.lm_category) var trn_categories: [TrnCategory]?
    
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
    var mcc: String = ""
    var name: String = ""
    var lm_category: LMCategory?
    
    // the properties of an LMCategory
    var lm_id: String = ""
    var lm_name: String = ""
    var lm_descript: String = ""
    var exclude_from_budget: Bool = false
    var exclude_from_totals: Bool = false
    
    init(mcc: String, name: String, lm_category: LMCategory? = nil) {
        self.mcc = mcc
        self.name = name
        self.lm_category = lm_category
        // defaults are provided at declaration for migration safety
    }
    
    public func set_lm_category(id: String, name: String, descript: String, exclude_from_budget: Bool, exclude_from_totals: Bool){
        self.lm_id = id
        self.lm_name = name
        self.lm_descript = descript
        self.exclude_from_budget = exclude_from_budget
        self.exclude_from_totals = exclude_from_totals
    }
    
    public func clear_lm_category(){
        self.lm_id = ""
        self.lm_name = ""
        self.lm_descript = ""
        self.exclude_from_budget = false
        self.exclude_from_totals = false
    }
}
