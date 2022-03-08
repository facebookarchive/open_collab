// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import UIKit

class CollabColors {
  static let buttonGradientColors: [Any] = [
    UIColor(red: 235, green: 97, blue: 208).cgColor, // Pink
    UIColor(red: 49, green: 115, blue: 229).cgColor, // Blue
    UIColor(red: 108, green: 233, blue: 172).cgColor // Green
  ]
  static let buttonGradientLocations: [NSNumber] = [0, 0.8, 1]
  static let buttonGradientStartPosition = CGPoint(x: 0, y: 0.4)
  static let buttonGradientEndPosition = CGPoint(x: 1.0, y: 0.8)

  static let fullScreenGradientBackgroundColors: [Any] = [
    UIColor(red: 0.169, green: 0.737, blue: 0.945, alpha: 1).cgColor,
    UIColor(red: 0.31, green: 0.471, blue: 0.917, alpha: 1).cgColor,
    UIColor(red: 0.553, green: 0.298, blue: 0.894, alpha: 1).cgColor,
    UIColor(red: 0.71, green: 0.318, blue: 0.644, alpha: 1).cgColor
  ]
  static let fullScreenGradientBackgroundLocations: [NSNumber] = [0, 0.22, 0.5, 1]
  static let fullScreenGradientBackgroundStartPosition = CGPoint(x: 0.5, y: 1.0)
  static let fullScreenGradientBackgroundEndPosition = CGPoint(x: 0.5, y: 0)
}
