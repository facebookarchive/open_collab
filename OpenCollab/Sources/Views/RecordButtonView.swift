// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import UIKit
import Foundation
import CoreGraphics

class RecordButtonView: UIView {

  // MARK: - Properties

  var state: RecordButtonView.State = .notRecording {
    didSet {
      if oldValue != state {
        UIView.animate(withDuration: Constants.interimAnimationDuration) {
          self.updateUI()
        }
      }
    }
  }

  fileprivate let gradientView = GradientView()
  fileprivate let rotationLayer = CALayer()
  fileprivate let rotationGradientView = GradientView()

  // MARK: - Init

  override init(frame: CGRect) {
    super.init(frame: frame)

    clipsToBounds = true
    layer.cornerRadius = frame.width / 2.0

    layer.addSublayer(rotationLayer)

    gradientView.frame = bounds.insetBy(dx: Constants.gradientDelta,
                                        dy: Constants.gradientDelta)
    gradientView.gradientLayer.colors = Constants.gradientColors
    gradientView.gradientLayer.locations = Constants.gradientLocations
    gradientView.gradientLayer.startPoint = Constants.gradientStartPosition
    gradientView.gradientLayer.endPoint = Constants.gradientEndPosition
    gradientView.clipsToBounds = true
    gradientView.layer.borderWidth = Constants.gradientBorderWidth
    gradientView.layer.borderColor = UIColor.black.cgColor
    addSubview(gradientView)

    let path = UIBezierPath()
    path.addArc(withCenter: CGPoint(x: bounds.midX, y: bounds.midY),
                radius: bounds.width / 2.0 - Constants.gradientBorderWidth,
                startAngle: 0,
                endAngle: Constants.gradientArcEndAngle,
                clockwise: true)
    let shapeLayer = CAShapeLayer()
    shapeLayer.path = path.cgPath
    shapeLayer.strokeColor = UIColor.white.cgColor
    shapeLayer.fillColor = UIColor.clear.cgColor
    shapeLayer.lineWidth = Constants.gradientDelta
    rotationGradientView.gradientLayer.colors = Constants.gradientColors
    rotationGradientView.gradientLayer.locations = Constants.gradientLocations
    rotationGradientView.gradientLayer.startPoint = Constants.gradientStartPosition
    rotationGradientView.gradientLayer.endPoint = Constants.gradientEndPosition

    addSubview(rotationGradientView)
    rotationGradientView.layer.mask = rotationLayer
    rotationLayer.addSublayer(shapeLayer)

    updateUI()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - UIView

  override func layoutSubviews() {
    super.layoutSubviews()

    layer.cornerRadius = frame.width / 2.0
    rotationLayer.frame = bounds
    rotationGradientView.frame = bounds
    if gradientView.transform.isIdentity {
      gradientView.frame = bounds.insetBy(dx: Constants.gradientDelta,
                                          dy: Constants.gradientDelta)
    }
  }

  // MARK: - State Change Helpers

  fileprivate func updateUI() {
    switch state {
    case .notRecording:
      stopAnimating()
      layer.borderWidth = Constants.gradientDelta
      layer.borderColor = Constants.borderColor.cgColor
      rotationLayer.opacity = 0.0
      gradientView.transform = .identity
      gradientView.alpha = 1.0
      gradientView.layer.cornerRadius = gradientView.bounds.width / 2.0
    case .waitingToRecord:
      layer.borderWidth = Constants.gradientDelta
      layer.borderColor = Constants.borderColor.cgColor
      rotationLayer.opacity = 0.0
      gradientView.layer.cornerRadius = Constants.gradientDelta
      gradientView.transform = CGAffineTransform(scaleX: Constants.recordingScaleFactor,
                                                 y: Constants.recordingScaleFactor)

      UIView.animate(withDuration: Constants.interimAnimationDuration,
                     delay: Constants.interimAnimationDuration,
                     options: [], animations: { self.gradientView.alpha = 1.0 }, completion: nil)
    case .recording:
      layer.borderWidth = 0
      rotationLayer.opacity = 1.0
      gradientView.layer.cornerRadius = Constants.gradientDelta
      gradientView.transform = CGAffineTransform(scaleX: Constants.recordingScaleFactor,
                                                 y: Constants.recordingScaleFactor)

      UIView.animate(withDuration: Constants.interimAnimationDuration,
                     delay: Constants.interimAnimationDuration,
                     options: [], animations: { self.gradientView.alpha = 1.0 }, completion: nil)
      startAnimating()
    }
  }

  // MARK: - Touch Handling

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
      self.gradientView.alpha = alpha
    }
  }
}

// MARK: - Types

extension RecordButtonView {
  enum State {
    case notRecording, waitingToRecord, recording
  }

  enum Constants {
    static let gradientColors: [Any] = [
      UIColor(red: 0.929, green: 0.345, blue: 0.294, alpha: 1).cgColor,
      UIColor(red: 0.71, green: 0.318, blue: 0.644, alpha: 1).cgColor,
      UIColor(red: 0.553, green: 0.298, blue: 0.894, alpha: 1).cgColor,
      UIColor(red: 0.31, green: 0.471, blue: 0.917, alpha: 1).cgColor,
      UIColor(red: 0.169, green: 0.737, blue: 0.945, alpha: 1).cgColor
    ]
    static let gradientLocations: [NSNumber] = [0, 0.22, 0.49, 0.7, 1]
    static let gradientStartPosition = CGPoint(x: 1.0, y: 0.0)
    static let gradientEndPosition = CGPoint(x: 0, y: 1)
    static let touchAlpha: CGFloat = 0.7
    static let touchAnimationDuration: TimeInterval = 0.1
    static let animationName = "rotationAnimation"
    static let remixAnimationDuration: TimeInterval = 2.5
    static let rotateAnimationKeyTimes: [NSNumber] = [0, 1]
    static let rotateAnimationKeyValues: [Any] = [0, 2 * CGFloat.pi]
    static let gradientDelta: CGFloat = 6.0
    static let gradientBorderWidth: CGFloat = 3.0
    static let gradientArcEndAngle: CGFloat = 2 * CGFloat.pi * 0.34
    static let borderColor = UIColor(red: 0.983, green: 0.983, blue: 0.983, alpha: 0.5)
    static let inactiveAlpha: CGFloat = 0.5
    static let recordingScaleFactor: CGFloat = 0.6
    static let interimAnimationDuration: TimeInterval = 0.2
  }
}

// MARK: - Animation

extension RecordButtonView {
  func startAnimating() {
    guard rotationLayer.animation(forKey: Constants.animationName) == nil else { return }
    let rotate = CAKeyframeAnimation(keyPath: "transform.rotation")
    rotate.timingFunction = CAMediaTimingFunction(name: .linear)
    rotate.calculationMode = .linear
    rotate.values = Constants.rotateAnimationKeyValues
    rotate.keyTimes = Constants.rotateAnimationKeyTimes
    rotate.duration = Constants.remixAnimationDuration
    rotate.repeatCount = .infinity
    rotationLayer.add(rotate, forKey: Constants.animationName)
  }

  func stopAnimating() {
    rotationLayer.removeAnimation(forKey: Constants.animationName)
  }
}
