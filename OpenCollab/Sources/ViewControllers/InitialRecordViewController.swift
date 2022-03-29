// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import AVFoundation
import Foundation
import Photos
import UIKit

class InitialRecordViewController: UIViewController {
  enum Constants {
    static let additionalSidePadding: CGFloat = 20.0
    static let additionalMetronomePadding: CGFloat = 12.0
    static let actionViewHeight: CGFloat = 94.0
    static let firstRecordTimeWarningLimit: TimeInterval = 10.0
    static let firstRecordTimeLimit: TimeInterval = 90.0
    static let defaultBeatsPerBar = 4
    static let defaultAccentedBeatInBar = 1
    static let bricHeight: CGFloat = 58.0
    static let spinnerContainerAlpha: CGFloat = 0.75
  }
  static let defaultBPM = 128

  fileprivate var creationRecordViewController: CreationRecordViewController?
  fileprivate var recordActionViewController = RecordActionViewController(metronomeEnabled: true)
  fileprivate let spinnerContainerView = UIView()
  fileprivate let spinnerView = SpinnerView.withSize(size: Constants.bricHeight)
  fileprivate var actionView: UIViewController {
    willSet {
      actionView.view.removeFromSuperview()
    }
    didSet {
      view.addSubview(actionView.view)
      view.setNeedsLayout()
    }
  }
  fileprivate lazy var metronomeHeadphoneView: UILabel =
    UINib(nibName: "MetronomeHeadphoneView", bundle: nil)
      .instantiate(withOwner: nil, options: nil)[0] as! UILabel
  fileprivate var metronomeIsPlaying: Bool = false
  fileprivate var isRecording = false {
    didSet {
      if !isRecording {
        maxRecordLimitDispatchItem = nil
        recordButtonUpdateDispatchItem = nil
      }
    }
  }
  fileprivate var countDownTime: CMTime {
    get {
      let halfBPM = BPM / 2
      return BeatSnapper.timePerBeat(BPM: halfBPM)
    }
  }
  fileprivate var maxRecordLimitDispatchItem: DispatchWorkItem? {
    willSet {
      maxRecordLimitDispatchItem?.cancel()
    }
  }
  fileprivate var recordButtonUpdateDispatchItem: DispatchWorkItem? {
    willSet {
      recordButtonUpdateDispatchItem?.cancel()
    }
  }
  fileprivate var BPM: Int = InitialRecordViewController.defaultBPM {
    didSet {
      creationRecordViewController?.BPM = BPM
      if metronomeIsPlaying {
        playClickTrack()
      }
    }
  }
  fileprivate var playbackCoordinator: PlaybackCoordinator? {
    willSet {
      self.playbackCoordinator?.clear()
    }
  }
  fileprivate var clickTrackLooper: QueuePlayerLooper? {
    willSet {
      guard let clickTrackLooper = clickTrackLooper else { return }
      playbackCoordinator?.detach(looper: clickTrackLooper)
      playbackCoordinator = nil
      recordActionViewController.stopMetronomeAnimation()
    }
    didSet {
      guard let clickTrackLooper = clickTrackLooper else { return }
      if playbackCoordinator == nil {
        setupPlaybackCoordinator(duration: clickTrackLooper.playbackDuration)
      }

      clickTrackLooper.volume = 1.0
      clickTrackLooper.shouldMuteWithoutHeadphones = true

      guard let playbackCoordinator = playbackCoordinator else { return }
      playbackCoordinator.attach(looper: clickTrackLooper)

      guard let lastLoopTime = playbackCoordinator.lastLoopTime else {
        missedMetronomeAnimationStart = true
        return
      }
      recordActionViewController.startMetronomeAnimation(BPM: BPM, startTime: lastLoopTime)
    }
  }
  fileprivate var missedMetronomeAnimationStart = false

  init() {
    actionView = recordActionViewController
    super.init(nibName: nil, bundle: nil)
    recordActionViewController.metronomeDelegate = self

    setupUI()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  fileprivate func setupPlaybackCoordinator(duration: CMTime) {
    playbackCoordinator =
      PlaybackCoordinator(gracePeriod: 0.3,
                          duration: duration)
    self.playbackCoordinator?.delegate = self
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    // keep screen on for the duration of creation session
    // this setting will be reset when creation session ends
    // either by publishing or exiting creation.
    UIApplication.shared.isIdleTimerDisabled = true

    setupRecord()
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    stopSpinner()
  }

  override public func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()

    let bounds = self.view.bounds
    var insets = self.view.safeAreaInsets
    insets.right += Constants.additionalSidePadding
    insets.left += Constants.additionalSidePadding
    insets.bottom += Constants.actionViewHeight + Constants.additionalSidePadding
    let availableBoundsForRecording = bounds.inset(by: insets)
    let safeAreaFrame = view.safeAreaLayoutGuide.layoutFrame
    let properAspectRatioFittedSize = AspectRatioCalculator.collabSizeThatFits(size: availableBoundsForRecording.size)

    let recordingFrame = CGRect(x: availableBoundsForRecording.midX - (properAspectRatioFittedSize.width / 2),
                                y: availableBoundsForRecording.midY - (properAspectRatioFittedSize.height / 2),
                                width: properAspectRatioFittedSize.width,
                                height: properAspectRatioFittedSize.height)
    creationRecordViewController?.view.frame = recordingFrame

    let actionFrame = CGRect(x: safeAreaFrame.origin.x,
                             y: safeAreaFrame.maxY - Constants.actionViewHeight,
                             width: safeAreaFrame.width,
                             height: Constants.actionViewHeight)
    recordActionViewController.view.frame = actionFrame

    guard let window = self.view.window else { return }
    spinnerContainerView.frame = window.bounds
  }

  fileprivate func setupRecord() {
    BPM = InitialRecordViewController.defaultBPM
    AppHeadphoneManager.shared
      .setAudioSessionForRecord(on: AppDelegate.avSessionQueue).onComplete { [self] _ in
        self.creationRecordViewController =
          CreationRecordViewController(duration: nil,
                                       initialTakeCount: 0,
                                       BPM: self.BPM,
                                       avSessionQueue: AppDelegate.avSessionQueue,
                                       delegate: self)

        guard let creationRecordViewController = self.creationRecordViewController else { return }
        view.addSubview(creationRecordViewController.view)
        recordActionViewController.showCaptureButtons(animated: true)
      }
  }

  fileprivate func startRecording() {
    assert(Thread.isMainThread, "should be called on main thread")
    print("-------------------------------- RECORD START --------------------------------")

    isRecording = true
    // Restrict first clip to 2 minutes
    maxRecordLimitDispatchItem = DispatchWorkItem(block: { [weak self] in
      guard let self = self else { return }
      self.creationRecordViewController?.activateRecordingLimitTimer(startCount: Int(Constants.firstRecordTimeWarningLimit),
                                                                     completion: { [weak self] in
                                                                      guard let self = self else { return }
                                                                      guard self.isRecording else { return }
                                                                      self.stopRecording()
                                                                     })
    })
    let firstTakeCountDownTime = countDownTime.toSeconds() * Double(TakeViewController.countdownTimerLimit)
    DispatchQueue.main.asyncAfter(deadline: .now() + firstTakeCountDownTime + Constants.firstRecordTimeLimit - Constants.firstRecordTimeWarningLimit,
                                  execute: maxRecordLimitDispatchItem!)
    let recordButtonUpdateTimeInterval = firstTakeCountDownTime

    recordActionViewController.updateRecordButtons(state: .waitingToRecord)
    recordButtonUpdateDispatchItem = DispatchWorkItem(block: { [weak self] in
      guard let self = self else { return }
      self.recordActionViewController.updateRecordButtons(state: .recording)
    })
    DispatchQueue.main.asyncAfter(deadline: .now() + recordButtonUpdateTimeInterval,
                                  execute: recordButtonUpdateDispatchItem!)
    creationRecordViewController?.startRecording()
  }

  fileprivate func stopRecording(shouldDiscard: Bool = false) {
    print("----------------------------------- RECORD STOP ------------------------------")
    navigationItem.leftBarButtonItem?.action = nil
    creationRecordViewController?.stopRecording(shouldDiscard: shouldDiscard)
  }

  fileprivate func toggleClicktrack() {
    if metronomeIsPlaying {
      stopClickTrack()
    } else {
      playClickTrack()
    }
  }

  fileprivate func setupUI() {
    self.view.backgroundColor = .black
    self.hidesBottomBarWhenPushed = true
    self.recordActionViewController.metronomePadding = Constants.additionalMetronomePadding
    self.creationRecordViewController =
      CreationRecordViewController(duration: nil,
                                   initialTakeCount: 0,
                                   BPM: BPM,
                                   avSessionQueue: AppDelegate.avSessionQueue,
                                   delegate: self)
    actionView = recordActionViewController
    recordActionViewController.hideUI()
    recordActionViewController
      .setRecordButtonAction(target: self,
                             selector: #selector(didClickRecordButton(_:)),
                             forEvent: .touchUpInside)
    recordActionViewController
      .setFlipCameraButtonAction(target: self,
                                 selector: #selector(didClickFlipCameraButton(_:)),
                                 forEvent: .touchUpInside)
    recordActionViewController
      .setMetronomeButtonTap(target: self,
                                selector: #selector(didClickMetronomeButton(_:)))
    recordActionViewController
      .setCameraRollButton(target: self,
                           selector: #selector(didClickUploadFromCameraRoll(_:)),
                           forEvent: .touchUpInside)
    setupSpinner()

    self.navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "xmark")?.withRenderingMode(.alwaysTemplate),
                                                            style: .plain,
                                                            target: self,
                                                            action: #selector(didTapBack))
    self.navigationItem.leftBarButtonItem?.tintColor = .white
  }

  // MARK: Navigation

  @objc func didTapBack() {
    UIApplication.shared.isIdleTimerDisabled = false
    stopClickTrack()
    self.navigationController?.popViewController(animated: true)
  }

  // MARK: - Button Action Handlers

  @objc func didClickFlipCameraButton(_ sender: AnyObject?) {
    guard !isRecording else { return }
    recordActionViewController.disableAllButtons()

    creationRecordViewController?.flipCamera().onComplete {_ in
      DispatchQueue.main.async {
        // We don't really care if we failed or not. We should always
        // re-enable the button.
        self.recordActionViewController.enableAllButtons()

        // TODO : handle if the flip camera failed by showing a message
        // to the user.
      }
    }
  }

  @objc func didClickUploadFromCameraRoll(_ sender: AnyObject) {
    stopClickTrack()
    let picker = UIImagePickerController()
    picker.sourceType = .photoLibrary
    picker.allowsEditing = false
    picker.mediaTypes = ["public.movie"]
    picker.delegate = self
    present(picker, animated: true)
  }

  @objc func didClickMetronomeButton(_ sender: AnyObject?) {
    let shouldHide = metronomeIsPlaying
    recordActionViewController.toggleEditMetronome(shouldHide: shouldHide)
    toggleClicktrack()
  }

  @objc func didClickRecordButton(_ sender: AnyObject?) {
    if isRecording {
      navigationItem.leftBarButtonItem?.action = nil
    }
    RecordingAuthorizer.isAuthorized(
    ).onSuccess { [self] (status) in
      guard status == .authorized else {
        RecordingAuthorizer.showUnauthorizedAlert(vc: self, status: status)
        navigationItem.leftBarButtonItem?.action = #selector(didTapBack)
        return
      }
      if isRecording {
        stopRecording()
      } else {
        startRecording()
      }
    }.onFailure { (_) in
      Fatal.safeError("RecordingAuthorizer should not fail")
    }
  }

  @objc func didClickDoneEditingMetronomeButton(_ sender: AnyObject?) {
    actionView = recordActionViewController
  }

  @objc fileprivate func updateTitleMessage() {
    DispatchQueue.main.async {
      let headphonesIn = AppHeadphoneManager.shared.currentState() == .Connected
      if self.metronomeIsPlaying {
        if headphonesIn {
          self.navigationItem.titleView = nil
        } else {
          self.navigationItem.titleView = self.metronomeHeadphoneView
        }
      } else {
        self.navigationItem.titleView = nil
      }
    }
  }
}

// MARK: - CreationRecordViewControllerDelegate

extension InitialRecordViewController: CreationRecordViewControllerDelegate {
  func readyToRecord() {
    guard let creationRecordViewController = creationRecordViewController,
          creationRecordViewController.isReadyToRecord else { return }

    self.recordActionViewController.showCaptureButtons()
  }

  func recordStopped() {
    // Called when the record stack has stopped recording. This doesn't mean that the
    // record stack has finished generating takes but we can use this function to update
    // the UI.
    if isRecording {
      enableSpinner()
    }
    resetRecordingState()
  }

  fileprivate func resetRecordingState() {
    isRecording = false
    stopClickTrack()
    recordActionViewController.updateRecordButtons(state: .notRecording)
  }

  func restoreUI() {
    navigationItem.leftBarButtonItem?.action = #selector(didTapBack)
    stopSpinner()
  }

  func recordFinished(fragments: [FragmentHost]) {
    guard Thread.isMainThread else { Fatal.safeError("Should be on main thread") }

    print("--------------------------- RECORD SESSION FINISHED ---------------------------")
    resetRecordingState()

    let recordedFragment = fragments[0]
    guard recordedFragment.assetDuration >= FragmentHost.minFragmentDuration else {
      // If the recorded fragment is less than the minimum, don't continue to the trimmer and just allow them to record again
      stopSpinner()
      return
    }

    let model = PlaybackDataModel(from: recordedFragment)
    self.navigationController?.pushViewController(TrimViewController(model: model), animated: true)
  }

  func didTapDeleteClip(viewController: CreationRecordViewController) {
    // no-op
  }
}

// MARK: - Click Track Support

extension InitialRecordViewController {
  fileprivate func playClickTrack() {
    metronomeIsPlaying = true
    self.clickTrackLooper = createClickTrack()
    updateTitleMessage()
  }

  fileprivate func stopClickTrack() {
    metronomeIsPlaying = false
    recordActionViewController.toggleEditMetronome(shouldHide: true)
    self.clickTrackLooper = nil
    updateTitleMessage()
  }

  fileprivate func createClickTrack() -> QueuePlayerLooper? {
    let clickTrackDuration = CMTimeMultiply(BeatSnapper.timePerBar(BPM: BPM,
                                                                   beatsPerBar: Int32(Constants.defaultBeatsPerBar)),
                                 multiplier: 4)

    guard let clickTrackAsset =
            ClickTrackComposer.composeClickTrackFor(BPM: BPM,
                                                    duration: clickTrackDuration,
                                                    beatsPerBar: Constants.defaultBeatsPerBar,
                                                    accentedBeatInBar: Constants.defaultAccentedBeatInBar) else {
      print("Tried to play the metronome but couldn't create a click track.")
      return nil
    }

    return QueuePlayerLooper(asset: clickTrackAsset, playbackStartTime: .zero, playbackDuration: clickTrackDuration)
  }
}

extension InitialRecordViewController: PlaybackCoordinatorDelegate {
  func bufferingStarted() {
    // no-op
  }

  func bufferingStopped() {
    // no-op
  }

  func looped(atTime: CMTime, loopCount: Int) {
    if loopCount == 0, clickTrackLooper != nil, missedMetronomeAnimationStart {
      recordActionViewController.startMetronomeAnimation(BPM: BPM, startTime: atTime)
      missedMetronomeAnimationStart = false
    }
    guard isRecording, loopCount > 0 else { return }

    creationRecordViewController?.looped(atTime: atTime, loopCount: loopCount)
  }

  func playbackStarted() {
    stopSpinner()
  }
}

// MARK: - MetronomeEditViewControllerDelegate

extension InitialRecordViewController: MetronomeEditViewControllerDelegate {
  func didUpdateBPM(BPM: Int) {
    if !metronomeIsPlaying {
      playClickTrack()
    }
    self.BPM = BPM
  }

  func pauseClickTrack() {
    metronomeIsPlaying = false
    self.clickTrackLooper = nil
    // temporary pause, so don't update title message or hide edit metronome view
  }
}

// MARK: - Loading

extension InitialRecordViewController {
  fileprivate func setupSpinner() {
    spinnerContainerView.backgroundColor = UIColor.black.withAlphaComponent(Constants.spinnerContainerAlpha)
    spinnerView.translatesAutoresizingMaskIntoConstraints = false
    spinnerContainerView.addSubview(spinnerView)
    NSLayoutConstraint.activate([
      spinnerView.centerXAnchor.constraint(equalTo: spinnerContainerView.centerXAnchor),
      spinnerView.centerYAnchor.constraint(equalTo: spinnerContainerView.centerYAnchor),
      spinnerView.heightAnchor.constraint(equalToConstant: Constants.bricHeight),
      spinnerView.widthAnchor.constraint(equalToConstant: Constants.bricHeight)
    ])
  }

  func enableSpinner() {
    guard spinnerContainerView.superview == nil else {
      return
    }
    self.view.addSubview(spinnerContainerView)
    spinnerView.startAnimating()
    spinnerView.alpha = 1.0
  }

  fileprivate func stopSpinner() {
    spinnerContainerView.removeFromSuperview()
    spinnerView.stopAnimating()
  }
}

// MARK: media picker

extension InitialRecordViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    picker.dismiss(animated: true)
  }

  func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
    guard let videoURL = info[.mediaURL] as? URL else {
      return
    }
    let model = PlaybackDataModel(from: videoURL)
    self.navigationController?.pushViewController(TrimViewController(model: model), animated: true)
    picker.dismiss(animated: true)
  }
}
