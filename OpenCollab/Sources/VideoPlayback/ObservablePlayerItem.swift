// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import AVFoundation

open class ObservablePlayerItem: AVPlayerItem {

  private var playerItemContext = 0
  private var isObservingStatus = false
  private var statusUpdateCallback: ((AVPlayerItem.Status) -> Void)?

  private var isObservingPlaybackLikelyToKeepUp = false
  private var playbackLikelyToKeepUpCallback: ((Bool) -> Void)?

  private var isObservingPlaybackBufferFull = false
  private var playbackBufferFullCallback: ((Bool) -> Void)?

  public func beginObservingStatus(withCallback callback: ((AVPlayerItem.Status) -> Void)?) {
    guard !isObservingStatus else { return }
    isObservingStatus = true
    statusUpdateCallback = callback
    self.addObserver(self,
                     forKeyPath: #keyPath(AVPlayerItem.status),
                     options: [.old, .new],
                     context: &playerItemContext)
  }

  public func endObservingStatus() {
    guard isObservingStatus else { return }
    isObservingStatus = false
    statusUpdateCallback = nil
    self.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.status))
  }

  public func beginObservingPlaybackLikelyToKeepUp(withCallback callback: ((Bool) -> Void)?) {
    guard !isObservingPlaybackLikelyToKeepUp else { return }
    isObservingPlaybackLikelyToKeepUp = true
    playbackLikelyToKeepUpCallback = callback
    self.addObserver(self,
                     forKeyPath: #keyPath(AVPlayerItem.isPlaybackLikelyToKeepUp),
                     options: [.old, .new],
                     context: &playerItemContext)
  }

  public func endObservingPlaybackLikelyToKeepUp() {
    guard isObservingPlaybackLikelyToKeepUp else { return }
    isObservingPlaybackLikelyToKeepUp = false
    playbackLikelyToKeepUpCallback = nil
    self.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.isPlaybackLikelyToKeepUp))
  }

  public func beginObservingPlaybackBufferFull(withCallback callback: ((Bool) -> Void)?) {
    guard !isObservingPlaybackBufferFull else { return }
    isObservingPlaybackBufferFull = true
    playbackBufferFullCallback = callback
    self.addObserver(self,
                     forKeyPath: #keyPath(AVPlayerItem.isPlaybackBufferFull),
                     options: [.old, .new],
                     context: &playerItemContext)
  }

  public func endObservingPlaybackBufferFull() {
    guard isObservingPlaybackBufferFull else { return }
    isObservingPlaybackBufferFull = false
    playbackBufferFullCallback = nil
    self.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.isPlaybackBufferFull))
  }

  deinit {
    if isObservingStatus {
      endObservingStatus()
    }

    if isObservingPlaybackLikelyToKeepUp {
      endObservingPlaybackLikelyToKeepUp()
    }

    if isObservingPlaybackBufferFull {
      endObservingPlaybackBufferFull()
    }
  }

  // swiftlint:disable block_based_kvo
  override public func observeValue(forKeyPath keyPath: String?,
                                    of object: Any?,
                                    change: [NSKeyValueChangeKey: Any]?,
                                    context: UnsafeMutableRawPointer?) {
    // Only handle observations for the playerItemContext
    guard context == &playerItemContext else {
      super.observeValue(forKeyPath: keyPath,
                         of: object,
                         change: change,
                         context: context)
      return
    }

    if keyPath == #keyPath(AVPlayerItem.status) {
      let status: AVPlayerItem.Status

      // Get the status change from the change dictionary
      if let statusNumber = change?[.newKey] as? NSNumber {
        status = AVPlayerItem.Status(rawValue: statusNumber.intValue)!
      } else {
        status = .unknown
      }

      statusUpdateCallback?(status)
    }

    if keyPath == #keyPath(AVPlayerItem.isPlaybackLikelyToKeepUp) {
      let isPlaybackLikelyToKeepUp = change?[.newKey] as? Bool ?? false

      playbackLikelyToKeepUpCallback?(isPlaybackLikelyToKeepUp)
    }

    if keyPath == #keyPath(AVPlayerItem.isPlaybackBufferFull) {
      let isPlaybackBufferFull = change?[.newKey] as? Bool ?? false

      playbackBufferFullCallback?(isPlaybackBufferFull)
    }
  }
}
