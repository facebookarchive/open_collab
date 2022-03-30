// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import UIKit

class SpinnerView: UIView {

  private enum Constants {
    static let touchAlpha: CGFloat = 0.6
    static let touchAnimationDuration: TimeInterval = 0.1
    static let cornerRadiusRatio: CGFloat = 0.18
    static let borderWidth: CGFloat = 3.0
    static let arcEndAngle: CGFloat = 2 * CGFloat.pi * 0.7
    static let lineWidth: CGFloat = 6.0
    static let animationName = "rotationAnimation"
    static let remixAnimationDuration: TimeInterval = 2
    static let rotateAnimationKeyTimes: [NSNumber] = [0, 1]
    static let rotateAnimationKeyValues: [Any] = [0, 2 * CGFloat.pi]
  }

  fileprivate let shapeLayer = CAShapeLayer()

  // MARK: - Init

  static func withDefaultSize() -> SpinnerView {
    return withSize(size: 60.0)
  }

  static func withSize(size: CGFloat,
                       color: UIColor = .black,
                       gradientDelta: CGFloat = Constants.lineWidth) -> SpinnerView {
    return SpinnerView(frame: CGRect(x: 0,
                                        y: 0,
                                        width: size,
                                        height: size),
                       color: color,
                       gradientDelta: gradientDelta)
  }

  init(frame: CGRect, color: UIColor, gradientDelta: CGFloat) {
    super.init(frame: frame)

    let path = UIBezierPath()
    path.addArc(withCenter: CGPoint(x: bounds.midX, y: bounds.midY),
                radius: bounds.width / 2.0 - Constants.borderWidth,
                startAngle: 0,
                endAngle: Constants.arcEndAngle,
                clockwise: true)
    shapeLayer.path = path.cgPath
    shapeLayer.strokeColor = color.withAlphaComponent(0.5).cgColor
    shapeLayer.fillColor = UIColor.clear.cgColor
    shapeLayer.lineWidth = gradientDelta
    shapeLayer.lineCap = .round
    self.layer.addSublayer(shapeLayer)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    shapeLayer.frame = bounds
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    animateAlphaChange(Constants.touchAlpha)
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    animateAlphaChange(1.0)
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    animateAlphaChange(1.0)
  }

  fileprivate func animateAlphaChange(_ alpha: CGFloat) {
    UIView.animate(withDuration: Constants.touchAnimationDuration) {
      self.alpha = alpha
    }
  }

  // MARK: - Public

  func startAnimating() {
    guard shapeLayer.animation(forKey: Constants.animationName) == nil else { return }
    let rotate = CAKeyframeAnimation(keyPath: "transform.rotation")
    rotate.timingFunction = CAMediaTimingFunction(name: .linear)
    rotate.calculationMode = .linear
    rotate.values = Constants.rotateAnimationKeyValues
    rotate.keyTimes = Constants.rotateAnimationKeyTimes
    rotate.duration = Constants.remixAnimationDuration
    rotate.repeatCount = .infinity
    shapeLayer.add(rotate, forKey: Constants.animationName)
  }

  func stopAnimating() {
    shapeLayer.removeAnimation(forKey: Constants.animationName)
  }
}
