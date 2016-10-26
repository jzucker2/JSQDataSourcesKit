//
//  Created by Jesse Squires
//  http://www.jessesquires.com
//
//
//  Documentation
//  http://jessesquires.com/JSQDataSourcesKit
//
//
//  GitHub
//  https://github.com/jessesquires/JSQDataSourcesKit
//
//
//  License
//  Copyright © 2015 Jesse Squires
//  Released under an MIT license: http://opensource.org/licenses/MIT
//

import CoreData
import Foundation
import UIKit


/// A `FetchedResultsDelegateProvider` is responsible for providing a delegate object for an instance of `NSFetchedResultsController`.
public final class FetchedResultsDelegateProvider<CellFactory: ReusableViewFactoryProtocol> {

    // MARK: Type aliases

    /// The parent view of cell's that the cell factory produces.
    public typealias ParentView = CellFactory.View.ParentView


    // MARK: Properties

    /// The table view or collection view displaying data for the fetched results controller.
    public weak var cellParentView: ParentView?

    /// The cell factory used to configure cells.
    public let cellFactory: CellFactory


    // MARK: private

    fileprivate typealias Item = CellFactory.Item

    fileprivate var bridgedDelegate: BridgedFetchedResultsDelegate?

    fileprivate init(cellFactory: CellFactory, cellParentView: ParentView) {
        self.cellFactory = cellFactory
        self.cellParentView = cellParentView
    }


    // MARK: Private, collection view properties

    fileprivate typealias SectionChangeTuple = (changeType: NSFetchedResultsChangeType, sectionIndex: Int)
    fileprivate lazy var sectionChanges = [SectionChangeTuple]()

    fileprivate typealias ObjectChangeTuple = (changeType: NSFetchedResultsChangeType, indexPaths: [IndexPath])
    fileprivate lazy var objectChanges = [ObjectChangeTuple]()

    fileprivate lazy var updatedObjects = [IndexPath: Item]()
}


extension FetchedResultsDelegateProvider where CellFactory.View.ParentView == UICollectionView {

    // MARK: Collection views

    /**
     Initializes a new fetched results delegate provider for collection views.

     - parameter cellFactory:    The cell factory with which the fetched results controller delegate will configure cells.
     - parameter collectionView: The collection view to be updated when the fetched results change.

     - returns: A new `FetchedResultsDelegateProvider` instance.
     */
    public convenience init(cellFactory: CellFactory, collectionView: UICollectionView) {
        self.init(cellFactory: cellFactory, cellParentView: collectionView)
    }

    /// Returns the `NSFetchedResultsControllerDelegate` object for a collection view.
    public func collectionDelegate(accessQueue: DispatchQueue) -> NSFetchedResultsControllerDelegate {
        if bridgedDelegate == nil {
            bridgedDelegate = bridgedCollectionFetchedResultsDelegate(accessQueue: accessQueue)
        }
        return bridgedDelegate!
    }

    private weak var collectionView: UICollectionView? { return cellParentView }

    private func bridgedCollectionFetchedResultsDelegate(accessQueue: DispatchQueue) -> BridgedFetchedResultsDelegate {
        let delegate = BridgedFetchedResultsDelegate(
            willChangeContent: { [unowned self] (controller) in
                
                print("------------------------------------------------------")
                print("\(#function) willChangeContent")
                print("------------------------------------------------------")
                accessQueue.async {
                    self.sectionChanges.removeAll()
                    self.objectChanges.removeAll()
                    self.updatedObjects.removeAll()
                }
            },
            didChangeSection: { [unowned self] (controller, sectionInfo, sectionIndex, changeType) in
                print("\(#function) didChangeSection sectionInfo: \(sectionInfo) sectionIndex: \(sectionIndex) changeType: \(changeType.rawValue)")
                accessQueue.async {
                    self.sectionChanges.append((changeType, sectionIndex))
                }
                
            },
            didChangeObject: { [unowned self] (controller, anyObject, indexPath: IndexPath?, changeType, newIndexPath: IndexPath?) in
                print("\(#function) didChangeObject indexPath: \(indexPath) changeType: \(changeType.rawValue) newIndexPath: \(newIndexPath)")
                accessQueue.async {
                    switch changeType {
                    case .insert:
                        if let insertIndexPath = newIndexPath {
                            self.objectChanges.append((changeType, [insertIndexPath]))
                        }
                    case .delete:
                        if let deleteIndexPath = indexPath {
                            self.objectChanges.append((changeType, [deleteIndexPath]))
                        }
                    case .update:
                        if let indexPath = indexPath {
                            self.objectChanges.append((changeType, [indexPath]))
                            self.updatedObjects[indexPath] = anyObject as? Item
                        }
                    case .move:
                        if let old = indexPath, let new = newIndexPath {
                            self.objectChanges.append((changeType, [old, new]))
                        }
                    }
                }
                
            },
            didChangeContent: { [unowned self] (controller) in
                print("\(#function) didChangeContent begin before performBatchUpdates")
                self.collectionView?.performBatchUpdates({ [weak self] in
                    print("\(#function) didChangeContent performBatchUpdates begin")
                    let barrierWorkItem = DispatchWorkItem(qos: .userInitiated, flags: [.barrier], block: {
                        print("\(#function) didChangeContent performBatchUpdates barrier work start")
                        self?.applyObjectChanges()
                        print("\(#function) didChangeContent performBatchUpdates barrier work finished object changes")
                        self?.applySectionChanges()
                        print("\(#function) didChangeContent performBatchUpdates barrier work finished section changes")
                    })
                    accessQueue.sync(execute: barrierWorkItem) // or async?
                    print("\(#function) didChangeContent performBatchUpdates end")
                    }, completion:{ [weak self] finished in
                        print("\(#function) didChangeContent completion before reload supplementary")
                        accessQueue.async {
                            self?.reloadSupplementaryViewsIfNeeded()
                        }
                        
                        print("\(#function) didChangeContent completion after reload supplementary")
                })
            })

        return delegate
    }

    private func applyObjectChanges() {
        if Thread.isMainThread {
            for (changeType, indexPaths) in objectChanges {
                
                switch(changeType) {
                case .insert:
                    collectionView?.insertItems(at: indexPaths)
                case .delete:
                    collectionView?.deleteItems(at: indexPaths)
                case .update:
                    if let indexPath = indexPaths.first,
                        let item = updatedObjects[indexPath],
                        let collectionView = collectionView,
                        let cell = collectionView.cellForItem(at: indexPath) as? CellFactory.View {
                        cellFactory.configure(view: cell, item: item, type: .cell, parentView: collectionView, indexPath: indexPath)
                    }
                case .move:
                    if let deleteIndexPath = indexPaths.first {
                        self.collectionView?.deleteItems(at: [deleteIndexPath])
                    }
                    
                    if let insertIndexPath = indexPaths.last {
                        self.collectionView?.insertItems(at: [insertIndexPath])
                    }
                }
            }
        } else {
            DispatchQueue.main.async {
                for (changeType, indexPaths) in self.objectChanges {
                    
                    switch(changeType) {
                    case .insert:
                        self.collectionView?.insertItems(at: indexPaths)
                    case .delete:
                        self.collectionView?.deleteItems(at: indexPaths)
                    case .update:
                        if let indexPath = indexPaths.first,
                            let item = self.updatedObjects[indexPath],
                            let collectionView = self.collectionView,
                            let cell = self.collectionView?.cellForItem(at: indexPath) as? CellFactory.View {
                            self.cellFactory.configure(view: cell, item: item, type: .cell, parentView: collectionView, indexPath: indexPath)
                        }
                    case .move:
                        if let deleteIndexPath = indexPaths.first {
                            self.collectionView?.deleteItems(at: [deleteIndexPath])
                        }
                        
                        if let insertIndexPath = indexPaths.last {
                            self.collectionView?.insertItems(at: [insertIndexPath])
                        }
                    }
                }
            }
        }
            
    }

    private func applySectionChanges() {
        if Thread.isMainThread {
            for (changeType, sectionIndex) in sectionChanges {
                let section = IndexSet(integer: sectionIndex)
                
                switch(changeType) {
                case .insert:
                    collectionView?.insertSections(section)
                case .delete:
                    collectionView?.deleteSections(section)
                default:
                    break
                }
            }
        } else {
            DispatchQueue.main.async {
                for (changeType, sectionIndex) in self.sectionChanges {
                    let section = IndexSet(integer: sectionIndex)
                    
                    switch(changeType) {
                    case .insert:
                        self.collectionView?.insertSections(section)
                    case .delete:
                        self.collectionView?.deleteSections(section)
                    default:
                        break
                    }
                }
            }
        }
    }

    private func reloadSupplementaryViewsIfNeeded() {
        if sectionChanges.count > 0 {
            print("\(#function) will reloadData")
            if Thread.isMainThread {
                self.collectionView?.reloadData()
                print("\(#function) did reloadData sync")
            } else {
                DispatchQueue.main.async {
                    self.collectionView?.reloadData()
                    print("\(#function) did reloadData async")
                }
            }
        }
    }
}


extension FetchedResultsDelegateProvider where CellFactory.View.ParentView == UITableView {

    // MARK: Table views

    /**
     Initializes a new fetched results delegate provider for table views.

     - parameter cellFactory: The cell factory with which the fetched results controller delegate will configure cells.
     - parameter tableView:   The table view to be updated when the fetched results change.

     - returns: A new `FetchedResultsDelegateProvider` instance.
     */
    public convenience init(cellFactory: CellFactory, tableView: UITableView) {
        self.init(cellFactory: cellFactory, cellParentView: tableView)
    }

    /// Returns the `NSFetchedResultsControllerDelegate` object for a table view.
    public var tableDelegate: NSFetchedResultsControllerDelegate {
        if bridgedDelegate == nil {
            bridgedDelegate = bridgedTableFetchedResultsDelegate()
        }
        return bridgedDelegate!
    }

    private weak var tableView: UITableView? { return cellParentView }

    private func bridgedTableFetchedResultsDelegate() -> BridgedFetchedResultsDelegate {
        let delegate = BridgedFetchedResultsDelegate(
            willChangeContent: { [unowned self] (controller) in
                self.tableView?.beginUpdates()
            },
            didChangeSection: { [unowned self] (controller, sectionInfo, sectionIndex, changeType) in
                switch changeType {
                case .insert:
                    self.tableView?.insertSections(IndexSet(integer: sectionIndex), with: .fade)
                case .delete:
                    self.tableView?.deleteSections(IndexSet(integer: sectionIndex), with: .fade)
                default:
                    break
                }
            },
            didChangeObject: { [unowned self] (controller, anyObject, indexPath, changeType, newIndexPath) in
                switch changeType {
                case .insert:
                    if let insertIndexPath = newIndexPath {
                        self.tableView?.insertRows(at: [insertIndexPath], with: .fade)
                    }
                case .delete:
                    if let deleteIndexPath = indexPath {
                        self.tableView?.deleteRows(at: [deleteIndexPath], with: .fade)
                    }
                case .update:
                    if let indexPath = indexPath,
                        let tableView = self.tableView,
                        let cell = tableView.cellForRow(at: indexPath) as? CellFactory.View {
                        self.cellFactory.configure(view: cell, item: anyObject as? Item, type: .cell, parentView: tableView, indexPath: indexPath)
                    }
                case .move:
                    if let deleteIndexPath = indexPath {
                        self.tableView?.deleteRows(at: [deleteIndexPath], with: .fade)
                    }

                    if let insertIndexPath = newIndexPath {
                        self.tableView?.insertRows(at: [insertIndexPath], with: .fade)
                    }
                }
            },
            didChangeContent: { [unowned self] (controller) in
                self.tableView?.endUpdates()
            })
        
        return delegate
    }
}
