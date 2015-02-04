//
//  GenericEntity.swift
//  Kjuu
//
//  Created by Pascal Cremer on 04.02.15.
//  Copyright (c) 2015 Pascal Cremer. All rights reserved.
//

import Foundation

protocol GenericEntity {
    var id: String? { get }
    var createdAt: NSDate? { get }
    var updatedAt: NSDate? { get }
}

protocol Cachable {
    typealias T
    
    var localId: String { get set }
    
    func toRealmObject() -> T
    
    class func fromRealmObject(realmObject: T) -> Self
}