// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import Foundation

protocol FragmentDataModelListener: AnyObject {
  func updated(model: PlaybackDataModel)
}

class FragmentDataModelEventHandler {
  static var listeners = MulticastDelegate<FragmentDataModelListener>()

  class func announceUpdate(model: PlaybackDataModel) {
    listeners.invoke { (listener) in
      listener.updated(model: model)
    }
  }
}
