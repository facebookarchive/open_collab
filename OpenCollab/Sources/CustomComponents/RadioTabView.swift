// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import UIKit

class RadioTabView: UIView {
  var title: String?
  var isActive = false {
    didSet {
      buttonView.isSelected = isActive
    }
  }
  let buttonView: UIButton = {
    let button = UIButton()
    button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .bold)
    button.setTitleColor(.white, for: .normal)
    button.setTitleColor(.black, for: .selected)
    button.setBackgroundColor(.black, for: .normal)
    button.setBackgroundColor(.white.withAlphaComponent(0.5), for: .selected)
    button.layer.masksToBounds = true
    button.isUserInteractionEnabled = false
    button.isSelected = false
    return button
  }()

  init(title: String) {
    self.title = title
    super.init(frame: .zero)

    self.backgroundColor = .clear
    buttonView.setTitle(self.title, for: .normal)
    buttonView.setTitle(self.title, for: .selected)
    self.addSubview(buttonView)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    buttonView.layer.cornerRadius = self.frame.height / 2
    buttonView.frame = self.bounds
  }
}
