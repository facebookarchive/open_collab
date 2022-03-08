// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

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
