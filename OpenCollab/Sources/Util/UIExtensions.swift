// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import UIKit
// import CoreMedia

extension UIImage {
  convenience init?(color: UIColor, size: CGSize = CGSize(width: 1, height: 1)) {
    let rect = CGRect(origin: .zero, size: size)
    UIGraphicsBeginImageContextWithOptions(rect.size, false, 0.0)
    color.setFill()
    UIRectFill(rect)
    let image = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()

    guard let cgImage = image?.cgImage else { return nil }
    self.init(cgImage: cgImage)
  }

  func translucentImageWithAlpha(alpha: CGFloat) -> UIImage {

    UIGraphicsBeginImageContextWithOptions(self.size, false, 0.0)
    let bounds = CGRect(x: 0, y: 0, width: self.size.width, height: self.size.height)
    self.draw(in: bounds, blendMode: .screen, alpha: alpha)

    let translucentImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()

    return translucentImage! // swiftlint:disable:this force_unwrapping
  }
}

extension UIColor {
  convenience init(red: Int, green: Int, blue: Int, a: CGFloat = 1.0) {
    self.init(
      red: CGFloat(red) / 255.0,
      green: CGFloat(green) / 255.0,
      blue: CGFloat(blue) / 255.0,
      alpha: a
    )
  }

  convenience init(rgb: Int, a: CGFloat = 1.0) {
    self.init(
      red: (rgb >> 16) & 0xFF,
      green: (rgb >> 8) & 0xFF,
      blue: rgb & 0xFF,
      a: a
    )
  }
}

// Declare a global var to produce a unique address as the assoc object handle
var highlightedColorHandle: UInt8 = 0
extension UIButton {

  func setBackgroundColor(_ color: UIColor, for state: UIControl.State) {
    self.setBackgroundImage(UIImage(color: color), for: state)
  }

  func setBackgroundGradient(for state: UIControl.State) {
    let gradientLayer = CAGradientLayer()
    gradientLayer.frame = self.frame
    gradientLayer.setupButtonCollabGradientLayer()

    UIGraphicsBeginImageContext(CGSize(width: self.frame.width, height: self.frame.height))
    if let context = UIGraphicsGetCurrentContext() {
      gradientLayer.render(in: context)
      let gradientImage = UIGraphicsGetImageFromCurrentImageContext()
      UIGraphicsEndImageContext()
      self.setBackgroundImage(gradientImage, for: state)
      self.clipsToBounds = true
    }
  }

  @IBInspectable
  var highlightedColor: UIColor? {
    get {
      if let color = objc_getAssociatedObject(self, &highlightedColorHandle) as? UIColor {
        return color
      }
      return nil
    }
    set {
      if let color = newValue {
        self.setBackgroundColor(color, for: .highlighted)
        objc_setAssociatedObject(self, &highlightedColorHandle, color, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
      } else {
        self.setBackgroundImage(nil, for: .highlighted)
        objc_setAssociatedObject(self, &highlightedColorHandle, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
      }
    }
  }
}

extension CAGradientLayer {
  func setupFullScreenCollabGradientLayer() {
    self.colors = CollabColors.fullScreenGradientBackgroundColors
    self.locations = CollabColors.fullScreenGradientBackgroundLocations
    self.startPoint = CollabColors.fullScreenGradientBackgroundStartPosition
    self.endPoint = CollabColors.fullScreenGradientBackgroundEndPosition
  }

  func setupButtonCollabGradientLayer() {
    self.colors = CollabColors.buttonGradientColors
    self.locations = CollabColors.buttonGradientLocations
    self.startPoint = CollabColors.buttonGradientStartPosition
    self.endPoint = CollabColors.buttonGradientEndPosition
  }
}
