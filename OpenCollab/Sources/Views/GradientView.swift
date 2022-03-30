// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import UIKit

class GradientView: UIView {

  var gradientLayer: CAGradientLayer {
    return self.layer as! CAGradientLayer // swiftlint:disable:this force_cast
  }

  override class var layerClass: AnyClass {
    return CAGradientLayer.self
  }
}
