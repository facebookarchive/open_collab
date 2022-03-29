// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import CoreMedia
import QuartzCore
import UIKit

class RecordActionViewController: UIViewController {
  struct Constants {
    static let recordButtonSize: CGFloat = 64.0
    static let flipCameraButtonSize: CGFloat = 50.0
    static let metronomeButtonSize: CGFloat = 50.0
    static let buttonMinimumPadding: CGFloat = 40.0
    static let nextButtonHeight: CGFloat = 50.0
    static let nextButtonWidth: CGFloat = 100.0
    static let smallFontSize: CGFloat = 14.0
    static let showHideAnimationDuration: TimeInterval = 0.4
    static let enabledRecordButtonImage = UIImage(color: .red, size: CGSize(width: Constants.recordButtonSize,
                                                                            height: Constants.recordButtonSize))
    static let disabledRecordButtonImage = UIImage(color: .darkGray, size: CGSize(width: Constants.recordButtonSize,
                                                                            height: Constants.recordButtonSize))
  }

  init(metronomeEnabled: Bool) {
    self.metronomeEnabled = metronomeEnabled
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    Fatal.safeError("init(coder:) has not been implemented")
  }

  // MARK: - Properties

  private let recordButton = RecordButtonView(frame: CGRect(origin: .zero, size: CGSize(width: Constants.recordButtonSize, height: Constants.recordButtonSize)))
  private let flipCameraButton = UIButton(type: .custom)
  private var cameraRollButton = UIButton(type: .custom)
  private let nextButton = UIButton(type: .custom)
  private let metronomeButton = UIButton(type: .custom)
  private var metronomeEditViewController = MetronomeEditViewController(BPM: InitialRecordViewController.defaultBPM)
  public var metronomeDelegate: MetronomeEditViewControllerDelegate?
  private let metronomeAnimationOverlay = UIView()
  private var animationBPM: Int?
  private var animationStartTime: CMTime?
  private let metronomeEnabled: Bool
  public var metronomePadding: CGFloat = 0
  private let replacementMessage = UILabel()

  override func viewDidLoad() {
    super.viewDidLoad()

    setupUI()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    if let BPM = animationBPM, let startTime = animationStartTime {
      startMetronomeAnimation(BPM: BPM, startTime: startTime)
      animationBPM = nil
      animationStartTime = nil
    }

    if recordButton.state == .recording {
      let existingState = recordButton.state
      recordButton.state = .notRecording
      recordButton.state = existingState
    }
  }

  // MARK: - Public Functions

  public func showReplacementMessage() {
    replacementMessage.isHidden = false
  }

  public func hideReplacementMessage() {
    replacementMessage.isHidden = true
  }

  public func showRecordButton(animated: Bool = true) {
    guard animated else {
      recordButton.isHidden = false
      return
    }
    recordButton.alpha = 0.0
    recordButton.isHidden = false
    UIView.animate(withDuration: Constants.showHideAnimationDuration) {
      self.recordButton.alpha = 1.0
    }
  }

  public func hideRecordButton(animated: Bool = true) {
    guard animated else {
      recordButton.isHidden = true
      return
    }
    UIView.animate(withDuration: Constants.showHideAnimationDuration, animations: {
      self.recordButton.alpha = 0.0
    }) { (_) in
      self.recordButton.isHidden = true
      self.recordButton.alpha = 1.0
    }
  }

  public func showMetronomeButton(animated: Bool = true) {
    guard metronomeEnabled else { return }
    guard animated else {
      metronomeButton.isHidden = false
      return
    }
    metronomeButton.alpha = 0.0
    metronomeButton.isHidden = false
    UIView.animate(withDuration: Constants.showHideAnimationDuration) {
      self.metronomeButton.alpha = 1.0
    }
  }

  public func hideMetronomeButton(animated: Bool = true) {
    guard metronomeEnabled else { return }
    guard animated else {
      metronomeEditViewController.view.isHidden = true
      metronomeButton.isHidden = true
      return
    }
    UIView.animate(withDuration: Constants.showHideAnimationDuration, animations: {
      self.metronomeButton.alpha = 0.0
      self.metronomeEditViewController.view.alpha = 0.0
    }) { (_) in
      self.metronomeButton.isHidden = true
      self.metronomeButton.alpha = 1.0
      self.metronomeEditViewController.view.isHidden = true
      self.metronomeEditViewController.view.alpha = 1.0
    }
  }

  public func showFlipCameraButton(animated: Bool = true) {
    guard animated else {
      flipCameraButton.isHidden = false
      return
    }
    flipCameraButton.alpha = 0.0
    flipCameraButton.isHidden = false
    UIView.animate(withDuration: Constants.showHideAnimationDuration) {
      self.flipCameraButton.alpha = 1.0
    }
  }

  public func hideFlipCameraButton(animated: Bool = true) {
    guard animated else {
      flipCameraButton.isHidden = true
      return
    }
    UIView.animate(withDuration: Constants.showHideAnimationDuration, animations: {
      self.flipCameraButton.alpha = 0.0
    }) { (_) in
      self.flipCameraButton.isHidden = true
      self.flipCameraButton.alpha = 1.0
    }
  }

  public func showNextButton(animated: Bool = true) {
    // The next button always hides the other buttons in the view.
    hideCaptureButtons(animated: false)

    guard animated else {
      nextButton.isHidden = false
      return
    }
    nextButton.alpha = 0.0
    nextButton.isHidden = false
    UIView.animate(withDuration: Constants.showHideAnimationDuration) {
      self.nextButton.alpha = 1.0
    }
  }

  public func hideNextButton(animated: Bool = true) {
    guard animated else {
      nextButton.isHidden = true
      return
    }
    UIView.animate(withDuration: Constants.showHideAnimationDuration, animations: {
      self.nextButton.alpha = 0.0
    }) { (_) in
      self.nextButton.isHidden = true
      self.nextButton.alpha = 1.0
    }
  }

  public func showCaptureButtons(animated: Bool = true) {
    showRecordButton(animated: animated)
    showFlipCameraButton(animated: animated)
    showMetronomeButton(animated: animated)
    if SettingsViewController.uploadFromCameraRollEnabled {
      cameraRollButton.isHidden = false
    }
  }

  public func hideUI() {
    hideAllButtons()
    hideReplacementMessage()
  }

  public func hideCaptureButtons(animated: Bool = true) {
    hideRecordButton(animated: animated)
    hideFlipCameraButton(animated: animated)
    hideMetronomeButton(animated: animated)
  }

  public func hideAllButtons() {
    recordButton.isHidden = true
    flipCameraButton.isHidden = true
    nextButton.isHidden = true
    metronomeButton.isHidden = true
    cameraRollButton.isHidden = true
    metronomeEditViewController.view.isHidden = true
  }

  public func disableAllButtons() {
    // Will respect if the button is hidden.
    recordButton.isUserInteractionEnabled = false
    flipCameraButton.isUserInteractionEnabled = false
    nextButton.isUserInteractionEnabled = false
    cameraRollButton.isUserInteractionEnabled = false
    metronomeButton.isUserInteractionEnabled = false
  }

  public func enableAllButtons() {
    // Will respect if the button is hidden.
    recordButton.isUserInteractionEnabled = true
    flipCameraButton.isUserInteractionEnabled = true
    nextButton.isUserInteractionEnabled = true
    cameraRollButton.isUserInteractionEnabled = true
    metronomeButton.isUserInteractionEnabled = true
  }

  public func setRecordButtonAction(target: Any?,
                                    selector: Selector,
                                    forEvent: UIControl.Event) {
    recordButton.addGestureRecognizer(UITapGestureRecognizer(target: target, action: selector))
  }

  public func setFlipCameraButtonAction(target: Any?,
                                        selector: Selector,
                                        forEvent: UIControl.Event) {
    flipCameraButton.addTarget(target, action: selector, for: forEvent)
  }

  public func setNextButtonAction(target: Any?,
                                  selector: Selector,
                                  forEvent: UIControl.Event) {
    nextButton.addTarget(target, action: selector, for: forEvent)
  }

  public func setCameraRollButton(target: Any?,
                                  selector: Selector,
                                  forEvent: UIControl.Event) {
    cameraRollButton.addTarget(target, action: selector, for: forEvent)
  }

  public func setMetronomeButtonTap(target: Any?,
                                    selector: Selector) {
    let tap = UITapGestureRecognizer(target: target, action: selector)
    tap.numberOfTouchesRequired = 1
    metronomeButton
      .addGestureRecognizer(tap)
  }

  public func updateRecordButtons(state: RecordButtonView.State) {
    flipCameraButton.isHidden = (state != .notRecording)
    recordButton.state = state
    cameraRollButton.isHidden = (state == .recording || state == .waitingToRecord) || !metronomeEnabled
  }

  public func toggleEditMetronome(shouldHide: Bool) {
    guard !metronomeButton.isHidden else { return }
    metronomeEditViewController.view.isHidden = shouldHide
  }

  public func startMetronomeAnimation(BPM: Int, startTime: CMTime) {
    guard self.view.superview != nil else {
      animationBPM = BPM
      animationStartTime = startTime
      return
    }
    let currentTime = CMClockGetTime(CMClockGetHostTimeClock())
    guard CMTimeCompare(currentTime, startTime) >= 0 else {
      print("Can't animate the metronome for a startTime after the current time.")
      return
    }

    let timePerBeat = BeatSnapper.timePerBeat(BPM: BPM)
    var nextBeat = CMTimeAdd(startTime, timePerBeat)
    // iteratively find next beat time that's in the future
    while CMTimeCompare(nextBeat, currentTime) < 0 {
      nextBeat = CMTimeAdd(nextBeat, timePerBeat)
    }

    let deltaFromNext = currentTime.absoluteDifference(other: nextBeat).toSeconds()
    let timePerBeatSeconds = timePerBeat.toSeconds()

    metronomeAnimationOverlay.alpha = 1.0
    metronomeAnimationOverlay.layer.removeAllAnimations()
    let scale = CAKeyframeAnimation(keyPath: "transform.scale")
    scale.timingFunction = CAMediaTimingFunction(name: .linear)
    scale.calculationMode = .linear
    scale.values = [1, 0.25, 1]
    scale.keyTimes = [0, 0.5, 1]
    scale.duration = timePerBeatSeconds
    scale.repeatCount = Float.infinity
    scale.beginTime = CACurrentMediaTime() + deltaFromNext

    metronomeAnimationOverlay.layer.add(scale, forKey: nil)
  }

  public func stopMetronomeAnimation() {
    metronomeAnimationOverlay.layer.removeAllAnimations()
    metronomeAnimationOverlay.alpha = 0.0
    animationBPM = nil
    animationStartTime = nil
  }

  // MARK: - Private Helpers

  fileprivate func setupUI() {
    recordButton.translatesAutoresizingMaskIntoConstraints = false
    flipCameraButton.translatesAutoresizingMaskIntoConstraints = false
    cameraRollButton.translatesAutoresizingMaskIntoConstraints = false
    nextButton.translatesAutoresizingMaskIntoConstraints = false
    replacementMessage.translatesAutoresizingMaskIntoConstraints = false
    metronomeButton.translatesAutoresizingMaskIntoConstraints = false
    metronomeAnimationOverlay.translatesAutoresizingMaskIntoConstraints = false

    self.view.addSubview(recordButton)

    let flipCameraImage = UIImage(systemName: "camera.rotate.fill")?.withRenderingMode(.alwaysTemplate)
    flipCameraButton.setImage(flipCameraImage, for: .normal)
    flipCameraButton.tintColor = .white
    self.view.addSubview(flipCameraButton)

    flipCameraButton.backgroundColor = UIColor(rgb: 0x1A1A1A)
    flipCameraButton.highlightedColor = flipCameraButton.backgroundColor?.withAlphaComponent(0.6)
    flipCameraButton.clipsToBounds = true
    flipCameraButton.layer.cornerRadius = Constants.flipCameraButtonSize / 2.0

    if SettingsViewController.uploadFromCameraRollEnabled {
      let cameraRollImage = UIImage(systemName: "photo.fill")?.withRenderingMode(.alwaysTemplate)
      cameraRollButton.setImage(cameraRollImage, for: .normal)
      cameraRollButton.tintColor = .white
      cameraRollButton.backgroundColor = UIColor(rgb: 0x1A1A1A)
      cameraRollButton.highlightedColor = flipCameraButton.backgroundColor?.withAlphaComponent(0.6)
      cameraRollButton.clipsToBounds = true
      cameraRollButton.layer.cornerRadius = 4.0
      self.view.addSubview(cameraRollButton)
    }

    metronomeButton.backgroundColor = UIColor(rgb: 0x1A1A1A)
    metronomeButton.setImage(UIImage(systemName: "metronome.fill")?.withRenderingMode(.alwaysTemplate), for: .normal)
    metronomeButton.tintColor = .white
    metronomeButton.clipsToBounds = true
    metronomeButton.layer.cornerRadius = Constants.flipCameraButtonSize / 2.0
    self.view.addSubview(metronomeButton)

    metronomeEditViewController.view.translatesAutoresizingMaskIntoConstraints = false
    metronomeEditViewController.delegate = metronomeDelegate
    self.view.addSubview(metronomeEditViewController.view)

    metronomeAnimationOverlay.backgroundColor = UIColor(rgb: 0xB7B7B7)
    metronomeAnimationOverlay.clipsToBounds = true
    metronomeAnimationOverlay.layer.cornerRadius = Constants.flipCameraButtonSize / 2.0
    metronomeAnimationOverlay.alpha = 0.0
    metronomeButton.insertSubview(metronomeAnimationOverlay,
                                  belowSubview: metronomeButton.imageView!)
    metronomeButton.highlightedColor = metronomeAnimationOverlay.backgroundColor?.withAlphaComponent(0.6)

    nextButton.setBackgroundColor(.white, for: .normal)
    nextButton.highlightedColor = UIColor.white.withAlphaComponent(0.6)
    nextButton.setTitle("Next", for: .normal)
    nextButton.setTitleColor(.black, for: .normal)
    nextButton.clipsToBounds = true
    nextButton.layer.cornerRadius = Constants.nextButtonHeight / 2.0
    self.view.addSubview(nextButton)

    replacementMessage.textAlignment = .center
    replacementMessage.font = .systemFont(ofSize: Constants.smallFontSize)
    replacementMessage.textColor = .white
    replacementMessage.numberOfLines = 0
    replacementMessage.text = "Select where you'd like to \n record"
    self.view.addSubview(replacementMessage)

    NSLayoutConstraint.activate([
      recordButton.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
      recordButton.centerYAnchor.constraint(equalTo: self.view.centerYAnchor, constant: metronomePadding),
      recordButton.widthAnchor.constraint(equalToConstant: Constants.recordButtonSize),
      recordButton.heightAnchor.constraint(equalToConstant: Constants.recordButtonSize),
      flipCameraButton.leadingAnchor.constraint(equalTo: recordButton.trailingAnchor, constant: Constants.buttonMinimumPadding),
      flipCameraButton.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
      flipCameraButton.widthAnchor.constraint(equalToConstant: Constants.flipCameraButtonSize),
      flipCameraButton.heightAnchor.constraint(equalToConstant: Constants.flipCameraButtonSize),
      metronomeButton.trailingAnchor.constraint(equalTo: recordButton.leadingAnchor, constant: SettingsViewController.uploadFromCameraRollEnabled ? -20 : -Constants.buttonMinimumPadding),
      metronomeButton.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
      metronomeButton.widthAnchor.constraint(equalToConstant: Constants.metronomeButtonSize),
      metronomeButton.heightAnchor.constraint(equalToConstant: Constants.metronomeButtonSize),
      metronomeAnimationOverlay.heightAnchor.constraint(equalTo: metronomeButton.heightAnchor),
      metronomeAnimationOverlay.widthAnchor.constraint(equalTo: metronomeButton.widthAnchor),
      metronomeAnimationOverlay.centerXAnchor.constraint(equalTo: metronomeButton.centerXAnchor),
      metronomeAnimationOverlay.centerYAnchor.constraint(equalTo: metronomeButton.centerYAnchor),
      metronomeEditViewController.view.centerXAnchor.constraint(equalTo: metronomeButton.centerXAnchor),
      metronomeEditViewController.view.bottomAnchor.constraint(equalTo: metronomeButton.topAnchor, constant: -7),
      metronomeEditViewController.view.heightAnchor.constraint(equalToConstant: 28),
      metronomeEditViewController.view.widthAnchor.constraint(equalToConstant: 114),
      nextButton.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
      nextButton.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
      nextButton.widthAnchor.constraint(equalToConstant: Constants.nextButtonWidth),
      nextButton.heightAnchor.constraint(equalToConstant: Constants.nextButtonHeight),
      replacementMessage.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
      replacementMessage.centerYAnchor.constraint(equalTo: self.view.centerYAnchor)
    ])
    if SettingsViewController.uploadFromCameraRollEnabled {
      NSLayoutConstraint.activate([
        cameraRollButton.trailingAnchor.constraint(equalTo: metronomeButton.leadingAnchor, constant: -18.0),
        cameraRollButton.centerYAnchor.constraint(equalTo: metronomeButton.centerYAnchor),
        cameraRollButton.widthAnchor.constraint(equalToConstant: 32),
        cameraRollButton.heightAnchor.constraint(equalToConstant: 32)
      ])
    }
  }
}
