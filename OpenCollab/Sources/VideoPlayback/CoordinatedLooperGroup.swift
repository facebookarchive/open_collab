// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import AVFoundation
import CoreMedia

class CoordinatedLooperGroup: NSObject, Looper {

  // MARK: - Properties - Data
  internal var id: String = UUID().uuidString

  // The loopers that play at the same time.
  private var loopers: [QueuePlayerLooper] = []

  // MARK: Properties - Delegation

  weak var delegate: LooperDelegate?

  // MARK: - Coordinated Looper Group

  required init(loopers: [QueuePlayerLooper]) {
    self.loopers = loopers
    super.init()

    self.loopers.forEach {
      $0.delegate = self
    }
  }

  // MARK: - External Control

  func preheat(syncClock: CMClock) {
    loopers.forEach { $0.preheat(syncClock: syncClock) }
  }

  func play(itemTime: CMTime, syncTime: CMTime, syncClock: CMClock) {
    loopers.forEach {
      $0.play(itemTime: itemTime,
              syncTime: syncTime,
              syncClock: syncClock)
    }
  }

  func loop(loopTime: CMTime, loopDuration: CMTime, syncClock: CMClock) {
    loopers.forEach {
      $0.loop(loopTime: loopTime,
              loopDuration: loopDuration,
              syncClock: syncClock)
    }
  }

  func clear() {
    loopers.forEach {
      // Unregister as the delegate.
      $0.delegate = nil
      $0.clear()
    }
  }

  private func groupReadyToLoop() -> Bool {
    return !loopers.map { $0.isReadyToLoop }.contains(false)
  }
}

// MARK: - Hot Player Delegate

extension CoordinatedLooperGroup: LooperDelegate {
  func isBuffering(looper: Looper) {
    self.delegate?.isBuffering(looper: self)
  }

  func stoppedBuffering(looper: Looper) {
    self.delegate?.stoppedBuffering(looper: self)
  }

  func readyToLoop(looper: Looper) {
    guard groupReadyToLoop() else { return }

    self.delegate?.readyToLoop(looper: self)
  }
}
