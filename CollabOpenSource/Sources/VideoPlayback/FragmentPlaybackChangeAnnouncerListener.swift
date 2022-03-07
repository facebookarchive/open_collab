// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

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
