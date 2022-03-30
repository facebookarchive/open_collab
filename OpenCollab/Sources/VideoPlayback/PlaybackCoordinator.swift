// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import AVFoundation
import AVKit
import BrightFutures
import CoreMedia
import Foundation
import UIKit

protocol PlaybackCoordinatorDelegate: NSObjectProtocol {
  func looped(atTime: CMTime, loopCount: Int)
  func playbackStarted()
  func bufferingStarted()
  func bufferingStopped()
}

class PlaybackCoordinator: NSObject {

  private struct ObserverContexts {
    static var urlAssetDurationKey = "duration"
    static var urlAssetPlayableKey = "playable"
  }

  // MARK: - Properties - Data Management

  fileprivate var playerHostViews: Set<AVPlayerHostView> = []

  fileprivate lazy var activeAttachFutures: [Int: Future<Bool, Never>] = [:]

  // MARK: - Properties - Looping

  fileprivate(set) var hotLooper: HotLooper
  fileprivate(set) var coordinatedLooperGroup: CoordinatedLooperGroup? {
    willSet {
      guard let coordinatedLooperGroup = coordinatedLooperGroup else { return }
      hotLooper.detach(looper: coordinatedLooperGroup)
    }
  }

  fileprivate var shouldIgnoreMute: Bool

  fileprivate var duration: CMTime?

  var lastLoopTime: CMTime? {
    get {
      return hotLooper.loopStartTime
    }
  }

  // MARK: - Properties - Attach/Detach

  fileprivate let gracePeriod: TimeInterval

  // A map of index position to a token.
  // This is used for enable dynamic attach detach of players to views.
  // Since detach occurs after a grace period, we won't subsequent attach calls
  // cancel the scheduled detach. To do so, all we need is to update the token for
  // the specified position.
  fileprivate var attachDetachTokens: [Int: UInt32] = [:]

  // MARK: - Properties - Delegation

  public weak var delegate: PlaybackCoordinatorDelegate?

  // MARK: - Init

  public init(gracePeriod: TimeInterval = 2.0,
              duration: CMTime,
              shouldIgnoreMute: Bool = false) {
    self.gracePeriod = gracePeriod
    self.shouldIgnoreMute = shouldIgnoreMute
    self.duration = duration
    self.hotLooper = HotLooper(duration: duration)

    super.init()
    self.hotLooper.delegate = self
    FragmentDataModelEventHandler.listeners.add(delegate: self)

    print(self.hashValue, "Playback coordinator made hot looper: \(hotLooper.hashValue)")
  }

  // MARK: - Playback Control

  func resetToTime(playbackTime: CMTime, atTime: CMTime) {
    self.hotLooper.resetToPlaybackTime(playbackTime: playbackTime, atTime: atTime)
  }

  func currentTime() -> CMTime? {
    return self.hotLooper.currentPlaybackTime()
  }

  func updateProgress(fragment: FragmentHost, progress: Float) {
    adjustVolume(playerHostView: fragment.hostView,
                 volume: fragment.volume * progress)
  }

  public func adjustVolume(playerHostView: AVPlayerHostView, volume: Float) {
    assert(Thread.isMainThread, "should be called on main thread")

    playerHostView.playerView?.looper?.volume = volume
    if !shouldIgnoreMute {
      playerHostView.playerView?.looper?.isMuted =
        (AppMuteManager.shared.currentState() == .Muted)
    }
  }

  public func adjustPlaybackTime(fragment: FragmentHost) {
    assert(Thread.isMainThread, "should be called on main thread")

    detachImmediately(fragment: fragment, previewImageToo: false)
    attach(fragment: fragment)
  }

  public func clear() {
    assert(Thread.isMainThread, "should be called on main thread")

    print("clear \(self)")
    print("Number of host views to clear: \(playerHostViews.count)")

    coordinatedLooperGroup?.clear()

    hotLooper.clear()

    for playerHostView in playerHostViews {
      playerHostView.waitingToBeAttached = false
      playerHostView.playerView?.looper?.clear()
      playerHostView.playerView?.looper = nil
      playerHostView.playerView = nil
    }
    playerHostViews.removeAll()
    activeAttachFutures.removeAll()

    NotificationCenter.default.removeObserver(self)
  }

  public func stopLoop() {
    hotLooper.clear()
  }

  public func pause() {
    hotLooper.pause()
  }

  public func unpause(playbackTime: CMTime?) {
    self.hotLooper.unpause(playbackTime: playbackTime)
  }

  public func scrub(fragments: [FragmentHost], time: CMTime) {
    for fragment in fragments {
      fragment.updateFrame(atTime: time)
    }
  }

  // MARK: - Looper

  public func getLoopTimes() -> [CMTime] {
    return hotLooper.getLoopTimes()
  }

  // MARK: - Convenience

  fileprivate func getAsset(fragment: FragmentHost) -> Future<(AVURLAsset?, FragmentHost), AssetError> {
    assert(Thread.isMainThread, "should be called on main thread")
    return fragment.asset()
      .flatMap { asset -> Future<(AVURLAsset?, FragmentHost), AssetError> in
        return Future(value: (asset, fragment))
      }
  }

  deinit {
    print("DEINIT PlaybackCoordinator")

    // TODO : Make sure to stop observing.
  }

  // MARK: - KVO
  // swiftlint:disable:next block_based_kvo
  override public func observeValue(
    forKeyPath keyPath: String?,
    of object: Any?,
    change: [NSKeyValueChangeKey: Any]?,
    context: UnsafeMutableRawPointer?) {
    // TODO : Should we be observing for any failures to start recovery.
  }
}

// MARK: - Attach / Detatch

extension PlaybackCoordinator {

  public func attachPreview(fragment: FragmentHost) {
    assert(Thread.isMainThread, "should be called on main thread")

    guard fragment.hostView.playerView?.looper == nil else {
      return
    }

    fragment.setThumbnail()
  }

  public func coordinateAndAttach(fragments: [FragmentHost]) -> Future<Bool, Never> {
    let promise = Promise<Bool, Never>()
    let assetAndFragmentFutures = fragments.map { (fragment) in
      return getAsset(fragment: fragment)
    }

    assetAndFragmentFutures.sequence().onSuccess { [weak self] (results) in
      guard let self = self else {
        promise.complete(.success(false))
        return
      }
      var playerLoopers: [QueuePlayerLooper] = []
      results.forEach {
        if let asset = $0.0 {
          let fragmentHost = $0.1
          let looper = self.setupViewAndCreateLooperForAsset(fragment: fragmentHost,
                                                             asset: asset)
          playerLoopers.append(looper)
        } else {
          print("Tried to play an asset that couldn't be fetched. It might be deleted.")
        }
      }
      self.coordinatedLooperGroup = CoordinatedLooperGroup(loopers: playerLoopers)
      self.hotLooper.attach(looper: self.coordinatedLooperGroup!) // swiftlint:disable:this force_unwrapping
      promise.complete(.success(true))
    }.onFailure {_ in
      promise.complete(.success(false))
    }

    return promise.future
  }

  @discardableResult
  public func attach(fragment: FragmentHost) -> Future<Bool, Never> {
    assert(Thread.isMainThread, "should be called on main thread")
    guard !fragment.assetInfo.isEmpty else { return Future(value: false) }

    let fragmentId = fragment.assetInfo.loggingID

    print(self.hashValue, "Trying to attach \(fragmentId)")
    let playerHostView = fragment.hostView
    updateToken(playerHostView.hash)

    if let activeFuture = activeAttachFutures[playerHostView.hash] {
      return activeFuture
    }

    guard playerHostView.playerView?.looper == nil,
          !playerHostView.waitingToBeAttached else {
      return Future(value: true)
    }

    playerHostView.waitingToBeAttached = true
    self.playerHostViews.insert(playerHostView)
    let promise = Promise<Bool, Never>()

    playerHostView
      .setPlaybackLoadingStartTime(startTime: CMClockGetTime(CMClockGetHostTimeClock()),
                                   videoDuration: fragment.assetDuration)

    getAsset(fragment: fragment).onSuccess {[weak self] (result) in
      print(self.hashValue, "Successfully got asset for fragment: \(fragmentId)")
      guard let self = self,
            let asset = result.0 else {
        playerHostView.waitingToBeAttached = false
        promise.complete(.success(false))
        return
      }

      DispatchQueue.main.async(execute: {
        guard self.playerHostViews.contains(playerHostView),
              self.canBeAttached(asset: asset, fragmentId: fragmentId) else {
          playerHostView.waitingToBeAttached = false
          promise.complete(.success(false))
          return
        }

        guard playerHostView.playerView?.looper == nil else { return }

        let looper = self.setupViewAndCreateLooperForAsset(fragment: fragment,
                                                           asset: asset)

        print("Created and attaching looper \(looper.hashValue) for \(fragmentId)")

        self.hotLooper.attach(looper: looper)
        playerHostView.waitingToBeAttached = false
        promise.complete(.success(true))
      })
    }.onFailure { (error) in
      print(self.hashValue, "Failed to get asset for fragment: \(fragmentId)")
      playerHostView.waitingToBeAttached = false
      // We have failed to fetch an asset, tbd what to do here
      print(error)
      promise.complete(.success(false))
    }.onComplete { [weak self]  (_) in
      self?.activeAttachFutures[playerHostView.hash] = nil
    }
    let future = promise.future
    self.activeAttachFutures[playerHostView.hash] = future
    return future
  }

  public func detach(fragment: FragmentHost, previewImageToo: Bool) {
    assert(Thread.isMainThread, "should be called on main thread")
    // TODO : Check if we're calling detach multiple times, and whether it matters.

    let playerHostView = fragment.hostView

    guard playerHostView.playerView?.looper != nil else {
      playerHostView.waitingToBeAttached = false
      activeAttachFutures[playerHostView.hash] = nil
      playerHostViews.remove(playerHostView)
      return
    }

    let hashKey = playerHostView.hash
    let token = attachDetachTokens[hashKey]

    if !previewImageToo {
      if let time = currentTime() {
        let frameOffset = CMTimeMakeWithSeconds(self.gracePeriod, preferredTimescale: time.timescale)
        fragment.updateFrame(atTime: CMTimeAdd(time, frameOffset))
      }
    }

    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + self.gracePeriod) { [weak self] in
      guard let self = self else { return }

      print("Actually detaching clip from remix: \(fragment.assetInfo.loggingID)")

      let newToken = self.attachDetachTokens[hashKey]
      guard let t = token,
        let n = newToken,
        t == n else { return }

      self.detachImmediately(fragment: fragment, previewImageToo: previewImageToo)
    }
  }

  public func detachImmediately(fragment: FragmentHost, previewImageToo: Bool) {
    let playerHostView = fragment.hostView

    defer {
      playerHostView.waitingToBeAttached = false
      playerHostViews.remove(playerHostView)
      activeAttachFutures[playerHostView.hash] = nil
    }

    guard let looper = playerHostView.playerView?.looper else {
      return
    }

    hotLooper.detach(looper: looper)
    playerHostView.playerView?.looper?.clear()
    playerHostView.playerView?.looper = nil
    playerHostView.playerView = nil

    if previewImageToo {
      playerHostView.removeKeyFrameImage()
    }
  }

  // MARK: - Attach/Detach Convenience

  fileprivate func updateToken(_ viewHash: Int) {
    assert(Thread.isMainThread, "should be called on main thread")
    attachDetachTokens[viewHash] = UInt32.random(in: 0..<UInt32.max)
  }

  fileprivate func canBeAttached(asset: AVAsset, fragmentId: String) -> Bool {
    guard let assetVideoTrack = asset.tracks(withMediaType: .video).first else {
      print("Fragment \(fragmentId) has no video track")
      return false
    }
    guard let assetAudioTrack = asset.tracks(withMediaType: .audio).first else {
      print("Fragment \(fragmentId) has no audio track")
      return false
    }

    let commonAssetTimeRange =
      assetVideoTrack.timeRange.intersection(assetAudioTrack.timeRange)
    print(
      "ATTACHING FRAGMENT: \(fragmentId) with composed duration: \(commonAssetTimeRange.duration.toSeconds())")

    return true
  }

  fileprivate func setupViewAndCreateLooperForAsset(fragment: FragmentHost,
                                                    asset: AVAsset) -> QueuePlayerLooper {
    guard let duration = duration else {
      Fatal.safeError("Looper created with nil duration.")
    }

    let looper = QueuePlayerLooper(asset: asset,
                                   playerHostView: fragment.hostView,
                                   playbackStartTime: fragment.playbackStartTime,
                                   playbackDuration: duration)
    let playerView = AVLooperView()
    playerView.looper = looper

    let playerHostView = fragment.hostView
    playerHostView.playerView = playerView
    playerHostView.setKeyFrameIfNeeded(of: asset)

    self.adjustVolume(playerHostView: playerHostView, volume: fragment.volume)

    return looper
  }
}

// MARK: - Direct Attach

// TODO : This follows a pattern where we just directly attach to the hotlooper
// and bypass the playback coordinator. We should edit remix to directly access the HotLooper.
extension PlaybackCoordinator {
  func attach(looper: QueuePlayerLooper) {
    hotLooper.attach(looper: looper)
  }

  func detach(looper: QueuePlayerLooper) {
    hotLooper.detach(looper: looper)
  }
}

// MARK: - HotLooperDelegate
extension PlaybackCoordinator: HotLooperDelegate {
  func bufferingStarted() {
    delegate?.bufferingStarted()
  }

  func bufferingStopped() {
    delegate?.bufferingStopped()
  }

  func looped(atTime: CMTime, loopCount: Int) {
    delegate?.looped(atTime: atTime, loopCount: loopCount)
  }

  func playbackStarted() {
    delegate?.playbackStarted()
  }
}

extension PlaybackCoordinator: FragmentDataModelListener {
  func updated(model: PlaybackDataModel) {
    // TODO
  }
}
