// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import AVFoundation

final class InstrumentedAVPlayer: AVPlayer {

  // MARK: - Properties

  static var instrumenter = PlayerInstrumenter<InstrumentedAVPlayer>()

  // MARK: - AVQueuePlayer

  override init() {
    super.init()
    InstrumentedAVPlayer.instrumenter.register(player: self)
  }

  override init(url URL: URL) {
    super.init(url: URL)
  }

  override init(playerItem item: AVPlayerItem?) {
    super.init(playerItem: item)
  }
}

// MARK: - Alive Player Accounting

extension InstrumentedAVPlayer: InstrumentedPlayer {
  var urlAsset: AVURLAsset? {
    return self.currentItem?.asset as? AVURLAsset
  }
}
