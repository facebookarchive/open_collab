// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import AVFoundation
import BrightFutures
import CoreMedia
import UIKit

protocol TakeViewControllerDelegate: NSObjectProtocol {
  func readyToRecord()
  func stoppedRecording()
  func restoreUI()
  func generatedFragments(fragments: [FragmentHost])
}

class TakeViewController: UIViewController {
  private enum Constants {
    static let inactiveAlpha: CGFloat = 0.0
    static let passiveAlpha: CGFloat = 0.2
    static let activeAlpha: CGFloat = 0.8
    static let largeFontSize: CGFloat = 36.0
    static let mediumFontSize: CGFloat = 24.0
    static let smallFontSize: CGFloat = 14.0
    static let progressBarHeight: CGFloat = 10.0
    static let headphonesSpacing: CGFloat = 10.0
    static let takeLabelHeight: CGFloat = 30.0
    static let cornerRadius: CGFloat = 6.0
    static let timeIntervalScaleFactor: Int32 = 100000000
    static let takeLimit: Int = 10
    static let finalTakeLabel = "Final Take"
    static let recordingBuffer = 0.25
  }

  static let countdownTimerLimit = 4

  // Take management
  fileprivate var takeStartTimes: [CMTime] = []
  // The screenshot thumbnails we generate for takes while record is active.
  // These are kept in order: [Take 1 Image, Take 2 Image ... ]
  fileprivate var activeTakeThumbnails: [UIImage] = []
  fileprivate var initialTakeCount: Int
  fileprivate var takeCountWhileRecording: Int = 0
  fileprivate var takeTimer: Timer?
  fileprivate var currentTakeTime: Double = 0
  private var takeGenerator: TakeGenerator?
  var shouldDiscardTakes: Bool = false

  // Countdown
  var countDownInterval: TimeInterval
  private var countdownTimer: Timer?
  private var currentTimerCount = 0

  // UI
  private let takeLabel = FragmentLabelView()
  private let notificationLabel = UILabel()
  private let overlay = UIView()
  private let takeProgressBar = UIProgressView()
  private let headphoneMessageStackView = UIStackView()

  // Video Capture
  private var syncOffsetAtStartOfRecord: CMTime = .zero
  private var duration: CMTime?
  private var editPadding: CMTime
  private let captureViewController: CaptureViewController

  var isReadyToRecord: Bool {
    get {
      return captureViewController.isReadyToRecord
    }
  }

  private weak var delegate: TakeViewControllerDelegate?

  // MARK: - Init

  init(duration: CMTime?,
       countDownInterval: TimeInterval,
       editPadding: CMTime = .zero,
       assetManager: LocalAssetManager?,
       delegate: TakeViewControllerDelegate,
       avSessionQueue: DispatchQueue,
       initialTakeCount: Int = 0) {
    self.duration = duration
    self.countDownInterval = countDownInterval
    self.editPadding = editPadding
    self.captureViewController = CaptureViewController(avSessionQueue: avSessionQueue)
    self.captureViewController.assetManager = assetManager
    self.delegate = delegate
    self.initialTakeCount = initialTakeCount

    super.init(nibName: nil, bundle: nil)
    self.captureViewController.delegate = self
  }

  required init?(coder: NSCoder) {
    Fatal.safeError("init(coder:) has not been implemented")
  }

  deinit {
    NotificationCenter.default.removeObserver(self,
                                              name: UIApplication.didBecomeActiveNotification,
                                              object: nil)
  }

  // MARK: - UIViewController

  override func viewDidLoad() {
    super.viewDidLoad()

    self.captureViewController.addToContainerViewController(self, setBounds: false)
    setupUI()
    self.view.clipsToBounds = true
    self.view.layer.cornerRadius = Constants.cornerRadius

    NotificationCenter.default.addObserver(self,
                                           selector: #selector(didEnterForeground(_:)),
                                           name: UIApplication.didBecomeActiveNotification,
                                           object: nil)
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let bounds = self.view.bounds
    overlay.frame = bounds
    captureViewController.view.frame = bounds

    var extraHeightSpacing: CGFloat = 0
    if bounds.size.height > Constants.headphonesSpacing {
      headphoneMessageStackView.spacing = Constants.headphonesSpacing
      extraHeightSpacing = Constants.headphonesSpacing
    }
    let size = headphoneMessageStackView.systemLayoutSizeFitting(bounds.size)
    headphoneMessageStackView.frame = CGRect(x: bounds.midX - size.width / 2.0,
                                             y: bounds.midY - size.height / 2.0,
                                             width: size.width,
                                             height: size.height + extraHeightSpacing)
  }

  // MARK: - Private Helpers

  // MARK: - UI Helpers

  fileprivate func setupUI() {
    setupOverlay()
    setupNotificationLabel()
    setupTakeLabel()
    setupTakeProgressBar()
    setupHeadphoneMessageView()
  }

  fileprivate func setupOverlay() {
    overlay.backgroundColor = .black
    overlay.alpha = Constants.inactiveAlpha

    self.view.addSubview(overlay)
  }

  fileprivate func setupTakeLabel() {
    takeLabel.takeNumber = " "
    takeLabel.alpha = Constants.inactiveAlpha
    takeLabel.translatesAutoresizingMaskIntoConstraints = false

    self.view.addSubview(self.takeLabel)

    NSLayoutConstraint.activate([
      takeLabel.heightAnchor.constraint(equalToConstant: Constants.takeLabelHeight),
      takeLabel.rightAnchor.constraint(equalTo: self.view.rightAnchor,
                                       constant: -FragmentCreationViewController.buttonBarSideInset),
      takeLabel.topAnchor.constraint(equalTo: self.view.topAnchor,
                                     constant: FragmentCreationViewController.buttonBarTopInset)
    ])
  }

  fileprivate func setupNotificationLabel() {
    notificationLabel.translatesAutoresizingMaskIntoConstraints = false
    notificationLabel.textAlignment = .center
    notificationLabel.font = .systemFont(ofSize: Constants.largeFontSize,
                                         weight: UIFont.Weight.bold)
    notificationLabel.textColor = .white
    notificationLabel.text = " "

    self.view.addSubview(notificationLabel)

    NSLayoutConstraint.activate([
      notificationLabel.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
      notificationLabel.centerYAnchor.constraint(equalTo: self.view.centerYAnchor)
    ])
  }

  fileprivate func setupTakeProgressBar() {
    takeProgressBar.translatesAutoresizingMaskIntoConstraints = false
    takeProgressBar.progressTintColor = UIColor.white
    takeProgressBar.progressImage = UIImage(named: "progress")
    takeProgressBar.trackTintColor = UIColor.white.withAlphaComponent(0.0)
    takeProgressBar.clipsToBounds = true

    self.view.addSubview(takeProgressBar)

    NSLayoutConstraint.activate([
      takeProgressBar.widthAnchor.constraint(equalTo: self.view.widthAnchor),
      takeProgressBar.heightAnchor.constraint(
        equalToConstant: Constants.progressBarHeight),
      takeProgressBar.topAnchor.constraint(equalTo: self.view.topAnchor),
      takeProgressBar.centerXAnchor.constraint(equalTo: self.view.centerXAnchor)
    ])
  }

  fileprivate func setupHeadphoneMessageView() {
    headphoneMessageStackView.alignment = .center
    headphoneMessageStackView.axis = .vertical
    headphoneMessageStackView.distribution = .fill

    let headphoneIcon = UIImageView(image: UIImage(systemName: "headphones")?.withRenderingMode(.alwaysTemplate))
    headphoneIcon.tintColor = .white
    headphoneIcon.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      headphoneIcon.heightAnchor.constraint(equalTo: headphoneIcon.widthAnchor)
    ])

    headphoneMessageStackView.addArrangedSubview(headphoneIcon)

    let headphoneMessage = UILabel()
    headphoneMessage.translatesAutoresizingMaskIntoConstraints = false
    headphoneMessage.textAlignment = .center
    headphoneMessage.font = .systemFont(ofSize: Constants.smallFontSize,
                                        weight: UIFont.Weight.bold)
    headphoneMessage.textColor = .white
    headphoneMessage.numberOfLines = 0
    headphoneMessage.text = "Headphones\nrequired"

    headphoneMessageStackView.addArrangedSubview(headphoneMessage)

    self.view.addSubview(headphoneMessageStackView)

    headphoneMessageStackView.isHidden = true
  }

  fileprivate func activateCountdownTimer(startCount: Int,
                                          interval: TimeInterval,
                                          completion: (() -> Void)? = nil) {
    countdownTimer?.invalidate()
    self.notificationLabel.text = "\(startCount)"
    self.notificationLabel.sizeToFit()
    countdownTimer = Timer.scheduledTimer(withTimeInterval: interval,
                                          repeats: true,
                                          block: { [weak self] (_) in
                                            guard let self = self else { return }
                                            self.currentTimerCount = self.currentTimerCount + 1
                                            self.notificationLabel.text =
                                            "\(startCount - self.currentTimerCount)"
                                            self.notificationLabel.sizeToFit()
                                            if self.currentTimerCount == startCount {
                                              self.notificationLabel.text = " "
                                              self.currentTimerCount = 0
                                              self.countdownTimer?.invalidate()
                                              self.countdownTimer = nil
                                              self.overlay.alpha = Constants.inactiveAlpha
                                              completion?()
                                            }})
  }

  fileprivate func startTakeProgressBar(takeDurationSeconds: Double) {
    if takeDurationSeconds == 0 { return }

    takeTimer?.invalidate()
    self.currentTakeTime = 0
    self.takeProgressBar.setProgress(0, animated: false)

    takeTimer = Timer.scheduledTimer(withTimeInterval: 0.05,
                                     repeats: true,
                                     block: { [weak self] (_) in
                                      guard let self = self else { return }
                                      self.currentTakeTime = self.currentTakeTime + 0.05
                                      let progress =
                                        min(self.currentTakeTime / takeDurationSeconds, 1.0)
                                      self.takeProgressBar.setProgress(Float(progress),
                                                                       animated: true)
    })
    takeTimer?.tolerance = 0.05
  }

  fileprivate func updateTakeLabel(takeNumber: String, prefix: String? = nil) {
    takeLabel.takeNumber = takeNumber
    if let prefix = prefix {
      takeLabel.prefix = prefix
    }
    takeLabel.sizeToFit()
    takeLabel.alpha = 1.0
  }

  fileprivate func stopTakeProgressBar() {
    takeTimer?.invalidate()
    self.currentTakeTime = 0
    self.takeProgressBar.setProgress(0, animated: true)
  }

  private func activateCountdownUI(startCount: Int, interval: TimeInterval) {
    overlay.alpha = Constants.activeAlpha
    activateCountdownTimer(startCount: startCount, interval: interval)
  }

  private func hideTakeLabel() {
    self.takeLabel.takeNumber = ""
    self.takeLabel.alpha = Constants.inactiveAlpha
  }

  public func hideCountdownUI() {
    overlay.alpha = Constants.inactiveAlpha

    countdownTimer?.invalidate()
    self.notificationLabel.text = ""
  }

  // MARK: - Public

  public func startRecording() {
    takeCountWhileRecording = 0
    takeStartTimes.removeAll()

    syncOffsetAtStartOfRecord = AppHeadphoneManager.shared.manualSyncingOffset - AppHeadphoneManager.shared.recordingOffset

    captureViewController.startRecording()
    activateCountdownUI(startCount: TakeViewController.countdownTimerLimit,
                        interval: countDownInterval)
  }

  public func startTake(atTime: CMTime) {
    // Starting a take is used when continuously recording many takes. If there is no duration
    // we are capturing on big take and just calling startRecording and stopRecording is sufficent.
    guard let duration = duration else { return }
    takeCountWhileRecording += 1
    takeStartTimes.append(atTime)

    // Take a screenshot for the take.
    captureViewController.capturePhoto()

    guard takeCountWhileRecording <= Constants.takeLimit else {
      DispatchQueue.main.asyncAfter(deadline: .now() + Constants.recordingBuffer) {
        [weak self] in self?.stopRecording()
      }
      return
    }

    let currentTake = takeCountWhileRecording + initialTakeCount
    let isFinalTake = takeCountWhileRecording == Constants.takeLimit
    let takeLabel = isFinalTake ? "" : "\(currentTake)"
    let prefix = isFinalTake ? Constants.finalTakeLabel : nil

    updateTakeLabel(takeNumber: takeLabel, prefix: prefix)
    startTakeProgressBar(takeDurationSeconds: duration.toSeconds())
  }

  public func stopRecording() {
    captureViewController.stopRecording(shouldDiscard: shouldDiscardTakes)
  }

  public func flipCamera() -> Future<Bool, CaptureError> {
    return captureViewController.flipCamera()
  }

  public func showHeadphoneMessage() {
    overlay.alpha = Constants.activeAlpha
    headphoneMessageStackView.isHidden = false
  }

  public func hideHeadphoneMessage() {
    overlay.alpha = Constants.inactiveAlpha
    headphoneMessageStackView.isHidden = true
  }

  public func getTakeThumbnail(takeNumber: Int) -> UIImage? {
    guard takeNumber - 1 < activeTakeThumbnails.count else { return nil }

    return activeTakeThumbnails[takeNumber - 1]
  }

  public func reset() {
    currentTimerCount = 0
    hideCountdownUI()
    hideTakeLabel()
    stopTakeProgressBar()
    hideHeadphoneMessage()
    captureViewController.prepareToRecord()
    self.delegate?.restoreUI()
  }

  @objc func didEnterForeground(_ sender: Notification) {
    if captureViewController.isRecording { return }
    reset()
  }
}

// MARK: - VideoCaptureViewControllerDelegate

extension TakeViewController: CaptureViewControllerDelegate {
  func capturedPhoto(image: UIImage) {
    activeTakeThumbnails.append(image)
  }

  func readyToRecord() {
    self.delegate?.readyToRecord()
  }

  func stoppedRecording() {
    takeTimer?.invalidate()
    self.delegate?.stoppedRecording()
  }

  func finishedRecording(url: URL?, recordStartTime: CMTime?) {
    print("------------------------------- CAPTURE STOPPED ------------------------------")

    // If user wants to discard takes, don't generate them
    guard !shouldDiscardTakes else {
      if let url = url {
        try? FileManager.default.removeItem(at: url)
      }
      reset()
      return
    }

    guard let url = url else {
      print("Recording finished with no url.")
      self.reset()
      return
    }

    guard FileManager.default.fileExists(atPath: url.path) else {
      self.reset()
      return
    }

    guard var recordStartTime = recordStartTime else {
        // cleanup the half finished video file
        try? FileManager.default.removeItem(at: url)
        self.reset()
        return
    }

    // Calculate padding for the countdown to be able to crop the video accordingly
    let countDownPadding = duration == nil ? Double(TakeViewController.countdownTimerLimit) * countDownInterval : 0.0

    // Shift record start time if there was a manual sync applied to playback
    // so that the takes will align correctly.
    recordStartTime = CMTimeAdd(recordStartTime, syncOffsetAtStartOfRecord)

    // Use the take generator even if there is only one take since this crops the video appropriately.
    takeGenerator = TakeGenerator(url: url,
                                  takeDuration: duration,
                                  durationPadding: self.editPadding,
                                  recordStartTime: recordStartTime,
                                  startTimes: takeStartTimes,
                                  countDownTime: countDownPadding)

    takeGenerator?.delegate = self
    takeGenerator?.generateTakes()
  }

  func recordingInterrupted() {
    if captureViewController.isRecording {
      stopRecording()
    }
  }
}

// MARK: - Take Generation

extension TakeViewController: TakeGeneratorDelegate {
  func generatedFragments(fragments: [FragmentHost]) {
    var modifiedFragments = fragments
    // Add the optimistic thumbnails
    for (index, _) in fragments.enumerated() {
      guard index < activeTakeThumbnails.count else { break }
      modifiedFragments[index].localThumbnailImage = activeTakeThumbnails[index]
    }

    DispatchQueue.main.async {
      self.reset()
      self.delegate?.generatedFragments(fragments: modifiedFragments)
    }
  }

  func takeGenerationFailed() {
    self.reset()
  }
}

// MARK: - Recording Limit Support

extension TakeViewController {

  func activateRecordingLimitTimer(startCount: Int,
                                   completion: (() -> Void)? = nil) {
    overlay.alpha = Constants.passiveAlpha
    activateCountdownTimer(startCount: startCount,
                           interval: countDownInterval,
                           completion: completion)
  }
}
