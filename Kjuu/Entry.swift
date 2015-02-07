//
//  Entry.swift
//  Kjuu
//
//  Created by Pascal Cremer on 04.02.15.
//  Copyright (c) 2015 Pascal Cremer. All rights reserved.
//

import Realm
import CloudKit

enum EntryNotificationType {
    case Date(date: NSDate)
    case Location(location: CLLocation)
}

protocol EntryProtocol: GenericEntity {
    var url: String { get set }
    var title: String? { get set }
    var description: String? { get set }
    var notificationType: EntryNotificationType { get set }
    var archivedAt: NSDate? { get set }
}

// Workaround, see https://github.com/realm/realm-cocoa/issues/1024
class DateObject: RLMObject {
    dynamic var date: NSDate = NSDate()
}

class EntryCache: RLMObject {
    dynamic var id = ""
    dynamic var url = ""
    dynamic var title = ""
    dynamic var descriptions = ""
    dynamic var dateReminder: DateObject?
    dynamic var latitude: Double = 0.0
    dynamic var longitude: Double = 0.0
    dynamic var createdAt = NSDate()
    dynamic var updatedAt = NSDate()
    dynamic var archivedAt: DateObject?
    
    override class func primaryKey() -> String {
        return "id"
    }
}

class Entry: EntryProtocol {
    let record: CKRecord
    
    // MARK: EntryProtocol properties
    
    var id: String? {
        return record.recordID.recordName
    }
    
    var url: String {
        get {
            return record.objectForKey("url") as String
        }
        
        set {
            record.setObject(newValue, forKey: "url")
        }
    }
    
    var title: String? {
        get {
            return record.objectForKey("title") as String?
        }
        
        set {
            record.setObject(newValue, forKey: "title")
        }
    }
    
    var description: String? {
        get {
            return record.objectForKey("description") as String?
        }
        
        set {
            record.setObject(newValue, forKey: "description")
        }
    }
    
    var notificationType: EntryNotificationType {
        get {
            if let dateReminder = record.objectForKey("dateReminder") as? NSDate {
                return .Date(date: dateReminder)
            }
            
            if let locationReminder = record.objectForKey("locationReminder") as? CLLocation {
                return .Location(location: locationReminder)
            }
            
            // Defaults to an already expired date based reminder
            return .Date(date: NSDate().dateByAddingTimeInterval(-1*24*60*60))
        }
        
        set {
            switch(newValue) {
            case .Date(let date):
                record.setObject(date, forKey: "dateReminder")
            case .Location(let location):
                record.setObject(location, forKey: "locationReminder")
            }
        }
    }
    
    var createdAt: NSDate? {
        get {
            return record.creationDate as NSDate?
        }
    }
    
    var updatedAt: NSDate? {
        get {
            return record.modificationDate as NSDate?
        }
    }
    
    var archivedAt: NSDate? {
        get {
            return record.objectForKey("archivedAt") as NSDate?
        }
        
        set {
            record.setObject(newValue, forKey: "archivedAt")
        }
    }
    
    // MARK: Initializers
    
    required init(record: CKRecord) {
        self.record = record
    }
    
    convenience init() {
        let record = CKRecord(recordType: "Entry")
        self.init(record: record)
    }
}

extension Entry: Cachable {
    typealias T = EntryCache
    
    var localId: String {
        get {
            if let localId = record.objectForKey("localId") as String? {
                return localId
            }
            
            return NSUUID().UUIDString
        }
        
        set {
            record.setObject(newValue, forKey: "localId")
        }
    }
    
    func toRealmObject() -> T {
        let entryCache = EntryCache()
        
        entryCache.id = localId
        entryCache.url = url
        
        if let title = title {
            entryCache.title = title
        }
        
        if let description = description {
            entryCache.descriptions = description
        }
        
        switch(notificationType) {
        case .Date(let date):
            let dateObject = DateObject()
            dateObject.date = date
            entryCache.dateReminder = dateObject
        case .Location(let location):
            entryCache.latitude = location.location.coordinate.latitude
            entryCache.longitude = location.location.coordinate.longitude
        }
        
        if let createdAt = createdAt {
            entryCache.createdAt = createdAt
        }
        
        if let updatedAt = updatedAt {
            entryCache.updatedAt = updatedAt
        }
        
        if let archivedAt = archivedAt {
            let dateObject = DateObject()
            dateObject.date = archivedAt
            entryCache.archivedAt = dateObject
        }
        
        return entryCache
    }
    
    class func fromRealmObject(realmObject: T) -> Self {
        let entry = self(record: CKRecord(recordType: "Entry"))
        
        entry.localId = realmObject.id
        entry.url = realmObject.url
        entry.title = realmObject.title
        entry.description = realmObject.descriptions
        
        if let date = realmObject.dateReminder?.date {
            entry.notificationType = .Date(date: date)
        } else {
            let location = CLLocation(latitude: realmObject.latitude, longitude: realmObject.longitude)
            entry.notificationType = .Location(location: location)
        }
        
        if let date = realmObject.archivedAt?.date {
            entry.archivedAt = date
        }
        
        return entry
    }
}