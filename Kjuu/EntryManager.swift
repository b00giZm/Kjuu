//
//  EntryManager.swift
//  Kjuu
//
//  Created by Pascal Cremer on 07.02.15.
//  Copyright (c) 2015 Pascal Cremer. All rights reserved.
//

import CloudKit
import Realm

protocol EntryManagerPrototol {
    func createEntry(entry: Entry, callback: ((sucess: Bool, entry: Entry?) -> ())?)
    func getAllEntries(callback: ((entries: [Entry]) -> ())?)
    func downloadAllEntriesAndResetCache(callback: ((entries: [Entry]) -> ())?)
    func getEntryByLocalID(localId: String) -> Entry?
    func downloadEntryByLocalID(localId: String, callback: ((entry: Entry?) -> ())?)
    func updateEntry(entry: Entry, callback: ((success: Bool) -> ())?)
    func deleteEntry(entry: Entry, callback: ((success: Bool) -> ())?)
}

class EntryManager: EntryManagerPrototol {
    let database: CKDatabase
    
    lazy var isCloudKitEnabled: Bool = {
        return true
    }()
    
    init(database: CKDatabase) {
        self.database = database
    }
    
    convenience init() {
        self.init(database: CKContainer.defaultContainer().privateCloudDatabase)
    }
    
    func createEntry(entry: Entry, callback: ((sucess: Bool, entry: Entry?) -> ())?) {
        // Ensure local ID
        entry.localId = NSUUID().UUIDString
        
        if isCloudKitEnabled {
            database.saveRecord(entry.record) { (record, error) in
                if error != nil {
                    println("there was an error: \(error.localizedDescription)")
                    callback?(sucess: false, entry: nil)
                }
                
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
                    let realm = RLMRealm.defaultRealm()
                    realm.transactionWithBlock {
                        realm.addObject(entry.toRealmObject())
                        callback?(sucess: true, entry: entry)
                    }
                }
            }
        } else {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
                let realm = RLMRealm.defaultRealm()
                realm.transactionWithBlock {
                    realm.addObject(entry.toRealmObject())
                    callback?(sucess: true, entry: entry)
                }
            }
        }
    }
    
    func getAllEntries(callback: ((entries: [Entry]) -> ())?) {
        let results = EntryCache.allObjects()
        var entries = [Entry]()
        
        var idx: UInt = 0
        for idx = 0; idx < results.count; idx++ {
            entries.append(Entry.fromRealmObject(results.objectAtIndex(idx) as EntryCache))
        }
        
        callback?(entries: entries)
    }
    
    func downloadAllEntriesAndResetCache(callback: ((entries: [Entry]) -> ())?) {
        if isCloudKitEnabled {
            let query = CKQuery(recordType: "Entry", predicate: NSPredicate(value: true))
            let queryOperation = CKQueryOperation(query: query)
            var entries = [Entry]()
            
            queryOperation.recordFetchedBlock = { record in entries.append(Entry(record: record)) }
            queryOperation.queryCompletionBlock = { _ in
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
                    let realm = RLMRealm.defaultRealm()
                    realm.transactionWithBlock {
                        realm.deleteAllObjects()
                        for entry in entries {
                            realm.addObject(entry.toRealmObject())
                        }
                    }
                    self.getAllEntries(callback)
                }
            }
            
            database.addOperation(queryOperation)
        } else {
            self.getAllEntries(callback)
        }
    }
    
    func getEntryByLocalID(localId: String) -> Entry? {
        if let cachedEntry = EntryCache(forPrimaryKey: localId) {
            return Entry.fromRealmObject(cachedEntry)
        }
        
        return nil
    }
    
    func downloadEntryByLocalID(localId: String, callback: ((entry: Entry?) -> ())?) {
        if isCloudKitEnabled {
            let query = CKQuery(recordType: "Entry", predicate: NSPredicate(format: "localId = %@", localId))
            let queryOperation = CKQueryOperation(query: query)
            var entries = [Entry]()
            
            queryOperation.recordFetchedBlock = { record in entries.append(Entry(record: record)) }
            queryOperation.queryCompletionBlock = { _, error in
                if error != nil {
                    println("there was a problem completing the operation: \(error.localizedDescription)")
                }
                
                callback?(entry: entries.first)
            }
            
            database.addOperation(queryOperation)
        } else {
            println("CloudKit isn't enabled")
            callback?(entry: nil)
        }
    }
    
    func updateEntry(entry: Entry, callback: ((success: Bool) -> ())?) {
        if isCloudKitEnabled {
            downloadEntryByLocalID(entry.localId) { cloudEntry in
                if let cloudEntry = cloudEntry {
                    cloudEntry.url = entry.url
                    cloudEntry.title = entry.title
                    cloudEntry.description = entry.description
                    cloudEntry.notificationType = entry.notificationType
                    cloudEntry.archivedAt = entry.archivedAt
                    
                    let updateOperation = CKModifyRecordsOperation(recordsToSave: [cloudEntry.record], recordIDsToDelete: nil)
                    updateOperation.perRecordCompletionBlock = { (record, error) in
                        if error != nil {
                            println("unable to modify record \(record). Error: \(error.localizedDescription)")
                        }
                    }
                    updateOperation.modifyRecordsCompletionBlock = { (saved, _, error) in
                        if error != nil {
                            if error.code == CKErrorCode.PartialFailure.rawValue {
                                println("there was a problem completing the operation. The following records had problems: \(error.userInfo?[CKPartialErrorsByItemIDKey])")
                            }
                            
                            callback?(success: false)
                        } else {
                            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
                                let realm = RLMRealm.defaultRealm()
                                realm.transactionWithBlock {
                                    let cachedEntry = cloudEntry.toRealmObject()
                                    realm.addOrUpdateObject(cachedEntry)
                                    if let dateReminder = cachedEntry.dateReminder {
                                        realm.deleteObject(dateReminder)
                                    }
                                    if let archivedAt = cachedEntry.archivedAt {
                                        realm.deleteObject(archivedAt)
                                    }
                                }
                                
                                callback?(success: true)
                            }
                        }
                    }
                    
                    self.database.addOperation(updateOperation)
                } else {
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
                        let realm = RLMRealm.defaultRealm()
                        realm.transactionWithBlock {
                            let cachedEntry = EntryCache(forPrimaryKey: entry.localId)
                            realm.addOrUpdateObject(cachedEntry)
                            if let dateReminder = cachedEntry.dateReminder {
                                realm.deleteObject(dateReminder)
                            }
                            if let archivedAt = cachedEntry.archivedAt {
                                realm.deleteObject(archivedAt)
                            }
                        }
                        
                        callback?(success: true)
                    }
                }
            }
        } else {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
                let realm = RLMRealm.defaultRealm()
                realm.transactionWithBlock {
                    let cachedEntry = EntryCache(forPrimaryKey: entry.localId)
                    realm.addOrUpdateObject(cachedEntry)
                    if let dateReminder = cachedEntry.dateReminder {
                        realm.deleteObject(dateReminder)
                    }
                    if let archivedAt = cachedEntry.archivedAt {
                        realm.deleteObject(archivedAt)
                    }
                }
                
                callback?(success: true)
            }
        }
    }
    
    func deleteEntry(entry: Entry, callback: ((success: Bool) -> ())?) {
        let deleteFromCacheBlock: () -> () = {
            let realm = RLMRealm.defaultRealm()
            
            realm.transactionWithBlock {
                realm.deleteObject(EntryCache(forPrimaryKey: entry.localId))
            }
            
            callback?(success: true)
        }
        
        if isCloudKitEnabled {
            downloadEntryByLocalID(entry.localId) { cloudEntry in
                if let cloudEntry = cloudEntry {
                    let deleteOperation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [CKRecordID(recordName: cloudEntry.id)])
                    deleteOperation.perRecordCompletionBlock = { (record, error) in
                        if error != nil {
                            println("unable to delete record \(record). Error: \(error.localizedDescription)")
                        }
                    }
                    deleteOperation.modifyRecordsCompletionBlock = { _, deleted, error in
                        if error != nil {
                            if error.code == CKErrorCode.PartialFailure.rawValue {
                                println("there was a problem completing the operation. The following records had problems: \(error.userInfo?[CKPartialErrorsByItemIDKey])")
                            }
                            
                            callback?(success: false)
                        } else {
                            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
                                let realm = RLMRealm.defaultRealm()
                                realm.transactionWithBlock {
                                    let cachedEntry = EntryCache(forPrimaryKey: cloudEntry.localId)
                                    if let dateReminder = cachedEntry.dateReminder {
                                        realm.deleteObject(dateReminder)
                                    }
                                    if let archivedAt = cachedEntry.archivedAt {
                                        realm.deleteObject(archivedAt)
                                    }
                                    realm.deleteObject(cachedEntry)
                                }
                                
                                callback?(success: true)
                            }
                        }
                    }
                    
                    self.database.addOperation(deleteOperation)
                } else {
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
                        let realm = RLMRealm.defaultRealm()
                        
                        realm.transactionWithBlock {
                            let cachedEntry = EntryCache(forPrimaryKey: entry.localId)
                            if let dateReminder = cachedEntry.dateReminder {
                                realm.deleteObject(dateReminder)
                            }
                            if let archivedAt = cachedEntry.archivedAt {
                                realm.deleteObject(archivedAt)
                            }
                            realm.deleteObject(cachedEntry)
                        }
                        
                        callback?(success: true)
                    }
                }
            }
        } else {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
                let realm = RLMRealm.defaultRealm()
                realm.transactionWithBlock {
                    let cachedEntry = EntryCache(forPrimaryKey: entry.localId)
                    if let dateReminder = cachedEntry.dateReminder {
                        realm.deleteObject(dateReminder)
                    }
                    if let archivedAt = cachedEntry.archivedAt {
                        realm.deleteObject(archivedAt)
                    }
                    realm.deleteObject(cachedEntry)
                }
                
                callback?(success: true)
            }
        }
    }
}
