// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import AVFoundation
import CoreMedia

class QueuePlayerLooper: NSObject, Looper {

  // MARK: - Properties - Data
  internal var id: String = UUID().uuidString

  // MARK: - Properties - Playback

  // The master layer that hosts the other playerLayers when they become the current
  // player.
  public let layer: AVPlayerLayer
  public var currentPlayer: HotPlayer?
  public var bufferPlayer: HotPlayer?

  let asset: AVAsset
  var playerHostView: AVPlayerHostView?
  let playbackStartTime: CMTime
  let playbackDuration: CMTime

  // MARK: Properties - State
  private var isPreheating = false
  var isReadyToLoop = false

  // MARK: Properties - Delegation

  weak var delegate: LooperDelegate?

  // MARK: Properties - Volume

  var isMuted: Bool = false {
    didSet {
      currentPlayer?.isMuted = self.isMuted
      bufferPlayer?.isMuted = self.isMuted
    }
  }

  var volume: Float = 1.0 {
    didSet {
      currentPlayer?.volume = self.volume
      bufferPlayer?.volume = self.volume
    }
  }

  var shouldMuteWithoutHeadphones: Bool = false {
    didSet {
      headphoneStateChanged()
    }
  }

  // MARK: - Looper

  required init(asset: AVAsset,
                playerHostView: AVPlayerHostView? = nil,
                playbackStartTime: CMTime,
                playbackDuration: CMTime) {
    self.asset = asset
    self.playerHostView = playerHostView
    self.playbackStartTime = playbackStartTime
    self.playbackDuration = playbackDuration
    self.layer = AVPlayerLayer()
    layer.contentsGravity = .resizeAspectFill
    layer.videoGravity = .resizeAspectFill

    super.init()

    NotificationCenter.default.addObserver(self,
                                           selector: #selector(muteStateChanged),
                                           name: AppMuteManager.Notifications.muteSwitchStateChanged,
                                           object: nil)

    NotificationCenter.default.addObserver(self,
                                           selector: #selector(headphoneStateChanged),
                                           name: AppHeadphoneManager.Notifications.headphoneStateChanged,
                                           object: nil)
  }

  // MARK: - External Control

  func preheat(syncClock: CMClock) {
    isPreheating = true
    currentPlayer = createPlayer(syncClock: syncClock)
    currentPlayer?.preheat()
  }

  func play(itemTime: CMTime, syncTime: CMTime, syncClock: CMClock) {
    assert(Thread.isMainThread, "should be called on main thread")

    print(self.hashValue,
                      "------------------------- PLAY QUEUE PLAYER LOOPER ------------------------")
    print(self.hashValue, "Play looper at itemTime: \(itemTime.toSeconds()) for syncTime: \(syncTime.toSeconds())")

    // We may have already created a player while preheating. If the player is currently
    // preheating we can still call schedule on it. HotPlayer will handle the logic for
    // preparing to play after preheating is done if its been scheduled.
    if self.currentPlayer != nil {
      print(self.hashValue,
                        "Play was called on a QPL that was already preheating.")
    }
    let currentPlayer = self.currentPlayer ?? createPlayer(syncClock: syncClock)
    currentPlayer.schedule(itemTime: itemTime, syncTime: syncTime)
    attachPlayer(player: currentPlayer)

    let remainingPlaybackTime = CMTimeSubtract(playbackDuration, itemTime)
    let nextLoopTime = CMTimeAdd(syncTime, remainingPlaybackTime)

    setBufferPlayer(syncTime: nextLoopTime, syncClock: syncClock)
  }

  func loop(loopTime: CMTime, loopDuration: CMTime, syncClock: CMClock) {
    assert(Thread.isMainThread, "should be called on main thread")

    print(self.hashValue,
      "------------------------- LOOP QUEUE PLAYER LOOPER ------------------------")

    print(self.hashValue, "Loop time: \(loopTime.toSeconds()) with duration: \(loopDuration.toSeconds())")

    guard bufferPlayer != nil else {
      print("Tried to loop but there is no buffer player to play")
      return
    }

    // Looping consists of three steps:
    // 1) Stop the current player
    // 2) Swap the current player and buffer player in the layer
    // 3) Create a new buffer player
    removeCurrentPlayer()
    attachBufferPlayer()
    let nextLoopTime = CMTimeAdd(loopTime, loopDuration)
    setBufferPlayer(syncTime: nextLoopTime, syncClock: syncClock)
  }

  func clear() {
    assert(Thread.isMainThread, "should be called on main thread")

    self.currentPlayer?.clear()
    self.currentPlayer = nil

    self.bufferPlayer?.clear()
    self.bufferPlayer = nil
  }

  private func createPlayer(syncClock: CMClock) -> HotPlayer {
    let player = HotPlayer(asset: asset,
                           assetPlaybackStartTime: playbackStartTime,
                           assetPlaybackDuration: playbackDuration,
                           clock: syncClock,
                           volume: volume,
                           isMuted: isMuted)

    player.delegate = self
    return player
  }

  private func attachPlayer(player: HotPlayer) {
    print(self.hashValue,
                      "Attached a current player with time: \(String(describing: player.currentTime?.toSeconds()))")

    currentPlayer = player

    player.volume = volume
    player.isMuted = isMuted

    layer.addSublayer(player.layer)
    player.layer.frame = layer.bounds
  }

  private func setBufferPlayer(syncTime: CMTime, syncClock: CMClock) {
    print(self.hashValue, "Created a buffer player with sync time: \(syncTime.toSeconds())")
    bufferPlayer = createPlayer(syncClock: syncClock)
    bufferPlayer?.schedule(itemTime: .zero, syncTime: syncTime)
  }

  private func attachBufferPlayer() {
    guard let bufferPlayer = bufferPlayer else {
      print(self.hashValue, "Tried to attach the buffer player but it doesn't exist.")
      return
    }

    print(self.hashValue, "attaching a buffer player")
    attachPlayer(player: bufferPlayer)

    self.bufferPlayer = nil
  }

  private func removeCurrentPlayer() {
    currentPlayer?.clear()
    self.currentPlayer = nil
  }
}

// MARK: - Volume Control

extension QueuePlayerLooper {
  @objc func muteStateChanged() {
    if AppMuteManager.shared.currentState() == .Muted || shouldMuteWithoutHeadphones {
      isMuted = true
    } else {
      isMuted = false
    }
  }

  @objc func headphoneStateChanged() {
    guard shouldMuteWithoutHeadphones else { return }
    isMuted = !(AppHeadphoneManager.shared.currentState() == .Connected)
  }
}

// MARK: - Hot Player Delegate

extension QueuePlayerLooper: HotPlayerDelegate {
  func bufferingStarted(player: HotPlayer) {
    self.delegate?.isBuffering(looper: self)
  }

  func bufferingStopped(player: HotPlayer) {
    self.delegate?.stoppedBuffering(looper: self)
  }

  func playerPreheated(player: HotPlayer) {
    assert(Thread.isMainThread, "should be called on main thread")
    // Guard against the player being detached while preheating.
    guard player == currentPlayer else {
      print(self.hashValue,
                        "Player preheat complete for a player that is no longer the currentPlayer.")
      return
    }

    guard isPreheating else {
      print(self.hashValue,
                        "Player preheat complete for a player but the QPL is no longer preheating.")
      return
    }

    isPreheating = false
    isReadyToLoop = true

    delegate?.readyToLoop(looper: self)
  }

  func playerStartedPlaying(player: HotPlayer, time: CMTime) {
    assert(Thread.isMainThread, "should be called on main thread")
    playerHostView?.setPlaybackLoadingEndTime(endTime: time)
  }
}
