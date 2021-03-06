// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

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
      // swiftlint:disable:next force_cast
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
