// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import CoreMedia
import UIKit

class NudgeViewController: UIViewController {
  private struct Constants {
    static let alpha: CGFloat = 0.2
    static let inactiveAlpha: CGFloat = 0.6
    static let activationButtonCornerRadius: CGFloat = 2.0
    static let edgeInsets = UIEdgeInsets(top: 9, left: 5, bottom: 9, right: 5)
    static let saveButtonEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
    static let nudgeButtonCornerRadius: CGFloat = 24.0
    static let nudgeButtonDiameter: CGFloat = 48.0
    static let nudgeButtonInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: -8)
    static let font: UIFont = .systemFont(ofSize: 20.0, weight: .bold)
    static let fontColor = UIColor(rgb: 0xFFFFFF)
  }

  // MARK: - Data
  let playbackEditor: PlaybackEditor
  let saveNudge: (() -> Void)?
  var nudgeCount: Int = 0 {
    didSet {
      nudgeCounterLabel.text = nudgeCount > 0 ? "+\(nudgeCount)" : "\(nudgeCount)"
    }
  }
  var storedNudgeCount: Int = 0

  // MARK: - UI

  let activationButton: UIButton = {
    let btn = UIButton()
    btn.backgroundColor = UIColor.black.withAlphaComponent(Constants.alpha)
    btn.layer.cornerRadius = Constants.activationButtonCornerRadius

    let icon = UIImage(systemName: "chevron.up.chevron.down")?.withRenderingMode(.alwaysTemplate)
    btn.setImage(icon, for: .normal)
    btn.tintColor = .white
    btn.transform = CGAffineTransform(rotationAngle: .pi / 2)

    btn.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      btn.widthAnchor.constraint(equalTo: btn.heightAnchor)
    ])
    return btn
  }()

  let nudgeInstructionsLabel: UILabel = {
    let label = UILabel()
    label.backgroundColor = .clear
    label.text = "Tap arrows to align your clip"
    label.font = UIFont.systemFont(ofSize: 14.0, weight: .bold)
    label.textAlignment = .center
    label.numberOfLines = 0
    label.textColor = .white
    label.layer.shadowRadius = 2.0
    label.layer.shadowColor = UIColor.black.cgColor
    label.layer.shadowOffset = CGSize(width: 2, height: 4)
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  let closeNudgeButton: UIButton = {
    let btn = UIButton()
    btn.backgroundColor = UIColor.black.withAlphaComponent(Constants.alpha)
    btn.layer.cornerRadius = Constants.activationButtonCornerRadius
    btn.setImage(UIImage(systemName: "xmark")?.withRenderingMode(.alwaysTemplate), for: .normal)
    btn.tintColor = .white
    btn.translatesAutoresizingMaskIntoConstraints = false
    return btn
  }()

  let saveNudgeButton: UIButton = {
    let btn = UIButton()
    btn.backgroundColor = UIColor.black.withAlphaComponent(Constants.alpha)
    btn.layer.cornerRadius = Constants.activationButtonCornerRadius

    btn.setTitle("Save", for: .normal)
    btn.titleLabel?.font = UIFont.systemFont(ofSize: 14.0, weight: .bold)
    btn.setTitleColor(UIColor(rgb: 0xFFFFFF), for: .normal)
    btn.contentEdgeInsets = Constants.saveButtonEdgeInsets

    btn.translatesAutoresizingMaskIntoConstraints = false
    return btn
  }()

  let nudgeBackwardButton: UIButton = {
    let btn = UIButton()
    let icon = UIImage(systemName: "chevron.left")?.withRenderingMode(.alwaysTemplate)
    btn.setImage(icon, for: .normal)
    btn.tintColor = .white
    btn.backgroundColor = .black.withAlphaComponent(Constants.alpha)
    btn.layer.cornerRadius = Constants.nudgeButtonDiameter / 2

    btn.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      btn.widthAnchor.constraint(equalToConstant: Constants.nudgeButtonDiameter),
      btn.heightAnchor.constraint(equalToConstant: Constants.nudgeButtonDiameter)
    ])

    return btn
  }()

  let nudgeForwardButton: UIButton = {
    let btn = UIButton()
    let icon = UIImage(systemName: "chevron.right")?.withRenderingMode(.alwaysTemplate)
    btn.setImage(icon, for: .normal)
    btn.tintColor = .white
    btn.backgroundColor = .black.withAlphaComponent(Constants.alpha)
    btn.layer.cornerRadius = Constants.nudgeButtonDiameter / 2

    btn.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      btn.widthAnchor.constraint(equalToConstant: Constants.nudgeButtonDiameter),
      btn.heightAnchor.constraint(equalToConstant: Constants.nudgeButtonDiameter)
    ])

    return btn
  }()

  let nudgeCounterLabel: UILabel = {
    let label = UILabel()
    label.font = Constants.font
    label.textColor = Constants.fontColor
    label.translatesAutoresizingMaskIntoConstraints = false
    label.textAlignment = .center

    return label
  }()

  // MARK: - Init

  init(playbackEditor: PlaybackEditor, saveNudgeCompletion: (() -> Void)? = nil) {
    self.playbackEditor = playbackEditor
    self.saveNudge = saveNudgeCompletion
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
    nudgeInstructionsLabel.isHidden = false
    saveNudgeButton.isHidden = false
    closeNudgeButton.isHidden = false
    nudgeForwardButton.isHidden = false
    nudgeBackwardButton.isHidden = false
    nudgeCounterLabel.isHidden = false

    updateNudgeButtons()

    // Store the initial nudgeCount at the start of this activation.
    storedNudgeCount = nudgeCount
    self.view.isUserInteractionEnabled = true

    print("-------------------------- ACTIVATED NUDGE -----------------------------")
  }

  public func deactivate() {
    nudgeInstructionsLabel.isHidden = true
    saveNudgeButton.isHidden = true
    closeNudgeButton.isHidden = true
    nudgeForwardButton.isHidden = true
    nudgeBackwardButton.isHidden = true
    nudgeCounterLabel.isHidden = true

    playbackEditor.storeValues()
    self.view.isUserInteractionEnabled = false
    print("-------------------------- DEACTIVATED NUDGE -----------------------------")
  }

  public func reset() {
    // Reset the nudgeCount to the count stored at the start of this activation.
    nudgeCount = storedNudgeCount
    playbackEditor.reset()
  }

  // MARK: - UI Helpers

  fileprivate func setupUI() {
    nudgeForwardButton.addTarget(self,
                                 action: #selector(didTapNudgeForward(_:)),
                                 for: .touchUpInside)
    self.view.addSubview(nudgeForwardButton)
    nudgeForwardButton.isHidden = true

    nudgeBackwardButton.addTarget(self,
                                  action: #selector(didTapNudgeBackward(_:)),
                                  for: .touchUpInside)
    self.view.addSubview(nudgeBackwardButton)
    nudgeBackwardButton.isHidden = true

    self.view.addSubview(nudgeCounterLabel)
    nudgeCounterLabel.isHidden = true

    NSLayoutConstraint.activate([
      nudgeBackwardButton.leftAnchor.constraint(equalTo: self.view.leftAnchor,
                                                constant: Constants.nudgeButtonInsets.left),
      nudgeBackwardButton.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
      nudgeForwardButton.rightAnchor.constraint(equalTo: self.view.rightAnchor,
                                                constant: Constants.nudgeButtonInsets.right),
      nudgeForwardButton.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
      nudgeCounterLabel.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
      nudgeCounterLabel.centerYAnchor.constraint(equalTo: self.view.centerYAnchor)
    ])

    self.view.addSubview(nudgeInstructionsLabel)
    nudgeInstructionsLabel.isHidden = true

    saveNudgeButton.addTarget(self,
                              action: #selector(didTapSaveNudge(_:)),
                              for: .touchUpInside)
    self.view.addSubview(saveNudgeButton)
    saveNudgeButton.isHidden = true
    closeNudgeButton.addTarget(self,
                              action: #selector(didTapCloseNudge(_:)),
                              for: .touchUpInside)
    self.view.addSubview(closeNudgeButton)
    closeNudgeButton.isHidden = true
    NSLayoutConstraint.activate([
      saveNudgeButton.topAnchor.constraint(equalTo: self.view.topAnchor,
                                           constant: FragmentCreationViewController.buttonBarTopInset),
      saveNudgeButton.rightAnchor.constraint(equalTo: self.view.rightAnchor,
                                           constant: -FragmentCreationViewController.buttonBarSideInset),
      closeNudgeButton.topAnchor.constraint(equalTo: self.view.topAnchor,
                                           constant: FragmentCreationViewController.buttonBarTopInset),
      closeNudgeButton.leftAnchor.constraint(equalTo: self.view.leftAnchor,
                                           constant: FragmentCreationViewController.buttonBarSideInset),
      closeNudgeButton.heightAnchor.constraint(equalTo: saveNudgeButton.heightAnchor),
      closeNudgeButton.widthAnchor.constraint(equalTo: closeNudgeButton.heightAnchor),
      nudgeInstructionsLabel.bottomAnchor.constraint(equalTo: self.view.bottomAnchor,
                                                     constant: -Constants.saveButtonEdgeInsets.right),
      nudgeInstructionsLabel.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
      nudgeInstructionsLabel.widthAnchor.constraint(equalTo: self.view.widthAnchor,
                                                    constant: -2.0 * Constants.saveButtonEdgeInsets.right)
    ])
  }

  fileprivate func updateNudgeCounter(change: Int) {
    nudgeCount += change
  }

  // MARK: - Playback Editing

  fileprivate func nudgeForward() {
    playbackEditor.shiftPlayback(direction: 1)
    updateNudgeCounter(change: 1)
    updateNudgeButtons()
    print("NUDGE FORWARD")
  }

  fileprivate func nudgeBackward() {
    playbackEditor.shiftPlayback(direction: -1)
    updateNudgeCounter(change: -1)
    updateNudgeButtons()
    print("NUDGE BACKWARD")
  }

  fileprivate func updateNudgeButtons() {
    updateForwardNudge()
    updateBackwardNudge()
  }

  fileprivate func updateForwardNudge() {
    nudgeForwardButton.isEnabled = playbackEditor.shiftIsValid(direction: 1)
    nudgeForwardButton.alpha =
      nudgeForwardButton.isEnabled ? 1.0 : Constants.inactiveAlpha
  }

  fileprivate func updateBackwardNudge() {
    nudgeBackwardButton.isEnabled = playbackEditor.shiftIsValid(direction: -1)
    nudgeBackwardButton.alpha =
      nudgeBackwardButton.isEnabled ? 1.0 : Constants.inactiveAlpha
  }

  // MARK: - Action Handlers
  @objc func didTapSaveNudge(_ sender: UIButton) {
    DispatchQueue.main.async {
      self.saveNudge?()
    }
  }

  @objc func didTapCloseNudge(_ sender: UIButton) {
    DispatchQueue.main.async {
      self.reset()
      self.saveNudge?()
    }
  }

  @objc func didTapNudgeForward(_ sender: UIButton) {
    DispatchQueue.main.async {
      self.nudgeForward()
    }
  }

  @objc func didTapNudgeBackward(_ sender: UIButton) {
    DispatchQueue.main.async {
      self.nudgeBackward()
    }
  }
}
