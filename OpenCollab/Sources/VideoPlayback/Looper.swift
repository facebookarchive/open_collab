// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import CoreMedia
import Foundation

protocol Looper: NSObject {
  var delegate: LooperDelegate? { get set }
  var id: String { get set }

  func preheat(syncClock: CMClock)
  func play(itemTime: CMTime, syncTime: CMTime, syncClock: CMClock)
  func loop(loopTime: CMTime, loopDuration: CMTime, syncClock: CMClock)
  func clear()
}

protocol LooperDelegate: NSObjectProtocol {
  func readyToLoop(looper: Looper)
  func isBuffering(looper: Looper)
  func stoppedBuffering(looper: Looper)
}
