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
    func synchronizeWithServer(callback: ((success: Bool) -> ())?)
    func getAllCachedEntries() -> [Entry]
    func lookupEntryByLocalID(localID: String, callback: ((entry: Entry?) -> ())?)
    func updateEntry(entry: Entry, callback: ((success: Bool) -> ())?)
    func deleteEntry(entry: Entry, callback: ((success: Bool) -> ())?)
}

class EntryManager: EntryManagerPrototol {
    let database: CKDatabase
    var changeToken: CKServerChangeToken?
    
    lazy var isCloudKitEnabled: Bool = {
        // TODO: Compute real value
        return true
    }()
    
    init(database: CKDatabase) {
        self.database = database
        self.changeToken = nil
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
    
    func synchronizeWithServer(callback: ((success: Bool) -> ())?) {
        if isCloudKitEnabled {
            let recordZone = CKRecordZone(zoneName: AppConfig.customRecordZoneName)
            let fetchChangesOperation = CKFetchRecordChangesOperation(recordZoneID: recordZone.zoneID, previousServerChangeToken: changeToken)
            
            var changedEntries = [Entry]()
            var deletedServerIDs = [String]()
            
            fetchChangesOperation.recordChangedBlock = { record in
                changedEntries.append(Entry(record: record))
            }
            
            fetchChangesOperation.recordWithIDWasDeletedBlock = { recordID in
                deletedServerIDs.append(recordID.recordName)
            }
            
            fetchChangesOperation.fetchRecordChangesCompletionBlock = { (changeToken, _, error) in
                if error != nil {
                    println("there was an error: \(error.localizedDescription)")
                    callback?(success: false)
                } else {
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
                        let realm = RLMRealm.defaultRealm()
                        realm.transactionWithBlock {
                            for entry in changedEntries {
                                // Determine if entry is already in cache
                                if let cachedEntry = EntryCache(forPrimaryKey: entry.localId) {
                                    if let dateReminder = cachedEntry.dateReminder {
                                        realm.deleteObject(dateReminder)
                                    }
                                    if let archivedAt = cachedEntry.archivedAt {
                                        realm.deleteObject(archivedAt)
                                    }
                                }
                                
                                realm.addOrUpdateObject(entry.toRealmObject())
                            }
                            
                            let results = EntryCache.objectsWithPredicate(NSPredicate(format: "serverId IN %@", deletedServerIDs))
                            for object in results {
                                let cachedEntry = object as! EntryCache
                                if let dateReminder = cachedEntry.dateReminder {
                                    realm.deleteObject(dateReminder)
                                }
                                if let archivedAt = cachedEntry.archivedAt {
                                    realm.deleteObject(archivedAt)
                                }
                            }
                            
                            realm.deleteObjects(results)
                        }
                        
                        self.changeToken = changeToken
                        callback?(success: true)
                    }
                }
            }
            
            database.addOperation(fetchChangesOperation)
        }
    }
    
    func getAllCachedEntries() -> [Entry] {
        var entries = [Entry]()
        for object in EntryCache.allObjects() {
            entries.append(Entry.fromRealmObject(object as! EntryCache))
        }
        
        return entries
    }
    
    func lookupEntryByLocalID(localID: String, callback: ((entry: Entry?) -> ())?) {
        if isCloudKitEnabled {
            let query = CKQuery(recordType: "Entry", predicate: NSPredicate(format: "localId = %@", localID))
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
            println("cannot look up entry, CloudKit is not enabled!")
            callback?(entry: nil)
        }
    }
    
    func updateEntry(entry: Entry, callback: ((success: Bool) -> ())?) {
        let cacheUpdateBlock: ((entry: Entry) -> (() -> Void)) = { entry in
            return {
                let realm = RLMRealm.defaultRealm()
                realm.transactionWithBlock {
                    if let cachedEntry = EntryCache(forPrimaryKey: entry.localId) {
                        if let dateReminder = cachedEntry.dateReminder {
                            realm.deleteObject(dateReminder)
                        }
                        if let archivedAt = cachedEntry.archivedAt {
                            realm.deleteObject(archivedAt)
                        }
                    }
                    
                    realm.addOrUpdateObject(entry.toRealmObject())
                }
                
                callback?(success: true)
            }
        }
        
        if isCloudKitEnabled {
            let localID = entry.localId
            lookupEntryByLocalID(localID) { cloudEntry in
                var record: CKRecord!
                if let cloudEntry = cloudEntry {
                    cloudEntry.url = entry.url
                    cloudEntry.title = entry.title
                    cloudEntry.description = entry.description
                    cloudEntry.notificationType = entry.notificationType
                    cloudEntry.archivedAt = entry.archivedAt
                    
                    record = cloudEntry.record
                } else {
                    entry.localId = localID
                    record = entry.record
                }
                
                let updateOperation = CKModifyRecordsOperation(recordsToSave: [record!], recordIDsToDelete: nil)
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
                        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), cacheUpdateBlock(entry: entry))
                    }
                }
                
                self.database.addOperation(updateOperation)
            }
        } else {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), cacheUpdateBlock(entry: entry))
        }
    }
    
    func deleteEntry(entry: Entry, callback: ((success: Bool) -> ())?) {
        let deleteFromCacheBlock: ((entry: Entry) -> (() -> Void)) = { entry in
            return {
                let realm = RLMRealm.defaultRealm()
                realm.transactionWithBlock {
                    if let cachedEntry = EntryCache(forPrimaryKey: entry.localId) {
                        if let dateReminder = cachedEntry.dateReminder {
                            realm.deleteObject(dateReminder)
                        }
                        if let archivedAt = cachedEntry.archivedAt {
                            realm.deleteObject(archivedAt)
                        }
                        
                        realm.deleteObject(cachedEntry)
                    }
                }
                
                callback?(success: true)
            }
        }
        
        if isCloudKitEnabled {
            lookupEntryByLocalID(entry.localId) { cloudEntry in
                if let cloudEntry = cloudEntry {
                    let recordZone = CKRecordZone(zoneName: AppConfig.customRecordZoneName)
                    let deleteOperation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [CKRecordID(recordName: cloudEntry.id, zoneID: recordZone.zoneID)])
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
                            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), deleteFromCacheBlock(entry: cloudEntry))
                        }
                    }
                    
                    self.database.addOperation(deleteOperation)
                } else {
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), deleteFromCacheBlock(entry: entry))
                }
            }
        } else {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), deleteFromCacheBlock(entry: entry))
        }
    }
}
