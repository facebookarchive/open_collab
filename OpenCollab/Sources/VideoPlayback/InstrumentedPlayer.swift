// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import AVFoundation

protocol InstrumentedPlayer: NSObject {
  var urlAsset: AVURLAsset? { get }
  var playerDescription: String { get }
}

extension InstrumentedPlayer {
  var playerDescription: String {
    return self.description
  }
}

class PlayerInstrumenter<T> where T: InstrumentedPlayer {

  private var alivePlayers: [WeakRef<T>] = []

  func register(player: T) {
    alivePlayers.append(WeakRef(player))
  }

  func printAlivePlayerInfo() {
    assert(Thread.isMainThread)
    self.alivePlayers = self.alivePlayers.filter({ $0.value != nil })

    let type = T.self.description()
    guard self.alivePlayers.count > 0 else {
      return
    }

    print("-------------------------------- ALIVE \(type) -----------------------------------")
    self.alivePlayers.forEach { (weakRef) in
      if let player = weakRef.value {
        print(player.playerDescription)
      }
    }
  }
}
