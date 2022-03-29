// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import AVFoundation

protocol HotPlayerDelegate: NSObjectProtocol {
  func playerPreheated(player: HotPlayer)
  // Currently only used for debugging playback loading purposes.
  func playerStartedPlaying(player: HotPlayer, time: CMTime)
  func bufferingStarted(player: HotPlayer)
  func bufferingStopped(player: HotPlayer)
}

// A HotPlayer is a specialized player that can be scheduled for a given
// playback time synced to a host time using a host clock before the player
// is ready to play. The HotPlayer doesn't necessarily host a AVPlayer unless its close to
// the scheduled playback time or has been forced to preheat ahead of time.
final class HotPlayer: NSObject {

  private enum Constants {
    // TODO : Experiment with this timing. For now we give a generous buffer.
    static let allotedPrerollBuffer = CMTimeMakeWithSeconds(4, preferredTimescale: 600)
  }

  // MARK: - Properties

  private var itemTime: CMTime?
  private var syncTime: CMTime?
  private let syncClock: CMClock?

  // We always create a player layer so that even if the player isn't ready we can attach
  // the layer to the view and once the player is ready it will attach to the layer. This
  // allows us to maintain the looping logic completely independent of the player's state.
  lazy var layer: AVPlayerLayer = {
    let layer = AVPlayerLayer()
    layer.contentsGravity = .resizeAspectFill
    layer.videoGravity = .resizeAspectFill
    return layer
  }()

  var player: InstrumentedAVPlayer?
  var playerItem: ObservablePlayerItem?

  private let asset: AVAsset
  private let assetPlaybackStartTime: CMTime
  private let assetPlaybackDuration: CMTime

  private var isDetectingRecovery = false
  private var isObservingBuffering = false

  private var isPreheating = false
  private var isScheduled = false
  private var shouldBePlaying = false

  // MARK: Properties - Playback

  private var playWorkItem: DispatchWorkItem?

  // MARK: Properties - Delegation

  weak var delegate: HotPlayerDelegate?

  // MARK: Properties - Volume

  var isMuted: Bool = false {
    didSet {
      player?.isMuted = self.isMuted
    }
  }

  var volume: Float = 1.0 {
    didSet {
      player?.volume = self.volume
    }
  }

  var currentTime: CMTime? {
    get {
      guard let currentTime = player?.currentTime() else {
        return nil
      }

      return CMTimeSubtract(currentTime, assetPlaybackStartTime)
    }
  }

  required init(asset: AVAsset,
                assetPlaybackStartTime: CMTime,
                assetPlaybackDuration: CMTime,
                clock: CMClock?,
                volume: Float,
                isMuted: Bool) {
    self.asset = asset
    self.assetPlaybackStartTime = assetPlaybackStartTime
    self.assetPlaybackDuration = assetPlaybackDuration
    self.syncClock = clock
    self.volume = volume
    self.isMuted = isMuted

    super.init()
  }

  func preheat() {
    // TODO : Investigate moving Hot Player code to the background thread.
    assert(Thread.isMainThread, "should be called on main thread")
    if isScheduled {
      print("Tried to preroll a player that has already been scheduled.")
      return
    }

    isPreheating = true
    createPlayer()
  }

  func schedule(itemTime: CMTime, syncTime: CMTime?) {
    assert(Thread.isMainThread, "should be called on main thread")
    self.itemTime = itemTime
    self.syncTime = syncTime

    isScheduled = true

    print(self.hashValue, "Scheduled a player for: \(itemTime.toSeconds()) at sync time: \(String(describing: syncTime?.toSeconds()))")

    // If we are preheating just wait for preroll to complete and then preroll will prepare
    // playback.
    if isPreheating {
      print(self.hashValue, "scheduled player is already preheating")
      return
    }
    preparePlayback()
  }

  // MARK: - Playback
  private func prerollPlayer() {
    assert(Thread.isMainThread, "should be called on main thread")
    guard let player = player else {
      Fatal.safeAssert("Tried to preroll a hot player with no AVPlayer")
      return
    }

    print(self.hashValue, "prerolling an AVPlayer")

    player.preroll(atRate: 1.0) { (finished) -> Void in
      assert(Thread.isMainThread, "should be called on main thread")

      guard finished else {
        print("ERROR: Failed to preroll a player")
        return
      }

      self.isPreheating = false

      // If itemTime has been set while prerolling then we should prepare playback().
      guard self.itemTime == nil else {
        print(self.hashValue, "Player preroll complete - preparing for scheduled playback time.")
        self.preparePlayback()
        return
      }

      // Otherwise we should notify that the hot player is preheated.
      print(self.hashValue, "Player preroll complete - but its not scheduled so we'll notify that its ready.")
      self.delegate?.playerPreheated(player: self)
    }
  }

  private func preparePlayback() {
    // If there is no sync time then we will just automatically play when ready.
    guard let syncTime = syncTime, let syncClock = syncClock else {
      print(self.hashValue, "No sync time just play the player.")
      self.prepareToPlay()
      return
    }

    // Otherwise, figure out how much time remains until the player is scheduled to play.
    // If its less than the preroll buffer required just start creating the player so that
    // we can set the rate in time to play on schedule. If there isn't enough time left to
    // preroll the player there will be a pause in playback but the player will start
    // playing synced correctly. If there is time remaining until playback is scheduled
    // we'll dispatch a work item to preroll closer to the scheduled time.
    let currentSyncClockTime = CMClockGetTime(syncClock)
    let endTime = CMTimeAdd(syncTime, assetPlaybackDuration)

    if CMTimeCompare(currentSyncClockTime, endTime) > 0 {
      print("Not bothering to create an AVPlayer for this Hot Player because its already past its scheduled playback time.")
      return
    }

    let remainingTime = CMTimeSubtract(syncTime, currentSyncClockTime)
    print(self.hashValue, "Going to dispatch play work for player that needs to start in \(remainingTime.toSeconds()).")
    let dispatchWaitTime = CMTimeSubtract(remainingTime, Constants.allotedPrerollBuffer)

    if CMTimeCompare(dispatchWaitTime, .zero) > 0 {
      self.dispatchPlayWork(waitTime: dispatchWaitTime)
      return
    }

    self.prepareToPlay()
  }

  private func dispatchPlayWork(waitTime: CMTime) {
    print(self.hashValue, "Dispatching play work in wait time: \(waitTime.toSeconds())")
    playWorkItem?.cancel()
    playWorkItem = DispatchWorkItem { [weak self] in
      self?.prepareToPlay()
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + waitTime.toSeconds(),
                                  execute: playWorkItem!)
  }

  private func prepareToPlay() {
    // We observe the player whenever a reference is set and when its ready we will start to
    // play. We may have already created a player during preheat so only create one if
    // necessary.
    guard self.player == nil else {
      print(self.hashValue, "Preparing to play a scheduled player.")
      playAtScheduledTime()
      return
    }

    print(self.hashValue, "Preparing to play a new player.")
    createPlayer()
  }

  private func playAtScheduledTime() {
    guard let player = player else {
      print("Tried to play a Hot Player at a scheduled time but there is no AVPlayer.")
      return
    }

    print(self.hashValue, "playing player at scheduled time.")

    // If the playback time was never specified then just play.
    guard let itemTime = itemTime,
          let syncTime = syncTime,
          let syncClock = syncClock else {
      // TODO : We could support playing at a given time that isn't synced to
      // a clock by seeking to itemTime and then playing.
      print(self.hashValue, "Just play the player.")
      player.play()
      return
    }

    var relativeItemTime = CMTimeAdd(assetPlaybackStartTime, itemTime)
    // Copy sync time. We might adjust it and we don't want to change the set syncTime incase
    // we need to recover.
    var hostTime = syncTime

    // If the sync time was for a time in the past adjust the scheduled playback time to be synced
    // to the current clock time so that the video won't fast forward to sync.
    let currentSyncClockTime = CMClockGetTime(syncClock)
    if CMTimeCompare(currentSyncClockTime, syncTime) > 0 {
      let elapsedTime = CMTimeSubtract(currentSyncClockTime, syncTime)
      let adjustedItemTime = CMTimeAdd(elapsedTime, relativeItemTime)

      relativeItemTime = adjustedItemTime
      hostTime = currentSyncClockTime
    }

    print(self.hash, "setting rate to 1 time \(relativeItemTime.toSeconds()) atHostTime \(currentSyncClockTime.toSeconds())")
    player.setRate(1.0, time: relativeItemTime, atHostTime: hostTime)

    self.delegate?.playerStartedPlaying(player: self,
                                        time: currentSyncClockTime)

    shouldBePlaying = true
  }

  private func play() {
    assert(Thread.isMainThread, "should be called on main thread")

    if self.isPreheating {
      self.prerollPlayer()
      return
    } else if self.isScheduled {
      self.playAtScheduledTime()
      return
    }

    Fatal.safeAssert("Created a player when we weren't preheating or scheduled")
  }

  // MARK: - Convenience

  private func createPlayer() {
    self.playerItem = ObservablePlayerItem(asset: asset)
    playerItem?.forwardPlaybackEndTime = CMTimeAdd(assetPlaybackStartTime, assetPlaybackDuration)
    playerItem?.preferredForwardBufferDuration = 1.5

    // Start observing player status changes before the playerItem is associated
    // with an AVPlayer to catch all status changes.
    beginObservingPlayerStatus()

    let player = InstrumentedAVPlayer(playerItem: playerItem)
    player.isMuted = isMuted
    player.volume = volume

    player.masterClock = syncClock
    player.automaticallyWaitsToMinimizeStalling = false

    self.player = player
    layer.player = self.player

    startRecoveryDetection()
  }

  func clear() {
    clearInternalState()

    // Clear external state.
    layer.removeFromSuperlayer()
    delegate = nil
  }

  private func clearInternalState() {
    stopRecoveryDetection()

    playWorkItem?.cancel()

    player?.pause()
    player?.cancelPendingPrerolls()
    player = nil
    playerItem = nil

    layer.player = nil
  }

  // MARK: - Buffering

  private func endBufferingObservationAndRestartPlayback() {
    assert(Thread.isMainThread, "should be called on main thread")

    // Another buffering observer may have completed already so we'll
    // avoid double calling the following code.
    guard isObservingBuffering else { return }

    self.delegate?.bufferingStopped(player: self)
    isObservingBuffering = false
    self.playerItem?.endObservingPlaybackLikelyToKeepUp()
    self.playerItem?.endObservingPlaybackBufferFull()

    self.play()
  }

  // MARK: - Recovery

  private func startRecoveryDetection() {
    assert(Thread.isMainThread, "should be called on main thread")
    guard !isDetectingRecovery, let playerItem = player?.currentItem else { return }

    NotificationCenter.default.addObserver(self,
                                           selector: #selector(onItemRateChanged(_:)),
                                           name: kCMTimebaseNotification_EffectiveRateChanged as NSNotification.Name,
                                           object: playerItem.timebase)

    isDetectingRecovery = true
  }

  private func stopRecoveryDetection() {
    assert(Thread.isMainThread, "should be called on main thread")
    guard isDetectingRecovery, let playerItem = player?.currentItem else { return }

    NotificationCenter.default.removeObserver(self,
                                              name: kCMTimebaseNotification_EffectiveRateChanged as NSNotification.Name,
                                              object: playerItem.timebase)

    isDetectingRecovery = false
  }

  @objc func onItemRateChanged(_ sender: Notification) {
    let changedRate = CMTimebaseGetRate(sender.object as! CMTimebase)
    guard changedRate == 0.0 else { return }

    print(self.hashValue, "PlayerItem rate set to 0. Checking to see if we should recover")

    DispatchQueue.main.async {
      guard self.isDetectingRecovery, self.playbackIsStuck() == true else {
        print(self.hashValue,
                          "-------------------------------- RECOVERY NOT REQUIRED -----------------------------------")
        return
      }

      // Check if we've stopped playing because playback has stalled because
      // we need to buffer.
      guard self.playerItem?.isPlaybackBufferEmpty == false else {
        print(self.hashValue,
                          "-------------------------------- BUFFERING REQUIRED -----------------------------------")
        self.beginObservingBuffering()
        return
      }

      print(self.hashValue,
                        "-------------------------------- RECOVERY REQUIRED -----------------------------------")
      self.logPlayerStatus()
      self.recover()
    }
  }

  private func playbackIsStuck() -> Bool? {
    assert(Thread.isMainThread, "should be called on main thread")
    guard let playerItem = player?.currentItem else {
        Fatal.safeAssert("Tried to detect if we are stuck but we don't have a current player.")
        return nil
    }

    guard let timebase = playerItem.timebase,
      CMTimebaseGetRate(timebase) == 0.0 else {
        print(self.hashValue, "The current player has started to play and we don't need to recover.")
        return false
    }

    let currentItemTime = CMTimebaseGetTime(timebase)
    let endTime = playerItem.forwardPlaybackEndTime

    guard currentItemTime < endTime && currentItemTime > .zero else {
      print(self.hashValue, "The current player is stopped because playback completed or hasn't started. No need to recover.")
      return false
    }

    return true
  }

  private func recover() {
    assert(Thread.isMainThread, "should be called on main thread")
    print("Recovering an asset with playable status: \(asset.isPlayable)")
    print("Recovering an asset with readable status: \(asset.isReadable)")
    print("Recovering an asset with duration: \(asset.duration.toSeconds())")
    print("Recovering an asset with \(asset.tracks.count) asset tracks")
    clearInternalState()
    preparePlayback()
  }

  private func logPlayerStatus() {
    switch player?.status {
    case .readyToPlay:
      print(self.hashValue, "Player status is ready to play")
    case .failed:
      print(self.hashValue, "Player status is failed")
    default:
        print(self.hashValue, "Player status is unknown")
    }

    print(self.hashValue, "Player error is: \(String(describing: player?.error.debugDescription))")

    switch player?.currentItem?.status {
    case .readyToPlay:
      print(self.hashValue, "PlayerItem status is ready to play")
    case .failed:
      print(self.hashValue, "PlayerItem status is failed")
    default:
        print(self.hashValue, "PlayerItem status is unknown")
    }

    print(self.hashValue, "PlayerItem error is: \(String(describing: player?.currentItem?.error.debugDescription))")

    print(self.hashValue, "PlayerItem time: \(String(describing: player?.currentItem?.currentTime().toSeconds()))")
  }

  // MARK: - KVO and State Management

  private func beginObservingPlayerStatus() {
    assert(Thread.isMainThread, "should be called on main thread")
    playerItem?.beginObservingStatus(withCallback: { [weak self] status  in
      guard let self = self else { return }
      if status == .readyToPlay {
        DispatchQueue.main.async {
          self.playerItem?.endObservingStatus()

          if self.playerItem?.isPlaybackLikelyToKeepUp == true
              || self.playerItem?.isPlaybackBufferFull == true {
            self.play()
          } else {
            self.beginObservingBuffering()
          }
        }
      } else {
        print(self.hashValue, "AVPlayer failed to get ready to play - recovering")
        DispatchQueue.main.async {
          self.recover()
        }
      }
    })
  }

  private func beginObservingBuffering() {
    assert(Thread.isMainThread, "should be called on main thread")

    self.delegate?.bufferingStarted(player: self)

    // We observe both isPlaybackLikelyToKeepUp and isPlaybackBufferFull to
    // to determine if we have sufficiently buffered. We'll use this flag to
    // make sure callbacks from either KVO will be thread/race condition safe.
    isObservingBuffering = true

    // Check if the player is buffered since we decided to start observing.
    guard self.playerItem?.isPlaybackLikelyToKeepUp == false
            && self.playerItem?.isPlaybackBufferFull == false else {
      self.play()
      return
    }

    self.playerItem?.beginObservingPlaybackLikelyToKeepUp { [weak self] isPlaybackLikelyToKeepUp in
      if isPlaybackLikelyToKeepUp {
        print(self.hashValue, "Playback likely to keep up - restart")
        DispatchQueue.main.async {
          // Avoids double ending observation and restarting playback when there might be
          // a race condition between isPlaybackLikelyToKeepUp and isPlaybackBufferFull
          self?.endBufferingObservationAndRestartPlayback()
        }
      }
    }

    self.playerItem?.beginObservingPlaybackBufferFull { [weak self] isPlaybackBufferFull in
      if isPlaybackBufferFull {
        print(self.hashValue, "Playback buffer full - restart")
        DispatchQueue.main.async {
          // Avoids double ending observation and restarting playback when there might be
          // a race condition between isPlaybackLikelyToKeepUp and isPlaybackBufferFull
          self?.endBufferingObservationAndRestartPlayback()
        }
      }
    }
  }
}
