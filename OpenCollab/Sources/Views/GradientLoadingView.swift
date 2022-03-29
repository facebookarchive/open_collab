// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import UIKit

class GradientLoadingView: UIView {

  fileprivate enum Constants {
    static let animationDuration: TimeInterval = 0.7
    static let gradientColors: [CGColor] = [
      UIColor(red: 0.929, green: 0.345, blue: 0.294, alpha: 1).cgColor,
      UIColor(red: 0.71, green: 0.318, blue: 0.644, alpha: 1).cgColor,
      UIColor(red: 0.553, green: 0.298, blue: 0.894, alpha: 1).cgColor,
      UIColor(red: 0.31, green: 0.471, blue: 0.917, alpha: 1).cgColor
    ]
    static let gradientStartPosition = CGPoint.zero
    static let gradientEndPosition = CGPoint(x: 1, y: 1)
  }

  fileprivate var gradientSet = [[CGColor]]()
  fileprivate var currentGradient: Int = 0

  override init(frame: CGRect) {
    super.init(frame: frame)

    for i in 0..<Constants.gradientColors.count - 1 {
      gradientSet.append([Constants.gradientColors[i], Constants.gradientColors[i + 1]])
    }
    currentGradient = Int(arc4random()) % gradientSet.count

    gradient.colors = gradientSet[currentGradient]
    gradient.startPoint = Constants.gradientStartPosition
    gradient.endPoint = Constants.gradientEndPosition
    gradient.drawsAsynchronously = true
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func animateGradient() {
    currentGradient = (currentGradient + 1) % gradientSet.count

    let gradientChangeAnimation = CABasicAnimation(keyPath: "colors")
    gradientChangeAnimation.duration = Constants.animationDuration
    gradientChangeAnimation.toValue = gradientSet[currentGradient]
    gradientChangeAnimation.fillMode = CAMediaTimingFillMode.forwards
    gradientChangeAnimation.isRemovedOnCompletion = false
    gradientChangeAnimation.delegate = self
    gradient.add(gradientChangeAnimation, forKey: "colorChange")
  }

  func stopAnimation() {
    gradient.removeAllAnimations()
  }

  var gradient: CAGradientLayer {
    return self.layer as! CAGradientLayer
  }

  override class var layerClass: AnyClass {
    return CAGradientLayer.self
  }
}

extension GradientLoadingView: CAAnimationDelegate {
  func animationDidStop(_ animation: CAAnimation, finished flag: Bool) {
    if flag {
      gradient.colors = gradientSet[currentGradient]
      animateGradient()
    }
  }
}
