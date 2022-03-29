// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import UIKit

class TrimViewController: UIViewController {
  let trimNextButtonImage = UIImage(systemName: "arrow.right")?.withRenderingMode(.alwaysTemplate)
  let trimNextButtonDisabledImage = UIImage(systemName: "arrow.right")?.translucentImageWithAlpha(alpha: 0.6).withRenderingMode(.alwaysTemplate)
  let actionViewHeight: CGFloat = 120.0
  let trimResetTimePadding = CMTimeMakeWithSeconds(2.5, preferredTimescale: 600)
  fileprivate var trimmerViewController = WaveformTrimmerViewController()
  fileprivate let previewView = TrimEditLoopingVideoView()
  fileprivate var model: PlaybackDataModel

  init(model: PlaybackDataModel) {
    self.model = model
    super.init(nibName: nil, bundle: nil)

    trimmerViewController.willMove(toParent: self)
    addChild(trimmerViewController)
    trimmerViewController.didMove(toParent: self)
    view.addSubview(trimmerViewController.view)
    trimmerViewController.delegate = self

    setupNavBar()

    let initialFragment = model.selectedFragments[0]
    let longerThanMax = initialFragment.maxPlaybackDuration > initialFragment.playbackDuration
    let enabled = longerThanMax
    self.navigationItem.rightBarButtonItem?.isEnabled = enabled
    self.navigationItem.rightBarButtonItem?.image = enabled ? trimNextButtonImage : trimNextButtonDisabledImage
    self.navigationItem.rightBarButtonItem?.tintColor = .white

    trimmerViewController.setFragment(fragment: initialFragment)
    initialFragment.asset().onSuccess { asset in
      if let asset = asset {
        self.previewView.configureForVideo(asset: asset)
        self.view.addSubview(self.previewView)
      }
    }

    FragmentDataModelEventHandler.listeners.add(delegate: self)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    print("-------------------------------- TRIM STARTED --------------------------------")

    // keep screen on for the duration of creation session
    // this setting will be reset when creation session ends
    // either by publishing or exiting creation.
    UIApplication.shared.isIdleTimerDisabled = true

    previewView.unpause(at: model.selectedFragments[0].playbackStartTime) { [weak self] _ in
      guard let self = self else { return }
      guard let player = self.previewView.player else { return }
      self.trimmerViewController.startProgressIndicator(for: player)
    }
  }

  private func setupNavBar() {
    let barItem = UIBarButtonItem(image: trimNextButtonImage?.translucentImageWithAlpha(alpha: 0),
                                  style: .plain,
                                  target: self,
                                  action: #selector(didSelectTrimDoneButton))
    self.navigationItem.setRightBarButton(barItem, animated: true)

    self.navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "xmark")?.withRenderingMode(.alwaysTemplate),
                                                            style: .plain,
                                                            target: self,
                                                            action: #selector(didTapBack))
    self.navigationItem.leftBarButtonItem?.tintColor = .white
  }

  private func setNextButtonEnabled() {
    let enabled = trimmerViewController.isValidTrim
    self.navigationItem.rightBarButtonItem?.isEnabled = enabled
    self.navigationItem.rightBarButtonItem?.image = enabled ? trimNextButtonImage : trimNextButtonDisabledImage
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()

    let bounds = self.view.bounds
    var insets = self.view.safeAreaInsets
    insets.right += 20
    insets.left += 20
    insets.bottom += actionViewHeight + 20
    let availableBoundsForVideo = bounds.inset(by: insets)
    let properAspectRatioFittedSize = AspectRatioCalculator.collabSizeThatFits(size: availableBoundsForVideo.size)
    let safeAreaFrame = view.safeAreaLayoutGuide.layoutFrame

    let videoFrame = CGRect(x: availableBoundsForVideo.midX - (properAspectRatioFittedSize.width / 2),
                            y: availableBoundsForVideo.midY - (properAspectRatioFittedSize.height / 2),
                            width: properAspectRatioFittedSize.width,
                            height: properAspectRatioFittedSize.height)

    let actionFrame = CGRect(x: 0,
                             y: safeAreaFrame.maxY - actionViewHeight,
                             width: safeAreaFrame.width,
                             height: actionViewHeight)

    previewView.frame = videoFrame
    trimmerViewController.view.frame = actionFrame
  }

  @objc func didTapBack() {
    let alert = UIAlertController(title: "Discard Recording?", message: "If you go back now you will lose your original clip", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "Discard", style: .destructive, handler: { _ in
      print("-------------------------------- TRIM FINISHED --------------------------------")
      self.previewView.cleanUp()
      self.navigationController?.popViewController(animated: true)
    }))
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

    self.present(alert, animated: true)
  }
}

// MARK: - TrimActionViewControllerDelegate

extension TrimViewController: CollabTrimmerViewControllerDelegate {
  func didStartProgressDrag() {
    previewView.pause()
  }

  func didFinishProgressDrag(time: CMTime) {
    previewView.unpause(at: time) { [weak self] _ in
      guard let self = self else { return }
      guard let player = self.previewView.player else { return }
      self.trimmerViewController.startProgressIndicator(for: player)
    }
  }

  @objc func didSelectTrimDoneButton() {
    print("-------------------------------- TRIM FINISHED --------------------------------")
    previewView.pause()

    model.selectedFragments[0].captureThumbnail().onSuccess { [weak self] (image) in
      guard let self = self else { return }
      self.model.selectedFragments[0].localThumbnailImage = image
      let remixModel = PlaybackDataModel(trimmerModel: self.model)
      let remixVC = RemixViewController(model: remixModel,
                                        initialPlaybackTime: .zero)
      self.navigationController?.pushViewController(remixVC, animated: true)
    }
  }

  func didDragTrimmer(range: ClosedRange<CMTime>) {
    adjustTime(range: range)
  }

  private func adjustTime(range: ClosedRange<CMTime>) {
    let recordedFragment = model.selectedFragments[0]
    let didStartTimeChange = range.lowerBound != recordedFragment.playbackStartTime
    let didEndTimeChange = range.upperBound != recordedFragment.playbackEndTime

    // If we made a trimmer end change reset playback to near the end of the clip.
    let playbackStartTime: CMTime = didEndTimeChange && !didStartTimeChange
    ? CMTimeSubtract(range.upperBound, trimResetTimePadding)
    : range.lowerBound

    let timeRange = CMTimeRange(start: range.lowerBound, end: range.upperBound)
    previewView.adjustTrimTimes(range: timeRange)
    previewView.unpause(at: playbackStartTime) { [weak self] _ in
      guard let self = self else { return }
      guard let player = self.previewView.player else { return }
      self.trimmerViewController.startProgressIndicator(for: player)
    }

    model.adjustTrimTimes(trimRange: range, of: 0)
    FragmentDataModelEventHandler.announceUpdate(model: model)
  }

  func didDragProgress(time: CMTime) {
    previewView.scrub(to: time)
  }

  func didNudgeStartTime(direction: Int32) {
    let recordedFragment = model.selectedFragments[0]
    let delta = CMTimeMultiply(PlaybackEditor.increment, multiplier: direction)
    let shiftedStartTime = CMTimeAdd(recordedFragment.playbackStartTime, delta)
    adjustTime(range: shiftedStartTime ... recordedFragment.playbackEndTime)
  }

  func didNudgeEndTime(direction: Int32) {
    let recordedFragment = model.selectedFragments[0]
    let delta = CMTimeMultiply(PlaybackEditor.increment, multiplier: direction)
    let shiftedEndTime = CMTimeAdd(recordedFragment.playbackEndTime, delta)
    adjustTime(range: recordedFragment.playbackStartTime ... shiftedEndTime)
  }

  func displayMaxTrimNotice() {
  }

  func displayMinTrimNotice() {
  }
}

extension TrimViewController: FragmentDataModelListener {
  func updated(model: PlaybackDataModel) {
    self.model = model
    let fragment = model.selectedFragments[0]
    trimmerViewController.setFragment(fragment: fragment)
    setNextButtonEnabled()
  }
}
