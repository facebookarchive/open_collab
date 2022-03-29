// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import UIKit

protocol VolumeViewControllerDelegate: NSObjectProtocol {
  func volumeChanged(volume: Float)
  func volumeChangeStarted()
  func volumeChangeEnded()
}

class VolumeViewController: UIViewController {
  private enum Constants {
    static let inactiveAlpha: CGFloat = 0.0
    static let activeAlpha: CGFloat = 0.8
    static let partialAlpha: CGFloat = 0.3
    static let panTolerance: CGFloat = 5.0
    static let heightTolerance: CGFloat = 0.6
    static let heightInset: CGFloat = 10.0
    static let volumeIndicatorWidth: CGFloat = 5
    static let volumeIndicatorTopPadding: CGFloat = 10.0
    static let volumeIndicatorRightPadding: CGFloat = 10.0
    static let volumeIndicatorBottomPadding: CGFloat = 6.0
    static let volumeIconBottomPadding: CGFloat = 10.0
    static let volumeIconRightPadding: CGFloat = 6.0
    static let volumeIconHeight: CGFloat = 14.0
    static let volumeIconWidth: CGFloat = 14.0
  }

  // MARK: - Data

  fileprivate var volume: Float
  fileprivate var volumeAdjustmentActive: Bool = true

  fileprivate let heightInset: CGFloat

  weak var delegate: VolumeViewControllerDelegate?

  // MARK: - UI

  fileprivate var volumeIndicator = UIView()
  fileprivate var volumeProgress = UIProgressView()
  fileprivate var volumeIcon = UIImageView()

  fileprivate var panGesture: UIPanGestureRecognizer?

  // MARK: - Init

  init(volume: Float, heightInset: CGFloat = .zero) {
    self.volume = volume
    self.heightInset = heightInset + Constants.heightInset
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    Fatal.safeError("init(coder:) has not been implemented")
  }

  // MARK: - UIViewController

  override func viewDidLoad() {
    super.viewDidLoad()

    setupUI()
  }

  // MARK: - Public

  public func activate() {
    panGesture?.isEnabled = true
    volumeIndicator.isHidden = false
    volumeIcon.isHidden = false
  }

  public func deactivate() {
    panGesture?.isEnabled = false
    volumeIndicator.isHidden = true
    volumeIcon.isHidden = true
  }

  // MARK: - UI Helpers

  fileprivate func setupUI() {
    setupVolumeIcon()
    setupVolumeIndicator()

    panGesture = UIPanGestureRecognizer(target: self, action: #selector(pan(gesture:)))
    self.view.addGestureRecognizer(panGesture!)
  }

  fileprivate func setupVolumeIndicator() {
    volumeIndicator.translatesAutoresizingMaskIntoConstraints = false
    self.view.addSubview(volumeIndicator)

    volumeProgress.translatesAutoresizingMaskIntoConstraints = false
    volumeProgress.progressTintColor = UIColor.white
    volumeProgress.trackTintColor =
      UIColor.white.withAlphaComponent(Constants.partialAlpha)
    volumeProgress.layer.cornerRadius = 0.5 * Constants.volumeIndicatorWidth
    volumeProgress.clipsToBounds = true
    volumeProgress.transform = CGAffineTransform(rotationAngle: .pi / -2)
    volumeProgress.progress = volume
    volumeIndicator.addSubview(volumeProgress)

    let bottomAnchorConstant = Constants.volumeIndicatorTopPadding + Constants.volumeIconHeight + Constants.volumeIndicatorBottomPadding
    let heightPadding = bottomAnchorConstant + heightInset

    NSLayoutConstraint.activate([
      volumeIndicator.heightAnchor.constraint(equalTo: self.view.heightAnchor,
                                              constant: -heightPadding),
      volumeIndicator.widthAnchor.constraint(equalToConstant: Constants.volumeIndicatorWidth),
      volumeIndicator.topAnchor.constraint(equalTo: self.view.topAnchor, constant: heightInset),
      volumeIndicator.rightAnchor.constraint(equalTo: self.view.rightAnchor,
                                             constant: -Constants.volumeIndicatorRightPadding),
      volumeProgress.widthAnchor.constraint(equalTo: volumeIndicator.heightAnchor),
      volumeProgress.heightAnchor.constraint(equalTo: volumeIndicator.widthAnchor),
      volumeProgress.centerXAnchor.constraint(equalTo: volumeIndicator.centerXAnchor),
      volumeProgress.centerYAnchor.constraint(equalTo: volumeIndicator.centerYAnchor)
    ])
  }

  fileprivate func setupVolumeIcon() {
    volumeIcon.tintColor = .white
    self.view.addSubview(volumeIcon)
    self.volumeIcon.translatesAutoresizingMaskIntoConstraints = false
    setVolumeIcon(volume: volume)

    NSLayoutConstraint.activate([
      volumeIcon.bottomAnchor.constraint(equalTo: self.view.bottomAnchor,
                                         constant: -Constants.volumeIconBottomPadding),
      volumeIcon.rightAnchor.constraint(equalTo: self.view.rightAnchor,
                                        constant: -Constants.volumeIconRightPadding),
      volumeIcon.widthAnchor.constraint(equalToConstant: Constants.volumeIconWidth),
      volumeIcon.heightAnchor.constraint(equalToConstant: Constants.volumeIconHeight)
    ])
  }

  lazy var volumeImage = UIImage(systemName: "volume.1.fill")?.withRenderingMode(.alwaysTemplate)
  lazy var muteImage = UIImage(systemName: "volume.slash.fill")?.withRenderingMode(.alwaysTemplate)
  fileprivate func setVolumeIcon(volume: Float?) {
    if let volume = volume {
      if volume > 0.0 {
        volumeIcon.image = volumeImage
      } else {
        volumeIcon.image = muteImage
      }
    }
  }

  // MARK: - Action Handlers

  @objc fileprivate func press(gesture: UILongPressGestureRecognizer) {
    if gesture.state == UIGestureRecognizer.State.began {
      volumeAdjustmentActive = true
    }

    if gesture.state == UIGestureRecognizer.State.ended {
      volumeAdjustmentActive = false
    }
  }

  @objc fileprivate func pan(gesture: UIPanGestureRecognizer) {
    if gesture.state == UIGestureRecognizer.State.ended {
      volumeAdjustmentActive = false
      delegate?.volumeChangeEnded()

      return
    }

    let yTranslation = -gesture.translation(in: gesture.view).y

    if abs(yTranslation) >= Constants.panTolerance {
      if !volumeAdjustmentActive {
        volumeAdjustmentActive = true
        delegate?.volumeChangeStarted()
      }

      let height = self.view.frame.size.height * Constants.heightTolerance
      let newVolume = volume + Float(yTranslation / height)
      volume = min(max(newVolume, 0.0), 1.0)

      volumeProgress.setProgress(volume, animated: true)
      setVolumeIcon(volume: volume)

      delegate?.volumeChanged(volume: volume)

      // Reset the overall translation within the view
      gesture.setTranslation(.zero, in: gesture.view)
    }
  }
}
