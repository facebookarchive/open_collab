// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import AVFoundation
import AVKit
import Foundation

final class TrimEditLoopingVideoView: UIView {
  private var asset: AVAsset?
  private var playerLooper: AVPlayerLooper?
  private var playerLayer: AVPlayerLayer?
  public var player: AVQueuePlayer?
  private var playerItem: AVPlayerItem?
  private var thumbnailView: UIImageView = {
    let view = UIImageView()
    view.clipsToBounds = true
    view.contentMode = .scaleAspectFill
    return view
  }()

  init() {
    super.init(frame: .zero)
    addSubview(thumbnailView)

    clipsToBounds = true
    layer.cornerRadius = 6.0
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configureForVideo(asset: AVAsset) {
    cleanUp()
    self.asset = asset
    playerItem = AVPlayerItem(asset: asset)
    player = AVQueuePlayer(items: [playerItem!])
    if let player = player {
      playerLooper = AVPlayerLooper(player: player, templateItem: playerItem!)
    }
    playerLayer = AVPlayerLayer(player: player)
    playerLayer?.frame = bounds
    playerLayer?.videoGravity = .resizeAspectFill
    playerLayer?.contentsGravity = .resizeAspectFill
    if let playerLayer = self.playerLayer {
      layer.addSublayer(playerLayer)
    }
    setThumbnail(for: .zero)
    player?.play()
  }

  private func setThumbnail(for time: CMTime) {
    let size = thumbnailView.bounds.size
    guard let asset = asset else { return }
    DispatchQueue.global().async {
      let imageFuture = asset.getFrameImageAsync(atTime: time, size: size)
      imageFuture.onSuccess { (image) in
        DispatchQueue.main.async {
          self.thumbnailView.image = image
        }
      }
    }
  }

  func scrub(to time: CMTime) {
    setThumbnail(for: time)
    playerLayer?.isHidden = true
  }

  func pause() {
    player?.pause()
  }

  func unpause(at time: CMTime, completionHandler: @escaping (Bool) -> Void) {
    player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: { [weak self] _ in
      guard let self = self else { return }
      self.player?.play()
      self.playerLayer?.isHidden = false
      completionHandler(true)
    })
  }

  func adjustTrimTimes(range: CMTimeRange) {
    setThumbnail(for: range.start)
    guard let player = player, let playerItem = playerItem else { return }
    player.removeAllItems()
    playerLooper = AVPlayerLooper(player: player, templateItem: playerItem, timeRange: range)
    playerLayer?.isHidden = false
  }

  public func cleanUp() {
    player?.pause()
    playerLayer?.removeFromSuperlayer()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    playerLayer?.frame = bounds
    thumbnailView.frame = bounds
  }
}
