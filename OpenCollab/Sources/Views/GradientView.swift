// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import UIKit

class GradientView: UIView {

  var gradientLayer: CAGradientLayer {
    return self.layer as! CAGradientLayer
  }

  override class var layerClass: AnyClass {
    return CAGradientLayer.self
  }
}
