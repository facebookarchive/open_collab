// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import UIKit

class DimOverlayView: UIView {
  let initialView: UIView
  let ommittedLocation: CGRect
  let completion: (() -> Void)?

  struct Constants {
    static let dimOverlayColor: UIColor = UIColor(rgb: 0x181818)
    static let dimOverlayAlpha: Float = 0.8 // 0.3
    static let pixelBuffer: CGFloat = 2.0 // Make up for minor cutoffs
  }

  private let dimBackgroundLayer: CAShapeLayer = {
    let fillLayer = CAShapeLayer()
    fillLayer.fillRule = .evenOdd
    fillLayer.fillColor = Constants.dimOverlayColor.cgColor
    fillLayer.opacity = Constants.dimOverlayAlpha
    return fillLayer
  }()

  init(initialView: UIView, ommittedLocation: CGRect, completion: (() -> Void)? = nil) {
    self.initialView = initialView
    self.ommittedLocation = ommittedLocation
    self.completion = completion

    super.init(frame: initialView.bounds)
    setupTapToDismiss()

    dimBackgroundLayer.frame = initialView.bounds
    dimBackgroundLayer.path = createLayerHole(location: ommittedLocation).cgPath
    self.layer.addSublayer(dimBackgroundLayer)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupTapToDismiss() {
    let tap = UILongPressGestureRecognizer(target: self, action: #selector(self.didTapBackground(_:)))
    tap.minimumPressDuration = 0
    self.addGestureRecognizer(tap)
  }

  @objc
  private func didTapBackground(_ sender: UITapGestureRecognizer) {
    completion?()
  }

  private func createLayerHole(location: CGRect) -> UIBezierPath { // creates rectangular holes
    let path = UIBezierPath(roundedRect: self.bounds, cornerRadius: 0)
    let rectPath = UIBezierPath(rect: CGRect(x: location.minX, y: location.minY, width: location.size.width + Constants.pixelBuffer, height: location.size.height + Constants.pixelBuffer))
    path.append(rectPath)
    path.usesEvenOddFillRule = true
    return path
  }
}
