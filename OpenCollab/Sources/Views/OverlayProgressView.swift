// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import Foundation

class OverlayProgressView: UIView {

  var overlay: UIView = {
    let view = UIView()
    view.backgroundColor = .white
    view.alpha = Constants.overlayMaxAlpha
    return view
  }()

  fileprivate lazy var progressBarGradientView: GradientView = {
    let gradientView = GradientView()
    gradientView.gradientLayer.colors = Constants.gradientColors
    gradientView.gradientLayer.locations = Constants.gradientLocations
    gradientView.gradientLayer.startPoint = Constants.gradientStartPosition
    gradientView.gradientLayer.endPoint = Constants.gradientEndPosition
    gradientView.clipsToBounds = true
    gradientView.layer.cornerRadius = Constants.radius
    return gradientView
  }()

  // MARK: - UIView

  override init(frame: CGRect) {
    super.init(frame: frame)

    self.clipsToBounds = true
    self.backgroundColor = .clear
    self.addSubview(overlay)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    overlay.frame = self.bounds
  }

  // MARK: - Public

  func startProgress() {
    setupProgressBar()

    overlay.alpha = Constants.overlayMaxAlpha
    UIView.animate(withDuration: Constants.animationDuration,
                   delay: 0.0,
                   options: [.curveEaseInOut],
                   animations: {
                    self.progressBarGradientView.transform = .identity
    }, completion: nil)
  }

  func completeProgress(completion: (() -> Void)? = nil) {
    self.progressBarGradientView.layer.removeAllAnimations()

    UIView.animate(withDuration: Constants.animationCompleteDuration, animations: {
      self.overlay.alpha = 0.0
      self.progressBarGradientView.transform = .identity
    }) { (_) in
      self.progressBarGradientView.removeFromSuperview()
      completion?()
    }
  }

  // MARK: - Helper

  fileprivate func setupProgressBar() {
    guard progressBarGradientView.superview == nil else {
      return
    }
    progressBarGradientView.translatesAutoresizingMaskIntoConstraints = false
    self.addSubview(progressBarGradientView)

    NSLayoutConstraint.activate([
      progressBarGradientView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
      progressBarGradientView.heightAnchor.constraint(
        equalToConstant: Constants.progressBarHeight),
      progressBarGradientView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
      progressBarGradientView.leadingAnchor.constraint(equalTo: self.leadingAnchor)
    ])
    progressBarGradientView.transform = CGAffineTransform(translationX: -self.bounds.width, y: 0.0)
  }
}

// MARK: - Constants

extension OverlayProgressView {
  fileprivate struct Constants {
    static let radius: CGFloat = 2.0
    static let overlayMaxAlpha: CGFloat = 0.6
    static let progressBarHeight: CGFloat = 6.0
    static let animationDuration: TimeInterval = 5.0
    static let animationCompleteDuration: TimeInterval = 0.6
    static let gradientColors: [Any] = [
      UIColor(red: 0.929, green: 0.345, blue: 0.294, alpha: 1).cgColor,
      UIColor(red: 0.71, green: 0.318, blue: 0.644, alpha: 1).cgColor,
      UIColor(red: 0.553, green: 0.298, blue: 0.894, alpha: 1).cgColor,
      UIColor(red: 0.31, green: 0.471, blue: 0.917, alpha: 1).cgColor,
      UIColor(red: 0.169, green: 0.737, blue: 0.945, alpha: 1).cgColor
    ]
    static let gradientLocations: [NSNumber] = [0, 0.32, 0.49, 0.8, 1]
    static let gradientStartPosition = CGPoint(x: 0, y: 0.5)
    static let gradientEndPosition = CGPoint(x: 1, y: 0.5)
    static let errorSize: CGFloat = 300.0
  }
}
