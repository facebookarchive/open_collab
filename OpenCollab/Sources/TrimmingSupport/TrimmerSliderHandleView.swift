// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import UIKit

class TrimmerSliderHandleView: UIView {

  enum DragType {
    case leading, center, trailing
  }

  struct Constants {
    static let handleCornerRadius: CGFloat = 4
  }

  static let trimmerBorderSize: CGFloat = 4
  // TODO : Calculations offseting by the handle width leaks into a handful of controllers.
  // it would be great if we could isolate accounting for the handle width into just TrimmerSliderHandleView.
  static let trimmerHandleWidth: CGFloat = 17
  static let handleOffset: CGFloat = 2 * trimmerHandleWidth

  // MARK: - Props

  var isDragging: ((_ type: DragType) -> Void)?
  var dragEnded: ((_ type: DragType) -> Void)?
  var dragStarted: ((_ type: DragType) -> Void)?

  let leftHandle: UIView = {
    let view = UIView()
    view.backgroundColor = .purple
    view.layer.cornerRadius = Constants.handleCornerRadius
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()
  let rightHandle: UIView = {
    let view = UIView()
    view.backgroundColor = .purple
    view.layer.cornerRadius = Constants.handleCornerRadius
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()
  let leftHandleImage: UIView = {
    let label = UILabel()
    label.text = "|"
    label.textColor = .white
    label.font = .systemFont(ofSize: 18.0, weight: .bold)
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()
  let rightHandleImage: UILabel = {
    let label = UILabel()
    label.text = "|"
    label.textColor = .white
    label.font = .systemFont(ofSize: 18.0, weight: .bold)
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()
  fileprivate let impact = UIImpactFeedbackGenerator()
  var centerTouchAllowed = true

  // MARK: - Init

  init(precisionTrim: Bool = false) {
    super.init(frame: .zero)
    self.layer.borderColor = UIColor.purple.cgColor
    self.layer.borderWidth = TrimmerSliderHandleView.trimmerBorderSize
    self.layer.cornerRadius = 4
    self.backgroundColor = .clear

    if precisionTrim {
      leftHandleImage.alpha = 0.3
      rightHandleImage.alpha = 0.3
    }
    leftHandle.addSubview(leftHandleImage)
    rightHandle.addSubview(rightHandleImage)
    self.addSubview(leftHandle)
    self.addSubview(rightHandle)

    NSLayoutConstraint.activate([
      leftHandle.topAnchor.constraint(equalTo: self.topAnchor),
      leftHandle.bottomAnchor.constraint(equalTo: self.bottomAnchor),
      leftHandle.leadingAnchor.constraint(equalTo: self.leadingAnchor),
      leftHandle.widthAnchor.constraint(equalToConstant: TrimmerSliderHandleView.trimmerHandleWidth),
      leftHandleImage.centerXAnchor.constraint(equalTo: leftHandle.centerXAnchor),
      leftHandleImage.centerYAnchor.constraint(equalTo: leftHandle.centerYAnchor),

      rightHandle.topAnchor.constraint(equalTo: self.topAnchor),
      rightHandle.bottomAnchor.constraint(equalTo: self.bottomAnchor),
      rightHandle.trailingAnchor.constraint(equalTo: self.trailingAnchor),
      rightHandle.widthAnchor.constraint(equalToConstant: TrimmerSliderHandleView.trimmerHandleWidth),
      rightHandleImage.centerXAnchor.constraint(equalTo: rightHandle.centerXAnchor),
      rightHandleImage.centerYAnchor.constraint(equalTo: rightHandle.centerYAnchor)
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: Public functions

  func setTrimConstraints(minPercent: Float64, maxPercent: Float64) {
    minTrimPercent = minPercent
    maxTrimPercent = maxPercent
  }

  func setColor(color: UIColor) {
    leftHandle.backgroundColor = color
    rightHandle.backgroundColor = color
    self.layer.borderColor = color.cgColor
  }

  // MARK: - Touch Handling

  var dragType: DragType = .center
  private var minTrimPercent: Float64 = 0
  private var maxTrimPercent: Float64 = 1.0
  private var minScrubberWidth: CGFloat {
    guard let superview = self.superview else { return .zero }
    return CGFloat((Float64(superview.frame.width - TrimmerSliderHandleView.handleOffset))
                    * minTrimPercent)
  }
  private var maxScrubberWidth: CGFloat {
    guard let superview = self.superview else { return .zero }
    return CGFloat((Float64(superview.frame.width - TrimmerSliderHandleView.handleOffset))
                    * maxTrimPercent)
  }
  private var originalThumbViewFrame = CGRect.zero
  private var originalPositionSelf = CGPoint.zero
  private var originalPositionSuper = CGPoint.zero

  private func setWidth(width: CGFloat) {
    // Sanity check that the width is always within the bounds.
    let totalMinWidth = minScrubberWidth + TrimmerSliderHandleView.handleOffset
    let totalMaxWidth = maxScrubberWidth + TrimmerSliderHandleView.handleOffset
    self.frame.size.width = min(max(width, totalMinWidth), totalMaxWidth)
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIKit.UIEvent?) {
    guard let touch = touches.first, let superview = self.superview else { return }
    var leadingHandleMaxX = self.bounds.origin.x + TrimmerSliderHandleView.trimmerHandleWidth
    var trailingHandleXOrigin = self.bounds.width - TrimmerSliderHandleView.trimmerHandleWidth

    // Don't expand the tap area if the handles are already close together
    let easierTouchBuffer: CGFloat = trailingHandleXOrigin - leadingHandleMaxX < 40 ? 0.0 : 20

    leadingHandleMaxX += easierTouchBuffer
    trailingHandleXOrigin -= easierTouchBuffer

    originalPositionSelf = touch.location(in: self)
    originalPositionSuper = touch.location(in: superview)
    originalThumbViewFrame = self.frame

    switch originalPositionSelf.x {
    case (trailingHandleXOrigin..<CGFloat.greatestFiniteMagnitude):
      dragType = .trailing
    case (leadingHandleMaxX..<trailingHandleXOrigin):
      dragType = .center
    default:
      dragType = .leading
    }

    dragStarted?(dragType)
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIKit.UIEvent?) {
    guard let touch = touches.first, let superview = self.superview else { return }
    let locationSuper = touch.location(in: superview)
    switch dragType {
    case .leading:
      let originalOriginX = originalThumbViewFrame.origin.x
      let originalTrailing = originalThumbViewFrame.maxX
      let minPos = floor(max(0 + TrimmerSliderHandleView.trimmerHandleWidth, originalTrailing - TrimmerSliderHandleView.trimmerHandleWidth - maxScrubberWidth))
      let maxPos = originalTrailing - TrimmerSliderHandleView.trimmerHandleWidth - minScrubberWidth

      let delta = locationSuper.x - originalPositionSuper.x
      let leadingPosition = originalOriginX + TrimmerSliderHandleView.trimmerHandleWidth + delta

      let xPosition = leadingPosition.clamped(minPos...maxPos)

      // Haptic feedback if clamping occurred.
      if xPosition == minPos || xPosition == maxPos {
        impact.impactOccurred()
      }

      self.frame.origin.x = xPosition - TrimmerSliderHandleView.trimmerHandleWidth
      setWidth(width: originalTrailing - xPosition + TrimmerSliderHandleView.trimmerHandleWidth)
    case .center:
      guard (superview.bounds.width - self.bounds.width) >= 0 else {
        print("Tried to drag trimmer but range is not valid")
        return
      }
      guard centerTouchAllowed else { return }
      let xPosition = (locationSuper.x - originalPositionSelf.x).clamped(0...(superview.bounds.width - self.bounds.width))
      self.frame.origin.x = xPosition
    case .trailing:
      let originalOriginX = originalThumbViewFrame.origin.x
      let maxPos = min(originalOriginX + TrimmerSliderHandleView.trimmerHandleWidth + maxScrubberWidth,
                       superview.frame.width - TrimmerSliderHandleView.trimmerHandleWidth)
      let minPos = min(maxPos, originalOriginX + TrimmerSliderHandleView.trimmerHandleWidth + minScrubberWidth)

      let delta = locationSuper.x - originalPositionSuper.x
      let trailingPosition = originalThumbViewFrame.maxX - TrimmerSliderHandleView.trimmerHandleWidth + delta

      let xPosition = trailingPosition.clamped(minPos...maxPos)

      // Haptic feedback if clamping occurred.
      if xPosition == minPos || xPosition == maxPos {
        impact.impactOccurred()
      }

      setWidth(width: xPosition - originalThumbViewFrame.origin.x + TrimmerSliderHandleView.trimmerHandleWidth)
    }

    isDragging?(dragType)
    self.setNeedsDisplay()
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIKit.UIEvent?) {
    dragEnded?(dragType)
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIKit.UIEvent?) {
    dragEnded?(dragType)
  }

  // MARK: - Hit Testing

  private func pointInsideModifiedHitRegion(point: CGPoint) -> Bool {
    let adjustedHitTestInsets = UIEdgeInsets(top: 0, left: -30, bottom: 0, right: -30)
    let hitFrame = self.bounds.inset(by: adjustedHitTestInsets)
    return hitFrame.contains(point)
  }

  override func point(inside point: CGPoint, with event: UIKit.UIEvent?) -> Bool {
    return pointInsideModifiedHitRegion(point: point)
  }

  // MARK: - Drawing

  override func draw(_ rect: CGRect) {
    super.draw(rect)
  }
}

extension Comparable {
  @inlinable func clamped(_ lower: Self, _ upper: Self) -> Self {
    return max(min(self, upper), lower)
  }
  @inlinable func clamped(_ range: ClosedRange<Self>) -> Self {
    return max(min(self, range.upperBound), range.lowerBound)
  }
}
