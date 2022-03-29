// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import AVFoundation
import BrightFutures
import CoreMedia
import UIKit

struct FragmentHost {
  static let minFragmentDuration: CMTime = CMTimeMakeWithSeconds(3, preferredTimescale: 600)
  static let maxFragmentDuration: CMTime = CMTimeMakeWithSeconds(25.0, preferredTimescale: 600)

  var assetInfo: AssetInfo
  var hostView: AVPlayerHostView = AVPlayerHostView()
  var volume: Float
  var isRecordPlaceholder: Bool = false

  // Holds the data information for a thumbnail for a local take.
  // This thumbnail is not necessarily shown on the AVPlayerHostView() until
  // attached for playback.
  var localThumbnailImage: UIImage?

  // Playback
  private(set) var playbackStartTime: CMTime
  private(set) var playbackEndTime: CMTime

  var playbackDuration: CMTime {
    get {
      return CMTimeSubtract(playbackEndTime, playbackStartTime)
    }
  }
  let assetDuration: CMTime
  let minPlaybackDuration: CMTime
  let maxPlaybackDuration: CMTime

  // TODO : Set when we to support BPM
  let BPM: Int? = nil

  // Announcing
  private(set) var playbackChangeAnnouncer = FragmentPlaybackChangeAnnouncer()

  init(assetInfo: AssetInfo,
       volume: Float = 1.0,
       assetDuration: CMTime,
       playbackEndTime: CMTime? = nil,
       playbackStartTime: CMTime? = nil,
       minPlaybackDuration: CMTime = .zero,
       maxPlaybackDuration: CMTime = .positiveInfinity) {
    self.assetInfo = assetInfo
    self.volume = volume
    self.playbackStartTime = playbackStartTime ?? .zero
    self.playbackEndTime = playbackEndTime ?? assetDuration
    self.assetDuration = assetDuration
    self.minPlaybackDuration = minPlaybackDuration
    self.maxPlaybackDuration = maxPlaybackDuration
  }

  init(fragment: FragmentHost) {
    self.assetInfo = fragment.assetInfo
    self.volume = fragment.volume
    self.playbackStartTime = fragment.playbackStartTime
    self.playbackEndTime = fragment.playbackEndTime
    self.assetDuration = fragment.assetDuration
    self.minPlaybackDuration = fragment.minPlaybackDuration
    self.maxPlaybackDuration = fragment.maxPlaybackDuration
    self.localThumbnailImage = fragment.localThumbnailImage
    self.isRecordPlaceholder = fragment.isRecordPlaceholder
  }

  init(croppedURL: URL, originalFragment: FragmentHost) {
    self.assetInfo = AssetInfo.userRecorded(croppedURL)
    self.volume = originalFragment.volume
    self.playbackStartTime = originalFragment.playbackStartTime
    self.playbackEndTime = originalFragment.playbackEndTime
    self.assetDuration = originalFragment.assetDuration
    self.minPlaybackDuration = originalFragment.minPlaybackDuration
    self.maxPlaybackDuration = originalFragment.maxPlaybackDuration
  }

  func captureThumbnail() -> Future<UIImage, AssetError> {
    return asset().flatMap { (asset) -> Future<UIImage, AssetError> in
      guard let asset = asset else { return Future(error: .AssetNotFound) }
      let size = self.hostView.imageView.bounds.size

      return asset.getFrameImageAsync(atTime: playbackStartTime,
                                      size: size)
    }
  }

  func setThumbnail() {
    // Use the local image if there is one. This is generated when we
    // generate takes.
    if let localThumbnailImage = localThumbnailImage {
      hostView.updateThumbnail(image: localThumbnailImage)
      return
    }

    // Otherwise fetch the thumbnail from the server.
    guard let fragment = assetInfo.downloadedFragment,
          let thumbnailURL = fragment.thumbnailURL else { return }

    hostView.updateThumbnail(thumbnailURL: thumbnailURL)
  }

  func updateFrame(atTime: CMTime = .zero) {
    asset().onSuccess { (asset) in
      hostView.updateFrame(of: asset, atTime: atTime)
    }
  }
}

// Asset Management
extension FragmentHost {
  func asset(allowManualSyncing: Bool = true) -> Future<AVURLAsset?, AssetError> {
    // Get the raw asset from the cache.
    let promise = Promise<AVURLAsset?, AssetError>()

    let future: Future<AVURLAsset?, AssetError> = getRawAsset()
    future.onSuccess { asset in
      promise.complete(.success(asset))
    }.onFailure {_ in
      promise.complete(.success(nil))
    }

    return promise.future
  }

  func loadAsset() -> Future<Void, AssetError> {
    guard let assetManager = AppDelegate.fragmentAssetManager else {
      return Future(error: .NoAssetManager)
    }

    return assetManager.loadAsset(fragment: self)
      .flatMap { _ in
        return Future(value: ())
      }
  }

  private func getRawAsset() -> Future<AVURLAsset?, AssetError> {
    guard let assetManager = AppDelegate.fragmentAssetManager else {
      print("ERROR: No asset manager to get raw asset!")
      return Future(error: .NoAssetManager)
    }

    return assetManager.getAsset(fragment: self)
  }
}

// Playback Editing
extension FragmentHost {
  // We always bundle changes to start/end time together even if one of them is nil.
  // This allows us to change both the start and end time during a nudge or shift and
  // only announce one change.
  mutating func setPlaybackTimes(startTime: CMTime?, endTime: CMTime?) {
    let startTime = startTime ?? playbackStartTime
    let endTime = endTime ?? playbackEndTime

    if startEndTimePairIsValid(startTime: startTime, endTime: endTime) {
      playbackStartTime = startTime
      playbackEndTime = endTime
    }

    playbackChangeAnnouncer.announcePlaybackChanged(fragment: self)
  }
}

// Playback Validity
extension FragmentHost {
  func startTimeIsValid(time: CMTime) -> Bool {
    let playbackDuration = CMTimeSubtract(playbackEndTime, time)
    guard CMTimeCompare(time, .zero) >= 0,
          CMTimeCompare(self.assetDuration, time) >= 0,
          CMTimeCompare(self.playbackEndTime, time) >= 0,
          CMTimeCompare(playbackDuration, minPlaybackDuration) >= 0 else {
      return false
    }

    return true
  }

  func endTimeIsValid(time: CMTime) -> Bool {
    let playbackDuration = CMTimeSubtract(time, playbackStartTime)
    guard CMTimeCompare(time, .zero) >= 0,
          CMTimeCompare(self.assetDuration, time) >= 0,
          CMTimeCompare(time, self.playbackStartTime) >= 0,
          CMTimeCompare(playbackDuration, minPlaybackDuration) >= 0 else {
      return false
    }

    return true
  }

  func startEndTimePairIsValid(startTime: CMTime, endTime: CMTime) -> Bool {
    let playbackDuration = CMTimeSubtract(endTime, startTime)
    guard CMTimeCompare(startTime, .zero) >= 0,
          CMTimeCompare(self.assetDuration, endTime) >= 0,
          CMTimeCompare(endTime, startTime) >= 0,
          CMTimeCompare(playbackDuration, minPlaybackDuration) >= 0 else {
      return false
    }
    return true
  }
}

// Time Conversions
extension FragmentHost {
  // Takes a time in the absolute range of the asset and converts to a time relative to
  // the start of playback time.
  func translateToPlaybackTime(assetTime: CMTime) -> CMTime {
    return CMTimeSubtract(assetTime, playbackStartTime)
  }

  // Takes a time relative to the start of playback time and translates it to a time in the
  // absolute entire range of the asset
  func translateToAssetTime(playbackTime: CMTime) -> CMTime {
    return CMTimeAdd(playbackStartTime, playbackTime)
  }
}

// Listeners
extension FragmentHost {
  func addListener(listener: FragmentPlaybackChangeAnnouncerListener) {
    playbackChangeAnnouncer.listeners.add(delegate: listener)
  }

  func removeListener(listener: FragmentPlaybackChangeAnnouncerListener) {
    playbackChangeAnnouncer.listeners.remove(delegate: listener)
  }
}
