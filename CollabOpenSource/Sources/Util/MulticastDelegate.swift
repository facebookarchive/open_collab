// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import Foundation

class MulticastDelegate <T> {
  private let delegates: NSHashTable<AnyObject> = NSHashTable.weakObjects()

  func add(delegate: T) {
    delegates.add(delegate as AnyObject)
  }

  func remove(delegate: T) {
    for oneDelegate in delegates.allObjects.reversed() {
      if oneDelegate === delegate as AnyObject {
        delegates.remove(oneDelegate)
      }
    }
  }

  func invoke(invocation: (T) -> Void) {
    for delegate in delegates.allObjects.reversed() {
      invocation(delegate as! T)
    }
  }

  func removeAll() {
    delegates.removeAllObjects()
  }
}

func += <T: AnyObject> (left: MulticastDelegate<T>, right: T) {
  left.add(delegate: right)
}

func -= <T: AnyObject> (left: MulticastDelegate<T>, right: T) {
  left.remove(delegate: right)
}
