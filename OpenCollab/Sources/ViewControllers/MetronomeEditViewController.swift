// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import UIKit

protocol MetronomeEditViewControllerDelegate: NSObjectProtocol {
  func didUpdateBPM(BPM: Int)
  func pauseClickTrack()
}

class MetronomeEditViewController: UIViewController {
  struct Constants {
    static let buttonSpacing: CGFloat = 5.0
    static let BPMButtonWidth: CGFloat = 24.0
    static let changeBPMButtonHeight: CGFloat = 28.0
    static let changeBPMButtonWidth: CGFloat = 54.0
    static let BPMButtonSize: CGFloat = 60.0
    static let largeFontSize: CGFloat = 54.0
    static let smallFontSize: CGFloat = 14.0
    static let buttonPressedAlpha: CGFloat = 0.6
    static let buttonColor: UIColor = UIColor(rgb: 0x1A1A1A)
    static let buttonHightlightedColor: UIColor = UIColor(rgb: 0xB7B7B7).withAlphaComponent(0.6)
    static let minBPM: Int = 40
    static let maxBPM: Int = 220
  }

  fileprivate var BPM: Int {
    didSet {
      if !(longPressTimer?.isValid ?? false) {
        self.delegate?.didUpdateBPM(BPM: BPM)
      }
      BPMButton.setTitle("\(String(BPM)) bpm", for: .normal)
    }
  }
  fileprivate var longPressTimer: Timer?

  weak var delegate: MetronomeEditViewControllerDelegate?

  init(BPM: Int) {
    self.BPM = BPM
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    Fatal.safeError("init(coder:) has not been implemented")
  }

  // MARK: - Properties

  private let minusButton: UIButton = {
    let btn = UIButton(type: .custom)

    btn.translatesAutoresizingMaskIntoConstraints = false
    btn.backgroundColor = .white
    btn.setTitle("-", for: .normal)
    btn.setTitleColor(.black, for: .normal)
    btn.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .bold)
    btn.highlightedColor = Constants.buttonHightlightedColor
    btn.clipsToBounds = true
    btn.layer.cornerRadius = 3.0

    NSLayoutConstraint.activate([
      btn.widthAnchor.constraint(equalToConstant: Constants.BPMButtonWidth),
      btn.heightAnchor.constraint(equalToConstant: Constants.changeBPMButtonHeight)
    ])

    return btn
  }()

  private let plusButton: UIButton = {
    let btn = UIButton(type: .custom)

    btn.translatesAutoresizingMaskIntoConstraints = false
    btn.backgroundColor = .white
    btn.setTitle("+", for: .normal)
    btn.setTitleColor(.black, for: .normal)
    btn.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .bold)
    btn.highlightedColor = Constants.buttonHightlightedColor
    btn.clipsToBounds = true
    btn.layer.cornerRadius = 3.0

    NSLayoutConstraint.activate([
      btn.widthAnchor.constraint(equalToConstant: Constants.BPMButtonWidth),
      btn.heightAnchor.constraint(equalToConstant: Constants.changeBPMButtonHeight)
    ])

    return btn
  }()

  private let BPMButton: UIButton = {
    let btn = UIButton(type: .custom)

    btn.translatesAutoresizingMaskIntoConstraints = false
    btn.setBackgroundColor(.white, for: .normal)
    btn.setTitleColor(.black, for: .normal)
    btn.titleLabel?.font = .systemFont(ofSize: 10.0, weight: .bold)
    btn.clipsToBounds = true
    btn.layer.cornerRadius = 3.0

    NSLayoutConstraint.activate([
      btn.widthAnchor.constraint(equalToConstant: Constants.changeBPMButtonWidth),
      btn.heightAnchor.constraint(equalToConstant: Constants.changeBPMButtonHeight)
    ])

    return btn
  }()

  override func viewDidLoad() {
    super.viewDidLoad()

    setupUI()
  }

  // MARK: - Private Helpers

  fileprivate func setupUI() {
    self.view.addSubview(minusButton)
    self.view.addSubview(BPMButton)
    BPMButton.setTitle("\(String(BPM)) bpm", for: .normal)
    self.view.addSubview(plusButton)

    self.minusButton.addTarget(self,
                               action: #selector(didClickMinusButton(_:)),
                               for: .touchUpInside)
    self.plusButton.addTarget(self,
                              action: #selector(didClickPlusButton(_:)),
                              for: .touchUpInside)
    let minusGesture = UILongPressGestureRecognizer(target: self, action: #selector(didLongPressMinusButton))
    let plusGesture = UILongPressGestureRecognizer(target: self, action: #selector(didLongPressPlusButton))
    self.minusButton.addGestureRecognizer(minusGesture)
    self.plusButton.addGestureRecognizer(plusGesture)

    NSLayoutConstraint.activate([
      BPMButton.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
      BPMButton.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
      minusButton.rightAnchor.constraint(equalTo: BPMButton.leftAnchor,
                                         constant: -Constants.buttonSpacing),
      minusButton.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
      plusButton.leftAnchor.constraint(equalTo: BPMButton.rightAnchor,
                                         constant: Constants.buttonSpacing),
      plusButton.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
    ])
  }

  fileprivate func updateHasNext() {
    minusButton.isEnabled = BPM > Constants.minBPM
    plusButton.isEnabled = BPM < Constants.maxBPM
  }

  // MARK: - Action Handlers

  @objc func didClickMinusButton(_ sender: AnyObject?) {
    BPM = BPM - 1
    updateHasNext()
    if !minusButton.isEnabled {
      longPressTimer?.invalidate()
      longPressTimer = nil
    }
  }

  @objc func didClickPlusButton(_ sender: AnyObject?) {
    BPM = BPM + 1
    updateHasNext()
    if !plusButton.isEnabled {
      longPressTimer?.invalidate()
      longPressTimer = nil
    }
  }

  @objc func didLongPressPlusButton(gesture: UILongPressGestureRecognizer) {
    let selector = #selector(didClickPlusButton(_:))
    didLongPressButton(gesture: gesture, button: plusButton, selector: selector)
  }

  @objc func didLongPressMinusButton(gesture: UILongPressGestureRecognizer) {
    let selector = #selector(didClickMinusButton(_:))
    didLongPressButton(gesture: gesture, button: minusButton, selector: selector)
  }

  fileprivate func didLongPressButton(gesture: UILongPressGestureRecognizer, button: UIButton, selector: Selector) {
    guard Thread.isMainThread else { Fatal.safeError("Should be called on main thread") }
    switch gesture.state {
    case .began:
      button.isHighlighted = true
      self.longPressTimer = Timer(timeInterval: 0.1, target: self, selector: selector, userInfo: nil, repeats: true)
      guard let timer = longPressTimer else { return }
      let runLoop = RunLoop.current
      runLoop.add(timer, forMode: RunLoop.Mode.default)
      delegate?.pauseClickTrack()
    case .ended:
      longPressTimer?.invalidate()
      longPressTimer = nil
      button.isHighlighted = false
      // Trigger didSet to update BPM
      BPM = { BPM }()
    default:
      return
    }
  }
}
