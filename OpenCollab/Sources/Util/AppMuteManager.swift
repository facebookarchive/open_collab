// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import Foundation
import AVFoundation

class AppMuteManager {

  enum Notifications {
    static let muteSwitchStateChanged =
      Notification.Name(rawValue: "com.openCollab.notification.name.muteSwitchStateChanged")
  }

  enum MuteState {
    case Muted, NotMuted
  }

  fileprivate var __token: Int32 = -1
  fileprivate var outputVolumeObserver: NSKeyValueObservation?
  fileprivate var inAppSwitchState = MuteState.Muted {
    didSet {
      didChange()
    }
  }

  // MARK: - Init

  init() {
    // com.apple.springboard.ringerstate shifted by 1
    var array: [Int8] =  [100, 112, 110, 47, 98, 113, 113, 109, 102, 47, 116, 113, 115, 106, 111, 104, 99, 112, 98, 115, 101, 47, 115, 106, 111, 104, 102, 115, 116, 117, 98, 117, 102, 1]

    for i in 0..<array.count {
      array[i] = array[i] - 1
    }

    // ## TODO : Get status here and then call self.updateHardwareMuteState()
  }

  // MARK: - Static Instance

  static let shared = AppMuteManager()

  // MARK: - Public

  func toggleMuteState() {
    let currentState = self.inAppSwitchState
    let targetState = (currentState == .Muted) ? MuteState.NotMuted : MuteState.Muted
    self.inAppSwitchState = targetState
  }

  func currentState() -> MuteState {
    return inAppSwitchState
  }

  func listenVolumeButtonChanges() {
    let audioSession = AVAudioSession.sharedInstance()
    outputVolumeObserver = audioSession.observe(\.outputVolume) { [weak self] (_, _) in
      guard let self = self else { return }
      guard self.inAppSwitchState == .Muted else { return }
      self.inAppSwitchState = .NotMuted
    }
  }

  // MARK: - Helper

  func updateHardwareMuteState() {
    let hardwareState = getHardwareState()
    let currentState = self.inAppSwitchState
    if currentState == .Muted && hardwareState == .NotMuted {
      // hardware unmute happened
      toggleMuteState()
    }

    if currentState == .Muted && hardwareState == .Muted {
      // hardware mute while in app is muted
      // no-op
    }

    if currentState == .NotMuted && hardwareState == .NotMuted {
      // hardware unmute while in app is also unmuted
      // no-op
    }

    if currentState == .NotMuted && hardwareState == .Muted {
      // hardware mute while in app is unmuted
      toggleMuteState()
    }
  }

  fileprivate func getHardwareState() -> MuteState? {
    var state: UInt64 = 0
    
    // ## TODO : get mute state and return nil if it's not valid

    return (state == 0) ? MuteState.Muted : MuteState.NotMuted
  }

  fileprivate func didChange() {
    NotificationCenter.default.post(name: Notifications.muteSwitchStateChanged, object: nil)
  }
}
