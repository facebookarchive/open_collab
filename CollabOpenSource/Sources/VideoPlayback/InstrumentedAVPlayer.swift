// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

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
