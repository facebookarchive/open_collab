// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import AVFoundation
import UIKit

class WaveformTrimmerSliderView: UIControl {

  // MARK: - Constants

  struct Constants {
    static let progressIndicatorWidth: CGFloat = 2.0
    static let progressIndicatorHeightOffset: CGFloat = 6.0
    static let trackHeightOffset: CGFloat = 8.0
    static let validTrimColor = UIColor(red: 108, green: 233, blue: 172)
    static let invalidTrimColor = UIColor.gray
  }

  // MARK: - Props

  var currentPlaybackTime: CMTime = .zero {
    didSet {
      let indicatorOrigin = translateToPosition(currentTime: currentPlaybackTime) - progressIndicator.frame.width / 2
      progressIndicator.frame = CGRect(x: indicatorOrigin + TrimmerSliderHandleView.trimmerHandleWidth,
                                       y: Constants.progressIndicatorHeightOffset,
                                       width: Constants.progressIndicatorWidth,
                                       height: self.frame.size.height - 2 * Constants.progressIndicatorHeightOffset)
    }
  }

  var dragType: TrimmerSliderHandleView.DragType {
    return handleView.dragType
  }

  var selectedRangeInPlayableView: ClosedRange<CGFloat>? {
    let playableViewOrigin = trackView.frame.minX
    let handleStartPosition = handleView.frame.minX + TrimmerSliderHandleView.trimmerHandleWidth
    let handleEndPosition = handleView.frame.maxX - TrimmerSliderHandleView.trimmerHandleWidth

    let start = handleStartPosition - playableViewOrigin
    let end = handleEndPosition - playableViewOrigin

    // Before the views are setup, the positions will not be setup
    guard start < end else { return nil }
    return (start...end)
  }
  var initialHandlePlayableRange: ClosedRange<CMTime>?
  var initialPlaybackPositionBeforeDrag: CGFloat = 0

  let handleOffset = 2 * TrimmerSliderHandleView.trimmerHandleWidth
  var trimStartTime: CMTime? {
    guard let range = selectedRangeInPlayableView else { return nil }
    return translateToTime(currentPosition: range.lowerBound)
  }
  var trimEndTime: CMTime? {
    guard let range = selectedRangeInPlayableView else { return nil }
    return translateToTime(currentPosition: range.upperBound)
  }
  private var minTrimPercent: Double {
    return minTrimDuration.toSeconds() / windowDuration.toSeconds()
  }
  private var windowDuration: CMTime = .zero
  private var minTrimDuration: CMTime = .zero
  private var maxTrimDuration: CMTime = .zero
  private var zoomStartTime: CMTime = .zero

  // MARK: - Subviews

  private let trackView: FDWaveformView = {
    let waveformView = FDWaveformView()
    waveformView.alpha = 0.0
    waveformView.doesAllowScrubbing = false
    waveformView.doesAllowStretch = false
    waveformView.doesAllowScroll = false
    waveformView.wavesColor = .white
    waveformView.waveformType = .linear
    return waveformView
  }()

  private var handleView: TrimmerSliderHandleView
  var progressIndicator = ProgressIndicator()

  // MARK: - Init

  override init(frame: CGRect) {
    handleView = TrimmerSliderHandleView(precisionTrim: false)
    super.init(frame: frame)
    trackView.delegate = self
    let trimProgressDrag =
      UIPanGestureRecognizer(target: self,
                             action: #selector(progressDragged(recognizer:)))
    progressIndicator.addGestureRecognizer(trimProgressDrag)

    // Configure subviews
    self.addSubview(trackView)
    self.insertSubview(progressIndicator, aboveSubview: handleView)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    trackView.frame = CGRect(x: TrimmerSliderHandleView.trimmerHandleWidth,
                             y: Constants.trackHeightOffset,
                             width: self.frame.width - handleOffset,
                             height: self.frame.height - (Constants.trackHeightOffset * 2))
    layoutHandleView()
  }

  private func layoutHandleView() {
    guard let range = initialHandlePlayableRange else { return }

    let startPosition = translateToPosition(currentTime: range.lowerBound)
    let endPosition = translateToPosition(currentTime: range.upperBound)

    handleView.frame = CGRect(x: startPosition,
                              y: (-TrimmerSliderHandleView.trimmerBorderSize / 2),
                              width: (endPosition - startPosition) + handleOffset,
                              height: self.frame.height + TrimmerSliderHandleView.trimmerBorderSize)
    updateTrimmerColor()
    initialHandlePlayableRange = nil
  }

  private func updateTrimmerColor() {
    let trimmerColor: UIColor = {
      if let end = trimEndTime, let start = trimStartTime {
        let currentDuration = end - start
        return currentDuration < maxTrimDuration ? Constants.validTrimColor : Constants.invalidTrimColor
      } else {
        return Constants.invalidTrimColor
      }
    }()

    handleView.setColor(color: trimmerColor)
  }

  // MARK: - Configuration

  func setupMoveableHandleView() {
    self.insertSubview(handleView, belowSubview: progressIndicator)
    handleView.setTrimConstraints(minPercent: Float64(minTrimPercent), maxPercent: 1.0)
    handleView.centerTouchAllowed = false
    handleView.dragStarted = { [weak self] _ in
      guard let self = self else { return }
      if self.dragType != .center {
        self.progressIndicator.isHidden = true
        self.sendActions(for: .editingDidBegin)
      }
    }
    handleView.isDragging = { [weak self] _ in
      guard let self = self else { return }
      self.updateTrimmerColor()
      self.sendActions(for: .editingChanged)
    }
    handleView.dragEnded = { [weak self] _ in
      guard let self = self else { return }
      if self.dragType != .center {
        self.progressIndicator.isHidden = false
        self.sendActions(for: .editingDidEnd)
      }
    }
  }

  func resetRange() {
    handleView.removeFromSuperview()
    handleView = TrimmerSliderHandleView(precisionTrim: false)
    zoomStartTime = .zero
  }

  func configureWithFragment(fragment: FragmentHost) {
    guard let url = fragment.assetInfo.userRecordedURL else {
      Fatal.safeAssert("No recorded URL found to populate trimmer timeline")
      return
    }

    let isNewRecording = url != trackView.audioURL
    if isNewRecording {
      trackView.audioURL = url
      self.windowDuration = fragment.assetDuration
    }

    self.minTrimDuration = fragment.minPlaybackDuration
    self.maxTrimDuration = fragment.maxPlaybackDuration

    initialHandlePlayableRange = (fragment.playbackStartTime ... fragment.playbackEndTime)
    setupMoveableHandleView()
  }

  public func zoomToTimes(startTime: CMTime, endTime: CMTime, assetDuration: CMTime) {
    guard let currentTrimStart = trimStartTime, let currentTrimEnd = trimEndTime else {
      return
    }
    windowDuration = endTime - startTime
    zoomStartTime = startTime
    initialHandlePlayableRange = currentTrimStart ... currentTrimEnd
    handleView.setTrimConstraints(minPercent: Float64(minTrimPercent), maxPercent: 1.0)

    trackView.zoomToTimes(startTime: startTime, endTime: endTime, assetDuration: assetDuration)
    setNeedsLayout()
    layoutIfNeeded()
  }

  @objc func progressDragged(recognizer: UIPanGestureRecognizer) {
    guard let range = selectedRangeInPlayableView else { return }
    if recognizer.state == .began {
      initialPlaybackPositionBeforeDrag = progressIndicator.frame.midX
      self.sendActions(for: .touchDragEnter)
      return
    }

    if recognizer.state == .ended {
      self.sendActions(for: .touchDragExit)
      return
    }

    let delta = recognizer.translation(in: trackView).x
    let newPosition = initialPlaybackPositionBeforeDrag + delta
    let newPositionClamped = newPosition.clamped(range.lowerBound ... range.upperBound)
    let newTime = translateToTime(currentPosition: newPositionClamped)
    currentPlaybackTime = newTime

    self.sendActions(for: .touchDragInside)
  }

  // assumes absolute time, relative to the duration of the entire asset
  private func translateToPosition(currentTime: CMTime) -> CGFloat {
    let lengthOfWaveform = trackView.bounds.width
    let relativeToWindowStartTime = currentTime - zoomStartTime
    let position = relativeToWindowStartTime.toSeconds() * (Float64(lengthOfWaveform) / windowDuration.toSeconds())

    return CGFloat(position)
  }

  // returns absolute time
  private func translateToTime(currentPosition: CGFloat) -> CMTime {
    let lengthOfWaveform = trackView.bounds.width
    let relativeSeconds = CMTimeMultiplyByFloat64(windowDuration, multiplier: Float64(currentPosition / lengthOfWaveform))
    let absoluteSeconds = zoomStartTime + relativeSeconds
    return absoluteSeconds
  }
}

extension WaveformTrimmerSliderView: FDWaveformViewDelegate {
  func waveformViewWillRender(_ waveformView: FDWaveformView) {}
  func waveformViewWillLoad(_ waveformView: FDWaveformView) {}
  func waveformViewDidLoad(_ waveformView: FDWaveformView) {}
  func waveformViewDidRender(_ waveformView: FDWaveformView) {
    UIView.animate(withDuration: 0.25, animations: {() -> Void in
      waveformView.alpha = 1.0
    })
  }
}
