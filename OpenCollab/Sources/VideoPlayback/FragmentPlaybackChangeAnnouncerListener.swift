// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import Foundation

protocol FragmentPlaybackChangeAnnouncerListener: NSObjectProtocol {
  func playbackChanged(fragment: FragmentHost)
}

class FragmentPlaybackChangeAnnouncer: NSObject {

  let listeners = MulticastDelegate<FragmentPlaybackChangeAnnouncerListener>()

  func announcePlaybackChanged(fragment: FragmentHost) {
    listeners.invoke { (listener) in
      listener.playbackChanged(fragment: fragment)
    }
  }
}
