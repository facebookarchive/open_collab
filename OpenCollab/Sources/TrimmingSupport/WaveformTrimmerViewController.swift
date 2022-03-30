// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import AVFoundation
import Foundation

class WaveformTrimmerViewController: UIViewController, CollabTrimmerViewController {
  struct Constants {
    static let trimmerTimeLabelHeight: CGFloat = 18.0
    static let precisionButtonHeight: CGFloat = 28.0
    static let nudgeButtonWidth: CGFloat = 24.0
    static let precisionButtonPadding: CGFloat = 20.0
    static let nextButtonSize: CGFloat = 24.0
    static let trimZoomBuffer: CMTime = CMTimeMakeWithSeconds(0.75, preferredTimescale: 600)
    static let redColor: UIColor = UIColor(rgb: 0xE45C7C)
  }
  weak var delegate: CollabTrimmerViewControllerDelegate?
  private var fragment: FragmentHost?

  private let waveformTrimmerView = WaveformTrimmerSliderView()
  private let trimmerTimingLabel: UILabel = {
    let label = UILabel()
    label.textColor = .white
    label.font = .boldSystemFont(ofSize: 12)
    return label
  }()
  private let precisionButton: UIButton = {
    let button = UIButton(type: .custom)
    button.setBackgroundColor(.white, for: .normal)
    button.setBackgroundColor(.lightGray, for: .disabled)
    button.layer.cornerRadius = 3.0
    button.clipsToBounds = true
    button.setTitle("Zoom In", for: .normal)
    button.setTitleColor(.black, for: .normal)
    button.titleLabel?.font = .boldSystemFont(ofSize: 10)
    button.isEnabled = false
    return button
  }()
  private static func nudgeButton() -> UIButton {
    let button = UIButton(type: .custom)
    button.imageEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
    button.setBackgroundColor(UIColor(rgb: 0xFBFBFB), for: .normal)
    button.layer.cornerRadius = 3.0
    button.clipsToBounds = true
    button.isEnabled = false
    return button
  }
  private let leftNudgeForwardButton: UIButton = {
    let button = nudgeButton()
    button.setTitle("<", for: .normal)
    button.setTitleColor(.black, for: .normal)
    return button
  }()
  private let leftNudgeBackwardButton: UIButton = {
    let button = nudgeButton()
    button.setTitle(">", for: .normal)
    button.setTitleColor(.black, for: .normal)
    return button
  }()
  private let rightNudgeForwardButton: UIButton = {
    let button = nudgeButton()
    button.setTitle("<", for: .normal)
    button.setTitleColor(.black, for: .normal)
    return button
  }()
  private let rightNudgeBackwardButton: UIButton = {
    let button = nudgeButton()
    button.setTitle(">", for: .normal)
    button.setTitleColor(.black, for: .normal)
    return button
  }()

  fileprivate var progressTimer: Timer?

  private var isPrecisionZoom = false {
    didSet {
      let title = isPrecisionZoom ? "Zoom Out" : "Zoom In"
      precisionButton.setTitle(title, for: .normal)
    }
  }

  public var isValidTrim: Bool {
    get {
      guard let fragment = self.fragment else { return false }
      let trimDuration = fragment.playbackEndTime - fragment.playbackStartTime
      return trimDuration < fragment.maxPlaybackDuration
    }
  }

  init() {
    super.init(nibName: nil, bundle: nil)
    setupTrimmer()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupTrimmer() {
    view.addSubview(waveformTrimmerView)
    waveformTrimmerView.addTarget(self,
                                  action: #selector(handleScrubberChangeStarted(_:)),
                                  for: .editingDidBegin)
    waveformTrimmerView.addTarget(self,
                                  action: #selector(handleScrubberChangedValue(_:)),
                                  for: .editingChanged)
    waveformTrimmerView.addTarget(self,
                                  action: #selector(handleScrubberChangeEnded(_:)),
                                  for: .editingDidEnd)
    waveformTrimmerView.addTarget(self,
                                  action: #selector(progressDragStarted(_:)),
                                  for: .touchDragEnter)
    waveformTrimmerView.addTarget(self,
                                  action: #selector(progressDragEnded(_:)),
                                  for: .touchDragExit)
    waveformTrimmerView.addTarget(self,
                                  action: #selector(progressDragChangedValue(_:)),
                                  for: .touchDragInside)

    view.addSubview(trimmerTimingLabel)
    precisionButton.addTarget(self, action: #selector(didTapPrecision(_:)), for: .touchUpInside)
    leftNudgeForwardButton.addTarget(self, action: #selector(didNudgeStartForward(_:)), for: .touchUpInside)
    leftNudgeBackwardButton.addTarget(self, action: #selector(didNudgeStartBackward(_:)), for: .touchUpInside)
    rightNudgeForwardButton.addTarget(self, action: #selector(didNudgeEndForward(_:)), for: .touchUpInside)
    rightNudgeBackwardButton.addTarget(self, action: #selector(didNudgeEndBackward(_:)), for: .touchUpInside)
    view.addSubview(precisionButton)
    view.addSubview(leftNudgeForwardButton)
    view.addSubview(leftNudgeBackwardButton)
    view.addSubview(rightNudgeForwardButton)
    view.addSubview(rightNudgeBackwardButton)
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    precisionButton.sizeToFit()
    var xLayout = view.bounds.width - 10.0 - Constants.nudgeButtonWidth
    rightNudgeBackwardButton.frame = CGRect(x: xLayout, y: 0.0, width: Constants.nudgeButtonWidth, height: Constants.precisionButtonHeight)
    xLayout -= Constants.nudgeButtonWidth + 5.0
    rightNudgeForwardButton.frame = CGRect(x: xLayout, y: 0.0, width: Constants.nudgeButtonWidth, height: Constants.precisionButtonHeight)
    xLayout -= precisionButton.bounds.width + Constants.precisionButtonPadding + 5.0
    precisionButton.frame = CGRect(x: xLayout,
                                   y: 0.0,
                                   width: precisionButton.bounds.width + Constants.precisionButtonPadding,
                                   height: Constants.precisionButtonHeight)
    xLayout -= Constants.nudgeButtonWidth + 5.0
    leftNudgeBackwardButton.frame = CGRect(x: xLayout, y: 0.0, width: Constants.nudgeButtonWidth, height: Constants.precisionButtonHeight)
    xLayout -= Constants.nudgeButtonWidth + 5.0
    leftNudgeForwardButton.frame = CGRect(x: xLayout, y: 0.0, width: Constants.nudgeButtonWidth, height: Constants.precisionButtonHeight)

    let centerTextStart = (precisionButton.frame.height - (precisionButton.titleLabel?.frame.height ?? 0)) / 4
    trimmerTimingLabel.frame = CGRect(x: 10.0,
                                      y: centerTextStart,
                                      width: CGFloat(view.bounds.width) - precisionButton.frame.width,
                                      height: Constants.trimmerTimeLabelHeight)
    waveformTrimmerView.frame = view.bounds.inset(by: UIEdgeInsets(top: Constants.precisionButtonHeight + 10, left: 10, bottom: 20, right: 10))
  }

  func setFragment(fragment: FragmentHost) {
    self.fragment = fragment
    waveformTrimmerView.configureWithFragment(fragment: fragment)
    setTimingLabelForTime(duration: fragment.playbackEndTime - fragment.playbackStartTime)
    setNudgeButtonsEnabled()
    view.setNeedsLayout()
  }

  func resetRange() {
    isPrecisionZoom = false
    precisionButton.isEnabled = false
    waveformTrimmerView.resetRange()
  }

  func startProgressIndicator(hotLooper: HotLooper) {
    progressTimer?.invalidate()

    progressTimer =
      Timer.scheduledTimer(withTimeInterval: 0.01,
                           repeats: true,
                           block: { [weak self] (_) in
                            guard let self = self else { return }
                            guard let fragment = self.fragment else { return }
                            if let currentTime = hotLooper.currentPlaybackTime() {
                              self.updatePositionOfProgressIndicatorForTime(time: fragment.translateToAssetTime(playbackTime: currentTime))
                            }
                           })
  }

  func startProgressIndicator(for player: AVQueuePlayer) {
    progressTimer?.invalidate()

    progressTimer =
      Timer.scheduledTimer(withTimeInterval: 0.01,
                           repeats: true,
                           block: { [weak self] (_) in
                            guard let self = self, player.currentTime() != .zero else { return }
                            self.updatePositionOfProgressIndicatorForTime(time: player.currentTime())
                           })
  }

  private func setTimingLabelForTime(duration: CMTime) {
    guard let fragment = self.fragment else { return }
    let maxTrimDuration = fragment.maxPlaybackDuration
    let roundedDuration = String(format: "%.3f", duration.toSeconds())
    if duration > maxTrimDuration {
      let maxDuration = String(format: "(%.0fs Max)", maxTrimDuration.toSeconds())
      let mutableMaxDuration = NSMutableAttributedString(string: maxDuration, attributes: [NSAttributedString.Key.foregroundColor: Constants.redColor])
      let message = NSMutableAttributedString(string: "\(roundedDuration)s selected ")
      message.append(mutableMaxDuration)

      trimmerTimingLabel.attributedText = message
    } else {
      trimmerTimingLabel.text = "\(roundedDuration)s selected"
    }
  }

  private func setPrecisionTrimButtonEnabled(startTime: CMTime, endTime: CMTime) {
    guard let fragment = self.fragment else { return }
    let sideBuffer = CMTimeMultiply(Constants.trimZoomBuffer, multiplier: 2)
    let validStartTime = startTime - sideBuffer > .zero
    let validEndTime = endTime + sideBuffer < fragment.assetDuration
    precisionButton.isEnabled = validStartTime || validEndTime
  }

  private func setNudgeButtonsEnabled() {
    guard let fragment = self.fragment else { return }

    let nextLeftForwardTime = CMTimeSubtract(fragment.playbackStartTime,
                                             PlaybackEditor.increment)
    let leftForwardEnabled = fragment.startTimeIsValid(time: nextLeftForwardTime)

    let nextLeftBackwardTime = CMTimeAdd(fragment.playbackStartTime,
                                         PlaybackEditor.increment)
    let leftBackwardEnabled = fragment.startTimeIsValid(time: nextLeftBackwardTime)

    let nextRightForwardTime = CMTimeSubtract(fragment.playbackEndTime,
                                              PlaybackEditor.increment)
    let rightForwardEnabled = fragment.endTimeIsValid(time: nextRightForwardTime)

    let nextRightBackwardTime = CMTimeAdd(fragment.playbackEndTime,
                                          PlaybackEditor.increment)
    let rightBackwardEnabled = fragment.endTimeIsValid(time: nextRightBackwardTime)

    leftNudgeForwardButton.isEnabled = leftForwardEnabled
    leftNudgeBackwardButton.isEnabled = leftBackwardEnabled

    rightNudgeForwardButton.isEnabled = rightForwardEnabled
    rightNudgeBackwardButton.isEnabled = rightBackwardEnabled
  }

  @objc private func didTapPrecision(_ sender: AnyObject?) {
    guard let fragment = self.fragment else { return }
    let assetDuration = fragment.assetDuration
    let assetTimeRange = CMTimeRangeMake(start: .zero, duration: assetDuration)
    let lowestTime = CMTimeClampToRange(fragment.playbackStartTime - Constants.trimZoomBuffer, range: assetTimeRange)
    let highestTime = CMTimeClampToRange(fragment.playbackEndTime + Constants.trimZoomBuffer, range: assetTimeRange)
    let zoomStartTime = isPrecisionZoom ? .zero : lowestTime
    let zoomEndTime = isPrecisionZoom ? assetDuration : highestTime
    UIView.animate(withDuration: 0.25) {
      self.waveformTrimmerView.zoomToTimes(startTime: zoomStartTime, endTime: zoomEndTime, assetDuration: assetDuration)
    }
    isPrecisionZoom.toggle()
  }

  @objc private func didNudgeStartForward(_ sender: AnyObject?) {
    delegate?.didNudgeStartTime(direction: -1)
  }

  @objc private func didNudgeStartBackward(_ sender: AnyObject?) {
    delegate?.didNudgeStartTime(direction: 1)
  }

  @objc private func didNudgeEndForward(_ sender: AnyObject?) {
    delegate?.didNudgeEndTime(direction: -1)
  }

  @objc private func didNudgeEndBackward(_ sender: AnyObject?) {
    delegate?.didNudgeEndTime(direction: 1)
  }

  @objc private func handleScrubberChangeStarted(_ sender: WaveformTrimmerSliderView) {
    progressDragStarted(sender)
  }

  @objc private func handleScrubberChangedValue(_ sender: WaveformTrimmerSliderView) {
    guard let start = sender.trimStartTime, let end = sender.trimEndTime else { return }
    let time = sender.dragType == .leading ? start : end
    self.updatePositionOfProgressIndicatorForTime(time: time)
    self.delegate?.didDragProgress(time: time)

    let duration = end - start
    setTimingLabelForTime(duration: duration)
    setPrecisionTrimButtonEnabled(startTime: start, endTime: end)
    setNudgeButtonsEnabled()
  }

  @objc private func handleScrubberChangeEnded(_ sender: WaveformTrimmerSliderView) {
    guard let start = sender.trimStartTime, let end = sender.trimEndTime, let maxEnd = fragment?.assetDuration else { return }
    let clampedEnd = end.clamped(.zero, maxEnd)
    delegate?.didDragTrimmer(range: start ... clampedEnd)
  }

  @objc private func progressDragStarted(_ sender: WaveformTrimmerSliderView) {
    self.progressTimer?.invalidate()
    self.delegate?.didStartProgressDrag()
  }

  @objc private func progressDragChangedValue(_ sender: WaveformTrimmerSliderView) {
    self.delegate?.didDragProgress(time: sender.currentPlaybackTime)
  }

  @objc private func progressDragEnded(_ sender: WaveformTrimmerSliderView) {
    self.delegate?.didFinishProgressDrag(time: sender.currentPlaybackTime)
  }

  fileprivate func updatePositionOfProgressIndicatorForTime(time: CMTime) {
    waveformTrimmerView.currentPlaybackTime = time
  }
}

// MARK: - FragmentPlaybackChangeAnnouncerListener

extension WaveformTrimmerViewController: FragmentPlaybackChangeAnnouncerListener {
  func playbackChanged(fragment: FragmentHost) {
    setFragment(fragment: fragment)
    setTimingLabelForTime(duration: fragment.playbackEndTime - fragment.playbackStartTime)
  }
}
