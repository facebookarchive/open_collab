// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import Foundation

final class WeakRef<T: AnyObject> {

    private(set) weak var value: T?

    init(_ value: T) {
      self.value = value
    }
}
