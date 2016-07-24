//
//  ListMonitor.swift
//  CoreStore
//
//  Copyright © 2015 John Rommel Estropia
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

import Foundation
import CoreData
#if USE_FRAMEWORKS
    import GCDKit
#endif


#if os(iOS) || os(watchOS) || os(tvOS)

// MARK: - ListMonitor

/**
 The `ListMonitor` monitors changes to a list of `NSManagedObject` instances. Observers that implement the `ListObserver` protocol may then register themselves to the `ListMonitor`'s `addObserver(_:)` method:
 ```
 let monitor = CoreStore.monitorList(
     From<MyPersonEntity>(),
     Where("title", isEqualTo: "Engineer"),
     OrderBy(.ascending("lastName"))
 )
 monitor.addObserver(self)
 ```
 The `ListMonitor` instance needs to be held on (retained) for as long as the list needs to be observed.
 Observers registered via `addObserver(_:)` are not retained. `ListMonitor` only keeps a `weak` reference to all observers, thus keeping itself free from retain-cycles.
 
 Lists created with `monitorList(...)` keep a single-section list of objects, where each object can be accessed by index:
 ```
 let firstPerson: MyPersonEntity = monitor[0]
 ```
 Accessing the list with an index above the valid range will raise an exception.
 
 Creating a sectioned-list is also possible with the `monitorSectionedList(...)` method:
 ```
 let monitor = CoreStore.monitorSectionedList(
     From<MyPersonEntity>(),
     SectionBy("age") { "Age \($0)" },
     Where("title", isEqualTo: "Engineer"),
     OrderBy(.ascending("lastName"))
 )
 monitor.addObserver(self)
 ```
 Objects from `ListMonitor`s created this way can be accessed either by an `NSIndexPath` or a tuple:
 ```
 let indexPath = NSIndexPath(forItem: 3, inSection: 2)
 let person1 = monitor[indexPath]
 let person2 = monitor[2, 3]
 ```
 In the example above, both `person1` and `person2` will contain the object at section=2, index=3.
 */
public final class ListMonitor<T: NSManagedObject>: Hashable {
    
    // MARK: Public (Accessors)
    
    /**
     Returns the object at the given index within the first section. This subscript indexer is typically used for `ListMonitor`s created with `monitorList(_:)`.
     
     - parameter index: the index of the object. Using an index above the valid range will raise an exception.
     - returns: the `NSManagedObject` at the specified index
     */
    public subscript(index: Int) -> T {
        
        return self.objectsInAllSections()[index]
    }
    
    /**
     Returns the object at the given index, or `nil` if out of bounds. This subscript indexer is typically used for `ListMonitor`s created with `monitorList(_:)`.
     
     - parameter index: the index for the object. Using an index above the valid range will return `nil`.
     - returns: the `NSManagedObject` at the specified index, or `nil` if out of bounds
     */
    public subscript(safeIndex index: Int) -> T? {
        
        let objects = self.objectsInAllSections()
        guard objects.indices.contains(index) else {
            
            return nil
        }
        return objects[index]
    }
    
    /**
     Returns the object at the given `sectionIndex` and `itemIndex`. This subscript indexer is typically used for `ListMonitor`s created with `monitorSectionedList(_:)`.
     
     - parameter sectionIndex: the section index for the object. Using a `sectionIndex` with an invalid range will raise an exception.
     - parameter itemIndex: the index for the object within the section. Using an `itemIndex` with an invalid range will raise an exception.
     - returns: the `NSManagedObject` at the specified section and item index
     */
    public subscript(sectionIndex: Int, itemIndex: Int) -> T {
        
        return self[NSIndexPath(indexes: [sectionIndex, itemIndex], length: 2) as IndexPath]
    }
    
    /**
     Returns the object at the given section and item index, or `nil` if out of bounds. This subscript indexer is typically used for `ListMonitor`s created with `monitorSectionedList(_:)`.
     
     - parameter sectionIndex: the section index for the object. Using a `sectionIndex` with an invalid range will return `nil`.
     - parameter itemIndex: the index for the object within the section. Using an `itemIndex` with an invalid range will return `nil`.
     - returns: the `NSManagedObject` at the specified section and item index, or `nil` if out of bounds
     */
    public subscript(safeSectionIndex sectionIndex: Int, safeItemIndex itemIndex: Int) -> T? {
        
        guard let section = self.sectionInfoAtIndex(safeSectionIndex: sectionIndex) else {
            
            return nil
        }
        guard itemIndex >= 0 && itemIndex < section.numberOfObjects else {
            
            return nil
        }
        return section.objects?[itemIndex] as? T
    }
    
    /**
     Returns the object at the given `NSIndexPath`. This subscript indexer is typically used for `ListMonitor`s created with `monitorSectionedList(_:)`.
     
     - parameter indexPath: the `NSIndexPath` for the object. Using an `indexPath` with an invalid range will raise an exception.
     - returns: the `NSManagedObject` at the specified index path
     */
    public subscript(indexPath: IndexPath) -> T {
        
        CoreStore.assert(
            !self.isPendingRefetch || Thread.isMainThread,
            "Attempted to access a \(cs_typeName(self)) outside the main thread while a refetch is in progress."
        )
        return self.fetchedResultsController.object(at: indexPath) as! T
    }
    
    /**
     Returns the object at the given `NSIndexPath`, or `nil` if out of bounds. This subscript indexer is typically used for `ListMonitor`s created with `monitorSectionedList(_:)`.
     
     - parameter indexPath: the `NSIndexPath` for the object. Using an `indexPath` with an invalid range will return `nil`.
     - returns: the `NSManagedObject` at the specified index path, or `nil` if out of bounds
     */
    public subscript(safeIndexPath indexPath: IndexPath) -> T? {
        
        return self[
            safeSectionIndex: indexPath[0],
            safeItemIndex: indexPath[1]
        ]
    }
    
    /**
     Checks if the `ListMonitor` has at least one section
     
     - returns: `true` if at least one section exists, `false` otherwise
     */
    public func hasSections() -> Bool {
        
        return self.sections().count > 0
    }
    
    /**
     Checks if the `ListMonitor` has at least one object in any section.
     
     - returns: `true` if at least one object in any section exists, `false` otherwise
     */
    public func hasObjects() -> Bool {
        
        return self.numberOfObjects() > 0
    }
    
    /**
     Checks if the `ListMonitor` has at least one object the specified section.
     
     - parameter section: the section index. Using an index outside the valid range will return `false`.
     - returns: `true` if at least one object in the specified section exists, `false` otherwise
     */
    public func hasObjectsInSection(_ section: Int) -> Bool {
        
        return self.numberOfObjectsInSection(safeSectionIndex: section) > 0
    }
    
    /**
     Returns all objects in all sections
     
     - returns: all objects in all sections
     */
    public func objectsInAllSections() -> [T] {
        
        CoreStore.assert(
            !self.isPendingRefetch || Thread.isMainThread,
            "Attempted to access a \(cs_typeName(self)) outside the main thread while a refetch is in progress."
        )
        return (self.fetchedResultsController.fetchedObjects as? [T]) ?? []
    }
    
    /**
     Returns all objects in the specified section
     
     - parameter section: the section index. Using an index outside the valid range will raise an exception.
     - returns: all objects in the specified section
     */
    public func objectsInSection(_ section: Int) -> [T] {
        
        return (self.sectionInfoAtIndex(section).objects as? [T]) ?? []
    }
    
    /**
     Returns all objects in the specified section, or `nil` if out of bounds.
     
     - parameter section: the section index. Using an index outside the valid range will return `nil`.
     - returns: all objects in the specified section
     */
    public func objectsInSection(safeSectionIndex section: Int) -> [T]? {
        
        return (self.sectionInfoAtIndex(safeSectionIndex: section)?.objects as? [T]) ?? []
    }
    
    /**
     Returns the number of sections
     
     - returns: the number of sections
     */
    public func numberOfSections() -> Int {
        
        CoreStore.assert(
            !self.isPendingRefetch || Thread.isMainThread,
            "Attempted to access a \(cs_typeName(self)) outside the main thread while a refetch is in progress."
        )
        return self.fetchedResultsController.sections?.count ?? 0
    }
    
    /**
     Returns the number of objects in all sections
     
     - returns: the number of objects in all sections
     */
    public func numberOfObjects() -> Int {
        
        CoreStore.assert(
            !self.isPendingRefetch || Thread.isMainThread,
            "Attempted to access a \(cs_typeName(self)) outside the main thread while a refetch is in progress."
        )
        return self.fetchedResultsController.fetchedObjects?.count ?? 0
    }
    
    /**
     Returns the number of objects in the specified section
     
     - parameter section: the section index. Using an index outside the valid range will raise an exception.
     - returns: the number of objects in the specified section
     */
    public func numberOfObjectsInSection(_ section: Int) -> Int {
        
        return self.sectionInfoAtIndex(section).numberOfObjects
    }
    
    /**
     Returns the number of objects in the specified section, or `nil` if out of bounds.
     
     - parameter section: the section index. Using an index outside the valid range will return `nil`.
     - returns: the number of objects in the specified section
     */
    public func numberOfObjectsInSection(safeSectionIndex section: Int) -> Int? {
        
        return self.sectionInfoAtIndex(safeSectionIndex: section)?.numberOfObjects
    }
    
    /**
     Returns the `NSFetchedResultsSectionInfo` for the specified section
     
     - parameter section: the section index. Using an index outside the valid range will raise an exception.
     - returns: the `NSFetchedResultsSectionInfo` for the specified section
     */
    public func sectionInfoAtIndex(_ section: Int) -> NSFetchedResultsSectionInfo {
        
        CoreStore.assert(
            !self.isPendingRefetch || Thread.isMainThread,
            "Attempted to access a \(cs_typeName(self)) outside the main thread while a refetch is in progress."
        )
        return self.fetchedResultsController.sections![section]
    }
    
    /**
     Returns the `NSFetchedResultsSectionInfo` for the specified section, or `nil` if out of bounds.
     
     - parameter section: the section index. Using an index outside the valid range will return `nil`.
     - returns: the `NSFetchedResultsSectionInfo` for the specified section, or `nil` if the section index is out of bounds.
     */
    public func sectionInfoAtIndex(safeSectionIndex section: Int) -> NSFetchedResultsSectionInfo? {
        
        CoreStore.assert(
            !self.isPendingRefetch || Thread.isMainThread,
            "Attempted to access a \(cs_typeName(self)) outside the main thread while a refetch is in progress."
        )
        guard section >= 0 else {
            
            return nil
        }
        guard let sections = self.fetchedResultsController.sections, section < sections.count else {
            
            return nil
        }
        return sections[section]
    }
    
    /**
     Returns the `NSFetchedResultsSectionInfo`s for all sections
     
     - returns: the `NSFetchedResultsSectionInfo`s for all sections
     */
    public func sections() -> [NSFetchedResultsSectionInfo] {
        
        CoreStore.assert(
            !self.isPendingRefetch || Thread.isMainThread,
            "Attempted to access a \(cs_typeName(self)) outside the main thread while a refetch is in progress."
        )
        return self.fetchedResultsController.sections ?? []
    }
    
    /**
     Returns the target section for a specified "Section Index" title and index.
     
     - parameter title: the title of the Section Index
     - parameter index: the index of the Section Index
     - returns: the target section for the specified "Section Index" title and index.
     */
    public func targetSectionForSectionIndex(title: String, index: Int) -> Int {
        
        CoreStore.assert(
            !self.isPendingRefetch || Thread.isMainThread,
            "Attempted to access a \(cs_typeName(self)) outside the main thread while a refetch is in progress."
        )
        return self.fetchedResultsController.section(forSectionIndexTitle: title, at: index)
    }
    
    /**
     Returns the section index titles for all sections
     
     - returns: the section index titles for all sections
     */
    public func sectionIndexTitles() -> [String] {
        
        CoreStore.assert(
            !self.isPendingRefetch || Thread.isMainThread,
            "Attempted to access a \(cs_typeName(self)) outside the main thread while a refetch is in progress."
        )
        return self.fetchedResultsController.sectionIndexTitles
    }
    
    /**
     Returns the index of the `NSManagedObject` if it exists in the `ListMonitor`'s fetched objects, or `nil` if not found.
     
     - parameter object: the `NSManagedObject` to search the index of
     - returns: the index of the `NSManagedObject` if it exists in the `ListMonitor`'s fetched objects, or `nil` if not found.
     */
    public func indexOf(_ object: T) -> Int? {
        
        CoreStore.assert(
            !self.isPendingRefetch || Thread.isMainThread,
            "Attempted to access a \(cs_typeName(self)) outside the main thread while a refetch is in progress."
        )
        return (self.fetchedResultsController.fetchedObjects as? [T] ?? []).index(of: object)
    }
    
    /**
     Returns the `NSIndexPath` of the `NSManagedObject` if it exists in the `ListMonitor`'s fetched objects, or `nil` if not found.
     
     - parameter object: the `NSManagedObject` to search the index of
     - returns: the `NSIndexPath` of the `NSManagedObject` if it exists in the `ListMonitor`'s fetched objects, or `nil` if not found.
     */
    public func indexPathOf(_ object: T) -> IndexPath? {
        
        CoreStore.assert(
            !self.isPendingRefetch || Thread.isMainThread,
            "Attempted to access a \(cs_typeName(self)) outside the main thread while a refetch is in progress."
        )
        return self.fetchedResultsController.indexPath(forObject: object)
    }
    
    
    // MARK: Public (Observers)
    
    /**
     Registers a `ListObserver` to be notified when changes to the receiver's list occur.
     
     To prevent retain-cycles, `ListMonitor` only keeps `weak` references to its observers.
     
     For thread safety, this method needs to be called from the main thread. An assertion failure will occur (on debug builds only) if called from any thread other than the main thread.
     
     Calling `addObserver(_:)` multiple times on the same observer is safe, as `ListMonitor` unregisters previous notifications to the observer before re-registering them.
     
     - parameter observer: a `ListObserver` to send change notifications to
     */
    public func addObserver<U: ListObserver where U.ListEntityType == T>(_ observer: U) {
        
        self.unregisterObserver(observer)
        self.registerObserver(
            observer,
            willChange: { (observer, monitor) in
                
                observer.listMonitorWillChange(monitor)
            },
            didChange: { (observer, monitor) in
                
                observer.listMonitorDidChange(monitor)
            },
            willRefetch: { (observer, monitor) in
                
                observer.listMonitorWillRefetch(monitor)
            },
            didRefetch: { (observer, monitor) in
                
                observer.listMonitorDidRefetch(monitor)
            }
        )
    }
    
    /**
     Registers a `ListObjectObserver` to be notified when changes to the receiver's list occur.
     
     To prevent retain-cycles, `ListMonitor` only keeps `weak` references to its observers.
     
     For thread safety, this method needs to be called from the main thread. An assertion failure will occur (on debug builds only) if called from any thread other than the main thread.
     
     Calling `addObserver(_:)` multiple times on the same observer is safe, as `ListMonitor` unregisters previous notifications to the observer before re-registering them.
     
     - parameter observer: a `ListObjectObserver` to send change notifications to
     */
    public func addObserver<U: ListObjectObserver where U.ListEntityType == T>(_ observer: U) {
        
        self.unregisterObserver(observer)
        self.registerObserver(
            observer,
            willChange: { (observer, monitor) in
                
                observer.listMonitorWillChange(monitor)
            },
            didChange: { (observer, monitor) in
                
                observer.listMonitorDidChange(monitor)
            },
            willRefetch: { (observer, monitor) in
                
                observer.listMonitorWillRefetch(monitor)
            },
            didRefetch: { (observer, monitor) in
                
                observer.listMonitorDidRefetch(monitor)
            }
        )
        self.registerObserver(
            observer,
            didInsertObject: { (observer, monitor, object, toIndexPath) in
                
                observer.listMonitor(monitor, didInsertObject: object, toIndexPath: toIndexPath)
            },
            didDeleteObject: { (observer, monitor, object, fromIndexPath) in
                
                observer.listMonitor(monitor, didDeleteObject: object, fromIndexPath: fromIndexPath)
            },
            didUpdateObject: { (observer, monitor, object, atIndexPath) in
                
                observer.listMonitor(monitor, didUpdateObject: object, atIndexPath: atIndexPath)
            },
            didMoveObject: { (observer, monitor, object, fromIndexPath, toIndexPath) in
                
                observer.listMonitor(monitor, didMoveObject: object, fromIndexPath: fromIndexPath, toIndexPath: toIndexPath)
            }
        )
    }
    
    /**
     Registers a `ListSectionObserver` to be notified when changes to the receiver's list occur.
     
     To prevent retain-cycles, `ListMonitor` only keeps `weak` references to its observers.
     
     For thread safety, this method needs to be called from the main thread. An assertion failure will occur (on debug builds only) if called from any thread other than the main thread.
     
     Calling `addObserver(_:)` multiple times on the same observer is safe, as `ListMonitor` unregisters previous notifications to the observer before re-registering them.
     
     - parameter observer: a `ListSectionObserver` to send change notifications to
     */
    public func addObserver<U: ListSectionObserver where U.ListEntityType == T>(_ observer: U) {
        
        self.unregisterObserver(observer)
        self.registerObserver(
            observer,
            willChange: { (observer, monitor) in
                
                observer.listMonitorWillChange(monitor)
            },
            didChange: { (observer, monitor) in
                
                observer.listMonitorDidChange(monitor)
            },
            willRefetch: { (observer, monitor) in
                
                observer.listMonitorWillRefetch(monitor)
            },
            didRefetch: { (observer, monitor) in
                
                observer.listMonitorDidRefetch(monitor)
            }
        )
        self.registerObserver(
            observer,
            didInsertObject: { (observer, monitor, object, toIndexPath) in
                
                observer.listMonitor(monitor, didInsertObject: object, toIndexPath: toIndexPath)
            },
            didDeleteObject: { (observer, monitor, object, fromIndexPath) in
                
                observer.listMonitor(monitor, didDeleteObject: object, fromIndexPath: fromIndexPath)
            },
            didUpdateObject: { (observer, monitor, object, atIndexPath) in
                
                observer.listMonitor(monitor, didUpdateObject: object, atIndexPath: atIndexPath)
            },
            didMoveObject: { (observer, monitor, object, fromIndexPath, toIndexPath) in
                
                observer.listMonitor(monitor, didMoveObject: object, fromIndexPath: fromIndexPath, toIndexPath: toIndexPath)
            }
        )
        self.registerObserver(
            observer,
            didInsertSection: { (observer, monitor, sectionInfo, toIndex) in
                
                observer.listMonitor(monitor, didInsertSection: sectionInfo, toSectionIndex: toIndex)
            },
            didDeleteSection: { (observer, monitor, sectionInfo, fromIndex) in
                
               observer.listMonitor(monitor, didDeleteSection: sectionInfo, fromSectionIndex: fromIndex)
            }
        )
    }
    
    /**
     Unregisters a `ListObserver` from receiving notifications for changes to the receiver's list.
     
     For thread safety, this method needs to be called from the main thread. An assertion failure will occur (on debug builds only) if called from any thread other than the main thread.
     
     - parameter observer: a `ListObserver` to unregister notifications to
     */
    public func removeObserver<U: ListObserver where U.ListEntityType == T>(_ observer: U) {
        
        self.unregisterObserver(observer)
    }
    
    
    // MARK: Public (Refetching)
    
    /**
     Returns `true` if a call to `refetch(...)` was made to the `ListMonitor` and is currently waiting for the fetching to complete. Returns `false` otherwise.
     */
    public private(set) var isPendingRefetch = false
    
    /**
     Asks the `ListMonitor` to refetch its objects using the specified series of `FetchClause`s. Note that this method does not execute the fetch immediately; the actual fetching will happen after the `NSFetchedResultsController`'s last `controllerDidChangeContent(_:)` notification completes.
     
     `refetch(...)` broadcasts `listMonitorWillRefetch(...)` to its observers immediately, and then `listMonitorDidRefetch(...)` after the new fetch request completes.
     
     - parameter fetchClauses: a series of `FetchClause` instances for fetching the object list. Accepts `Where`, `OrderBy`, and `Tweak` clauses. Note that only specified clauses will be changed; unspecified clauses will use previous values.
     */
    public func refetch(_ fetchClauses: FetchClause...) {
        
        self.refetch(fetchClauses)
    }
    
    /**
     Asks the `ListMonitor` to refetch its objects using the specified series of `FetchClause`s. Note that this method does not execute the fetch immediately; the actual fetching will happen after the `NSFetchedResultsController`'s last `controllerDidChangeContent(_:)` notification completes.
     
     `refetch(...)` broadcasts `listMonitorWillRefetch(...)` to its observers immediately, and then `listMonitorDidRefetch(...)` after the new fetch request completes.
     
     - parameter fetchClauses: a series of `FetchClause` instances for fetching the object list. Accepts `Where`, `OrderBy`, and `Tweak` clauses. Note that only specified clauses will be changed; unspecified clauses will use previous values.
     */
    public func refetch(_ fetchClauses: [FetchClause]) {
        
        self.refetch { (fetchRequest) in
            
            fetchClauses.forEach { $0.applyToFetchRequest(fetchRequest) }
        }
    }
    
    
    // MARK: Hashable
    
    public var hashValue: Int {
        
        return ObjectIdentifier(self).hashValue
    }
    
    
    // MARK: Internal
    
    internal convenience init(dataStack: DataStack, from: From<T>, sectionBy: SectionBy?, applyFetchClauses: (fetchRequest: NSFetchRequest<NSManagedObject>) -> Void) {
        
        self.init(
            context: dataStack.mainContext,
            transactionQueue: dataStack.childTransactionQueue,
            from: from,
            sectionBy: sectionBy,
            applyFetchClauses: applyFetchClauses,
            createAsynchronously: nil
        )
    }
    
    internal convenience init(dataStack: DataStack, from: From<T>, sectionBy: SectionBy?, applyFetchClauses: (fetchRequest: NSFetchRequest<NSManagedObject>) -> Void, createAsynchronously: (ListMonitor<T>) -> Void) {
        
        self.init(
            context: dataStack.mainContext,
            transactionQueue: dataStack.childTransactionQueue,
            from: from,
            sectionBy: sectionBy,
            applyFetchClauses: applyFetchClauses,
            createAsynchronously: createAsynchronously
        )
    }
    
    internal convenience init(unsafeTransaction: UnsafeDataTransaction, from: From<T>, sectionBy: SectionBy?, applyFetchClauses: (fetchRequest: NSFetchRequest<NSManagedObject>) -> Void) {
        
        self.init(
            context: unsafeTransaction.context,
            transactionQueue: unsafeTransaction.transactionQueue,
            from: from,
            sectionBy: sectionBy,
            applyFetchClauses: applyFetchClauses,
            createAsynchronously: nil
        )
    }
    
    internal convenience init(unsafeTransaction: UnsafeDataTransaction, from: From<T>, sectionBy: SectionBy?, applyFetchClauses: (fetchRequest: NSFetchRequest<NSManagedObject>) -> Void, createAsynchronously: (ListMonitor<T>) -> Void) {
        
        self.init(
            context: unsafeTransaction.context,
            transactionQueue: unsafeTransaction.transactionQueue,
            from: from,
            sectionBy: sectionBy,
            applyFetchClauses: applyFetchClauses,
            createAsynchronously: createAsynchronously
        )
    }
    
    internal func upcast() -> ListMonitor<NSManagedObject> {
        
        return unsafeBitCast(self, to: ListMonitor<NSManagedObject>.self)
    }
    
    internal func registerChangeNotification(_ notificationKey: UnsafePointer<Void>, name: Notification.Name, toObserver observer: AnyObject, callback: (monitor: ListMonitor<T>) -> Void) {
        
        cs_setAssociatedRetainedObject(
            NotificationObserver(
                notificationName: name,
                object: self,
                closure: { [weak self] (note) -> Void in
                    
                    guard let `self` = self else {
                        
                        return
                    }
                    callback(monitor: self)
                }
            ),
            forKey: notificationKey,
            inObject: observer
        )
    }
    
    internal func registerObjectNotification(_ notificationKey: UnsafePointer<Void>, name: Notification.Name, toObserver observer: AnyObject, callback: (monitor: ListMonitor<T>, object: T, indexPath: IndexPath?, newIndexPath: IndexPath?) -> Void) {
        
        cs_setAssociatedRetainedObject(
            NotificationObserver(
                notificationName: name,
                object: self,
                closure: { [weak self] (note) -> Void in
                    
                    guard let `self` = self,
                        let userInfo = note.userInfo,
                        let object = userInfo[String(NSManagedObject.self)] as? T else {
                            
                            return
                    }
                    callback(
                        monitor: self,
                        object: object,
                        indexPath: userInfo[String(IndexPath.self)] as? IndexPath,
                        newIndexPath: userInfo["\(String(IndexPath.self)).New"] as? IndexPath
                    )
                }
            ),
            forKey: notificationKey,
            inObject: observer
        )
    }
    
    internal func registerSectionNotification(_ notificationKey: UnsafePointer<Void>, name: Notification.Name, toObserver observer: AnyObject, callback: (monitor: ListMonitor<T>, sectionInfo: NSFetchedResultsSectionInfo, sectionIndex: Int) -> Void) {
        
        cs_setAssociatedRetainedObject(
            NotificationObserver(
                notificationName: name,
                object: self,
                closure: { [weak self] (note) -> Void in
                    
                    guard let `self` = self,
                        let userInfo = note.userInfo,
                        let sectionInfo = userInfo[String(NSFetchedResultsSectionInfo.self)] as? NSFetchedResultsSectionInfo,
                        let sectionIndex = (userInfo[String(NSNumber.self)] as? NSNumber)?.intValue else {
                            
                            return
                    }
                    callback(
                        monitor: self,
                        sectionInfo: sectionInfo,
                        sectionIndex: sectionIndex
                    )
                }
            ),
            forKey: notificationKey,
            inObject: observer
        )
    }
    
    internal func registerObserver<U: AnyObject>(_ observer: U, willChange: (observer: U, monitor: ListMonitor<T>) -> Void, didChange: (observer: U, monitor: ListMonitor<T>) -> Void, willRefetch: (observer: U, monitor: ListMonitor<T>) -> Void, didRefetch: (observer: U, monitor: ListMonitor<T>) -> Void) {
        
        CoreStore.assert(
            Thread.isMainThread,
            "Attempted to add an observer of type \(cs_typeName(observer)) outside the main thread."
        )
        self.registerChangeNotification(
            &self.willChangeListKey,
            name: Notification.Name.listMonitorWillChangeList,
            toObserver: observer,
            callback: { [weak observer] (monitor) -> Void in
                
                guard let observer = observer else {
                    
                    return
                }
                willChange(observer: observer, monitor: monitor)
            }
        )
        self.registerChangeNotification(
            &self.didChangeListKey,
            name: Notification.Name.listMonitorDidChangeList,
            toObserver: observer,
            callback: { [weak observer] (monitor) -> Void in
                
                guard let observer = observer else {
                    
                    return
                }
                didChange(observer: observer, monitor: monitor)
            }
        )
        self.registerChangeNotification(
            &self.willRefetchListKey,
            name: Notification.Name.listMonitorWillRefetchList,
            toObserver: observer,
            callback: { [weak observer] (monitor) -> Void in
                
                guard let observer = observer else {
                    
                    return
                }
                willRefetch(observer: observer, monitor: monitor)
            }
        )
        self.registerChangeNotification(
            &self.didRefetchListKey,
            name: Notification.Name.listMonitorDidRefetchList,
            toObserver: observer,
            callback: { [weak observer] (monitor) -> Void in
                
                guard let observer = observer else {
                    
                    return
                }
                didRefetch(observer: observer, monitor: monitor)
            }
        )
    }
    
    internal func registerObserver<U: AnyObject>(_ observer: U, didInsertObject: (observer: U, monitor: ListMonitor<T>, object: T, toIndexPath: IndexPath) -> Void, didDeleteObject: (observer: U, monitor: ListMonitor<T>, object: T, fromIndexPath: IndexPath) -> Void, didUpdateObject: (observer: U, monitor: ListMonitor<T>, object: T, atIndexPath: IndexPath) -> Void, didMoveObject: (observer: U, monitor: ListMonitor<T>, object: T, fromIndexPath: IndexPath, toIndexPath: IndexPath) -> Void) {
        
        CoreStore.assert(
            Thread.isMainThread,
            "Attempted to add an observer of type \(cs_typeName(observer)) outside the main thread."
        )
        
        self.registerObjectNotification(
            &self.didInsertObjectKey,
            name: Notification.Name.listMonitorDidInsertObject,
            toObserver: observer,
            callback: { [weak observer] (monitor, object, indexPath, newIndexPath) -> Void in
                
                guard let observer = observer else {
                    
                    return
                }
                didInsertObject(
                    observer: observer,
                    monitor: monitor,
                    object: object,
                    toIndexPath: newIndexPath!
                )
            }
        )
        self.registerObjectNotification(
            &self.didDeleteObjectKey,
            name: Notification.Name.listMonitorDidDeleteObject,
            toObserver: observer,
            callback: { [weak observer] (monitor, object, indexPath, newIndexPath) -> Void in
                
                guard let observer = observer else {
                    
                    return
                }
                didDeleteObject(
                    observer: observer,
                    monitor: monitor,
                    object: object,
                    fromIndexPath: indexPath!
                )
            }
        )
        self.registerObjectNotification(
            &self.didUpdateObjectKey,
            name: Notification.Name.listMonitorDidUpdateObject,
            toObserver: observer,
            callback: { [weak observer] (monitor, object, indexPath, newIndexPath) -> Void in
                
                guard let observer = observer else {
                    
                    return
                }
                didUpdateObject(
                    observer: observer,
                    monitor: monitor,
                    object: object,
                    atIndexPath: indexPath!
                )
            }
        )
        self.registerObjectNotification(
            &self.didMoveObjectKey,
            name: Notification.Name.listMonitorDidMoveObject,
            toObserver: observer,
            callback: { [weak observer] (monitor, object, indexPath, newIndexPath) -> Void in
                
                guard let observer = observer else {
                    
                    return
                }
                didMoveObject(
                    observer: observer,
                    monitor: monitor,
                    object: object,
                    fromIndexPath: indexPath!,
                    toIndexPath: newIndexPath!
                )
            }
        )
    }
    
    internal func registerObserver<U: AnyObject>(_ observer: U, didInsertSection: (observer: U, monitor: ListMonitor<T>, sectionInfo: NSFetchedResultsSectionInfo, toIndex: Int) -> Void, didDeleteSection: (observer: U, monitor: ListMonitor<T>, sectionInfo: NSFetchedResultsSectionInfo, fromIndex: Int) -> Void) {
        
        CoreStore.assert(
            Thread.isMainThread,
            "Attempted to add an observer of type \(cs_typeName(observer)) outside the main thread."
        )
        
        self.registerSectionNotification(
            &self.didInsertSectionKey,
            name: Notification.Name.listMonitorDidInsertSection,
            toObserver: observer,
            callback: { [weak observer] (monitor, sectionInfo, sectionIndex) -> Void in
                
                guard let observer = observer else {
                    
                    return
                }
                didInsertSection(
                    observer: observer,
                    monitor: monitor,
                    sectionInfo: sectionInfo,
                    toIndex: sectionIndex
                )
            }
        )
        self.registerSectionNotification(
            &self.didDeleteSectionKey,
            name: Notification.Name.listMonitorDidDeleteSection,
            toObserver: observer,
            callback: { [weak observer] (monitor, sectionInfo, sectionIndex) -> Void in
                
                guard let observer = observer else {
                    
                    return
                }
                didDeleteSection(
                    observer: observer,
                    monitor: monitor,
                    sectionInfo: sectionInfo,
                    fromIndex: sectionIndex
                )
            }
        )
    }
    
    internal func unregisterObserver(_ observer: AnyObject) {
        
        CoreStore.assert(
            Thread.isMainThread,
            "Attempted to remove an observer of type \(cs_typeName(observer)) outside the main thread."
        )
        let nilValue: AnyObject? = nil
        cs_setAssociatedRetainedObject(nilValue, forKey: &self.willChangeListKey, inObject: observer)
        cs_setAssociatedRetainedObject(nilValue, forKey: &self.didChangeListKey, inObject: observer)
        cs_setAssociatedRetainedObject(nilValue, forKey: &self.willRefetchListKey, inObject: observer)
        cs_setAssociatedRetainedObject(nilValue, forKey: &self.didRefetchListKey, inObject: observer)
        
        cs_setAssociatedRetainedObject(nilValue, forKey: &self.didInsertObjectKey, inObject: observer)
        cs_setAssociatedRetainedObject(nilValue, forKey: &self.didDeleteObjectKey, inObject: observer)
        cs_setAssociatedRetainedObject(nilValue, forKey: &self.didUpdateObjectKey, inObject: observer)
        cs_setAssociatedRetainedObject(nilValue, forKey: &self.didMoveObjectKey, inObject: observer)
        
        cs_setAssociatedRetainedObject(nilValue, forKey: &self.didInsertSectionKey, inObject: observer)
        cs_setAssociatedRetainedObject(nilValue, forKey: &self.didDeleteSectionKey, inObject: observer)
    }
    
    internal func refetch(_ applyFetchClauses: (fetchRequest: NSFetchRequest<NSManagedObject>) -> Void) {
        
        CoreStore.assert(
            Thread.isMainThread,
            "Attempted to refetch a \(cs_typeName(self)) outside the main thread."
        )
        
        if !self.isPendingRefetch {
            
            self.isPendingRefetch = true
            
            NotificationCenter.default.post(
                name: Notification.Name.listMonitorWillRefetchList,
                object: self
            )
        }
        self.applyFetchClauses = applyFetchClauses
        
        self.taskGroup.notify(.main) { [weak self] () -> Void in
            
            guard let `self` = self else {
                
                return
            }
            
            self.fetchedResultsControllerDelegate.enabled = false
            self.applyFetchClauses(fetchRequest: self.fetchedResultsController.fetchRequest)
            
            self.transactionQueue.async { [weak self] in
                
                guard let `self` = self else {
                    
                    return
                }
                
                try! self.fetchedResultsController.performFetchFromSpecifiedStores()
                
                GCDQueue.main.async { [weak self] () -> Void in
                    
                    guard let `self` = self else {
                        
                        return
                    }
                    
                    self.fetchedResultsControllerDelegate.enabled = true
                    self.isPendingRefetch = false
                    
                    NotificationCenter.default.post(
                        name: Notification.Name.listMonitorDidRefetchList,
                        object: self
                    )
                }
            }
        }
    }
    
    deinit {
        
        self.fetchedResultsControllerDelegate.fetchedResultsController = nil
        self.isPersistentStoreChanging = false
    }
    
    
    // MARK: Private
    
    private var willChangeListKey: Void?
    private var didChangeListKey: Void?
    private var willRefetchListKey: Void?
    private var didRefetchListKey: Void?
    
    private var didInsertObjectKey: Void?
    private var didDeleteObjectKey: Void?
    private var didUpdateObjectKey: Void?
    private var didMoveObjectKey: Void?
    
    private var didInsertSectionKey: Void?
    private var didDeleteSectionKey: Void?
    
    private let fetchedResultsController: CoreStoreFetchedResultsController
    private let fetchedResultsControllerDelegate: FetchedResultsControllerDelegate<T>
    private let sectionIndexTransformer: (sectionName: KeyPath?) -> String?
    private var observerForWillChangePersistentStore: NotificationObserver!
    private var observerForDidChangePersistentStore: NotificationObserver!
    private let taskGroup = GCDGroup()
    private let transactionQueue: GCDQueue
    private var applyFetchClauses: (fetchRequest: NSFetchRequest<NSManagedObject>) -> Void
    
    private var isPersistentStoreChanging: Bool = false {
        
        didSet {
            
            let newValue = self.isPersistentStoreChanging
            guard newValue != oldValue else {
                
                return
            }
            
            if newValue {
                
                self.taskGroup.enter()
            }
            else {
                
                self.taskGroup.leave()
            }
        }
    }
    
    private init(context: NSManagedObjectContext, transactionQueue: GCDQueue, from: From<T>, sectionBy: SectionBy?, applyFetchClauses: (fetchRequest: NSFetchRequest<NSManagedObject>) -> Void, createAsynchronously: ((ListMonitor<T>) -> Void)?) {
        
        let fetchRequest = CoreStoreFetchRequest<T>()
        fetchRequest.fetchLimit = 0
        fetchRequest.resultType = .managedObjectResultType
        fetchRequest.fetchBatchSize = 20
        fetchRequest.includesPendingChanges = false
        fetchRequest.shouldRefreshRefetchedObjects = true
        
        let fetchedResultsController = CoreStoreFetchedResultsController(
            context: context,
            fetchRequest: fetchRequest.dynamicCast(),
            from: from,
            sectionBy: sectionBy,
            applyFetchClauses: applyFetchClauses
        )
        
        let fetchedResultsControllerDelegate = FetchedResultsControllerDelegate<T>()
        
        self.fetchedResultsController = fetchedResultsController
        self.fetchedResultsControllerDelegate = fetchedResultsControllerDelegate
        
        if let sectionIndexTransformer = sectionBy?.sectionIndexTransformer {
            
            self.sectionIndexTransformer = sectionIndexTransformer
        }
        else {
            
            self.sectionIndexTransformer = { $0 }
        }
        self.transactionQueue = transactionQueue
        self.applyFetchClauses = applyFetchClauses
        
        fetchedResultsControllerDelegate.handler = self
        fetchedResultsControllerDelegate.fetchedResultsController = fetchedResultsController
        
        guard let coordinator = context.parentStack?.coordinator else {
            
            return
        }
        
        self.observerForWillChangePersistentStore = NotificationObserver(
            notificationName: NSNotification.Name.NSPersistentStoreCoordinatorStoresWillChange,
            object: coordinator,
            queue: OperationQueue.main,
            closure: { [weak self] (note) -> Void in
                
                guard let `self` = self else {
                    
                    return
                }
                
                self.isPersistentStoreChanging = true
                
                guard let removedStores = (note.userInfo?[NSRemovedPersistentStoresKey] as? [NSPersistentStore]).flatMap(Set.init),
                    !Set(self.fetchedResultsController.fetchRequest.affectedStores ?? []).intersection(removedStores).isEmpty else {
                        
                        return
                }
                self.refetch(self.applyFetchClauses)
            }
        )
        
        self.observerForDidChangePersistentStore = NotificationObserver(
            notificationName: NSNotification.Name.NSPersistentStoreCoordinatorStoresDidChange,
            object: coordinator,
            queue: OperationQueue.main,
            closure: { [weak self] (note) -> Void in
                
                guard let `self` = self else {
                    
                    return
                }
                
                if !self.isPendingRefetch {
                    
                    let previousStores = Set(self.fetchedResultsController.fetchRequest.affectedStores ?? [])
                    let currentStores = previousStores
                        .subtracting(note.userInfo?[NSRemovedPersistentStoresKey] as? [NSPersistentStore] ?? [])
                        .union(note.userInfo?[NSAddedPersistentStoresKey] as? [NSPersistentStore] ?? [])
                    
                    if previousStores != currentStores {
                        
                        self.refetch(self.applyFetchClauses)
                    }
                }
                
                self.isPersistentStoreChanging = false
            }
        )
        
        if let createAsynchronously = createAsynchronously {
            
            transactionQueue.async {
                
                try! fetchedResultsController.performFetchFromSpecifiedStores()
                self.taskGroup.notify(.main) {
                    
                    createAsynchronously(self)
                }
            }
        }
        else {
            
            try! fetchedResultsController.performFetchFromSpecifiedStores()
        }
    }
}


// MARK: - ListMonitor: Equatable

public func == <T: NSManagedObject>(lhs: ListMonitor<T>, rhs: ListMonitor<T>) -> Bool {
    
    return lhs === rhs
}

public func == <T: NSManagedObject, U: NSManagedObject>(lhs: ListMonitor<T>, rhs: ListMonitor<U>) -> Bool {
    
    return lhs.fetchedResultsController === rhs.fetchedResultsController
}

public func ~= <T: NSManagedObject>(lhs: ListMonitor<T>, rhs: ListMonitor<T>) -> Bool {
    
    return lhs === rhs
}

public func ~= <T: NSManagedObject, U: NSManagedObject>(lhs: ListMonitor<T>, rhs: ListMonitor<U>) -> Bool {
    
    return lhs.fetchedResultsController === rhs.fetchedResultsController
}

extension ListMonitor: Equatable { }


// MARK: - ListMonitor: FetchedResultsControllerHandler

extension ListMonitor: FetchedResultsControllerHandler {
    
    // MARK: FetchedResultsControllerHandler
    
    internal func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeObject anObject: AnyObject, atIndexPath indexPath: IndexPath?, forChangeType type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        
        switch type {
            
        case .insert:
            NotificationCenter.default.post(
                name: Notification.Name.listMonitorDidInsertObject,
                object: self,
                userInfo: [
                    String(NSManagedObject.self): anObject,
                    "\(String(IndexPath.self)).New": newIndexPath!
                ]
            )
            
        case .delete:
            NotificationCenter.default.post(
                name: Notification.Name.listMonitorDidDeleteObject,
                object: self,
                userInfo: [
                    String(NSManagedObject.self): anObject,
                    String(IndexPath.self): indexPath!
                ]
            )
            
        case .update:
            NotificationCenter.default.post(
                name: Notification.Name.listMonitorDidUpdateObject,
                object: self,
                userInfo: [
                    String(NSManagedObject.self): anObject,
                    String(IndexPath.self): indexPath!
                ]
            )
            
        case .move:
            NotificationCenter.default.post(
                name: Notification.Name.listMonitorDidMoveObject,
                object: self,
                userInfo: [
                    String(NSManagedObject.self): anObject,
                    String(IndexPath.self): indexPath!,
                    "\(String(IndexPath.self)).New": newIndexPath!
                ]
            )
        }
    }
    
    internal func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeSection sectionInfo: NSFetchedResultsSectionInfo, atIndex sectionIndex: Int, forChangeType type: NSFetchedResultsChangeType) {
        
        switch type {
            
        case .insert:
            NotificationCenter.default.post(
                name: Notification.Name.listMonitorDidInsertSection,
                object: self,
                userInfo: [
                    String(NSFetchedResultsSectionInfo.self): sectionInfo,
                    String(NSNumber.self): NSNumber(value: sectionIndex)
                ]
            )
            
        case .delete:
            NotificationCenter.default.post(
                name: Notification.Name.listMonitorDidDeleteSection,
                object: self,
                userInfo: [
                    String(NSFetchedResultsSectionInfo.self): sectionInfo,
                    String(NSNumber.self): NSNumber(value: sectionIndex)
                ]
            )
            
        default:
            break
        }
    }
    
    internal func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        
        self.taskGroup.enter()
        NotificationCenter.default.post(
            name: Notification.Name.listMonitorWillChangeList,
            object: self
        )
    }
    
   internal func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        
        NotificationCenter.default.post(
            name: Notification.Name.listMonitorDidChangeList,
            object: self
        )
        self.taskGroup.leave()
    }
    
   internal func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, sectionIndexTitleForSectionName sectionName: String?) -> String? {
    
        return self.sectionIndexTransformer(sectionName: sectionName)
    }
}


// MARK: - Notification Keys
    
private extension Notification.Name {
    
    private static let listMonitorWillChangeList = Notification.Name(rawValue: "listMonitorWillChangeList")
    private static let listMonitorDidChangeList = Notification.Name(rawValue: "listMonitorDidChangeList")
    private static let listMonitorWillRefetchList = Notification.Name(rawValue: "listMonitorWillRefetchList")
    private static let listMonitorDidRefetchList = Notification.Name(rawValue: "listMonitorDidRefetchList")
    private static let listMonitorDidInsertObject = Notification.Name(rawValue: "listMonitorDidInsertObject")
    private static let listMonitorDidDeleteObject = Notification.Name(rawValue: "listMonitorDidDeleteObject")
    private static let listMonitorDidUpdateObject = Notification.Name(rawValue: "listMonitorDidUpdateObject")
    private static let listMonitorDidMoveObject = Notification.Name(rawValue: "listMonitorDidMoveObject")
    private static let listMonitorDidInsertSection = Notification.Name(rawValue: "listMonitorDidInsertSection")
    private static let listMonitorDidDeleteSection = Notification.Name(rawValue: "listMonitorDidDeleteSection")
}

#endif