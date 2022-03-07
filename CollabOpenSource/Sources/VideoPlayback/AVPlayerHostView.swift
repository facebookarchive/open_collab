// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import UIKit
import AVFoundation

class AVPlayerHostView: UIView {

  static var debugInfoEnabled = false

  // The time that we started trying to load playback for the associated
  // video. Depending on where in the App playback is being started from
  // this value might be captured at a different time. Regardless of
  // when we capture the start of playback loading we always resolve loading
  // when the HotPlayer sets the rate on the AVPlayer.
  fileprivate var playbackLoadingStartTime: CMTime?
  fileprivate var playbackLoadingVideoDuration: CMTime?
  // Only allow playback loading to be logged the first time the video plays.
  fileprivate var debugPlaybackLoadingInfoHasBeenSet = false

  fileprivate let debugTimeToPlaybackInfoLabel: UILabel = {
    let label = UILabel()
    label.text = "-"
    label.font = UIFont.systemFont(ofSize: 20.0)
    label.textColor = .white
    label.textAlignment = .center
    label.numberOfLines = 0
    label.backgroundColor = UIColor.black.withAlphaComponent(0.8)
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  fileprivate let debugVideoDurationInfoLabel: UILabel = {
    let label = UILabel()
    label.text = "-"
    label.font = UIFont.systemFont(ofSize: 20.0)
    label.textColor = .white
    label.textAlignment = .center
    label.numberOfLines = 0
    label.backgroundColor = UIColor.black.withAlphaComponent(0.8)
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  fileprivate let debugDownloadInfoLabel: UILabel = {
    let label = UILabel()
    label.text = "-"
    label.font = UIFont.systemFont(ofSize: 20.0)
    label.textColor = .white
    label.textAlignment = .center
    label.numberOfLines = 0
    label.backgroundColor = UIColor.black.withAlphaComponent(0.8)
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  fileprivate var debugStackView: UIStackView?

  fileprivate var debugDownloadInfoHasBeenSet = false

  let imageView: UIImageView

  var waitingToBeAttached = false

  public override init(frame: CGRect) {
    imageView = UIImageView()
    imageView.clipsToBounds = true
    imageView.contentMode = .scaleAspectFill
    imageView.isHidden = true

    super.init(frame: frame)
    self.addSubview(imageView)
    self.clipsToBounds = true

    if AVPlayerHostView.debugInfoEnabled {
      debugStackView = UIStackView()

      guard let debugStackView = debugStackView else { return }

      debugStackView.axis = .vertical
      debugStackView.translatesAutoresizingMaskIntoConstraints = false
      self.addSubview(debugStackView )

      [debugDownloadInfoLabel, debugTimeToPlaybackInfoLabel, debugVideoDurationInfoLabel]
        .forEach { debugStackView.addArrangedSubview($0) }

      NSLayoutConstraint.activate([
        debugStackView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
        debugStackView.centerYAnchor.constraint(equalTo: self.centerYAnchor)
      ])
    }
  }

  required init?(coder: NSCoder) {
    Fatal.safeError("init(coder:) has not been implemented")
  }

  var playerView: AVLooperView? {
    willSet {
      self.playerView?.removeFromSuperview()
    }
    didSet {
      guard let playerView = self.playerView else { return }
      if let debugStackView = self.debugStackView {
        self.insertSubview(playerView, belowSubview: debugStackView)
      } else {
        self.addSubview(playerView)
      }
      self.setNeedsLayout()
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    self.playerView?.frame = self.bounds
    self.imageView.frame = self.bounds
  }

  func setKeyFrameIfNeeded(of asset: AVAsset?) {
    guard let asset = asset else { return }

    if imageView.image != nil, !imageView.isHidden {
      // there is already a valid key frame image set
      return
    }

    updateFrame(of: asset, atTime: .zero)
  }

  func updateThumbnail(thumbnailURL: String) {
    self.imageView.kf.setImage(with: URL(string: thumbnailURL))
    self.imageView.isHidden = false
  }

  func updateThumbnail(image: UIImage) {
    self.imageView.image = image
    self.imageView.isHidden = false
  }

  func updateFrame(of asset: AVAsset?, atTime: CMTime) {
    guard let asset = asset else { return }

    // TODO : This could be made more efficient by not trying to fetch an image
    // while we are actively fetching one but then the scrubber would be less responsive.
    let size = self.imageView.bounds.size
    DispatchQueue.global().async {
      let imageFuture = asset.getFrameImageAsync(atTime: atTime, size: size)
      imageFuture.onSuccess { (image) in
        DispatchQueue.main.async {
          self.imageView.image = image
          self.imageView.isHidden = false
        }
      }
    }
  }

  func removeKeyFrameImage() {
    imageView.image = nil
    imageView.isHidden = true
  }
}

// MARK: - Debug Info Support

extension AVPlayerHostView {
  func setPlaybackLoadingStartTime(startTime: CMTime,
                                   videoDuration: CMTime) {
    // Debugging info for playback loading can only be set once.
    guard playbackLoadingStartTime == nil,
          !debugPlaybackLoadingInfoHasBeenSet else { return }
    playbackLoadingStartTime = startTime
    playbackLoadingVideoDuration = videoDuration
  }

  func setPlaybackLoadingEndTime(endTime: CMTime) {
    // Debugging info for playback loading can only be set once.
    guard let startTime = playbackLoadingStartTime,
          let videoDuration = playbackLoadingVideoDuration,
          !debugPlaybackLoadingInfoHasBeenSet else { return }

    debugPlaybackLoadingInfoHasBeenSet = true
    let duration = CMTimeSubtract(endTime, startTime)

    setTimeToPlaybackDebugInfo(duration: duration.toSeconds(), videoDuration: videoDuration.toSeconds())
  }

  private func setTimeToPlaybackDebugInfo(duration: TimeInterval, videoDuration: TimeInterval) {
    guard AVPlayerHostView.debugInfoEnabled else { return }

    let playbackText = String(format: "Playback: %.2f sec", duration)
    debugTimeToPlaybackInfoLabel.text = playbackText
    let durationText = String(format: "Length: %.2f sec", videoDuration)
    debugVideoDurationInfoLabel.text = durationText
    self.setNeedsLayout()
    self.layoutIfNeeded()
  }

  func setDownloadTimeDebugInfo(duration: TimeInterval, url: URL) {
    // Only set download debug info once.
    guard AVPlayerHostView.debugInfoEnabled,
          !debugDownloadInfoHasBeenSet else {
      return
    }

    let text = AVPlayerHostView.assetLoadingDebugInfo(duration: duration,
                                                      url: url)

    debugDownloadInfoLabel.text = "Download: \(text)"
    debugDownloadInfoHasBeenSet = true
    self.setNeedsLayout()
    self.layoutIfNeeded()
  }

  static func assetLoadingDebugInfo(duration: TimeInterval, url: URL) -> String {
    let durationInfo = String(format: "%.2f sec", duration)
    let size = url.fileSizeInMB ?? 0
    let sizeInfo = String(format: "%.2f mb", size)
    return "\(durationInfo) \(sizeInfo)"
  }
}
