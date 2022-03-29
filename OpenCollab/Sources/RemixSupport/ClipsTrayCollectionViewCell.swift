// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import UIKit

class ClipsTrayCollectionViewCell: UICollectionViewCell {
  struct Constants {
    static let cellCornerRadius: CGFloat = 6
    static let dimOverlayAlpha: CGFloat = 0.5
    static let takeLabelHeight: CGFloat = 30.0
    static let takeLabelInset: CGFloat = 3.0
  }

  private let overlay = UIView()
  private var clipImageView: UIImageView = UIImageView()
  private let gradientLayer: CAGradientLayer = {
    let gradientLayer = CAGradientLayer()
    gradientLayer.colors = [UIColor(rgb: 0xC365EF).cgColor, UIColor(rgb: 0x3F27D3).cgColor]
    gradientLayer.startPoint = CGPoint(x: 1.0, y: 0.0)
    gradientLayer.endPoint = CGPoint(x: 0.0, y: 1.0)
    gradientLayer.locations = [0.00, 1.25]
    return gradientLayer
  }()
  private var slideView: SlideView?
  private let takeLabel = FragmentLabelView()
  override var isSelected: Bool {
    didSet {
      self.contentView.layer.borderWidth = isSelected ? 3 : 2
      self.contentView.layer.borderColor = isSelected ? UIColor.white.cgColor : UIColor(rgb: 0xFBFBFB, a: 0.25).cgColor
    }
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    commonInit()
  }

  required init?(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
    commonInit()
  }

  func commonInit() {
    self.backgroundColor = .clear

    gradientLayer.frame = self.bounds
    clipImageView.layer.addSublayer(gradientLayer)

    self.addSubview(self.clipImageView)
    clipImageView.frame = self.bounds
    clipImageView.layer.cornerRadius = Constants.cellCornerRadius
    clipImageView.layer.masksToBounds = true
    clipImageView.clipsToBounds = true
    clipImageView.contentMode = .scaleAspectFill

    setupTakeLabel()

    overlay.frame = self.bounds
    overlay.backgroundColor = .black
    self.addSubview(overlay)

    self.contentView.layer.borderWidth = isSelected ? 3 : 2
    self.contentView.layer.cornerRadius = Constants.cellCornerRadius
    self.contentView.layer.borderColor = isSelected ? UIColor.white.cgColor : UIColor(rgb: 0xFBFBFB, a: 0.25).cgColor
    self.contentView.layer.masksToBounds = true
    self.contentView.clipsToBounds = true
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    self.slideView = nil
    self.clipImageView.image = nil
    self.takeLabel.takeNumber = ""
    self.takeLabel.alpha = 0.0
  }

  // MARK: - Configuration

  func configureCell(slide: SlideView, enabled: Bool) {
    self.slideView = slide
    DispatchQueue.main.async { // image setting must be on main queue
      self.loadThumbnailForSlide(slide)
      if let takeNumber = self.slideView?.takeNumber {
        self.takeLabel.takeNumber = takeNumber.description
        self.takeLabel.alpha = 1.0
      }
      self.overlay.alpha = enabled ? 0 : Constants.dimOverlayAlpha
      self.contentView.layer.borderWidth = enabled ? (self.isSelected ? 3 : 2) : 0
    }
  }

  // MARK: - Private helpers
  fileprivate func loadThumbnailForSlide(_ slide: SlideView) {
    gradientLayer.removeFromSuperlayer()
    if let image = slide.thumbnailImage {
      self.clipImageView.image = image.image
    } else if let thumbnailURL = slide.thumbnailURL {
      self.clipImageView.kf.setImage(with: URL(string: thumbnailURL))
    }
  }

  fileprivate func setupTakeLabel() {
    takeLabel.takeNumber = ""
    takeLabel.prefix = ""
    takeLabel.alpha = 0.0
    takeLabel.translatesAutoresizingMaskIntoConstraints = false

    self.addSubview(self.takeLabel)

    NSLayoutConstraint.activate([
      takeLabel.heightAnchor.constraint(equalToConstant: Constants.takeLabelHeight),
      takeLabel.rightAnchor.constraint(equalTo: self.rightAnchor,
                                       constant: -Constants.takeLabelInset),
      takeLabel.topAnchor.constraint(equalTo: self.topAnchor,
                                     constant: Constants.takeLabelInset)
    ])
  }
}
