// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import UIKit

class FragmentLabelView: UIView {
  private struct Constants {
    static let font: UIFont = .systemFont(ofSize: 13.0, weight: UIFont.Weight.bold)
    static let fontColor = UIColor(rgb: 0xFFFFFF)
    static let alpha: CGFloat = 0.2
    static let cornerRadius: CGFloat = 2
    static let edgeInsets = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
  }

  var takeNumber: String = "" {
    didSet {
      fragmentLabel.text = prefix + takeNumber
    }
  }

  var prefix: String = "TAKE " {
    didSet {
      fragmentLabel.text = prefix + takeNumber
    }
  }

  private let fragmentLabel: UITextView = {
    let view = UITextView()

    view.backgroundColor = UIColor.black.withAlphaComponent(Constants.alpha)
    view.textAlignment = .center
    view.font = Constants.font
    view.textColor = Constants.fontColor
    view.isUserInteractionEnabled = false
    view.isScrollEnabled = false
    view.textContainerInset = Constants.edgeInsets
    view.layer.cornerRadius = Constants.cornerRadius

    view.translatesAutoresizingMaskIntoConstraints = false

    return view
  }()

  // MARK: - Init

  init() {
    super.init(frame: .zero)

    prefix = ""
    self.addSubview(fragmentLabel)

    NSLayoutConstraint.activate([
      fragmentLabel.widthAnchor.constraint(equalTo: self.widthAnchor),
      fragmentLabel.heightAnchor.constraint(equalTo: self.heightAnchor)
    ])
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    fragmentLabel.text = prefix + takeNumber
    let widthOfString = fragmentLabel.text.size(withAttributes: [.font: Constants.font]).width
    if widthOfString > frame.size.width - Constants.edgeInsets.left - Constants.edgeInsets.right {
      fragmentLabel.text = takeNumber
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
