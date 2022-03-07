// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import AVFoundation
import Foundation
import BrightFutures

class AppHeadphoneManager {
  private struct Constants {
    static let airpodProConstant = 0.0338958315551281
    static let airpodProOutputConstant = 0.16066665947437286
    static let airpodProOffset: CMTime =
      CMTimeMakeWithSeconds(airpodProOutputConstant,
                            preferredTimescale: 10000)
  }

  enum Notifications {
    static let headphoneStateChanged =
      Notification.Name(rawValue: "com.collabOpenSource.notification.name.headphoneStateChanged")
    static let headphoneTypeChanged =
      Notification.Name(rawValue: "com.collabOpenSource.notification.name.headphoneTypeChanged")
  }

  enum HeadphoneState {
    case Connected, NotConnected
  }

  enum HeadphoneType {
    case Unknown, AirPodPro
  }

  fileprivate var inAppHeadphoneState = HeadphoneState.NotConnected {
    didSet {
      didChange()
    }
  }

  fileprivate var headphoneType = HeadphoneType.Unknown {
    didSet {
      if oldValue != headphoneType {
        headphoneTypeChanged()
      }
    }
  }

  private var audioSessionTimer: Timer?
  var manualSyncingOffset: CMTime {
    get {
      return getAudioOffset()
    }
  }

  var recordingOffset: CMTime {
    return CMTimeMakeWithSeconds(AVAudioSession.sharedInstance().inputLatency * 2.0, preferredTimescale: 10000)
  }

  // MARK: - Init

  init() {
     NotificationCenter.default.addObserver(self,
                                           selector: #selector(handleRouteChange),
                                           name: AVAudioSession.routeChangeNotification,
                                           object: nil)
  }

  // MARK: - Static Instance

  static let shared = AppHeadphoneManager()

  // MARK: - Public

  func currentState() -> HeadphoneState {
    return inAppHeadphoneState
  }

  func currentHeadphoneType() -> HeadphoneType {
    return headphoneType
  }

  func updateHeadphoneState() {
    inAppHeadphoneState =
      hasHeadphones(in: AVAudioSession.sharedInstance().currentRoute) ? .Connected : .NotConnected

    headphoneType = updateHeadphoneType()
  }

  @discardableResult
  func updateHeadphoneType() -> HeadphoneType {
    // NOTE: This method is just a proxy for determining headphone type based of of consistent
    // latencies that we have observed.

    let session = AVAudioSession.sharedInstance()

    if session.outputLatency == Constants.airpodProOutputConstant {
      return HeadphoneType.AirPodPro
    }

    return HeadphoneType.Unknown
  }

  /**
   As the app becomes more interactive the possibilities of rapid audio session changes increases. Since setting the audio session is a relatively expensive operation we don't want to backlog these requests. Doing so introduces stutter.
   The solution is making these requests cancellable. currentAudioSessionChangeRequestToken controls the cancellation. Each subsequent request increments currentAudioSessionChangeRequestToken there by invalidating the previous requests.
   */
  var currentAudioSessionChangeRequestToken = 0

  func setAudioSessionForPlayback(on queue: DispatchQueue? = nil) -> Future<Bool, Error> {
    dispatchPrecondition(condition: .onQueue(DispatchQueue.main))
    currentAudioSessionChangeRequestToken += 1
    let tokenForThisRequest = currentAudioSessionChangeRequestToken
    let block = { [self] in
      guard tokenForThisRequest == currentAudioSessionChangeRequestToken else { return }
      print("*AUDIO* Setting audio session for playback.")
      
      let session = AVAudioSession.sharedInstance()
      do {
        guard tokenForThisRequest == currentAudioSessionChangeRequestToken else { return }
        try session.setCategory(.playback)
      } catch let error as NSError {
        print("Unable to set category audio session: \(error.localizedDescription)")
      }
      guard tokenForThisRequest == currentAudioSessionChangeRequestToken else { return }
      print("*AUDIO* Finished setting audio session for playback.")
    }

    guard let queue = queue else {
      block()
      return Future(value: true)
    }
    return Future<Bool, Error> { complete in
      queue.async {
         block()
         return complete(.success(true))
      }
    }
  }


  @discardableResult
  func setAudioSessionForRecord(on queue: DispatchQueue? = nil) -> Future<Bool, Error> {
    dispatchPrecondition(condition: .onQueue(DispatchQueue.main))

    // TODO : since we only set this on app start now we could probably
    // drop this performance logic.
    currentAudioSessionChangeRequestToken += 1
    let tokenForThisRequest = currentAudioSessionChangeRequestToken
    let block = { [self] in
      guard tokenForThisRequest == currentAudioSessionChangeRequestToken else { return }

      let session = AVAudioSession.sharedInstance()

      // Set category audio session
      do {
        guard tokenForThisRequest == currentAudioSessionChangeRequestToken else { return }
        try session.setCategory(.playAndRecord,
                                mode: .videoRecording,
                                options: .allowBluetoothA2DP)
      } catch let error as NSError {
        print("Unable to set category audio session: \(error.localizedDescription)")
      }

      // Set preferred audio sample rate
      do {
        guard tokenForThisRequest == currentAudioSessionChangeRequestToken else { return }
        try session.setPreferredSampleRate(48_100)
      } catch let error as NSError {
        print("Unable to set preferred audio sample rate:  \(error.localizedDescription)")
      }

      // Set preferred I/O buffer duration
      do {
        guard tokenForThisRequest == currentAudioSessionChangeRequestToken else { return }
        try session.setPreferredIOBufferDuration(0.005)
      } catch let error as NSError {
        print("Unable to set preferred I/O buffer duration:  \(error.localizedDescription)")
      }

      // Activate the audio session
      do {
        guard tokenForThisRequest == currentAudioSessionChangeRequestToken else { return }
        try session.setActive(true)
      } catch let error as NSError {
        print("Unable to activate audio session: \(error.localizedDescription)")
      }

      guard tokenForThisRequest == currentAudioSessionChangeRequestToken else { return }
      setPreferredInput()
      print("*AUDIO* Finished setting audio session for record.")
    }

    guard let queue = queue else {
      block()
      return Future(value: true)
    }
    return Future<Bool, Error> { complete in
      queue.async {
         block()
         return complete(.success(true))
      }
    }
  }

  fileprivate func setPreferredInput() {
    let session = AVAudioSession.sharedInstance()
    guard session.category == .playAndRecord else {
      // Only override preferredInput if recording
      return
    }
    // Set preferred input/outputs
    guard let inputs = session.availableInputs else { return }

    // Find wired-in mic (if any)
    let headsetMic = inputs.first(where: {
      $0.portType == .headsetMic
    })

    // Find built-in mic
    let builtInMic = inputs.first(where: {
      $0.portType == .builtInMic
    })

    // Find USB mic
    let usbMic = inputs.first(where: {
      $0.portType == .usbAudio
    })

    // Find line in mic
    let lineIn = inputs.first(where: {
      $0.portType == .lineIn
    })

    // Default to the usbMic or a lineIn mic if present, then a headsetMic before
    // defaulting to the builtInMic. Never use bluetooth mics for input the quality
    // is very low.
    guard let preferredInput = ((usbMic ?? lineIn) ?? headsetMic) ?? builtInMic else {
      return
    }
    // Set preferred input. This call will be a no-op if already selected
    do {
      try session.setPreferredInput(preferredInput)
    } catch let error as NSError {
      print("Unable to set preferred input: \(error.localizedDescription)")
    }
  }

  // MARK: - Helper

  @objc func handleRouteChange(notification: Notification) {
    print("*AUDIO* Handling route change")
    // For now just do a brute check on if there are any headphones on each route change.
    // If we want more fine grained handling of route changes, see iOS documentation on
    // how to check the reason for the change.
    updateHeadphoneState()
    setPreferredInput()
    print("*AUDIO* Finished route change")
  }

  fileprivate func hasHeadphones(in routeDescription: AVAudioSessionRouteDescription) -> Bool {
    // Filter the outputs to only those with a port type of headphones.
    return !routeDescription.outputs.filter({$0.portType == .headphones || $0.portType == .bluetoothA2DP || $0.portType == .usbAudio || $0.portType == .lineIn}).isEmpty
  }

  fileprivate func didChange() {
    NotificationCenter.default.post(name: Notifications.headphoneStateChanged, object: nil)
  }

  fileprivate func headphoneTypeChanged() {
    NotificationCenter.default.post(name: Notifications.headphoneTypeChanged, object: nil)
  }

  fileprivate func getAudioOffset() -> CMTime {
    return headphoneType == HeadphoneType.AirPodPro ? Constants.airpodProOffset : .zero
  }
}

//For audio debugging, some thing you might want to investigate are:
//  session.category == .playAndRecord
//  session.mode == .videoRecording
//  session.categoryOptions == .allowBluetoothA2DP
//  session.currentRoute.inputs.forEach { portDesc in
//    portDesc.portType == .builtInMic
//    portDesc.selectedDataSource?.dataSourceName
//    portDesc.selectedDataSource?.selectedPolarPattern ?? AVAudioSession.PolarPattern(rawValue: "[none]")
//  }
//  session.currentRoute.outputs.forEach { portDesc in
//    portDesc.portType == .bluetoothA2DP
//    portDesc.selectedDataSource?.dataSourceName
//    portDesc.selectedDataSource?.selectedPolarPattern ?? AVAudioSession.PolarPattern(rawValue: "[none]")
//  }
//  session.sampleRate
//  session.preferredSampleRate
//  session.ioBufferDuration
//  session.preferredIOBufferDuration
//  session.inputLatency
//  String(describing: session.inputDataSource)
//  session.outputLatency
//  String(describing: session.outputDataSource)
