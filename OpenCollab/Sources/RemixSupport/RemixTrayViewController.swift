// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import UIKit

protocol RemixTrayViewControllerDelegate: NSObject {
  func didSelectClip(index: Int)
}

class RemixTrayViewController: UIViewController {

  struct Constants {
    static let buttonMinimumPadding: CGFloat = 40.0
    static let largeFontSize: CGFloat = 54.0
    static let smallFontSize: CGFloat = 14.0
    static let trayViewTopInset: CGFloat = 6.0
    static let recordButtonDisabledOpacity: CGFloat = 0.5
    static let recordIndex: Int = 0
  }
  static let clipsTrayHeight: CGFloat = 72.0
  static let tabBarHeight: CGFloat = 28.0
  static let verticalSpacing: CGFloat = 18.0

  let clipsTab = RadioTabView(title: "Select a clip")
  let tabBarControlView: RadioTabBarControlView
  let recordButton = RecordButtonView(frame: CGRect(origin: .zero, size: CGSize(width: RemixTrayViewController.clipsTrayHeight, height: RemixTrayViewController.clipsTrayHeight)))
  let clipsContentStackView: UIStackView = {
    let stackView = UIStackView()
    stackView.axis = .horizontal
    stackView.spacing = 18
    return stackView
  }()
  let clipsSlideshowContainerView = UIView()
  fileprivate var clipsCollectionView: ClipsTrayCollectionViewController
  var delegate: RemixTrayViewControllerDelegate?

  // MARK: - Init

  init(clipsTrayCollectionView: ClipsTrayCollectionViewController) {
    self.clipsCollectionView = clipsTrayCollectionView
    self.tabBarControlView = RadioTabBarControlView(tabs: [self.clipsTab])
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    Fatal.safeError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    setupUI()
    tabBarControlView.delegate = self
    clipsCollectionView.delegate = self
    toggleRecordButtonHidden(show: false, animated: false)
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    recordButton.frame = CGRect(x: 0.0, y: 0.0, width: RemixTrayViewController.clipsTrayHeight, height: RemixTrayViewController.clipsTrayHeight)
    tabBarControlView.frame = CGRect(x: 0.0, y: Constants.trayViewTopInset, width: self.view.frame.width - 10, height: RemixTrayViewController.tabBarHeight) // TODO: need to know how much smaller to make width to align with collab (10 is arbitrary) -- this should come from superview.
    let stackViewYOffset = RemixTrayViewController.tabBarHeight + RemixTrayViewController.verticalSpacing
    clipsContentStackView.frame = CGRect(x: 0.0, y: stackViewYOffset, width: self.view.frame.width, height: self.view.frame.height - stackViewYOffset)
    clipsCollectionView.view.frame = clipsSlideshowContainerView.bounds
  }

  // MARK: - Public Functions

  public func setRecordButtonAction(target: Any?,
                                    selector: Selector,
                                    forEvent: UIControl.Event) {
    recordButton.addGestureRecognizer(UITapGestureRecognizer(target: target, action: selector))
  }

  public func toggleRecordButtonHidden(show: Bool, animated: Bool) {
    toggle(button: recordButton, show: show, animated: animated)
  }

  public func toggleRecordButtonEnabled(enabled: Bool) {
    recordButton.alpha = enabled ? 1.0 : Constants.recordButtonDisabledOpacity
    recordButton.isUserInteractionEnabled = enabled
  }

  public func updateSelectedClip(index: Int) {
    toggleRecordButtonHidden(show: index == Constants.recordIndex, animated: true)
    clipsCollectionView.updateSelectedIndex(index: index)
  }

  public func updateClips(slideViews: [SlideView]) {
    clipsCollectionView.reloadClips(slideViews: slideViews)
  }

  public func optimisticallyInsertClip(index: Int, slideView: SlideView) {
    clipsCollectionView.optimisticallyInsertClip(index: index, slideView: slideView)
  }

  public func toggleClipSelectionEnabled(enabled: Bool) {
    clipsCollectionView.toggleClipSelectionEnabled(enabled: enabled)
  }

  // MARK: - Private Helpers

  public func toggle(button: UIView, show: Bool, animated: Bool) {
    if button.isHidden == !show {
      return
    }
    if animated {
      button.alpha = show ? 0.0 : 1.0
      if show {
        button.isHidden = false
      }
      UIView.animate(withDuration: 0.2, animations: {
        button.alpha = show ? 1.0 : 0.0
      }) { (_) in
        if !show {
          button.isHidden = true
        }
      }
    } else {
      button.isHidden = !show
    }
  }

  fileprivate func setupUI() {
    recordButton.translatesAutoresizingMaskIntoConstraints = false
    tabBarControlView.translatesAutoresizingMaskIntoConstraints = false
    clipsContentStackView.translatesAutoresizingMaskIntoConstraints = false
    clipsSlideshowContainerView.translatesAutoresizingMaskIntoConstraints = false
    tabBarControlView.isUserInteractionEnabled = false
    tabBarControlView.backgroundColor = .white.withAlphaComponent(0.1)

    self.view.addSubview(tabBarControlView)
    self.view.addSubview(clipsContentStackView)
    clipsContentStackView.addArrangedSubview(recordButton)
    clipsSlideshowContainerView.addSubview(clipsCollectionView.view)
    clipsContentStackView.addArrangedSubview(clipsSlideshowContainerView)

    NSLayoutConstraint.activate([
      recordButton.widthAnchor.constraint(equalToConstant: RemixTrayViewController.clipsTrayHeight),
      recordButton.heightAnchor.constraint(equalToConstant: RemixTrayViewController.clipsTrayHeight),
      tabBarControlView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
      tabBarControlView.topAnchor.constraint(equalTo: self.view.topAnchor, constant: Constants.trayViewTopInset),
      clipsContentStackView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
      clipsContentStackView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
      clipsSlideshowContainerView.heightAnchor.constraint(equalToConstant: RemixTrayViewController.clipsTrayHeight),
    ])
  }
}

extension RemixTrayViewController: RadioTabBarControlViewDelegate {
  enum RemixTrayTabs: Int {
    case clips = 0
  }

  func didTapTabView(_ index: Int) {
    if index == RemixTrayTabs.clips.rawValue {
      // no-op since there's only one tab right now, but in the future this would hold
      // a delegate call to switch tabs
    }
  }
}

extension RemixTrayViewController: ClipsTrayCollectionViewControllerDelegate {
  func didSelectClip(index: Int) {
    delegate?.didSelectClip(index: index)
  }
}
