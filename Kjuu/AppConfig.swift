//
//  AppConfig.swift
//  Kjuu
//
//  Created by Pascal Cremer on 07.02.15.
//  Copyright (c) 2015 Pascal Cremer. All rights reserved.
//

import Foundation

public class AppConfig {
    private struct Defaults {
        static let realmDatabaseFileName = "db"
    }
    
    public struct Extension {
        public static let applicationGroupsIdentifier = "group.Kjuu"
    }
    
    public enum Storage: Int {
        case Local = 0, Cloud
    }
    
    public class var sharedConfig: AppConfig {
        struct Singleton {
            static let sharedAppConfig = AppConfig()
        }
        
        return Singleton.sharedAppConfig
    }
    
    public class var realmDatabasePath: String? {
        if let sharedContainerURL = NSFileManager.defaultManager().containerURLForSecurityApplicationGroupIdentifier(Extension.applicationGroupsIdentifier) {
            return sharedContainerURL.URLByAppendingPathComponent(Defaults.realmDatabaseFileName).path
        }
        
        return nil
    }
}