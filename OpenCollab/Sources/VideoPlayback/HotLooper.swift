// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import AVFoundation
import CoreMedia
import Foundation
import UIKit

protocol HotLooperDelegate: NSObjectProtocol {
  func looped(atTime: CMTime, loopCount: Int)
  func playbackStarted()
  func bufferingStarted()
  func bufferingStopped()
}

class HotLooper: NSObject {
  private enum Constants {
    static let loopBuffer = CMTimeMake(value: 3, timescale: 300)
  }

  // MARK: Types

  private struct ObserverContexts {
    // TODO : Add observers to catch errors for recovery.
  }

  // MARK: Properties - Loop Control.

  public let duration: CMTime

  // StartTimes in the order that they we're invoked not necessarily in comparison order.
  private var loopTimes: [CMTime] = []

  private var lastObservedPlaybackTime: CMTime?
  private var scheduledPlaybackTime: CMTime?
  private var pausedLoopers: [Looper]?
  private var loopersToRecover: [Looper]?

  // TODO : Should this be by a timescale of 1/600.
  private(set) var loopStartTime: CMTime? {
    didSet {
      guard let loopStartTime = loopStartTime else { return }
      self.loopTimes.append(loopStartTime)
      delegate?.looped(atTime: loopStartTime, loopCount: loopCount)
    }
  }

  var loopCount: Int {
    get {
      return self.loopTimes.count == 0 ? 0 : self.loopTimes.count - 1
    }
  }

  private var loopTimer: Timer?

  private var accuracyTimer: Timer?

  // MARK: Properties - State

  private var isObserving = false

  private let syncClock: CMClock = CMClockGetHostTimeClock()

  // MARK: Properties - Loopers

  // The loopers being coordinated by the MultiLooper. MultiLooper is not responsible for
  // the creation or destruction of these loopers just the management of its references and
  // the state of playback.
  private var loopers: [Looper] = []

  // MARK: Properties - Buffering
  private var bufferingLooperCount = 0

  // MARK: - Properties - Delegation

  public weak var delegate: HotLooperDelegate?

  // MARK: Looper Management

  required init(duration: CMTime) {
    self.duration = duration
    super.init()

    NotificationCenter.default.addObserver(self,
                                           selector: #selector(didEnterBackground(_:)),
                                           name: UIApplication.didEnterBackgroundNotification,
                                           object: nil)

    NotificationCenter.default.addObserver(self,
                                           selector: #selector(didEnterForeground(_:)),
                                           name: UIApplication.didBecomeActiveNotification,
                                           object: nil)
  }

  deinit {
    NotificationCenter.default.removeObserver(self,
                                              name: UIApplication.didEnterBackgroundNotification,
                                              object: nil)

    NotificationCenter.default.removeObserver(self,
                                              name: UIApplication.didBecomeActiveNotification,
                                              object: nil)
  }

  // Resets the Hot Looper to be synced to a given time. Will not wait for
  // loopers to preroll before coordinating the loop. This could cause a gap
  // in playback. Useful for syncing the HotLooper to another instance of a HotLooper.
  func resetToPlaybackTime(playbackTime: CMTime, atTime: CMTime) {
    print(self.hashValue, "Reset loop to playback time: \(playbackTime.toSeconds()) at time: \(atTime.toSeconds())")
    // Reset the startTimes which also resets the loop count.
    loopStartTime = nil
    loopTimes = []

    let newStartTime = calculateStartTime(playbackTime: playbackTime, atTime: atTime)

    dispatchLoopEvent(loopStartTime: newStartTime, atTime: atTime)
    for looper in loopers {
      looper.clear()
      looper.play(itemTime: playbackTime, syncTime: atTime, syncClock: syncClock)
    }

    self.delegate?.playbackStarted()
  }

  func attach(looper: Looper) {
    assert(Thread.isMainThread, "should be called on main thread")

    print(self.hashValue, "Attaching QPL: \(looper.id)")

    if UIApplication.shared.applicationState == .active {
      activelyAttach(looper: looper)
    } else {
      postponeAttachUntilActive(looper: looper)
    }
  }

  func detach(looper: Looper) {
    assert(Thread.isMainThread, "should be called on main thread")
    // Control playback.
    looper.clear()

    // Drop reference.
    removeFromLoopers(looper: looper)

    // Unregister as the delegate.
    looper.delegate = nil

    print(self.hashValue, "Detached a Looper from HotLooper")
  }

  func pause() {
    self.lastObservedPlaybackTime = calculatePlaybackTime(currentTime: calculateCurrentTime())
    self.pausedLoopers = loopers

    clearLoopersAndPlaybackState()
  }

  // Unpause at given playback time when the players are ready.
  func unpause(playbackTime: CMTime?) {
    // CAUTION: Always attach before reseting playback time. If the playbackTime
    // is close to the end the logic for switching the current and buffer player
    // of the next loop gets a little weird. Looking at more robust playback logic
    // to avoid this issue.

    guard let unpausePlaybackTime = playbackTime ?? self.lastObservedPlaybackTime else { return }

    // Schedule what time the loopers should play when ready.
    scheduledPlaybackTime = unpausePlaybackTime

    // This will start preheating the loopers. When they are ready they will play.
    pausedLoopers?.forEach {
      attach(looper: $0)
    }

    self.pausedLoopers = nil
  }

  func clear() {
    clearLoopersAndPlaybackState()
    clearRecoveryState()
  }

  func clearLoopersAndPlaybackState() {
    clearPlaybackState()

    for looper in loopers {
      detach(looper: looper)
    }
  }

  private func postponeAttachUntilActive(looper: Looper) {
    assert(Thread.isMainThread, "should be called on main thread")

    print(self.hashValue, "Postponing attach for: \(looper.id)")

    if loopersToRecover == nil {
      loopersToRecover = [looper]
    } else {
      loopersToRecover?.append(looper)
    }

    if lastObservedPlaybackTime == nil {
      lastObservedPlaybackTime = .zero
    }
  }

  private func activelyAttach(looper: Looper) {
    assert(Thread.isMainThread, "should be called on main thread")

    let hasLooper = loopers.contains { $0.id == looper.id }

    if hasLooper {
      print(self.hashValue, "Loopers already contains \(looper.id)")
      print(self.hashValue, "Hot looper has \(loopers.count) loopers.")
      return
    }

    print(self.hashValue, "attaching a looper: \(looper.id)")
    loopers.append(looper)
    looper.delegate = self

    // If the hot loop hasn't started yet preheat the looper instead of syncing it. This
    // way we can guarantee the first playback plays from .zero time. If we just sync to
    // the loop, playback will start at N time where N is the time it takes to preroll.
    if loopStartTime == nil {
      print(self.hashValue, "Tried to attach but loop start time is nil so we'll start preheating the looper instead.")
      preheatLooper(looper: looper)
    } else {
      syncToLoop(looper: looper, atTime: calculateCurrentTime())
    }

    print(self.hashValue, "Attaching a Looper \(looper.id) to HotLooper")
  }

  private func clearRecoveryState() {
    loopersToRecover = nil
  }

  private func clearPlaybackState() {
    loopStartTime = nil
    loopTimes = []

    loopTimer?.invalidate()
    loopTimer = nil

    stopAccuracyTimer()
  }

  // MARK: Playback

  private func dispatchLoopEvent(loopStartTime: CMTime, atTime: CMTime) {
    assert(Thread.isMainThread, "should be called on main thread")

    print(self.hashValue, "Dispatching a loop event for startTime: \(loopStartTime.toSeconds()) at time: \(atTime.toSeconds()) at current time: \(calculateCurrentTime().toSeconds())")

    self.loopStartTime = loopStartTime

    // We calculate the remainingInterval to handle use cases where the playback time
    // is reset to an arbitrary time such as when we countdown for record.
    let loopInterval = calculateRemainingInterval(intervalStartTime: loopStartTime,
                                                  atTime: atTime)

    let bufferedLoopInterval = CMTimeSubtract(loopInterval, Constants.loopBuffer)

    loopTimer?.invalidate()
    loopTimer = nil
    loopTimer = Timer.scheduledTimer(withTimeInterval: bufferedLoopInterval.toSeconds(),
                                     repeats: false,
                                     block: { [weak self] (_) in
                                      guard let self = self else { return }
                                      self.triggerLoop()
                                     })
    // TODO : We could make this 1/300th of a second so that we are accurate up
    // to 1/600th of a second, which is what we are aiming for.
    loopTimer?.tolerance = .zero
    RunLoop.current.add(loopTimer!, forMode: .common)

    print(self.hash, "Dispatching a loop that should loop at: \(CMTimeAdd(loopStartTime, bufferedLoopInterval).toSeconds())")
  }

  private func triggerLoop() {
    assert(Thread.isMainThread, "should be called on main thread")

    print("----------------------- TRIGGER LOOP -------------------------")
    guard let algorithmicCurrentTime = algorithmicCurrentTimeAtLoop() else {
      print(self.hashValue, "Tried to loop but we have no initialStartTime.")
      return
    }

    print(self.hash,
                      "Looping at clock time: \(calculateCurrentTime().toSeconds())")
    print(self.hash,
                      "Looping at algorithmic clock time: \(algorithmicCurrentTime.toSeconds())")

    let playbackTime = calculatePlaybackTime(currentTime: algorithmicCurrentTime)
    print(self.hashValue, "Looping at playbackTime: \(playbackTime.toSeconds())")

    for looper in loopers {
      looper.loop(loopTime: algorithmicCurrentTime,
                  loopDuration: duration,
                  syncClock: syncClock)
    }

    // TODO : Refactor the loop timer into just a repeating timer. We'll have
    // to reapproach how we "reset" to a given playback time since the loop interval for
    // the first loop is different in this case than for a general loop.
    dispatchLoopEvent(loopStartTime: algorithmicCurrentTime,
                      atTime: algorithmicCurrentTime)
  }

  // Used to add a new looper to the loop once its prerolled and ready to go. At this point
  // the hot looper has control of the looper.
  private func syncToLoop(looper: Looper, atTime: CMTime) {
    assert(Thread.isMainThread, "should be called on main thread")
    let playbackTime = calculatePlaybackTime(currentTime: atTime)

    print(self.hashValue, "Syncing looper \(looper.id) to loop at time: \(atTime.toSeconds()) for playback time: \(playbackTime.toSeconds())")

    looper.play(itemTime: playbackTime, syncTime: atTime, syncClock: syncClock)
  }

  private func preheatLooper(looper: Looper) {
    looper.preheat(syncClock: syncClock)
  }

  // MARK: - Time Management

  // Returns the startTimes inclusive of the start and end index
  public func getLoopTimes() -> [CMTime] {
    return loopTimes
  }

  // Returns a time relative to the playback start time of the loop - not absolute time
  func currentPlaybackTime() -> CMTime? {
    guard loopStartTime != nil else { return nil }
    return calculatePlaybackTime(currentTime: calculateCurrentTime())
  }

  private func calculateCurrentTime() -> CMTime {
    return CMClockGetTime(syncClock)
  }

  private func algorithmicCurrentTimeAtLoop() -> CMTime? {
    guard let initialStartTime = loopTimes.first else {
      return nil
    }

    let elapsedTime = CMTimeMultiply(duration, multiplier: Int32(loopTimes.count))
    let loopTime = CMTimeAdd(initialStartTime, elapsedTime)

    print("Calculated algorithmic loop time \(loopTime.toSeconds()) for initial time: \(initialStartTime.toSeconds()) and number of loops: \(loopTimes.count)")
    return loopTime
  }

  private func calculatePlaybackTime(currentTime: CMTime) -> CMTime {
    guard let startTime = loopStartTime else {
      print(self.hash, "Tried to calculate playbackTime before we'd ever started looping. Playback time will be zero.")
      return CMTime.zero
    }

    // Calculate the time since we last started looping in the same timescale as duration.
    let elapsedTime = CMTimeSubtract(currentTime, startTime)
    let scaledElapsedTime = CMTimeConvertScale(elapsedTime,
                                               timescale: duration.timescale,
                                               method: .quickTime)

    // Every time we play for N = duration seconds we reset playbackTime to zero.
    let remainingTimeInDurationTimescale = scaledElapsedTime.value % duration.value
    let playbackTime = CMTimeMake(value: remainingTimeInDurationTimescale,
                                  timescale: duration.timescale)

    return playbackTime
  }

  private func calculateStartTime(playbackTime: CMTime, atTime: CMTime) -> CMTime {
    return CMTimeSubtract(atTime, playbackTime)
  }

  private func calculateRemainingInterval(intervalStartTime: CMTime,
                                          atTime: CMTime) -> CMTime {
    let elapsedInterval = CMTimeSubtract(atTime, intervalStartTime)
    let scaledElapsedInterval = CMTimeConvertScale(elapsedInterval,
                                                   timescale: duration.timescale,
                                                   method: .quickTime)

    let remainingInterval = CMTimeSubtract(duration, scaledElapsedInterval)

    return remainingInterval
  }

  // MARK: Convenience
  private func removeFromLoopers(looper: Looper) {
    assert(Thread.isMainThread, "should be called on main thread")

    let possibleIndex = loopers.firstIndex { $0.id == looper.id }

    guard let index = possibleIndex else {
      print(self.hashValue, "Tried to detach a Looper from the Multilooper that was never attached")
      return
    }

    loopers.remove(at: index)
  }

  private func stopAccuracyTimer() {
    accuracyTimer?.invalidate()
    accuracyTimer = nil
  }

  @objc func didEnterBackground(_ sender: Notification) {
    guard loopers.count > 0 else { return }

    let backgroundTask = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)

    self.lastObservedPlaybackTime = calculatePlaybackTime(currentTime: calculateCurrentTime())
    self.loopersToRecover = loopers

    clearLoopersAndPlaybackState()

    UIApplication.shared.endBackgroundTask(backgroundTask)
  }

  @objc func didEnterForeground(_ sender: Notification) {
    guard let loopersToRecover = loopersToRecover, let lastObservedPlaybackTime = lastObservedPlaybackTime else { return }
    for looper in loopersToRecover {
      attach(looper: looper)
    }
    // clear the saved loopers after recovery
    self.loopersToRecover = nil
    resetToPlaybackTime(playbackTime: lastObservedPlaybackTime, atTime: calculateCurrentTime())
  }
}

// MARK: - LooperDelegate

extension HotLooper: LooperDelegate {
  func isBuffering(looper: Looper) {
    bufferingLooperCount += 1

    // If we've just started buffering for the first time
    if bufferingLooperCount == 1 {
      self.delegate?.bufferingStarted()
    }
  }

  func stoppedBuffering(looper: Looper) {
    bufferingLooperCount -= 1

    // All loopers have finished buffering
    if bufferingLooperCount == 0 {
      self.delegate?.bufferingStopped()
    }
  }

  func readyToLoop(looper: Looper) {
    assert(Thread.isMainThread, "should be called on main thread")

    // We want to start the hot loop when the first player is ready.
    guard loopStartTime == nil else {
      print("Looper is ready but we've already started the loop.")
      return
    }

    print(
      "------------------------ LOOPER READY FOR HOT LOOP ------------------------")

    // Start playback for a scheduled time if there is any. Otherwise playback will start now.
    let currentTime = calculateCurrentTime()
    var startTime: CMTime

    if let scheduledPlaybackTime = scheduledPlaybackTime {
      startTime = calculateStartTime(playbackTime: scheduledPlaybackTime, atTime: currentTime)
      self.scheduledPlaybackTime = nil
    } else {
      startTime = currentTime
    }

    dispatchLoopEvent(loopStartTime: startTime, atTime: currentTime)

    self.delegate?.playbackStarted()

    for looper in loopers {
      syncToLoop(looper: looper, atTime: currentTime)
    }
  }
}
