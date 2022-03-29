// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import Foundation

final class WeakRef<T: AnyObject> {

    private(set) weak var value: T?

    init(_ value: T) {
      self.value = value
    }
}
