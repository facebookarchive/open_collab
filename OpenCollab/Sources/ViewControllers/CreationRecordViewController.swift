// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import AVFoundation
import UIKit
import BrightFutures

protocol CreationRecordViewControllerDelegate: AnyObject {
  func readyToRecord()
  func recordStopped()
  func restoreUI()
  func recordFinished(fragments: [FragmentHost])
  func didTapDeleteClip(viewController: CreationRecordViewController)
}

class CreationRecordViewController: UIViewController {
  private enum Constants {
    static let smallFontSize: CGFloat = 24.0
    static let cornerRadius: CGFloat = 6.0
    static let timerLimit = 4.0
    static let recordingBuffer = 0.03
    static let defaultBPM = 128
    static let defaultBeatBuffer = CMTimeMakeWithSeconds(1.0, preferredTimescale: 600)
    static let numberOfBeatsPerBuffer = 2
    static let showHideAnimationDuration: TimeInterval = 0.4
  }

  // Data
  fileprivate var takeViewController: TakeViewController?
  fileprivate var initialTakeCount: Int
  fileprivate var duration: CMTime?
  fileprivate let avSessionQueue: DispatchQueue

  var BPM: Int {
    didSet {
      takeViewController?.countDownInterval = countDownTime.toSeconds()
    }
  }
  // countDownTime should be uniformly calculated between CreationRecordViewController, RecordViewController, CreationViewController and TakeViewController.
  // TODO : Consolidate countDownTime better across all the controllers its used.
  fileprivate var countDownTime: CMTime {
    get {
      let halfBPM = BPM / 2
      return BeatSnapper.timePerBeat(BPM: halfBPM)
    }
  }
  fileprivate var totalLoopsWhileRecording = 0
  fileprivate var assetManager: LocalAssetManager?

  var isReadyToRecord: Bool {
    get {
      guard let takeViewController = takeViewController else { return false }
      return takeViewController.isReadyToRecord
    }
  }
  var shouldShowDeletionUI: Bool = false {
    didSet {
      if oldValue != shouldShowDeletionUI {
        setClipDeletionVisibility(hidden: !shouldShowDeletionUI)
      }
    }
  }
  private let paddingView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()
  private let buttonStackView: UIStackView = {
    let stackView = UIStackView()
    stackView.axis = .horizontal
    stackView.alignment = .fill
    stackView.distribution = .equalSpacing
    stackView.translatesAutoresizingMaskIntoConstraints = false

    return stackView
  }()
  var flipCameraButton: UIButton = {
    let btn = UIButton()
    btn.setImage(UIImage(systemName: "camera.rotate.fill")?.withRenderingMode(.alwaysTemplate), for: .normal)
    btn.tintColor = .white
    btn.translatesAutoresizingMaskIntoConstraints = false
    btn.imageView?.contentMode = .scaleAspectFit
    btn.contentMode = .scaleAspectFit
    btn.clipsToBounds = true
    return btn
  }()
  let deleteButton: UIButton = {
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

  private weak var delegate: CreationRecordViewControllerDelegate?

  // MARK: - Init

  init(duration: CMTime?,
       initialTakeCount: Int,
       BPM: Int,
       avSessionQueue: DispatchQueue,
       delegate: CreationRecordViewControllerDelegate) {
    self.duration = duration
    self.initialTakeCount = initialTakeCount
    self.delegate = delegate
    self.BPM = BPM
    self.avSessionQueue = avSessionQueue
    super.init(nibName: nil, bundle: nil)

    self.assetManager = AppDelegate.fragmentAssetManager
  }

  required init?(coder: NSCoder) {
    Fatal.safeError("init(coder:) has not been implemented")
  }

  func updateProgress(_ progress: Float) {
    // no-op
  }

  // MARK: - UIViewController

  override func viewDidLoad() {
    super.viewDidLoad()
    setupUI()
    setupTakeCapture()
    setupButtonBarStackView()
  }

  // MARK: - Public Methods

  public func setFlipCameraButtonAction(target: Any?,
                                        selector: Selector,
                                        forEvent: UIControl.Event) {
    flipCameraButton.addTarget(target, action: selector, for: forEvent)
  }

  func flipCamera() -> Future<Bool, CaptureError> {
    guard let takeViewController = takeViewController else {
      return Future(error: .TriedToModifyCaptureWhileNotReady)
    }
    return takeViewController.flipCamera()
  }

  public func showFlipCameraButton(animated: Bool = true) {
    guard animated else {
      flipCameraButton.isHidden = false
      return
    }
    flipCameraButton.alpha = 0.0
    flipCameraButton.isHidden = false
    UIView.animate(withDuration: Constants.showHideAnimationDuration) {
      self.flipCameraButton.alpha = 1.0
    }
  }

  func showHeadphoneMessage() {
    takeViewController?.showHeadphoneMessage()
  }

  func hideHeadphoneMessage() {
    takeViewController?.hideHeadphoneMessage()
  }

  func getTakeThumbnail(takeNumber: Int) -> UIImage? {
    return takeViewController?.getTakeThumbnail(takeNumber: takeNumber)
  }

  func setClipDeletionVisibility(hidden: Bool) {
    deleteButton.isHidden = hidden
  }

  // MARK: - Private Helpers

  fileprivate func setupUI() {
    self.view.clipsToBounds = true
    self.view.layer.cornerRadius = Constants.cornerRadius
  }

  fileprivate func setupTakeCapture() {
    // TODO : Check the BPM for the buffer and get it off the snapper.
    // Until we have BPM on the assets just default to 1 second.
    let beatPadding = BeatSnapper.getDurationOfBeats(BPM: BPM, beatCount: Constants.numberOfBeatsPerBuffer)
    self.takeViewController = TakeViewController(duration: duration,
                                                 countDownInterval: countDownTime.toSeconds(),
                                                 editPadding: beatPadding,
                                                 assetManager: assetManager,
                                                 delegate: self,
                                                 avSessionQueue: avSessionQueue,
                                                 initialTakeCount: initialTakeCount)

    guard let takeViewController = self.takeViewController else { return }
    self.view.addSubview(takeViewController.view)
  }

  fileprivate func setupButtonBarStackView() {

    deleteView.addSubview(deleteButton)
    buttonStackView.addArrangedSubview(deleteView)
    deleteButton.addTarget(self, action: #selector(didTapDelete(_:)), for: .touchUpInside)
    setClipDeletionVisibility(hidden: true)

    // Padding to fill the middle of the view when we conditionally add other views.
    buttonStackView.addArrangedSubview(paddingView)

    buttonStackView.addArrangedSubview(flipCameraButton)
    flipCameraButton.isHidden = true

    self.view.addSubview(buttonStackView)

    NSLayoutConstraint.activate([
      deleteButton.centerYAnchor.constraint(equalTo: deleteView.centerYAnchor),
      buttonStackView.leftAnchor.constraint(equalTo: self.view.leftAnchor, constant: FragmentCreationViewController.buttonBarTopInset),
      buttonStackView.rightAnchor.constraint(equalTo: self.view.rightAnchor, constant: -FragmentCreationViewController.buttonBarSideInset),
      buttonStackView.topAnchor.constraint(equalTo: self.view.topAnchor, constant: FragmentCreationViewController.buttonBarTopInset),
      buttonStackView.heightAnchor.constraint(equalToConstant: FragmentCreationViewController.buttonBarHeight),
      flipCameraButton.widthAnchor.constraint(equalTo: flipCameraButton.heightAnchor)
    ])
  }

  @objc func didTapDelete(_ sender: UIButton) {
    delegate?.didTapDeleteClip(viewController: self)
  }
}

// MARK: - Recording

extension CreationRecordViewController {
  func startRecording() {
    hideHeadphoneMessage() // redundant but should catch the occasional case where the headphone message doesn't dismiss
    totalLoopsWhileRecording = 0
    takeViewController?.startRecording()
  }

  func stopRecording(shouldDiscard: Bool = false) {
    // set discardTakes here to avoid race condition with stopping video
    self.takeViewController?.shouldDiscardTakes = shouldDiscard
    // Allow a small recording buffer to make sure we've actually recorded the entire take
    // and to give us some buffer when nudging to account for headphone latency. Worst case
    // this adds an extra take if the user tried to stop right before the take completed.
    DispatchQueue.main.asyncAfter(deadline: .now() + Constants.recordingBuffer) {
      [weak self] in self?.takeViewController?.stopRecording()
    }
  }

  func looped(atTime: CMTime, loopCount: Int) {
    totalLoopsWhileRecording += 1
    takeViewController?.startTake(atTime: atTime)
  }
}

// MARK: - TakeViewControllerDelegate

extension CreationRecordViewController: TakeViewControllerDelegate {
  func readyToRecord() {
    DispatchQueue.main.async {
      self.delegate?.readyToRecord()
    }
  }

  func stoppedRecording() {
    DispatchQueue.main.async {
      self.delegate?.recordStopped()
    }
  }

  func restoreUI() {
    DispatchQueue.main.async {
      self.delegate?.restoreUI()
    }
  }

  func generatedFragments(fragments: [FragmentHost]) {
    // Exit record mode.
    DispatchQueue.main.async {
      self.delegate?.recordFinished(fragments: fragments)
    }
  }
}

// MARK: - Max Recording Limit

extension CreationRecordViewController {
  func activateRecordingLimitTimer(startCount: Int,
                                   completion: (() -> Void)? = nil) {
    takeViewController?.activateRecordingLimitTimer(startCount: startCount,
                                                    completion: completion)
  }
}
