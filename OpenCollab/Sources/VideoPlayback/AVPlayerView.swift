// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import AVFoundation
import Foundation
import UIKit

protocol AVPlayerView: UIView {
  var playerLayer: AVPlayerLayer? { get }
}

public class AVLooperView: UIView, AVPlayerView {
  var looper: QueuePlayerLooper? {
    willSet {
      self.looper?.layer.removeFromSuperlayer()
    }
    didSet {
      guard let looper = looper else { return }
      looper.isMuted = (AppMuteManager.shared.currentState() == .Muted)
      self.layer.addSublayer(looper.layer)

      self.setNeedsLayout()
    }
  }

  override public func layoutSubviews() {
    super.layoutSubviews()

    guard let looper = looper else { return }
    looper.layer.frame = self.layer.bounds

    guard let sublayers = looper.layer.sublayers else { return }

    for sublayer in sublayers.filter({ $0 is AVPlayerLayer }) {
      sublayer.frame = self.layer.bounds
    }
  }

  override public init(frame: CGRect) {
    super.init(frame: frame)
    self.playerLayer?.contentsGravity = .resizeAspectFill
    self.playerLayer?.videoGravity = .resizeAspectFill
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  var playerLayer: AVPlayerLayer? {
    return looper?.layer
  }

  override public static var layerClass: AnyClass {
    return AVPlayerLayer.self
  }
}
