//
//  StorageInterfaceTests.swift
//  CoreStore
//
//  Copyright © 2016 John Rommel Estropia
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import XCTest

@testable
import CoreStore


//MARK: - StorageInterfaceTests

final class StorageInterfaceTests: XCTestCase {
    
    @objc
    dynamic func test_ThatDefaultInMemoryStores_ConfigureCorrectly() {
        
        let store = InMemoryStore()
        XCTAssertEqual(store.dynamicType.storeType, NSInMemoryStoreType)
        XCTAssertNil(store.configuration)
        XCTAssertNil(store.storeOptions)
    }
    
    @objc
    dynamic func test_ThatCustomInMemoryStores_ConfigureCorrectly() {
        
        let store = InMemoryStore(configuration: "config1")
        XCTAssertEqual(store.dynamicType.storeType, NSInMemoryStoreType)
        XCTAssertEqual(store.configuration, "config1")
        XCTAssertNil(store.storeOptions)
    }
    
    @objc
    dynamic func test_ThatSQLiteStoreDefaultDirectories_AreCorrect() {
        
        #if os(tvOS)
            let systemDirectorySearchPath = FileManager.SearchPathDirectory.cachesDirectory
        #else
            let systemDirectorySearchPath = FileManager.SearchPathDirectory.applicationSupportDirectory
        #endif
        
        let defaultSystemDirectory = FileManager.default
            .urlsForDirectory(systemDirectorySearchPath, inDomains: .userDomainMask).first!
        
        let defaultRootDirectory = try! defaultSystemDirectory.appendingPathComponent(
            Bundle.main.bundleIdentifier ?? "com.CoreStore.DataStack",
            isDirectory: true
        )
        let applicationName = (Bundle.main.objectForInfoDictionaryKey("CFBundleName") as? String) ?? "CoreData"
        
        let defaultFileURL = try! defaultRootDirectory
            .appendingPathComponent(applicationName, isDirectory: false)
            .appendingPathExtension("sqlite")
        
        XCTAssertEqual(SQLiteStore.defaultRootDirectory, defaultRootDirectory)
        XCTAssertEqual(SQLiteStore.defaultFileURL, defaultFileURL)
    }
    
    @objc
    dynamic func test_ThatDefaultSQLiteStores_ConfigureCorrectly() {
        
        let store = SQLiteStore()
        XCTAssertEqual(store.dynamicType.storeType, NSSQLiteStoreType)
        XCTAssertNil(store.configuration)
        XCTAssertEqual(store.storeOptions, [NSSQLitePragmasOption: ["journal_mode": "WAL"]] as NSDictionary)
        
        XCTAssertEqual(store.fileURL, SQLiteStore.defaultFileURL)
        XCTAssertEqual(store.mappingModelBundles, Bundle.allBundles)
        XCTAssertEqual(store.localStorageOptions, .none)
    }
    
    @objc
    dynamic func test_ThatFileURLSQLiteStores_ConfigureCorrectly() {
        
        let fileURL = try! URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("db")
        let bundles = [Bundle(for: self.dynamicType)]
        
        let store = SQLiteStore(
            fileURL: fileURL,
            configuration: "config1",
            mappingModelBundles: bundles,
            localStorageOptions: .recreateStoreOnModelMismatch
        )
        XCTAssertEqual(store.dynamicType.storeType, NSSQLiteStoreType)
        XCTAssertEqual(store.configuration, "config1")
        XCTAssertEqual(store.storeOptions, [NSSQLitePragmasOption: ["journal_mode": "WAL"]] as NSDictionary)
        
        XCTAssertEqual(store.fileURL, fileURL)
        XCTAssertEqual(store.mappingModelBundles, bundles)
        XCTAssertEqual(store.localStorageOptions, [.recreateStoreOnModelMismatch])
    }
    
    @objc
    dynamic func test_ThatFileNameSQLiteStores_ConfigureCorrectly() {
        
        let fileName = UUID().uuidString + ".db"
        let bundles = [Bundle(for: self.dynamicType)]
        
        let store = SQLiteStore(
            fileName: fileName,
            configuration: "config1",
            mappingModelBundles: bundles,
            localStorageOptions: .recreateStoreOnModelMismatch
        )
        XCTAssertEqual(store.dynamicType.storeType, NSSQLiteStoreType)
        XCTAssertEqual(store.configuration, "config1")
        XCTAssertEqual(store.storeOptions, [NSSQLitePragmasOption: ["journal_mode": "WAL"]] as NSDictionary)
        
        XCTAssertEqual(try! store.fileURL.deletingLastPathComponent(), SQLiteStore.defaultRootDirectory)
        XCTAssertEqual(store.fileURL.lastPathComponent, fileName)
        XCTAssertEqual(store.mappingModelBundles, bundles)
        XCTAssertEqual(store.localStorageOptions, [.recreateStoreOnModelMismatch])
    }
    
    @objc
    dynamic func test_ThatLegacySQLiteStoreDefaultDirectories_AreCorrect() {
        
        #if os(tvOS)
            let systemDirectorySearchPath = FileManager.SearchPathDirectory.cachesDirectory
        #else
            let systemDirectorySearchPath = FileManager.SearchPathDirectory.applicationSupportDirectory
        #endif
        
        let legacyDefaultRootDirectory = FileManager.default.urlsForDirectory(
            systemDirectorySearchPath,
            inDomains: .userDomainMask
            ).first!
        
        let legacyDefaultFileURL = try! legacyDefaultRootDirectory
            .appendingPathComponent(DataStack.applicationName, isDirectory: false)
            .appendingPathExtension("sqlite")
        
        XCTAssertEqual(LegacySQLiteStore.defaultRootDirectory, legacyDefaultRootDirectory)
        XCTAssertEqual(LegacySQLiteStore.defaultFileURL, legacyDefaultFileURL)
    }
    
    @objc
    dynamic func test_ThatDefaultLegacySQLiteStores_ConfigureCorrectly() {
        
        let store = LegacySQLiteStore()
        XCTAssertEqual(store.dynamicType.storeType, NSSQLiteStoreType)
        XCTAssertNil(store.configuration)
        XCTAssertEqual(store.storeOptions, [NSSQLitePragmasOption: ["journal_mode": "WAL"]] as NSDictionary)
        
        XCTAssertEqual(store.fileURL, LegacySQLiteStore.defaultFileURL)
        XCTAssertEqual(store.mappingModelBundles, Bundle.allBundles)
        XCTAssertEqual(store.localStorageOptions, .none)
    }
    
    @objc
    dynamic func test_ThatFileURLLegacySQLiteStores_ConfigureCorrectly() {
        
        let fileURL = try! URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("db")
        let bundles = [Bundle(for: self.dynamicType)]
        
        let store = LegacySQLiteStore(
            fileURL: fileURL,
            configuration: "config1",
            mappingModelBundles: bundles,
            localStorageOptions: .recreateStoreOnModelMismatch
        )
        XCTAssertEqual(store.dynamicType.storeType, NSSQLiteStoreType)
        XCTAssertEqual(store.configuration, "config1")
        XCTAssertEqual(store.storeOptions, [NSSQLitePragmasOption: ["journal_mode": "WAL"]] as NSDictionary)
        
        XCTAssertEqual(store.fileURL, fileURL)
        XCTAssertEqual(store.mappingModelBundles, bundles)
        XCTAssertEqual(store.localStorageOptions, [.recreateStoreOnModelMismatch])
    }
    
    @objc
    dynamic func test_ThatFileNameLegacySQLiteStores_ConfigureCorrectly() {
        
        let fileName = UUID().uuidString + ".db"
        let bundles = [Bundle(for: self.dynamicType)]
        
        let store = LegacySQLiteStore(
            fileName: fileName,
            configuration: "config1",
            mappingModelBundles: bundles,
            localStorageOptions: .recreateStoreOnModelMismatch
        )
        XCTAssertEqual(store.dynamicType.storeType, NSSQLiteStoreType)
        XCTAssertEqual(store.configuration, "config1")
        XCTAssertEqual(store.storeOptions, [NSSQLitePragmasOption: ["journal_mode": "WAL"]] as NSDictionary)
        
        XCTAssertEqual(try! store.fileURL.deletingLastPathComponent(), LegacySQLiteStore.defaultRootDirectory)
        XCTAssertEqual(store.fileURL.lastPathComponent, fileName)
        XCTAssertEqual(store.mappingModelBundles, bundles)
        XCTAssertEqual(store.localStorageOptions, [.recreateStoreOnModelMismatch])
    }
}