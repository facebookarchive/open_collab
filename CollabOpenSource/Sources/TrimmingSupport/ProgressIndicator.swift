// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import UIKit

class ProgressIndicator: UIView {

  var progressIndicatorView: UIView = {
    let view = UIView()
    view.backgroundColor = .white
    view.layer.cornerRadius = 2
    view.layer.shadowColor = UIColor.black.cgColor
    view.layer.shadowRadius = 4
    view.layer.shadowOpacity = 0.25
    view.isUserInteractionEnabled = true
    return view
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)

    progressIndicatorView.frame = self.bounds
    progressIndicatorView.contentMode = UIView.ContentMode.scaleToFill
    self.addSubview(progressIndicatorView)
  }

  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    progressIndicatorView.frame = self.bounds
  }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let buffer: CGFloat = 15.0
    // buffer on right side is 2x to make up for distance traveled (or perceived) by the right-movement of the indicator
    let frame = CGRect(x: -buffer,
                       y: 0,
                       width: self.frame.size.width + 2 * buffer,
                       height: self.frame.size.height)
    if frame.contains(point) {
        return self
    } else {
        return nil
    }
  }
}
