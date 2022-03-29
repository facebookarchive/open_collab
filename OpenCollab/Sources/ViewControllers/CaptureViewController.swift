// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import AVFoundation
import BrightFutures
import CoreMedia

enum CaptureError: Error {
  case CouldNotFlipCamera
  case TriedToModifyCaptureWhileNotReady
}

protocol CaptureViewControllerDelegate: NSObjectProtocol {
  func readyToRecord()
  func stoppedRecording()
  func finishedRecording(url: URL?, recordStartTime: CMTime?)
  func recordingInterrupted()
  func capturedPhoto(image: UIImage)
}

class CaptureViewController: UIViewController {

  private enum Constants {
    static let sessionPreset: AVCaptureSession.Preset = .high
    static let sessionWidth: CGFloat = 540
    static let sessionHeight: CGFloat = 960
    static let timeIntervalScaleFactor: Int32 = 100000000
    static let frameCaptureBuffer = CMTimeMakeWithSeconds(0.05, preferredTimescale: 600)
  }

  // MARK: - Public

  var assetManager: LocalAssetManager?
  weak var delegate: CaptureViewControllerDelegate?
  private var countdownLabel = UILabel()
  private var timer: Timer?
  private var currentTimerCount = 0

  var windowOrientation: UIInterfaceOrientation {
    return view.window?.windowScene?.interfaceOrientation ?? .unknown
  }

  // MARK: - Private

  private enum SessionSetupResult {
    case undetermined
    case success
    case notAuthorized(RecordingAuthorizer.RecordingAuthorizationStatus)
    case configurationFailed
  }

  private var previewView = PreviewView()
  private let session = AVCaptureSession()
  private var isSessionRunning = false
  private(set) var isRecording = false {
    didSet {
      if !isRecording {
        stopRecordingTime = .positiveInfinity
      }
    }
  }
  private var stopRecordingTime: CMTime = .positiveInfinity
  private var allAudioSamplesCaptured = false
  private var allVideoSamplesCaptured = false
  private let sampleBufferQueue = DispatchQueue(label: "com.openCollab.sampleBufferQueue")
  private let sessionQueue: DispatchQueue
  private var setupResult: SessionSetupResult = .undetermined
  @objc dynamic var videoDeviceInput: AVCaptureDeviceInput!
  private let videoDeviceDiscoverySession =
    AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInUltraWideCamera,
                                                   .builtInWideAngleCamera,
                                                   .builtInDualCamera,
                                                   .builtInTrueDepthCamera],
                                     mediaType: .video, position: .unspecified)
  private var photoSettings: AVCapturePhotoSettings {
    let settings = AVCapturePhotoSettings()
    let previewPixelType = settings.availablePreviewPhotoPixelFormatTypes.first!
    let previewFormat = [
      kCVPixelBufferPixelFormatTypeKey as String: previewPixelType,
      kCVPixelBufferWidthKey as String: 540,
      kCVPixelBufferHeightKey as String: 960
    ]
    settings.previewPhotoFormat = previewFormat
    return settings
  }

  // MARK: - Init

  init(avSessionQueue: DispatchQueue) {
    self.sessionQueue = avSessionQueue
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - UIViewController

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()

    previewView.frame = self.view.bounds
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    self.view.addSubview(previewView)

    previewView.session = session

    sessionQueue.suspend()
    RecordingAuthorizer.isAuthorized(
    ).onSuccess { status in
      if status != .authorized {
        self.setupResult = .notAuthorized(status)
      } else {
        self.setupResult = .success
      }
      self.sessionQueue.resume()
      self.prepareToRecord()
    }.onFailure { (_) in
      Fatal.safeError("RecordingAuthorizer should not fail")
    }

    configureSession()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)

    sessionQueue.async {
      switch self.setupResult {
      case .success:
        self.addObservers()
        self.session.startRunning()
        self.isSessionRunning = self.session.isRunning

      case SessionSetupResult.notAuthorized(let status):
        DispatchQueue.main.async {
          RecordingAuthorizer.showUnauthorizedAlert(vc: self, status: status)
        }
      case .configurationFailed:
        DispatchQueue.main.async {
          let message = "Unable to start the camera. Please exit recording and try again."
          let alertController = UIAlertController(title: "Uh oh...", message: message, preferredStyle: .alert)

          alertController.addAction(UIAlertAction(title: "OK",
                                                  style: .cancel,
                                                  handler: nil))

          self.present(alertController, animated: true, completion: nil)
        }
      case .undetermined:
      // ## Add a case for if recording is not authorized -- show an alert and prevent recording
      break
      }
    }
  }

  override func viewWillDisappear(_ animated: Bool) {
    sessionQueue.async {
      switch self.setupResult {
      case .success:
        self.session.stopRunning()
        self.isSessionRunning = self.session.isRunning
        self.removeObservers()
        return
      default:
        break
      }
    }

    super.viewWillDisappear(animated)
  }

  override var shouldAutorotate: Bool {
    return !session.isRunning
  }

  override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
    return .all
  }

  override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
    super.viewWillTransition(to: size, with: coordinator)

    DispatchQueue.main.async {
      if let videoPreviewLayerConnection = self.previewView.videoPreviewLayer.connection {
        let deviceOrientation = UIDevice.current.orientation
        guard let newVideoOrientation = AVCaptureVideoOrientation(rawValue: deviceOrientation.rawValue),
              deviceOrientation.isPortrait || deviceOrientation.isLandscape else {
          return
        }

        videoPreviewLayerConnection.videoOrientation = newVideoOrientation
      }
    }
  }

  // MARK: Session Management

  private func configureSession() {
    let windowOrientation = self.windowOrientation // only get orientation on main thread
    sessionQueue.async {
      dispatchPrecondition(condition: .onQueue(self.sessionQueue))

      switch self.setupResult {
        case .configurationFailed: // ## If a check for authorization is added, add .notAuthorized here
        return
      default:
        break
      }

      self.session.beginConfiguration()

      // Add video input.
      do {
        var defaultVideoDevice: AVCaptureDevice?

        if let ultraWideCamera = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .front) {
          defaultVideoDevice = ultraWideCamera
        } else if let dualWideAngleCamera = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .front) {
          defaultVideoDevice = dualWideAngleCamera
        } else if let wideAngleCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
          defaultVideoDevice = wideAngleCamera
        } else if let dualCamera = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .front) {
          defaultVideoDevice = dualCamera
        }
        guard let videoDevice = defaultVideoDevice else {
          print("Default video device is unavailable.")
          self.setupResult = .configurationFailed
          self.session.commitConfiguration()
          return
        }

        self.configureCameraForHighestFrameRate(device: videoDevice)
        let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)

        if self.session.canAddInput(videoDeviceInput) {
          self.session.addInput(videoDeviceInput)
          self.videoDeviceInput = videoDeviceInput
          var initialVideoOrientation: AVCaptureVideoOrientation = .portrait
          if windowOrientation != .unknown {
            if let videoOrientation = AVCaptureVideoOrientation(rawValue: self.windowOrientation.rawValue) {
              initialVideoOrientation = videoOrientation
            }
          }

          DispatchQueue.main.async {
            self.previewView.videoPreviewLayer.connection?.videoOrientation = initialVideoOrientation
          }
        } else {
          print("Couldn't add video device input to the session.")
          self.setupResult = .configurationFailed
          self.session.commitConfiguration()
          return
        }
      } catch {
        print("Couldn't create video device input: \(error)")
        self.setupResult = .configurationFailed
        self.session.commitConfiguration()
        return
      }

      // Add an audio input device.
      self.session.automaticallyConfiguresApplicationAudioSession = false

      do {
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
          print("Couldn't get default audio device")
          self.setupResult = .configurationFailed
          self.session.commitConfiguration()
          return
        }
        let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice)

        if self.session.canAddInput(audioDeviceInput) {
          self.session.addInput(audioDeviceInput)
        } else {
          print("Could not add audio device input to the session")
          self.setupResult = .configurationFailed
          self.session.commitConfiguration()
          return
        }
      } catch {
        print("Could not create audio device input: \(error)")
        self.setupResult = .configurationFailed
        self.session.commitConfiguration()
        return
      }

      let videoDataOutput = AVCaptureVideoDataOutput()
      videoDataOutput.alwaysDiscardsLateVideoFrames = false
      videoDataOutput.setSampleBufferDelegate(self, queue: self.sampleBufferQueue)

      if self.session.canAddOutput(videoDataOutput) {
        self.session.addOutput(videoDataOutput)
        self.session.sessionPreset = Constants.sessionPreset
        if let connection = videoDataOutput.connection(with: .video) {
          if connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .auto
          }
          DispatchQueue.main.async {
            if let videoPreviewLayerOrientation = self.previewView.videoPreviewLayer.connection?.videoOrientation {
              connection.videoOrientation = videoPreviewLayerOrientation
            }
          }
          if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            let isMirrored = !UserDefaults.standard.bool(forKey: SettingsViewController.Constants.disableCameraMirroringKey) && (self.videoDeviceInput.device.position == .front)
            connection.isVideoMirrored = isMirrored
          }
        }
        self.videoDataOutput = videoDataOutput
      } else {
        print("Could not add video output to the session")
        self.setupResult = .configurationFailed
        self.session.commitConfiguration()
        return
      }

      let audioDataOutput = AVCaptureAudioDataOutput()
      audioDataOutput.setSampleBufferDelegate(self, queue: self.sampleBufferQueue)

      if self.session.canAddOutput(audioDataOutput) {
        self.session.addOutput(audioDataOutput)
        self.audioDataOutput = audioDataOutput
      } else {
        print("Could not add audio output to the session")
        self.setupResult = .configurationFailed
        self.session.commitConfiguration()
        return
      }

      let photoOutput = AVCapturePhotoOutput()
      photoOutput.isHighResolutionCaptureEnabled = true

      if self.session.canAddOutput(photoOutput) {
        self.session.addOutput(photoOutput)
        if let connection = photoOutput.connection(with: .video) {
          if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            let isMirrored = !UserDefaults.standard.bool(forKey: SettingsViewController.Constants.disableCameraMirroringKey) && (self.videoDeviceInput.device.position == .front)
            connection.isVideoMirrored = isMirrored
          }
        }

        self.photoOutput = photoOutput
      } else {
        print("Could not add photo output to the session")
        self.setupResult = .configurationFailed
        self.session.commitConfiguration()
        return
      }

      self.session.commitConfiguration()
    }
  }

  private func resumeInterruptedSession() {
    sessionQueue.async {
      self.session.startRunning()
      self.isSessionRunning = self.session.isRunning
      if !self.session.isRunning {
        DispatchQueue.main.async {
          let message = "Unable to resume"
          let alertController = UIAlertController(title: "Collab", message: message, preferredStyle: .alert)
          let cancelAction = UIAlertAction(title: "OK", style: .cancel, handler: nil)
          alertController.addAction(cancelAction)
          self.present(alertController, animated: true, completion: nil)
        }
      }
    }
  }

  // MARK: - Recording Movies
  private var movieFileOutput: AVCaptureMovieFileOutput?
  private var backgroundRecordingID: UIBackgroundTaskIdentifier?

  private var videoDataOutput: AVCaptureVideoDataOutput?
  private var audioDataOutput: AVCaptureAudioDataOutput?
  private var photoOutput: AVCapturePhotoOutput?
  private var assetRecorder: AssetRecorder?
  private var assetRecorderIsReadyToRecord: Bool = false
  var isReadyToRecord: Bool {
    switch setupResult {
    case .success:
      return assetRecorderIsReadyToRecord
    default:
      return false
    }
  }

  func flipCamera() -> Future<Bool, CaptureError> {
    guard self.isReadyToRecord else {
      return Future(error: .TriedToModifyCaptureWhileNotReady)
    }

    return Future<Bool, CaptureError> { complete in
      sessionQueue.async {
        if self.isRecording { return }
        print("Video capture is flipping the camera")
        let currentVideoDevice = self.videoDeviceInput.device
        let currentPosition = currentVideoDevice.position
        let preferredPosition: AVCaptureDevice.Position
        let preferredDeviceType: AVCaptureDevice.DeviceType

        switch currentPosition {
        case .unspecified, .front:
          preferredPosition = .back
          preferredDeviceType = .builtInUltraWideCamera

        case .back:
          preferredPosition = .front
          preferredDeviceType = .builtInTrueDepthCamera

        default:
          preferredPosition = .back
          preferredDeviceType = .builtInUltraWideCamera
        }
        let devices = self.videoDeviceDiscoverySession.devices
        var newVideoDevice: AVCaptureDevice?

        // First, seek a device with both the preferred position and device type. Otherwise, seek a device with only the preferred position.
        if let device = devices.first(where: { $0.position == preferredPosition && $0.deviceType == preferredDeviceType }) {
          newVideoDevice = device
        } else if let device = devices.first(where: { $0.position == preferredPosition }) {
          newVideoDevice = device
        }

        if let videoDevice = newVideoDevice {
          do {
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)

            self.session.beginConfiguration()

            // Remove the existing device input first, because AVCaptureSession doesn't support
            // simultaneous use of the rear and front cameras.
            self.session.removeInput(self.videoDeviceInput)

            if self.session.canAddInput(videoDeviceInput) {
              NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: currentVideoDevice)
              self.session.addInput(videoDeviceInput)
              self.videoDeviceInput = videoDeviceInput
            } else {
              self.session.addInput(self.videoDeviceInput)
            }
            if let connection = self.videoDataOutput?.connection(with: .video) {
              if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
              }
              DispatchQueue.main.async {
                let videoPreviewLayerOrientation = self.previewView.videoPreviewLayer.connection?.videoOrientation
                connection.videoOrientation = videoPreviewLayerOrientation!
              }
              if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                let isMirrored = !UserDefaults.standard.bool(forKey: SettingsViewController.Constants.disableCameraMirroringKey) && (preferredPosition == .front)
                connection.isVideoMirrored = isMirrored
              }
            }

            self.session.commitConfiguration()

            return complete(.success(true))
          } catch {
            print("Error occurred while creating video device input: \(error)")
            return complete(.failure(.CouldNotFlipCamera))
          }
        }
      }
    }
  }

  func recordingIsPossible() -> Bool {
    switch setupResult {
    case .success:
      return true
    default:
      return false
    }
  }

  func prepareToRecord() {
    sessionQueue.async {
      self.assetRecorder = AssetRecorder(assetWidth: Constants.sessionWidth,
                                         assetHeight: Constants.sessionHeight)
      self.assetRecorder?.prepareToRecord()
        .onSuccess { success in
          guard success else {
            self.assetRecorderError()
            return
          }

          self.assetRecorderDidFinishPreparing()
        }.onFailure { error in
          print("Asset Recorder Error was: \(error)")
          self.assetRecorderError()
        }
    }
  }

  func startRecording() {
    sessionQueue.async {
      self.isRecording = true
      print("Video capture view state set to isRecording.")
    }
  }

  func stopRecording(shouldDiscard: Bool) {
    DispatchQueue.main.async {
      self.delegate?.stoppedRecording()
    }

    sessionQueue.async {
      if self.isRecording && !shouldDiscard {
        // Record what time we should stop recording. We'll continue to capture buffers
        // until the timestamps are past this time.
        self.stopRecordingTime = CMClockGetTime(CMClockGetHostTimeClock()) + Constants.frameCaptureBuffer
      } else {
        self.finishRecording()
      }
    }
  }

  private func finishRecording() {
    dispatchPrecondition(condition: .onQueue(sessionQueue))
    self.isRecording = false

    self.assetRecorder?.finishRecording()
      .onSuccess { (url, recordStartTime) in
        self.assetRecorderDidFinishRecording(url: url,
                                             recordStartTime: recordStartTime)
      }.onFailure { error in
        print("Asset Recorder Error was: \(error)")
        self.assetRecorderError()
      }
  }

  // MARK: KVO and Notifications

  private var keyValueObservations = [NSKeyValueObservation]()

  private func addObservers() {
    let systemPressureStateObservation = observe(\.videoDeviceInput.device.systemPressureState,
                                                 options: .new) { _, change in
      guard let systemPressureState = change.newValue else { return }
      self.setRecommendedFrameRateRangeForPressureState(systemPressureState: systemPressureState)
    }
    keyValueObservations.append(systemPressureStateObservation)

    NotificationCenter.default.addObserver(self,
                                           selector: #selector(sessionRuntimeError),
                                           name: .AVCaptureSessionRuntimeError,
                                           object: session)

    NotificationCenter.default.addObserver(self,
                                           selector: #selector(sessionWasInterrupted),
                                           name: .AVCaptureSessionWasInterrupted,
                                           object: session)
    NotificationCenter.default.addObserver(self,
                                           selector: #selector(sessionInterruptionEnded),
                                           name: .AVCaptureSessionInterruptionEnded,
                                           object: session)
  }

  private func removeObservers() {
    NotificationCenter.default.removeObserver(self)

    for keyValueObservation in keyValueObservations {
        keyValueObservation.invalidate()
    }
    keyValueObservations.removeAll()
  }

  @objc func sessionRuntimeError(notification: NSNotification) {
    guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }

    print("Capture session runtime error: \(error.code.rawValue)")
    // If media services were reset, and the last start succeeded, restart the session.
    if error.code == .mediaServicesWereReset {
      sessionQueue.async {
        if self.isSessionRunning {
          self.session.startRunning()
          self.isSessionRunning = self.session.isRunning
        }
      }
    }
  }

  private func setRecommendedFrameRateRangeForPressureState(systemPressureState: AVCaptureDevice.SystemPressureState) {
    let pressureLevel = systemPressureState.level
    if pressureLevel == .serious || pressureLevel == .critical {
      if self.videoDataOutput == nil || self.session.isRunning == false {
        do {
          try self.videoDeviceInput.device.lockForConfiguration()
          print("WARNING: Reached elevated system pressure level: \(pressureLevel). Throttling frame rate.")
          self.videoDeviceInput.device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 20)
          self.videoDeviceInput.device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 15)
          self.videoDeviceInput.device.unlockForConfiguration()
        } catch {
          print("Could not lock device for configuration: \(error)")
        }
      }
    } else if pressureLevel == .shutdown {
        print("Session stopped running due to shutdown system pressure level.")
    }
  }

  @objc func sessionWasInterrupted(notification: NSNotification) {
    print("Capture session was interrupted")
    let shouldDiscard = isRecording ? false : true
    self.stopRecording(shouldDiscard: shouldDiscard)
  }

  @objc func sessionInterruptionEnded(notification: NSNotification) {
    print("Capture session interruption ended")
  }

  private func configureCameraForHighestFrameRate(device: AVCaptureDevice) {
    var bestFormat: AVCaptureDevice.Format?
    var bestFrameRateRange: AVFrameRateRange?

    for format in device.formats {
      for range in format.videoSupportedFrameRateRanges {
        if range.maxFrameRate > bestFrameRateRange?.maxFrameRate ?? 0 {
          bestFormat = format
          bestFrameRateRange = range
        }
      }
    }

    if let bestFormat = bestFormat,
       let bestFrameRateRange = bestFrameRateRange {
      collabConfigureDevice(device,
                            bestFormat,
                            bestFrameRateRange.minFrameDuration)
    }
  }
}

extension CaptureViewController: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {

  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    sessionQueue.async {
      if self.isRecording {
        let sampleTime =
          CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let sampleWithinRecordingLimit =
          CMTimeCompare(sampleTime, self.stopRecordingTime) <= 0

        let captureType = output == self.videoDataOutput ? AVMediaType.video : AVMediaType.audio

        // Mark that we've captured all required samples for the media type.
        guard sampleWithinRecordingLimit else {
          self.allAudioSamplesCaptured = captureType == AVMediaType.audio ? true : self.allAudioSamplesCaptured
          self.allVideoSamplesCaptured = captureType == AVMediaType.video ? true : self.allVideoSamplesCaptured

          if self.allVideoSamplesCaptured && self.allAudioSamplesCaptured {
            self.finishRecording()
          }

          return
        }

        self.assetRecorder?.appendSampleBuffer(sampleBuffer: sampleBuffer,
                                          mediaType: captureType)
      }
    }
  }
}

extension CaptureViewController: AVCapturePhotoCaptureDelegate {
  func capturePhoto() {
    photoOutput?.capturePhoto(with: photoSettings, delegate: self)
  }

  func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
    guard let imageData = photo.fileDataRepresentation() else { return }
    guard let previewImage = UIImage(data: imageData) else { return }

    // dispose system shutter sound
    AudioServicesDisposeSystemSoundID(1108)
    self.delegate?.capturedPhoto(image: previewImage)
  }
}

extension CaptureViewController {
  func assetRecorderDidFinishPreparing() {
    DispatchQueue.main.async {
      self.assetRecorderIsReadyToRecord = true
      self.delegate?.readyToRecord()
    }
  }

  func assetRecorderDidFinishRecording(url: URL, recordStartTime: CMTime) {
    DispatchQueue.main.async {
      self.assetRecorderIsReadyToRecord = false

      let tempUrl = self.assetManager?.saveTemporaryAsset(from: url, categoryId: "temp")
      FileUtil.removeFile(URL: url as NSURL)
      self.delegate?.finishedRecording(url: tempUrl, recordStartTime: recordStartTime)
    }
  }

  func assetRecorderError() {
    DispatchQueue.main.async {
      // Dispatch and delegation on the main queue.
      // TODO : Stop the record session on an error, notify the user and reset.
      print("Asset recording error.")
      self.delegate?.finishedRecording(url: nil, recordStartTime: nil)
    }
  }
}
