// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import UIKit
import CoreMedia
import BrightFutures
import AVKit

class PublishViewController: UIViewController {

  // MARK: - Data Model

  fileprivate let fragments: [FragmentHost]
  fileprivate let duration: CMTime
  
  fileprivate var viewDidDisappear = true

  // MARK: - UI

  fileprivate var contentContainerView = UIView()
  fileprivate var contentStackView = UIStackView()
  fileprivate var layoutEngine = LayoutEngineViewController()
  fileprivate lazy var spinner = SpinnerView.withSize(size: Constants.spinnerHeight)
  fileprivate var overlay: OverlayProgressView? {
    willSet {
      overlay?.removeFromSuperview()
    }
  }

  fileprivate lazy var unmuteView: UILabel =
    UINib(nibName: "UnmuteView", bundle: nil)
      .instantiate(withOwner: nil, options: nil)[0] as! UILabel

  fileprivate let saveButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.backgroundColor = .white
    button.setTitle("Share", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: Constants.smallFontSize,
                                          weight: .bold)
    button.setTitleColor(.black, for: .normal)
    button.clipsToBounds = true
    button.layer.cornerRadius = Constants.saveButtonHeight / 2.0
    return button
  }()
  let gradientLayer: CAGradientLayer = {
    let gradientLayer = CAGradientLayer()
    gradientLayer.colors = [UIColor.black.withAlphaComponent(0.8).cgColor, UIColor.clear.cgColor]
    gradientLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
    gradientLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
    gradientLayer.locations = [0.0, 0.15]
    return gradientLayer
  }()

  // MARK: - Helper objects

  fileprivate var playbackCoordinator: PlaybackCoordinator? {
    willSet {
      self.playbackCoordinator?.clear()
    }
  }

  // MARK: - Init

  required init?(coder: NSCoder) {
    Fatal.safeError()
  }

  init(fragments: [FragmentHost],
       duration: CMTime) {
    self.duration = duration
    self.fragments = fragments
    super.init(nibName: nil, bundle: nil)
  }

  deinit {
    print("DEINIT PublishViewController")
    NotificationCenter.default.removeObserver(self)
    cleanup()
  }

  // MARK: - UIViewController

  override func viewDidLoad() {
    super.viewDidLoad()

    setupUI()
    setupPlaybackCoordinator()
    attachFragments()
    updatePostButton()
    NotificationCenter.default.addObserver(self,
                                           selector: #selector(muteStateChanged),
                                           name: AppMuteManager.Notifications.muteSwitchStateChanged,
                                           object: nil)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    print("------------------------------------ ENTER PUBLISH -----------------------------------")

    guard viewDidDisappear else { return }
    viewDidDisappear = false

    toggleUnmuteMessage(isMuted: (AppMuteManager.shared.currentState() == .Muted))
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)

    viewDidDisappear = true
    cleanup()
    print("------------------------------------ EXIT PUBLISH -----------------------------------")
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()

    let bounds = self.view.bounds
    overlay?.frame = self.view.bounds

    contentContainerView.frame = bounds
    gradientLayer.frame = contentContainerView.layer.bounds
    contentStackView.frame = contentContainerView.bounds
    layoutEngine.view.frame = contentContainerView.bounds
  }

  // MARK: - Helper Functions

  fileprivate func updatePostButton() {
    saveButton.isEnabled = true
    saveButton.alpha = 1.0
  }

  fileprivate func setupActions() {
    saveButton.addTarget(self, action: #selector(didSelectCameraRollButton(_:)), for: .touchUpInside)
    self.view.addSubview(saveButton)
    
    NSLayoutConstraint.activate([
      saveButton.heightAnchor.constraint(equalToConstant: Constants.saveButtonHeight),
      saveButton.leadingAnchor.constraint(equalTo: self.view.leadingAnchor,
                                          constant: Constants.buttonPadding),
      saveButton.trailingAnchor.constraint(equalTo: self.view.trailingAnchor,
                                           constant: -Constants.buttonPadding),
      saveButton.bottomAnchor.constraint(equalTo: self.view.bottomAnchor,
                                         constant: -Constants.buttonPadding * 2)
    ])
  }

  fileprivate func setupUI() {
    self.view.backgroundColor = .black
    contentContainerView.backgroundColor = .black

    self.view.addSubview(contentContainerView)

    contentStackView.frame = self.view.bounds
    contentStackView.alignment = .fill
    contentStackView.axis = .vertical
    contentStackView.distribution = .fillEqually
    layoutEngine.view.frame = self.view.bounds
    let layoutToUse: UIView = layoutEngine.view

    contentContainerView.addSubview(layoutToUse)
    contentContainerView.layer.addSublayer(gradientLayer)

    for fragment in fragments {
      contentStackView.addArrangedSubview(fragment.hostView)
    }
    layoutEngine.configurePlaybackViewCells(playbackViews: fragments.map{ $0.hostView })
    setupActions()

    self.navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "arrow.left")?.withRenderingMode(.alwaysTemplate),
                                                            style: .plain,
                                                            target: self,
                                                            action: #selector(didTapClose))
    self.navigationItem.leftBarButtonItem?.tintColor = .white
  }

  @objc fileprivate func didTapClose() {
    self.navigationController?.popViewController(animated: true)
  }
  
  fileprivate func startSpinner() {
    self.spinner.alpha = 1.0
    self.buildOverlayIfNeeded()
    self.spinner.startAnimating()
  }
  
  fileprivate func removeSpinner() {
    self.spinner.alpha = 0.0
    self.overlay = nil
    self.spinner.stopAnimating()
  }
  
  fileprivate func buildOverlayIfNeeded() {
    if spinner.superview == nil {
      spinner.translatesAutoresizingMaskIntoConstraints = false
      self.view.addSubview(spinner)
      NSLayoutConstraint.activate([
        spinner.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
        spinner.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
        spinner.heightAnchor.constraint(equalToConstant: Constants.spinnerHeight),
        spinner.widthAnchor.constraint(equalToConstant: Constants.spinnerHeight)
      ])
    }

    if overlay == nil {
      let overlayView = OverlayProgressView()
      self.view.addSubview(overlayView)
      overlayView.frame = self.view.bounds
      overlayView.overlay.backgroundColor = .black
      overlay = overlayView
    }
  }

  // MARK: - Playback Handling

  fileprivate func attachFragments() {
    for fragment in fragments {
      _ = playbackCoordinator?.attach(fragment: fragment)
    }
  }

  fileprivate func cleanup() {
    guard Thread.isMainThread else { Fatal.safeError("Should be on main thread") }

    immediatelyDetachAllPlayersInMatrix()
    playbackCoordinator?.clear()
  }

  fileprivate func setupPlaybackCoordinator() {
    playbackCoordinator =
      PlaybackCoordinator(gracePeriod: Constants.gracePeriod,
                          duration: duration)
  }

  fileprivate func immediatelyDetachAllPlayersInMatrix() {
    guard Thread.isMainThread else { Fatal.safeError("Should be on main thread") }

    for fragment in fragments {
      playbackCoordinator?.detachImmediately(fragment: fragment,
                                             previewImageToo: true)
    }
  }

  // MARK: - Mute/Unmute Handling

  @objc fileprivate func muteStateChanged() {
    toggleUnmuteMessage(isMuted: (AppMuteManager.shared.currentState() == .Muted))
  }

  fileprivate func toggleUnmuteMessage(isMuted: Bool) {
    self.navigationItem.titleView = isMuted ? unmuteView : nil
  }
}

// MARK: - Publishing

extension PublishViewController {

  @objc fileprivate func didSelectCameraRollButton(_ sender: AnyObject?) {
    guard let assetManager = AppDelegate.fragmentAssetManager else {
      print("Tried to click share while app coordinators asset manager is nil")
      return
    }
    self.startSpinner()
    let volumeAndAssetFutures = fragments.map { (fragment) in
      return fragment.asset(allowManualSyncing: false)
        .flatMap { asset -> Future<(AVURLAsset?, Float), AssetError> in
          return Future(value: (asset, fragment.volume))
        }
    }

    volumeAndAssetFutures.sequence().onSuccess { assetAndVolumes in
      Rasterizer.shared.rasterize(assetWithVolumeTuples: assetAndVolumes,
                                  directoryURL: assetManager.rasterizationDirectory(),
                                  replaceLocalCopy: true)
        .onSuccess {[weak self] (url) in
          guard let self = self else { return }
          self.removeSpinner()
          // ## TODO : Add share sheet customization as needed, including the option to
          // exit or restart the creation flow once sharing is complete
          self.present(UIActivityViewController(activityItems: [url], applicationActivities: nil), animated: true, completion: nil)
      }.onFailure { (error) in
        self.removeSpinner()
        Alert.show(in: self, title: "Error", message: "Can't export \(error.localizedDescription)")
        print("ERROR: Failed to rasterize collab for share sheet.")
      }
    }
  }
}

// MARK: - Constants

extension PublishViewController {
  enum Constants {
    static let smallFontSize: CGFloat = 14.0
    static let gracePeriod: TimeInterval = 0.3
    static let saveButtonHeight: CGFloat = 34.0
    static let saveButtonBottopPadding: CGFloat = 12
    static let buttonPadding: CGFloat = 26.0
    static let spinnerHeight: CGFloat = 60.0
  }
}
