// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import UIKit
import BrightFutures
import CoreMedia

protocol FragmentCreationViewControllerDelegate: NSObject {
  func select(viewController: FragmentCreationViewController, type: FragmentCreationViewController.SelectionType)
  func fragmentVolumeChanged(fragment: FragmentHost, volume: Float)
  func fragmentPlaybackChanged(fragment: FragmentHost,
                               durationChanged: Bool,
                               startTimeChanged: Bool,
                               endTimeChanged: Bool)
  func fragmentInteractionStarted(viewController: FragmentCreationViewController)
  func fragmentInteractionEnded(viewController: FragmentCreationViewController)
  func fragmentNudgeInteractionStarted(viewController: FragmentCreationViewController)
  func fragmentNudgeInteractionEnded(viewController: FragmentCreationViewController)
  func trimFinished()
  func didTapDeleteClip(viewController: FragmentCreationViewController)
}

class FragmentCreationViewController: UIViewController {
  enum Constants {
    static let smallFontSize: CGFloat = 14.0
    static let inactiveAlpha: CGFloat = 0.0
    static let passiveAlpha: CGFloat = 0.2
    static let cornerRadius: CGFloat = 6.0
    static let nilFragmentText = "This clip has been removed.\n Replace it to publish."
    static let overlayAlpha: CGFloat = 0.8
    static let dimOverlayAlpha: CGFloat = 0.5
    static let selectionFontSize: CGFloat = 36.0
    static let overlayMessageHeightOffset: CGFloat = 10.0
    static let durationMessageFadeTime: Double = 1.0
  }

  static let buttonBarHeight: CGFloat = 30.0
  static let buttonBarTopInset: CGFloat = 10.0
  static let buttonBarSideInset: CGFloat = 6.0
  static let deleteButtonSize: CGFloat = 24.0

  enum SelectionType {
    case none
    case replaceView
  }

  // Data
  var fragment: FragmentHost
  // It would be better to separate the user generated fragments from
  // the server fragments. Currently we special case the UI but they should probably
  // just have their own unique classes.
  let editable: Bool
  fileprivate let firstClip: Bool
  var playbackEditor: PlaybackEditor?
  var shouldShowDeletionUI: Bool {
    didSet {
      if oldValue != shouldShowDeletionUI {
        setClipDeletionVisibility(hidden: !shouldShowDeletionUI)
      }
    }
  }

  let isNilFragment: Bool
  var isRecordPlaceholderFragment: Bool = false
  var managedSubview: UIView?
  private var activeSelectionType = SelectionType.none

  fileprivate var volumeViewController: VolumeViewController
  fileprivate var nudgeViewController: NudgeViewController?
  fileprivate let gradientLoadingView = GradientLoadingView()

  // UI

  private var paddingView: UIView {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }

  private let buttonStackView: UIStackView = {
    let stackView = UIStackView()
    stackView.axis = .horizontal
    stackView.alignment = .fill
    stackView.distribution = .fill
    stackView.translatesAutoresizingMaskIntoConstraints = false

    return stackView
  }()

  private let deleteButton: UIButton = {
    let btn = UIButton(type: .custom)
    btn.translatesAutoresizingMaskIntoConstraints = false

    btn.setImage(UIImage(systemName: "minus")?.withRenderingMode(.alwaysTemplate), for: .normal)
    btn.tintColor = .black
    btn.backgroundColor = .white
    btn.clipsToBounds = true
    btn.layer.cornerRadius = FragmentCreationViewController.deleteButtonSize / 2.0

    NSLayoutConstraint.activate([
      btn.widthAnchor.constraint(equalToConstant: FragmentCreationViewController.deleteButtonSize),
      btn.heightAnchor.constraint(equalToConstant: FragmentCreationViewController.deleteButtonSize)
    ])

    return btn
  }()
  private let deleteView: UIView = {
    let deleteView = UIView()
    deleteView.backgroundColor = .clear
    NSLayoutConstraint.activate([
      deleteView.widthAnchor.constraint(equalTo: deleteView.heightAnchor)
    ])
    return deleteView
  }()

  let takeNumber: Int?
  private var fragmentLabel: FragmentLabelView?
  private let overlay = UIView()
  private let nilFragmentMessage = UILabel()
  private let recordPlaceholderImageView = UIImageView()
  private let trimTimeMessageLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.textAlignment = .center
    label.font = .systemFont(ofSize: Constants.smallFontSize,
                             weight: UIFont.Weight.bold)
    label.textColor = .white
    label.numberOfLines = 0
    return label
  }()
  private let selectionOverlayView = UIView()
  private let selectionLabel = UILabel()
  private var selectionGestureRecognizer: UITapGestureRecognizer?

  private weak var delegate: FragmentCreationViewControllerDelegate?

  // MARK: - Init

  init(fragment: FragmentHost,
       editable: Bool = false,
       firstClip: Bool = false,
       takeNumber: Int? = nil,
       showDeleteOnInit: Bool = true,
       delegate: FragmentCreationViewControllerDelegate) {
    self.fragment = fragment
    self.editable = editable
    self.firstClip = firstClip
    self.takeNumber = takeNumber
    self.delegate = delegate
    self.isNilFragment = fragment.assetInfo.isEmpty
    let labelIsEmpty = takeNumber == nil
    let heightInset = labelIsEmpty ? 0.0 : FragmentCreationViewController.buttonBarHeight + FragmentCreationViewController.buttonBarTopInset
    self.volumeViewController = VolumeViewController(volume: fragment.volume, heightInset: heightInset)
    self.shouldShowDeletionUI = showDeleteOnInit

    super.init(nibName: nil, bundle: nil)
    self.volumeViewController.delegate = self

    if editable {
      self.playbackEditor = PlaybackEditor(fragment: fragment)
      self.fragment.addListener(listener: playbackEditor!)
      self.playbackEditor?.delegate = self
      if !self.firstClip {
        self.nudgeViewController = NudgeViewController(playbackEditor: playbackEditor!, saveNudgeCompletion: saveNudge)
      }
    }
  }

  required init?(coder: NSCoder) {
    Fatal.safeError("init(coder:) has not been implemented")
  }

  deinit {
    guard let playbackEditor = playbackEditor else { return }
    self.fragment.removeListener(listener: playbackEditor)
  }

  // MARK: - UIViewController

  override func viewDidLoad() {
    super.viewDidLoad()

    self.addChild(volumeViewController)
    volumeViewController.didMove(toParent: self)

    if self.isNilFragment {
      disableAdjustmentUI()
    } else {
      enableAdjustmentUI()
    }

    if let nudgeViewController = nudgeViewController {
      self.addChild(nudgeViewController)
      nudgeViewController.didMove(toParent: self)
    }

    setupUI()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    fragment.hostView.frame = self.view.bounds
    volumeViewController.view.frame = self.view.bounds
    nudgeViewController?.view.frame = self.view.bounds
    overlay.frame = self.view.bounds
    gradientLoadingView.frame = self.view.bounds
    selectionOverlayView.frame = self.view.bounds
    managedSubview?.frame = self.view.bounds
  }

  // MARK: - Public Methods

  func animateGradient() {
    gradientLoadingView.animateGradient()
  }

  func stopAnimatingGradient() {
    self.gradientLoadingView.stopAnimation()
    self.gradientLoadingView.removeFromSuperview()
  }

  func updateProgress(_ progress: Float) {
    volumeViewController.view.alpha = CGFloat(progress)
    overlay.alpha = (1.0 - CGFloat(progress)) * 0.5
  }

  func activateOverlay() {
    overlay.alpha = Constants.dimOverlayAlpha

    // Hide other UI.
    disableAdjustmentUI()
    buttonStackView.isHidden = true
  }

  func deactivateOverlay() {
    overlay.alpha = 0

    // Show other UI.
    enableAdjustmentUI()
    buttonStackView.isHidden = false
  }

  func enableAdjustmentUI() {
    volumeViewController.activate()
  }

  func disableAdjustmentUI() {
    volumeViewController.deactivate()
  }

  func setClipDeletionVisibility(hidden: Bool) {
    deleteButton.isHidden = hidden
  }

  func activateDimOverlay() {
    selectionOverlayView.alpha = Constants.dimOverlayAlpha
    showSelectionUI(message: "")
  }

  func deactivateDimOverlay() {
    selectionOverlayView.alpha = Constants.overlayAlpha
    hideSelectionUI()
  }

  func activateSelector(message: String,
                        type: SelectionType) {
    showSelectionUI(message: message)
    self.activeSelectionType = type
    selectionGestureRecognizer =
      UITapGestureRecognizer(target: self,
                             action: #selector(didSelect(_:)))
    selectionGestureRecognizer?.numberOfTouchesRequired = 1
    selectionOverlayView.addGestureRecognizer(selectionGestureRecognizer!)
  }

  func deactivateSelector() {
    guard let recognizer = selectionGestureRecognizer else {
      print("Trying to deactivateSelector with nil gesture recognizer")
      return
    }
    selectionOverlayView
      .removeGestureRecognizer(recognizer)
    self.activeSelectionType = SelectionType.none

    hideSelectionUI()
  }

  func addManagedSubview(view: UIView) {
    managedSubview?.removeFromSuperview()
    managedSubview = view
    self.view.addSubview(managedSubview!)
    self.view.setNeedsLayout()
  }

  func removeManagedSubview() {
    managedSubview?.removeFromSuperview()
  }

  public func showMaxTrimMessage() {
    let message = "Maximum \(Int(fragment.maxPlaybackDuration.toSeconds())) seconds"
    showTrimLengthMessage(message: message)
  }

  public func showMinTrimMessage() {
    let message = "Minimum \(Int(fragment.minPlaybackDuration.toSeconds())) seconds"
    showTrimLengthMessage(message: message)
  }

  // MARK: - Private Helpers

  fileprivate func setupUI() {
    self.view.addSubview(gradientLoadingView)
    self.view.addSubview(fragment.hostView)
    self.view.addSubview(overlay)

    if let nudgeViewController = nudgeViewController {
      self.view.addSubview(nudgeViewController.view)
    }

    self.view.addSubview(volumeViewController.view)

    overlay.backgroundColor = .black
    self.view.clipsToBounds = true
    self.view.layer.cornerRadius = Constants.cornerRadius

    if self.isRecordPlaceholderFragment {
      setupRecordPlaceholderUI()
    } else if self.isNilFragment {
      setupNilFragmentMessage()
    }

    setupFragmentLabel()
    setupButtonBarStackView()
    setupSelectionUI()
    setupTrimTimeMessageView()
  }

  fileprivate func setupSelectionUI() {
    selectionOverlayView.backgroundColor = .black
    selectionOverlayView.alpha = Constants.overlayAlpha

    selectionLabel.translatesAutoresizingMaskIntoConstraints = false
    selectionLabel.textAlignment = .center
    selectionLabel.font = .systemFont(ofSize: Constants.selectionFontSize, weight: UIFont.Weight.bold)
    selectionLabel.textColor = .white

    selectionOverlayView.addSubview(selectionLabel)
    NSLayoutConstraint.activate([
      selectionLabel.centerYAnchor.constraint(equalTo: selectionOverlayView.centerYAnchor),
      selectionLabel.centerXAnchor.constraint(equalTo: selectionOverlayView.centerXAnchor)
    ])
  }

  fileprivate func setupRecordPlaceholderUI() {
    recordPlaceholderImageView.image = UIImage(systemName: "camera")?.withRenderingMode(.alwaysTemplate)
    recordPlaceholderImageView.contentMode = .scaleAspectFit
    recordPlaceholderImageView.backgroundColor = .black
    recordPlaceholderImageView.tintColor = .purple
    recordPlaceholderImageView.translatesAutoresizingMaskIntoConstraints = false
    self.view.addSubview(recordPlaceholderImageView)
    NSLayoutConstraint.activate([
      recordPlaceholderImageView.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
      recordPlaceholderImageView.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
      recordPlaceholderImageView.heightAnchor.constraint(equalTo: self.view.heightAnchor),
      recordPlaceholderImageView.widthAnchor.constraint(equalTo: self.view.heightAnchor)
    ])
  }

  fileprivate func setupNilFragmentMessage() {
    nilFragmentMessage.text = Constants.nilFragmentText
    nilFragmentMessage.font = UIFont.boldSystemFont(ofSize: 14)
    nilFragmentMessage.numberOfLines = 0
    nilFragmentMessage.textColor = .white
    nilFragmentMessage.textAlignment = .center
    nilFragmentMessage.translatesAutoresizingMaskIntoConstraints = false
    nilFragmentMessage.backgroundColor = .clear
    self.view.addSubview(nilFragmentMessage)
    NSLayoutConstraint.activate([
      nilFragmentMessage.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
      nilFragmentMessage.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
      nilFragmentMessage.widthAnchor.constraint(equalTo: self.view.widthAnchor)
    ])
  }

  fileprivate func setupFragmentLabel() {
    guard let takeNumber = takeNumber else { return }
    let fragmentLabel = FragmentLabelView()
    fragmentLabel.takeNumber = "\(takeNumber)"
    fragmentLabel.translatesAutoresizingMaskIntoConstraints = false

    self.fragmentLabel = fragmentLabel
  }

  fileprivate func setupTrimTimeMessageView() {
    overlay.addSubview(trimTimeMessageLabel)
    trimTimeMessageLabel.isHidden = true
    NSLayoutConstraint.activate([
      trimTimeMessageLabel.centerYAnchor.constraint(equalTo: overlay.centerYAnchor, constant: Constants.overlayMessageHeightOffset),
      trimTimeMessageLabel.centerXAnchor.constraint(equalTo: overlay.centerXAnchor)
    ])
  }

  fileprivate func showTrimLengthMessage(message: String) {
    trimTimeMessageLabel.text = message
    trimTimeMessageLabel.isHidden = false
    overlay.alpha = 1.0
    overlay.backgroundColor = .clear
    UIView.animate(withDuration: Constants.durationMessageFadeTime,
                   animations: {
                     self.overlay.alpha = 0
                   }, completion: { finished in
                     if finished {
                       self.trimTimeMessageLabel.isHidden = true
                       self.overlay.backgroundColor = .black
                     }
    })
  }

  fileprivate func setupButtonBarStackView() {

    deleteView.addSubview(deleteButton)
    buttonStackView.addArrangedSubview(deleteView)
    deleteButton.addTarget(self, action: #selector(didTapDelete(_:)), for: .touchUpInside)

    // Padding to fill the middle of the view when we conditionally add other views.
    let variableWidthPaddingView = paddingView
    buttonStackView.addArrangedSubview(variableWidthPaddingView)

    if let nudgeViewController = nudgeViewController {
      buttonStackView.addArrangedSubview(nudgeViewController.activationButton)
      nudgeViewController.activationButton.addTarget(self,
                                                     action: #selector(didTapActivateNudge(_:)),
                                                     for: .touchUpInside)
    }
    let spacingPaddingView = paddingView
    buttonStackView.addArrangedSubview(spacingPaddingView)

    if let fragmentLabel = fragmentLabel {
      buttonStackView.addArrangedSubview(fragmentLabel)
    }

    self.view.addSubview(buttonStackView)

    NSLayoutConstraint.activate([
      spacingPaddingView.widthAnchor.constraint(equalToConstant: 6.0),
      deleteButton.centerYAnchor.constraint(equalTo: deleteView.centerYAnchor),
      buttonStackView.leftAnchor.constraint(equalTo: self.view.leftAnchor, constant: FragmentCreationViewController.buttonBarTopInset),
      buttonStackView.rightAnchor.constraint(equalTo: self.view.rightAnchor, constant: -FragmentCreationViewController.buttonBarSideInset),
      buttonStackView.topAnchor.constraint(equalTo: self.view.topAnchor, constant: FragmentCreationViewController.buttonBarTopInset),
      buttonStackView.heightAnchor.constraint(equalToConstant: FragmentCreationViewController.buttonBarHeight)
    ])
  }

  fileprivate func showSelectionUI(message: String) {
    selectionLabel.text = message
    self.view.addSubview(selectionOverlayView)
    self.view.setNeedsLayout()
  }

  fileprivate func hideSelectionUI() {
    selectionLabel.text = ""
    selectionOverlayView.removeFromSuperview()
    self.view.setNeedsLayout()
  }

  // MARK: - Action Handlers

  @objc fileprivate func didSelect(_ sender: AnyObject?) {
    if self.activeSelectionType != SelectionType.none {
      delegate?.select(viewController: self, type: self.activeSelectionType)
    }
  }
}

// MARK: - Trim

extension FragmentCreationViewController {
  func finishTrimming() {
    playbackEditor?.storeValues()
  }

  func playbackRangeChanged(range: ClosedRange<CMTime>) {
    playbackEditor?.setPlaybackRange(range: range)
  }

  func playbackStartTimeNudged(direction: Int32) {
    playbackEditor?.shiftPlaybackStartTime(direction: direction)
  }

  func playbackEndTimeNudged(direction: Int32) {
    playbackEditor?.shiftPlaybackEndTime(direction: direction)
  }
}

// MARK: - Nudge

extension FragmentCreationViewController {
  fileprivate func clearNudgeUI() {
    guard let nudgeViewController = nudgeViewController else { return }
    nudgeViewController.deactivate()

    // Show other views.
    enableAdjustmentUI()
    buttonStackView.isHidden = false

    self.delegate?.fragmentNudgeInteractionEnded(viewController: self)
  }

  func getNudgeButton() -> UIButton? {
    return nudgeViewController?.activationButton
  }

  // MARK: - Action Handlers

  @objc func didTapActivateNudge(_ sender: UIButton) {
    guard let nudgeViewController = nudgeViewController else { return }
    nudgeViewController.activate()
    self.view.bringSubviewToFront(nudgeViewController.view)

    // Hide other views.
    disableAdjustmentUI()
    buttonStackView.isHidden = true

    self.delegate?.fragmentNudgeInteractionStarted(viewController: self)
  }

  @objc func closeNudge() {
    guard let nudgeViewController = nudgeViewController else { return }
    // When the user closes we don't save their changes.
    nudgeViewController.reset()

    self.clearNudgeUI()
  }

  @objc func saveNudge() {
    self.clearNudgeUI()
  }

  @objc func didTapDelete(_ sender: UIButton) {
    delegate?.didTapDeleteClip(viewController: self)
  }
}

// MARK: - PlaybackEditorDelegate

extension FragmentCreationViewController: PlaybackEditorDelegate {
  func playbackTimeChanged(startTime: CMTime?, endTime: CMTime?) {
    assert(Thread.isMainThread)

    let originalPlaybackDuration = fragment.playbackDuration
    let originalPlaybackStartTime = fragment.playbackStartTime
    let originalPlaybackEndTime = fragment.playbackEndTime

    self.fragment.setPlaybackTimes(startTime: startTime, endTime: endTime)

    // TODO : These three bools are propogating info back to the playback
    // Coordinator with info on how it should loop. Ideally this is done in
    // CreationViewController instead of being passed all the way into the individual
    // Fragment Controller.
    let durationChanged = originalPlaybackDuration != fragment.playbackDuration
    let startTimeChanged = originalPlaybackStartTime != fragment.playbackStartTime
    let endTimeChanged = originalPlaybackEndTime != fragment.playbackEndTime

    // Communicate the fragment change.
    self.delegate?.fragmentPlaybackChanged(fragment: fragment,
                                           durationChanged: durationChanged,
                                           startTimeChanged: startTimeChanged,
                                           endTimeChanged: endTimeChanged)
  }
}

// MARK: - VolumeViewControllerDelegate

extension FragmentCreationViewController: VolumeViewControllerDelegate {
  func volumeChanged(volume: Float) {
    self.fragment.volume = volume
    self.delegate?.fragmentVolumeChanged(fragment: self.fragment, volume: self.fragment.volume)
  }

  func volumeChangeStarted() {
    self.delegate?.fragmentInteractionStarted(viewController: self)
  }

  func volumeChangeEnded() {
    self.delegate?.fragmentInteractionEnded(viewController: self)
  }
}
