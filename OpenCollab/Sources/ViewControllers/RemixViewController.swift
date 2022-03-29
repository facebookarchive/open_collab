// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import AVFoundation
import BrightFutures
import UIKit

enum RecordState {
  case none
  case promptForHeadphones
  case promptForMetronomeNux
  case done
}

enum RemixState {
  case
  none,
  remix,
  record
}

class RemixViewController: UIViewController {
  enum Constants {
    static let maxClipsPerCollab = 6
    static let slidePadding: CGFloat = 2.0
    static let verticalPadding: CGFloat = 10.0
    static let additionalSidePadding: CGFloat = 20.0
    static let actionStackViewMinHeight: CGFloat = 74.0
    static let timerLimit = 4.0
    static let bricHeight: CGFloat = 58.0
    static let spinnerContainerAlpha: CGFloat = 0.75
    static let previewButtonHeight: CGFloat = 32.0
    static let previewButtonWidth: CGFloat = 100.0
    static let previewButtonPadding: CGFloat = 26.0
    static let addButtonHeight: CGFloat = Constants.previewButtonHeight - 2
    static let addButtonWidth: CGFloat = 58.0
    static let addButtonCornerRadius: CGFloat = 6.0
    static let defaultBPM = 128
    static let defaultBeatsPerBar = 4
    static let defaultAccentedBeatInBar = 1
    static let clipsTrayHeight: CGFloat = RemixTrayViewController.clipsTrayHeight + RemixTrayViewController.tabBarHeight + RemixTrayViewController.verticalSpacing
    static let buttonDisabledAlpha: CGFloat = 0.4
    static let recordPlaceholderIndex = 0
    static let firstFragmentIndex = recordPlaceholderIndex + 1 // 0th index contains the record placeholder
  }

  // Init Properties
  fileprivate var creationSessionToken = arc4random()
  fileprivate var sessionIntervalToken: AnyHashable?
  fileprivate var layoutEngine = LayoutEngineViewController(useMargins: true)
  fileprivate var playbackData: PlaybackDataModel
  fileprivate let initTime: CMTime
  fileprivate let initialPlaybackTime: CMTime?
  fileprivate var initialSetupComplete = false
  fileprivate var onFirstAppearance = true
  // Used to enforce not animating dismissing this view controller
  // it's used to mimic standard iOS tab switching behavior
  var shouldAnimateClose = true
  var actionViewDisabled = false

  // Data
  fileprivate var creationRecordViewController: CreationRecordViewController?

  fileprivate var remixTrayViewController: RemixTrayViewController
  fileprivate var selectedSlideshow: SlideshowViewController {
    willSet {
      guard newValue != selectedSlideshow else { return }
      // If we are about to focus away from a slideshow that has a record preview force it off the
      // record preview. This is a little hacky. Ideally we might want to revert back to
      // whatever was previously selected instead of just choosing the first clip.
      if let selectedRank = selectedRank,
         playbackData.selectedFragments[selectedRank].isRecordPlaceholder,
         let randomClip = playbackData.randomClip() {

        playbackData.selectedFragments[selectedRank] = randomClip
      }
    }
    didSet {
      guard oldValue != selectedSlideshow else { return }

      selectedFragmentsChanged()

      oldValue.isSelected = false
      selectedSlideshow.isSelected = true
    }
  }

  fileprivate var selectedRank: Int? {
    return slideshows.firstIndex(of: selectedSlideshow)
  }

  fileprivate var fragmentMatrix: [[FragmentCreationViewController?]] = [] {
    didSet {
      toggleAddButtonVisibility(enabled: true, animated: false)
      toggleDeleteButtonsVisibility(enabled: true)
      togglePreviewButtonVisibility(enabled: true, animated: false)
    }
  }
  fileprivate var recordState = RecordState.none
  fileprivate var recordPreviewActive: Bool = false
  fileprivate var creationState = RemixState.none

  fileprivate var beatsPerBar: Int = Constants.defaultBeatsPerBar
  fileprivate var accentedBeatInBar: Int = Constants.defaultAccentedBeatInBar

  fileprivate var duration: CMTime {
    didSet {
      setupPlaybackCoordinator(duration: duration)
    }
  }
  fileprivate var playbackCoordinator: PlaybackCoordinator? {
    willSet {
      self.playbackCoordinator?.clear()
    }
  }

  fileprivate var slideshows: [SlideshowViewController] = []
  fileprivate var interactionsAreLocked: Bool = false {
    didSet {
      // Control scrolling for all slideshows
      slideshows.forEach {
        if interactionsAreLocked {
          $0.disableScrolling()
        } else {
          $0.enableScrolling()
        }
      }

      // Control clip tray selection
      remixTrayViewController.toggleClipSelectionEnabled(enabled: !interactionsAreLocked)

      // Control clip addition
      toggleAddButtonVisibility(enabled: !interactionsAreLocked, animated: true)

      // Control clip deletion
      toggleDeleteButtonsVisibility(enabled: !interactionsAreLocked)

      // Control ability to preview
      togglePreviewButtonVisibility(enabled: !interactionsAreLocked, animated: true)

      // Control navigation from creation
      toggleCloseButtonVisibility(enabled: !interactionsAreLocked)
    }
  }

  fileprivate var isRecording = false {
    didSet {
      if !isRecording {
        maxRecordLimitDispatchItem = nil
        recordButtonUpdateDispatchItem = nil
      }
    }
  }

  fileprivate var isNudging = false

  fileprivate var BPM: Int = Constants.defaultBPM {
    didSet {
      creationRecordViewController?.BPM = BPM
    }
  }

  fileprivate var invalidSingleClip = false {
    didSet {
      if oldValue != invalidSingleClip {
        updateTitleMessage()
      }
    }
  }
  // countDownTime should be uniformly calculated between CreationRecordViewController, RecordViewController, RemixViewController and TakeViewController.
  // TODO : Consolidate countDownTime better across all the controllers its used.
  fileprivate var countDownTime: CMTime {
    get {
      let halfBPM = BPM / 2
      return BeatSnapper.timePerBeat(BPM: halfBPM)
    }
  }
  fileprivate var maxRecordLimitDispatchItem: DispatchWorkItem? {
    willSet {
      maxRecordLimitDispatchItem?.cancel()
    }
  }
  fileprivate var recordButtonUpdateDispatchItem: DispatchWorkItem? {
    willSet {
      recordButtonUpdateDispatchItem?.cancel()
    }
  }

  fileprivate let spinnerContainerView = UIView()
  fileprivate let spinnerView = SpinnerView.withSize(size: Constants.bricHeight)
  fileprivate var dimOverlayView: UIView?

  fileprivate lazy var unmuteView: UILabel =
    UINib(nibName: "UnmuteView", bundle: nil)
      .instantiate(withOwner: nil, options: nil)[0] as! UILabel

  fileprivate lazy var singleClipInvalidView: UILabel =
    UINib(nibName: "SingleClipInvalidView", bundle: nil)
      .instantiate(withOwner: nil, options: nil)[0] as! UILabel

  let previewButton: UIButton = {
    let btn = UIButton(type: .custom)
    btn.setTitle("Preview ", for: .normal)
    btn.titleLabel?.font = .boldSystemFont(ofSize: 14)
    btn.translatesAutoresizingMaskIntoConstraints = false
    btn.backgroundColor = .white
    btn.setTitleColor(.black, for: .normal)
    btn.clipsToBounds = true
    btn.layer.cornerRadius = Constants.previewButtonHeight / 2.0

    NSLayoutConstraint.activate([
      btn.widthAnchor.constraint(equalToConstant: Constants.previewButtonWidth),
      btn.heightAnchor.constraint(equalToConstant: Constants.previewButtonHeight)
    ])

    return btn
  }()
  let addButton: UIButton = {
    let btn = UIButton(type: .custom)
    btn.translatesAutoresizingMaskIntoConstraints = false
    btn.setTitle("Add", for: .normal)
    btn.titleLabel?.font = .boldSystemFont(ofSize: 14)
    btn.setTitleColor(.black, for: .normal)
    btn.backgroundColor = .white
    btn.clipsToBounds = true
    btn.layer.cornerRadius = Constants.addButtonCornerRadius

    NSLayoutConstraint.activate([
      btn.widthAnchor.constraint(equalToConstant: Constants.addButtonWidth),
      btn.heightAnchor.constraint(equalToConstant: Constants.addButtonHeight)
    ])

    return btn
  }()
  var recordThumbnail: UIImageView {
    let imageView = UIImageView(image: UIImage(systemName: "camera")?.withRenderingMode(.alwaysTemplate))
    imageView.frame = CGRect(x: 0, y: 0, width: RemixTrayViewController.clipsTrayHeight, height: RemixTrayViewController.clipsTrayHeight)
    imageView.tintColor = .purple
    return imageView
  }
  var emptyThumbnail: UIImageView {
    let imageView = UIImageView()
    let imageGradientLayer = CAGradientLayer()
    imageGradientLayer.colors = [UIColor(rgb: 0xC365EF).cgColor, UIColor(rgb: 0x3F27D3).cgColor]
    imageGradientLayer.startPoint = CGPoint(x: 1.0, y: 0.0)
    imageGradientLayer.endPoint = CGPoint(x: 0.0, y: 1.0)
    imageGradientLayer.locations = [0.00, 1.25]
    imageGradientLayer.frame = CGRect(x: 0, y: 0, width: RemixTrayViewController.clipsTrayHeight, height: RemixTrayViewController.clipsTrayHeight)

    imageView.layer.addSublayer(imageGradientLayer)
    imageView.frame = CGRect(x: 0, y: 0, width: RemixTrayViewController.clipsTrayHeight, height: RemixTrayViewController.clipsTrayHeight)
    return imageView
  }

  // MARK: - Init

  required init?(coder: NSCoder) {
    Fatal.safeError()
  }

  init(model: PlaybackDataModel, initialPlaybackTime: CMTime?) {
    var recordFragmentHost = FragmentHost(assetInfo: .empty, assetDuration: model.duration)
    recordFragmentHost.isRecordPlaceholder = true
    model.recordFragment = recordFragmentHost

    if model.selectedFragments.count < Constants.maxClipsPerCollab {
      model.selectedFragments.append(recordFragmentHost)
    } else {
      model.selectedFragments[model.selectedFragments.count - 1] = recordFragmentHost
    }

    self.playbackData = model
    self.duration = model.duration
    self.initTime = CMClockGetTime(CMClockGetHostTimeClock())
    self.initialPlaybackTime = initialPlaybackTime
    self.remixTrayViewController = RemixTrayViewController(clipsTrayCollectionView: ClipsTrayCollectionViewController.withDefaultLayout())

    self.selectedSlideshow = SlideshowViewController(slideViews: [])
    super.init(nibName: nil, bundle: nil)
    remixTrayViewController.delegate = self
    playbackData.delegate = self

    setupPlaybackCoordinator(duration: duration)
    buildInitialFragmentMatrix()
    buildClipsTray()
  }

  // MARK: - UIViewController

  override public func viewDidLoad() {
    super.viewDidLoad()
    setupUI()

    self.view.addSubview(remixTrayViewController.view)
    previewButton.addTarget(self, action: #selector(didSelectNextRemixButton(_:)), for: .touchUpInside)
    addButton.addTarget(self, action: #selector(didSelectAddButton(_:)), for: .touchUpInside)

    remixTrayViewController.setRecordButtonAction(target: self,
                                                  selector: #selector(didClickRecordButton(_:)),
                                                  forEvent: .touchUpInside)

    NotificationCenter.default.addObserver(self,
                                           selector: #selector(updateTitleMessage),
                                           name: AppMuteManager.Notifications.muteSwitchStateChanged,
                                           object: nil)
    NotificationCenter.default.addObserver(self,
                                           selector: #selector(updateTitleMessage),
                                           name: AppHeadphoneManager.Notifications.headphoneStateChanged,
                                           object: nil)
    NotificationCenter.default.addObserver(self,
                                           selector: #selector(resetManualSyncing),
                                           name: AppHeadphoneManager.Notifications.headphoneTypeChanged,
                                           object: nil)

    self.navigationItem.leftBarButtonItem?.image = UIImage(systemName: "arrow.left")?.withRenderingMode(.alwaysTemplate)
    self.navigationItem.leftBarButtonItem?.tintColor = .white

    // ## TODO: For the ability to import a pool of existing fragments which can then be used in remix,
    // uncomment the following line and implement a way to pull those fragments in:

    // self.loadFragments()
  }

  override public func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    print("------------------------------------ ENTER REMIX -----------------------------------")

    // keep screen on for the duration of creation session
    // this setting will be reset when creation session ends
    // either by publishing or exiting creation.
    UIApplication.shared.isIdleTimerDisabled = true

    if AppMuteManager.shared.currentState() == .Muted {
      AppMuteManager.shared.toggleMuteState()
    }
    updateTitleMessage()
    initialSetupComplete = true

    if onFirstAppearance {
      self.selectedSlideshow = slideshows[slideshows.count - 1]
      onFirstAppearance = false
    } else {
      // Trigger a scroll event so that playback will attach
      slideshows.forEach {
        $0.scrollViewDidScroll($0.scrollView)
      }
    }
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    self.view.clipsToBounds = true
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)

    cleanup()
    print("------------------------------------ EXIT REMIX -----------------------------------")
  }

  override public func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()

    let bounds = self.view.bounds
    let safeAreaInsets = self.view.safeAreaInsets
    let safeAreaBounds = bounds.inset(by: safeAreaInsets)

    layoutEngine.view.frame = RemixViewController.calculateContentFrame(bounds: bounds,
                                                                                    safeAreaInsets: safeAreaInsets,
                                                                                    creationState: creationState,
                                                                                    dismissActionView: actionViewDisabled)
    let actionFrame: CGRect
    let sideGap = layoutEngine.view.frame.minX - safeAreaBounds.origin.x
    actionFrame = CGRect(x: safeAreaBounds.origin.x + sideGap / 2,
                         y: layoutEngine.view.frame.maxY,
                         width: safeAreaBounds.width - sideGap / 2,
                         height: Constants.clipsTrayHeight)
    remixTrayViewController.view.frame = actionFrame

    let viewsToLayout: [UIView] = slideshows.map { $0.view } // slidesshow is not set up yet, so layout engine will fatal error
    layoutEngine.configurePlaybackViewCells(playbackViews: viewsToLayout)

    guard let window = self.view.window else { return }
    spinnerContainerView.frame = window.bounds
  }

  public static func calculateContentFrame(bounds: CGRect,
                                    safeAreaInsets: UIEdgeInsets,
                                    creationState: RemixState,
                                    dismissActionView: Bool = false) -> CGRect {
    var insets = safeAreaInsets
    insets.right += Constants.additionalSidePadding
    insets.left += Constants.additionalSidePadding
    if !dismissActionView {
      let actionViewHeight = Constants.clipsTrayHeight
      insets.bottom += actionViewHeight
    }
    insets.bottom += 2.0 * Constants.verticalPadding
    let contentMaxBounds = bounds.inset(by: insets)
    let collabSize = AspectRatioCalculator.collabSizeThatFits(size: contentMaxBounds.size)
    let contentSize = CGSize(width: collabSize.width,
                             height: collabSize.height + 2.0 * Constants.verticalPadding)
    let origin = CGPoint(x: contentMaxBounds.midX - contentSize.width / 2.0,
                         y: contentMaxBounds.origin.y)
    return CGRect(origin: origin, size: contentSize)
  }

  public func disableActionView() {
    actionViewDisabled = true
  }

  fileprivate func renderLayout(_ views: [UIView]? = nil) {
    self.view.setNeedsLayout()
    self.view.layoutIfNeeded()
  }

  // MARK: - Setup

  fileprivate func setupUI() {
    self.view.backgroundColor = .black

    self.view.addSubview(layoutEngine.view)

    let navigationActionButtons = [UIBarButtonItem(customView: previewButton), UIBarButtonItem(customView: addButton)]
    navigationItem.setRightBarButtonItems(navigationActionButtons, animated: false)
    setupSpinner()

    nextCreationState()
    self.navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "xmark")?.withRenderingMode(.alwaysTemplate),
                                                            style: .plain,
                                                            target: self,
                                                            action: #selector(didTapBack))
  }

  fileprivate func buildSlideViewForFragment(_ fragment: FragmentCreationViewController) -> SlideView {
    var slide = SlideView(view: fragment.view, thumbnailURL: nil, thumbnailImage: nil)
    if fragment.fragment.assetInfo.isUserRecorded {
      if let thumbnailImage = fragment.fragment.localThumbnailImage {
        let imageView = UIImageView(image: thumbnailImage)

        imageView.frame = CGRect(x: 0, y: 0, width: RemixTrayViewController.clipsTrayHeight, height: RemixTrayViewController.clipsTrayHeight)

        slide.thumbnailImage = imageView
      } else {
        slide.thumbnailImage = emptyThumbnail
      }
      if let takeNumber = playbackData.takeFragments.firstIndex(where: { $0.assetInfo.userRecordedURL == fragment.fragment.assetInfo.userRecordedURL }) {
        slide.takeNumber = takeNumber + 1
      }
    } else if let f = fragment.fragment.assetInfo.downloadedFragment {
      slide.thumbnailURL = f.thumbnailURL
    } else if fragment.isRecordPlaceholderFragment {
      slide.thumbnailImage = recordThumbnail
    }
    return slide
  }

  fileprivate func buildSlideViewForFragment(_ fragment: FragmentHost) -> SlideView {
    if fragment.isRecordPlaceholder {
      return SlideView(view: UIView(),
                       thumbnailURL: nil,
                       thumbnailImage: recordThumbnail)
    }

    var slide = SlideView(view: UIView(), thumbnailURL: nil, thumbnailImage: nil)
    if fragment.assetInfo.isUserRecorded {
      if let thumbnailImage = fragment.localThumbnailImage {
        let imageView = UIImageView(image: thumbnailImage)

        imageView.frame = CGRect(x: 0, y: 0, width: RemixTrayViewController.clipsTrayHeight, height: RemixTrayViewController.clipsTrayHeight)

        slide.thumbnailImage = imageView
      } else {
        slide.thumbnailImage = emptyThumbnail
      }
      if let takeNumber = playbackData.takeFragments.firstIndex(where: { $0.assetInfo.userRecordedURL == fragment.assetInfo.userRecordedURL }) {
        slide.takeNumber = takeNumber + 1
      }
    } else if let f = fragment.assetInfo.downloadedFragment {
      slide.thumbnailURL = f.thumbnailURL
    }
    return slide
  }

  fileprivate func setupPlaybackCoordinator(duration: CMTime) {
    playbackCoordinator =
      PlaybackCoordinator(gracePeriod: 0.3,
                          duration: duration)
    self.playbackCoordinator?.delegate = self

    guard let initialPlaybackTime = initialPlaybackTime, onFirstAppearance else { return }
    playbackCoordinator?.resetToTime(playbackTime: initialPlaybackTime, atTime: initTime)
  }

  fileprivate func setupRecord(rank: Int) {
    guard !recordPreviewActive else { return }
    recordPreviewActive = true

    recordState = .none
    playbackCoordinator?.pause()
    remixTrayViewController.toggleRecordButtonEnabled(enabled: false)

    AppHeadphoneManager.shared
      .setAudioSessionForRecord(on: AppDelegate.avSessionQueue).onComplete { _ in
        self.creationRecordViewController =
          CreationRecordViewController(duration: self.duration,
                                       initialTakeCount: self.playbackData.takeFragments.count,
                                       BPM: self.BPM,
                                       avSessionQueue: AppDelegate.avSessionQueue,
                                       delegate: self)
        self.creationRecordViewController?
          .setFlipCameraButtonAction(target: self,
                                     selector: #selector(self.didClickFlipCameraButton(_:)),
                                     forEvent: .touchUpInside)

        guard let creationRecordViewController = self.creationRecordViewController else { return }

        let newSlide = SlideView(view: creationRecordViewController.view, thumbnailImage: self.recordThumbnail)
        self.slideshows[rank].replaceSlide(view: newSlide, index: 0)
        self.nextCreationState()
      }
  }

  fileprivate func removeCaptureView() {
    guard let recordRank = selectedRank,
          slideshows.count > recordRank,
          recordPreviewActive else { return }
    recordPreviewActive = false

    let slideshow = slideshows[recordRank]
    // Right now record placeholder should always be index 0, but we shouldn't assume so in the future
    guard let index = fragmentMatrix[recordRank].firstIndex(where: { $0?.isRecordPlaceholderFragment ?? false }) else { return }
    let placeholderSlide = SlideView(view: UIView(), thumbnailImage: recordThumbnail)
    slideshow.replaceSlide(view: placeholderSlide, index: index)
  }

  // MARK: - Reset & Cleanup

  private func removeSingularSlideshowFromView(slideshow: SlideshowViewController) {
    slideshow.didMove(toParent: nil)
    slideshow.view.removeFromSuperview()
    slideshow.removeFromParent()
  }

  fileprivate func immediatelyDetachAllPlayersInMatrix(previewImageToo: Bool = true) {
    guard Thread.isMainThread else { Fatal.safeError("Should be on main thread") }

    for fragmentRow in fragmentMatrix {
      for fragmentController in fragmentRow {
        guard let fragment = fragmentController?.fragment else { return }
        playbackCoordinator?.detachImmediately(fragment: fragment,
                                               previewImageToo: true)
      }
    }
  }

  fileprivate func attachVisiblePlayersInMatrix() {
    guard Thread.isMainThread else { Fatal.safeError("Should be on main thread") }
    for (rank, fragmentRow) in fragmentMatrix.enumerated() {
      guard fragmentRow.count > 0 && rank != selectedRank && rank < slideshows.count else { continue }
      let currentIndex = slideshows[rank].currentIndex()

      guard let fragment = getFragment(rank: rank, index: currentIndex) else { return }
      playbackCoordinator?.attach(fragment: fragment)
    }
  }

  fileprivate func clearPlayback() {
    playbackCoordinator?.clear()
  }

  fileprivate func cleanup() {
    guard Thread.isMainThread else { Fatal.safeError("Should be on main thread") }

    immediatelyDetachAllPlayersInMatrix()
    clearPlayback()
  }

  // MARK: - Private Helpers

  fileprivate func getFragmentController(rank: Int, index: Int) -> FragmentCreationViewController? {
    guard Thread.isMainThread else { Fatal.safeError("Should be on main thread") }

    guard rank < self.fragmentMatrix.count,
      rank >= 0,
      index < self.fragmentMatrix[rank].count,
      index >= 0 else {
      return nil
    }

    return fragmentMatrix[rank][index]
  }

  fileprivate func getFragment(rank: Int, index: Int) -> FragmentHost? {
    guard Thread.isMainThread else { Fatal.safeError("Should be on main thread") }

    guard rank < self.fragmentMatrix.count,
      rank >= 0,
      index < self.fragmentMatrix[rank].count,
      index >= 0 else {
      return nil
    }

    return fragmentMatrix[rank][index]?.fragment
  }

  fileprivate func getFragmentPosition(fragment: FragmentCreationViewController) -> (rank: Int, index: Int)? {
    guard Thread.isMainThread else { Fatal.safeError("Should be on main thread") }

    for (rank, fragments) in fragmentMatrix.enumerated() {
      guard let index = fragments.firstIndex(of: fragment) else { continue }
      return (rank, index)
    }

    return nil
  }

  fileprivate func getSlideshow(rank: Int) -> SlideshowViewController? {
    guard Thread.isMainThread else { Fatal.safeError("Should be called on main thread") }

    guard rank >= 0, rank < slideshows.count else { return nil }

    return slideshows[rank]
  }

  // MARK: - Button Action Handlers

  @objc fileprivate func didTapClose() {
    if isRecording {
      // TODO : Ask user if they want to stop recording, and return from this function
      stopRecording() }
    if playbackData.isCFS {
      didTapBackToTrim()
    }
    if getIsEnabled(button: previewButton) || playbackData.takeFragments.count > 0 {
      let alert = UIAlertController(title: "If you go back, your work will be discarded.", message: nil, preferredStyle: .actionSheet)
      alert.addAction(UIAlertAction(title: "Close & Discard", style: .destructive, handler: { _ in
        UIApplication.shared.isIdleTimerDisabled = false
        self.navigationController?.popViewController(animated: self.shouldAnimateClose)
      }))
      alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

      self.present(alert, animated: true)
    } else {
      UIApplication.shared.isIdleTimerDisabled = false
      self.navigationController?.popViewController(animated: shouldAnimateClose)
    }
  }

  @objc fileprivate func didSelectAddButton(_ sender: AnyObject?) {
    guard playbackData.selectedFragments.count < Constants.maxClipsPerCollab else { return }
    addNewRankToCollab()
    renderLayout()
  }

  @objc fileprivate func didSelectNextRemixButton(_ sender: AnyObject?) {
    guard Thread.isMainThread else { Fatal.safeError("Should be called on main thread") }
    previewCollab()
  }

  @objc func didClickFlipCameraButton(_ sender: AnyObject?) {
    guard !isRecording else { return }
    self.disableAllRecordButtons()

    creationRecordViewController?.flipCamera().onComplete {_ in
      DispatchQueue.main.async {
        // We don't really care if we failed or not. We should always re-enable the button.
        self.enableAllRecordButtons()
      }
    }
  }

  @objc func didClickRecordButton(_ sender: AnyObject?) {
    if isRecording {
      navigationItem.leftBarButtonItem?.action = nil
    }
    RecordingAuthorizer.isAuthorized(
    ).onSuccess { [self] (status) in
      guard status == .authorized else {
        RecordingAuthorizer.showUnauthorizedAlert(vc: self, status: status)
        navigationItem.leftBarButtonItem?.action = #selector(didTapBack)
        return
      }
      if isRecording {
        stopRecording()
      } else {
        startRecording()
      }
    }.onFailure { (_) in
      Fatal.safeError("RecordingAuthorizer should not fail")
    }
  }

  // MARK: - UI Record State Handlers

  fileprivate func next() {
    DispatchQueue.main.async {
      self.clearUIState(currentState: self.recordState)
      self.recordState = self.calculateNextState(currentState: self.recordState)

      switch self.recordState {
      case .none, .promptForMetronomeNux:
        break
      case .promptForHeadphones:
        // delay nux slightly so auth requests do not interfere with UI thread
        DispatchQueue.main.asyncAfter(deadline: .now()) {
          self.promptForHeadphones()
        }

      case .done:
        self.activateAllVolumeSelectors()
        self.creationRecordViewController?.shouldShowDeletionUI = self.playbackData.selectedFragments.count > 1
        self.creationRecordViewController?.showFlipCameraButton(animated: true)
        self.remixTrayViewController.toggleRecordButtonEnabled(enabled: true)
      }
    }
  }

  fileprivate func clearUIState(currentState: RecordState) {
    removeFragmentManagedSubviews()

    switch recordState {
    case .promptForHeadphones:
      creationRecordViewController?.hideHeadphoneMessage()

    case .none, .promptForMetronomeNux, .done:
      return
    }
  }

  fileprivate func calculateNextState(currentState: RecordState) -> RecordState {
    switch currentState {
    case .none:
      if AppHeadphoneManager.shared.currentState() == .Connected {
        return RecordState.done
      } else {
        return RecordState.promptForHeadphones
      }

    case .promptForHeadphones:
      return RecordState.done

    case .done, .promptForMetronomeNux:
      return .done
    }
  }

  fileprivate func disableAllRecordButtons() {
    remixTrayViewController.recordButton.isUserInteractionEnabled = false
    creationRecordViewController?.flipCameraButton.isUserInteractionEnabled = false
  }

  fileprivate func enableAllRecordButtons() {
    remixTrayViewController.recordButton.isUserInteractionEnabled = true
    creationRecordViewController?.flipCameraButton.isUserInteractionEnabled = true
  }

  fileprivate func displayDimOverlay(around view: UIView?, completion: (() -> Void)? = nil) {
    guard let view = view,
          let window = self.view.window else { return }
    if let existingOverlay = self.dimOverlayView, existingOverlay.isDescendant(of: window) {
      existingOverlay.removeFromSuperview()
      self.dimOverlayView = nil
    }
    guard let superview = view.superview else { return }
    let translatedFrame = window.convert(view.frame, from: superview)
    let dimOverlay = DimOverlayView(initialView: window, ommittedLocation: translatedFrame, completion: completion)
    dimOverlayView = dimOverlay
    self.view.addSubview(dimOverlay)
  }

  func recordPromptOverlayDismissed() {
    dimOverlayView?.removeFromSuperview()
    dimOverlayView = nil
    next()
  }

  fileprivate func promptForHeadphones() {
    displayDimOverlay(around: creationRecordViewController?.view, completion: recordPromptOverlayDismissed)
    creationRecordViewController?.showHeadphoneMessage()
  }

  fileprivate func deactivateAllSelectors() {
    for (rank, fragmentRow) in fragmentMatrix.enumerated() {
      guard fragmentRow.count > 0 else { continue }
      let currentIndex = slideshows[rank].currentIndex()
      let fragmentHost = getFragmentController(rank: rank, index: currentIndex)

      fragmentHost?.deactivateSelector()
    }
  }

  fileprivate func activateAllVolumeSelectors() {
    for (rank, fragmentRow) in fragmentMatrix.enumerated() {
      guard fragmentRow.count > 0 else { continue }
      let currentIndex = slideshows[rank].currentIndex()
      let fragmentController = getFragmentController(rank: rank, index: currentIndex)

      fragmentController?.enableAdjustmentUI()
    }
  }

  fileprivate func removeFragmentManagedSubviews() {
    for (rank, fragmentRow) in fragmentMatrix.enumerated() {
      guard fragmentRow.count > 0 else { continue }
      guard fragmentRow.count >= slideshows[rank].currentIndex() else {
        print("Error when removing fragment managed subviews in remix: Row \(rank) in fragment matrix has only \(fragmentRow.count) fragments, but we are trying to access index #\(slideshows[rank].currentIndex())")
        continue
      }
      let fragmentHost = fragmentRow[slideshows[rank].currentIndex()]

      fragmentHost?.removeManagedSubview()
    }
  }

  @objc fileprivate func updateTitleMessage() {
    DispatchQueue.main.async {
      if self.invalidSingleClip {
        self.navigationItem.titleView = self.singleClipInvalidView
        return
      }

      let isMuted = AppMuteManager.shared.currentState() == .Muted
      let headphonesIn = AppHeadphoneManager.shared.currentState() == .Connected
      print("Creation audio state: muted = \(isMuted), headphones in = \(headphonesIn)")
      self.navigationItem.titleView = isMuted ? self.unmuteView : nil
    }
  }

  fileprivate func positionOfFragment(fragmentController: FragmentCreationViewController) -> (rank: Int, index: Int) {
    for (rank, fragmentRow) in fragmentMatrix.enumerated() {
      guard let index =
        fragmentRow.firstIndex(of: fragmentController) else { continue }

      return (rank: rank, index: index)
    }
    Fatal.safeError("fragment \(fragmentController) not found in matrix \(fragmentMatrix)")
  }

  // MARK: - Back Button State Handlers

  fileprivate func nextCreationState() {
    let currentState = self.creationState
    switch currentState {
    case .none:
      creationState = .remix
    case .remix:
      creationState = .record
      invalidSingleClip = false
    case .record:
      creationState = .remix
    }
  }

  @objc func didTapBack() {
    didTapClose()
    creationState = .none
  }

  @objc func didTapBackToTrim() {
    if playbackData.takeFragments.count > 1 {
      let alert = UIAlertController(title: "Discard New Recordings?", message: "If you go back now you will lose all clips added to your original loop", preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: "Discard", style: .destructive, handler: { _ in
        self.navigationController?.popViewController(animated: true)
      }))
      alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

      self.present(alert, animated: true)
    } else {
      navigationController?.popViewController(animated: true)
    }
  }

  // MARK: - Post-Record Flow

  fileprivate func insertNewRecordedClips(fragments: [FragmentHost]) {

    // Triggers a rebuild of the clips tray
    playbackData.takeFragments.append(contentsOf: fragments)

    guard let selectedRank = selectedRank else {
      Fatal.safeAssert("Couldn't find selected slideshow")
      return
    }

    updateTakeFragmentsInMatrix(takeFragments: fragments)
    playbackData.selectedFragments[selectedRank] = fragments[fragments.count - 1]
  }

  fileprivate func previewCollab() {

    enableSpinner()

    var fragments: [FragmentHost] = []
    for (rank, slide) in slideshows.enumerated() {
      let index = slide.currentIndex()
      guard let fragment = getFragment(rank: rank, index: index) else { continue }
      let publishFragment = FragmentHost(fragment: fragment)
      fragments.append(publishFragment)
    }

    properlyCropRecordedFragments(fragments: fragments)
  }

  private func pushPublishViewController(fragments: [FragmentHost]) {
    let publishViewController = PublishViewController(fragments: fragments,
                                                      duration: duration)
    self.navigationController?.pushViewController(publishViewController,
                                                  animated: true)
  }

  private func properlyCropRecordedFragments(fragments: [FragmentHost]) {
    let croppingFutures: [Future<FragmentHost, RasterizationError>] =
      fragments.enumerated().map { (index, fragment) -> Future<FragmentHost, RasterizationError> in
        if fragment.assetInfo.isUserRecorded {
          return TakeGenerator.cropFragment(fragment: fragment, clipIndex: index, numberOfClips: fragments.count)
        } else {
          return Future(value: fragment)
        }
      }

    croppingFutures.sequence().onSuccess { [weak self] fragments in
      guard let self = self else { return }
      self.stopSpinner()
      self.pushPublishViewController(fragments: fragments)
    }.onFailure { [weak self] (error) in
      guard let self = self else { return }
      self.stopSpinner()
      // ## TODO : Show an error view with the option to retry
    }
  }

  // MARK: - Public Methods

  public func pausePlayback() {
    playbackCoordinator?.pause()
  }

  public func unpausePlayback() {
    playbackCoordinator?.unpause(playbackTime: nil)
  }
}

// MARK: - Remix Methods

extension RemixViewController {
  fileprivate func loadFragments() {
    // ## TODO : return if there's no pool to load fragments from
    // ## TODO : Once fragments (of type [Fragment] are pulled in, do the following:
        // self.insertFragments(fragments: fragments)
        // let selectedIndices = self.getSelectedIndices()
        // self.preloadNeighbors(indices: selectedIndices)
  }

  fileprivate func insertFragments(fragments: [Fragment]) {
    // Shuffle fragments
    let fragmentHosts: [FragmentHost] = fragments.map {
      let assetInfo = AssetInfo.create(fragment: $0)
      let fragmentHost =
        FragmentHost(assetInfo: assetInfo,
                     volume: 1.0,
                     assetDuration: self.playbackData.duration,
                     playbackEndTime: self.playbackData.duration)
      return fragmentHost
    }
    var shuffledFragments = fragmentHosts.shuffled()

    // Remove the existing fragments.
    shuffledFragments.removeAll(where: {
      let newFragment = $0
      var alreadyExists = false

      playbackData.poolFragments.forEach {
        guard let newFragmentId = newFragment.assetInfo.downloadedFragment?.id,
              let existingFragmentId = $0.assetInfo.downloadedFragment?.id else { return }
        if newFragmentId == existingFragmentId { alreadyExists = true }
      }

      return alreadyExists
    })

    // Triggers the clips tray to rebuild
    let newPool = playbackData.poolFragments + shuffledFragments
    playbackData.poolFragments = newPool

    updatePoolFragmentsInMatrix(addedFragments: shuffledFragments)
  }

  fileprivate func getSelectedIndices() -> [Int] {
    var currentFragmentPositions: [Int] = []

    for (rank, _) in self.playbackData.selectedFragments.enumerated() {
      guard let index = playbackData.getSelectedIndex(rank: rank) else {
        Fatal.safeAssert("Couldn't find index of selected fragment")
        continue
      }

      currentFragmentPositions.append(index)
    }

    return currentFragmentPositions
  }

  fileprivate func preloadNeighbors(indices: [Int]) {
    guard let playbackCoordinator = playbackCoordinator else { return }

    indices.enumerated().forEach { (rank, index) in
      // As the download is operating as a LIFO
      // attach left first to give priority to the right
      if let left = getFragment(rank: rank, index: index - 1) {
        playbackCoordinator.attachPreview(fragment: left)

        if let remoteFragment = left.assetInfo.downloadedFragment {
          AppDelegate.fragmentAssetManager?
            .preloadAsset(remoteFragment: remoteFragment)
        }
      }
      if let right = getFragment(rank: rank, index: index + 1) {
        playbackCoordinator.attachPreview(fragment: right)

        if let remoteFragment = right.assetInfo.downloadedFragment {
          AppDelegate.fragmentAssetManager?
            .preloadAsset(remoteFragment: remoteFragment)
        }
      }
    }
  }

  private func buildInitialFragmentMatrix() {
    // Update UI data (Fragment Matrix)
    var initialFragmentMatrix: [[FragmentCreationViewController]] = []

    // Add row in matrix for each clip in the collab
    for fragment in playbackData.selectedFragments {
      var poolRow = buildFragmentMatrixRow()

      // Handle the case where the collab has an empty clip. In this case the pool will not have the empty clip.
      // Instead we'll just append it to the end of the row that its selected in.
      if !fragment.isRecordPlaceholder && fragment.assetInfo.isEmpty {
        let emptyFragmentController = FragmentCreationViewController(fragment: FragmentHost(fragment: fragment), delegate: self)
        poolRow.append(emptyFragmentController)
      }
      initialFragmentMatrix.append(poolRow)
    }

    fragmentMatrix = initialFragmentMatrix

    // Rebuild UI
    buildSlideshows()
  }

  private func updatePoolFragmentsInMatrix(addedFragments: [FragmentHost]) {
    for rank in 0...(fragmentMatrix.count - 1) {
      addedFragments.forEach {
        let fragmentController = FragmentCreationViewController(fragment: FragmentHost(fragment: $0),
                                                                delegate: self)
        fragmentMatrix[rank].append(fragmentController)
        slideshows[rank].appendSlide(view: buildSlideViewForFragment(fragmentController))
      }
    }
  }

  private func updateTakeFragmentsInMatrix(takeFragments: [FragmentHost]) {
    let takeLabelStart = playbackData.takeFragments.count - takeFragments.count + 1
    for rank in 0...(fragmentMatrix.count - 1) {
      for (takeNumber, take) in takeFragments.enumerated() {
        let titleLabel = takeLabelStart + takeNumber
        let fragmentController = FragmentCreationViewController(fragment: FragmentHost(fragment: take),
                                                                editable: true,
                                                                takeNumber: titleLabel,
                                                                delegate: self)
        fragmentMatrix[rank].insert(fragmentController,
                                    at: Constants.firstFragmentIndex)
        slideshows[rank].insertSlide(view: buildSlideViewForFragment(fragmentController),
                                     index: Constants.firstFragmentIndex)
      }
    }
  }

  fileprivate func addNewRankToCollab() {
    playbackData.canNotify = false
    guard let recordFragment = playbackData.recordFragment else { return }
    playbackData.selectedFragments.append(recordFragment)
    playbackData.canNotify = true

    // Update UI data (Fragment Matrix)
    let newRow = buildFragmentMatrixRow()
    fragmentMatrix.append(newRow)

    let slideshow = buildSingularSlideshow(fragmentRow: newRow)
    slideshows.append(slideshow)

    // Update selected UI
    selectedSlideshow = slideshows[slideshows.count - 1]
  }

  fileprivate func deleteRankFromCollab(rank: Int) {
    guard let oldSelectedRank = selectedRank else { return }

    // Update selectedSlideshow incase we are deleting it.
    if oldSelectedRank == rank {
      // Select the first slideshow if its not being deleted otherwise select the last.
      selectedSlideshow = rank != 0 ? slideshows[0] : slideshows[slideshows.count - 1]
    }

    playbackData.canNotify = false
    playbackData.selectedFragments.remove(at: rank)
    playbackData.canNotify = true

    // Update UI data (Fragment Matrix)
    fragmentMatrix.remove(at: rank)
    slideshows.remove(at: rank)
  }

  private func  buildFragmentMatrixRow() -> [FragmentCreationViewController] {
    var row: [FragmentCreationViewController] = []

    guard let recordFragment = playbackData.recordFragment else { return row }
    let recordPlaceholder = FragmentCreationViewController(fragment: recordFragment, delegate: self)
    recordPlaceholder.isRecordPlaceholderFragment = true
    row.append(recordPlaceholder)

    let takeFragmentControllers = playbackData.takeFragments.enumerated().map {
      FragmentCreationViewController(fragment: FragmentHost(fragment: $1),
                                     editable: !(playbackData.isCFS && $0 == 0),
                                     takeNumber: $0 + 1,
                                     delegate: self) // if the fragment is user recorded (and not first CFS clip), should be nudgeable
    }
    let poolFragmentControllers = playbackData.poolFragments.map {
      FragmentCreationViewController(fragment: FragmentHost(fragment: $0),
                                     delegate: self)
    }
    row.append(contentsOf: takeFragmentControllers.reversed())
    row.append(contentsOf: poolFragmentControllers)

    return row
  }

  fileprivate func buildSlideshows() {
    var rebuiltSlideshows = [SlideshowViewController]()

    let selectedIndices = getSelectedIndices()

    // Determine the index of the videos used in the collab and then create
    // a slideshow for each row from the corresponding fragment matrix
    // row and set the starting clip on the slideshow.
    for (rank, fragmentRow) in fragmentMatrix.enumerated() {
      let slideshow = buildSingularSlideshow(fragmentRow: fragmentRow, index: selectedIndices[rank])
      rebuiltSlideshows.append(slideshow)
    }

    slideshows = rebuiltSlideshows
  }

  fileprivate func buildSingularSlideshow(fragmentRow: [FragmentCreationViewController?], index: Int = 0) -> SlideshowViewController {
    // TODO : fragmentRow should not allow nils
    var fragmentViews: [SlideView] = []
    for fragment in fragmentRow {
      guard let fragment = fragment else { continue }
      let slide = buildSlideViewForFragment(fragment)
      fragmentViews.append(slide)
    }

    return SlideshowViewController(slideViews: fragmentViews,
                                  direction: .Horizontal,
                                  delegate: self,
                                  slidePadding: Constants.slidePadding,
                                  startingIndex: index)
  }

  fileprivate func buildClipsTray() {
    // Don't use slide view for clips tray, use fragment hosts instead if we can
    var slideViews: [SlideView] = []

    for fragmentHost in self.playbackData.combinedFragments {
      slideViews.append(buildSlideViewForFragment(fragmentHost))
    }

    self.remixTrayViewController.updateClips(slideViews: slideViews)
  }

  fileprivate func updateSelectedClipInTray() {
    guard let selectedRank = selectedRank,
          let index = playbackData.getSelectedIndex(rank: selectedRank) else { return }

    remixTrayViewController.updateSelectedClip(index: index)
  }

  fileprivate func updateSlideshowViews() {
    for (rank, slideshow) in slideshows.enumerated() {
      guard let index = playbackData.getSelectedIndex(rank: rank) else { continue }
      slideshow.scrollToIndex(index: index, animated: false)
    }
  }
}

// MARK: - Recording Support

extension RemixViewController {
  fileprivate func startRecording() {
    assert(Thread.isMainThread, "should be called on main thread")
    print("-------------------------------- RECORD START --------------------------------")

    isRecording = true

    // Lock certain UI actions and prompt the user to stop recording first.
    interactionsAreLocked = true

    let playbackTime =
      CMTimeSubtract(duration,
                     CMTimeMultiplyByFloat64(countDownTime, multiplier: Constants.timerLimit))

    // Accuracy between the playback and the countdown isn't that important. Any difference
    // if most likely not noticable to the user. And the countdown has nothing to do with
    // recording. We start recording immediately to minimize possible delays in delegation
    // between controllers.
    playbackCoordinator?.resetToTime(playbackTime: playbackTime,
                                     atTime: CMClockGetTime(CMClockGetHostTimeClock()))

    updateRecordButtonsStates(state: .waitingToRecord)
    recordButtonUpdateDispatchItem = DispatchWorkItem(block: { [weak self] in
      guard let self = self else { return }
      self.updateRecordButtonsStates(state: .recording)
    })
    DispatchQueue.main.asyncAfter(deadline: .now() + Constants.timerLimit,
                                  execute: recordButtonUpdateDispatchItem!)
    creationRecordViewController?.startRecording()
  }

  fileprivate func stopRecording(shouldDiscard: Bool = false) {
    print("----------------------------------- RECORD STOP ------------------------------")
    navigationItem.leftBarButtonItem?.action = nil
    creationRecordViewController?.stopRecording(shouldDiscard: shouldDiscard)
  }

  fileprivate func updateRecordButtonsStates(state: RecordButtonView.State) {
    remixTrayViewController.recordButton.state = state
    creationRecordViewController?.flipCameraButton.isHidden = (state != .notRecording)
  }

  fileprivate func resetRecordingState() {
    isRecording = false
    updateRecordButtonsStates(state: .notRecording)
  }
}

// MARK: - Playback Syncing

extension RemixViewController {
  @objc private func resetManualSyncing() {
    // We only need to apply manual syncing in record mode.
    guard AVAudioSession.sharedInstance().category == .playAndRecord else {
      return
    }

    // Detach and reattach all videos so they can be recomposed with the new syncing
    DispatchQueue.main.async {
      self.immediatelyDetachAllPlayersInMatrix()
      self.attachVisiblePlayersInMatrix()
    }
  }
}

// MARK: - Loading

extension RemixViewController {
  fileprivate func setupSpinner() {
    spinnerContainerView.backgroundColor = UIColor.black.withAlphaComponent(Constants.spinnerContainerAlpha)
    spinnerView.translatesAutoresizingMaskIntoConstraints = false
    spinnerContainerView.addSubview(spinnerView)
    NSLayoutConstraint.activate([
      spinnerView.centerXAnchor.constraint(equalTo: spinnerContainerView.centerXAnchor),
      spinnerView.centerYAnchor.constraint(equalTo: spinnerContainerView.centerYAnchor),
      spinnerView.heightAnchor.constraint(equalToConstant: Constants.bricHeight),
      spinnerView.widthAnchor.constraint(equalToConstant: Constants.bricHeight)
    ])
  }

  func enableSpinner() {
    guard spinnerContainerView.superview == nil else {
      return
    }
    self.view.window?.addSubview(spinnerContainerView)
    spinnerView.startAnimating()
    spinnerView.alpha = 1.0
  }

  fileprivate func stopSpinner() {
    spinnerContainerView.removeFromSuperview()
    spinnerView.stopAnimating()
  }
}

// MARK: - SlideshowViewControllerDelegate

extension RemixViewController: SlideshowViewControllerDelegate {
  func update(viewController: SlideshowViewController, index: Int, progress: Float) {
    guard Thread.isMainThread else { Fatal.safeError("Should be called on main thread") }

    guard let rank = slideshows.firstIndex(of: viewController) else { return }
    guard let fragmentController =
            getFragmentController(rank: rank, index: index) else { return }
    playbackCoordinator?.updateProgress(fragment: fragmentController.fragment, progress: progress)
    fragmentController.updateProgress(progress)
  }

  func attach(viewController: SlideshowViewController, index: Int, previewOnly: Bool) {
    guard Thread.isMainThread else { Fatal.safeError("Should be called on main thread") }

    guard let rank = slideshows.firstIndex(of: viewController) else { return }
    if let fragmentController = getFragmentController(rank: rank, index: index),
       !fragmentController.isRecordPlaceholderFragment {
      let fragment = fragmentController.fragment

      fragmentController.animateGradient()
      playbackCoordinator?.attach(fragment: fragment).onComplete(callback: { (_) in
        fragmentController.stopAnimatingGradient()
      })
    }

    let forwardFragment = getFragment(rank: rank, index: index + 1)
    let backwardFragment = getFragment(rank: rank, index: index - 1)

    // Since the download queue is operating as a LIFO
    // attach backward host first to give priority to the forward one
    if let backwardFragment = backwardFragment {
      playbackCoordinator?.attachPreview(fragment: backwardFragment)
    }
    if let forwardFragment = forwardFragment {
      playbackCoordinator?.attachPreview(fragment: forwardFragment)
    }
  }

  func detach(viewController: SlideshowViewController, index: Int, currentIndex: Int) {
    guard Thread.isMainThread else { Fatal.safeError("Should be called on main thread") }

    guard let rank = slideshows.firstIndex(of: viewController) else { return }
    let distance = abs(currentIndex - index)
    let shouldDetachPreviewImageToo = distance > 1
    // Fail for invalid index, but return for nil fragment
    guard rank < self.fragmentMatrix.count,
          rank >= 0,
          index < self.fragmentMatrix[rank].count,
          index >= 0 else { Fatal.safeError("Fragment matrix index is invalid") }
    guard let fragment = getFragment(rank: rank, index: index) else { return }
    playbackCoordinator?.detach(fragment: fragment, previewImageToo: shouldDetachPreviewImageToo)
  }

  func scrollStarted(viewController: SlideshowViewController) {
    guard Thread.isMainThread else { Fatal.safeError("Should be on main thread") }

    // If a user starts to scroll a slideshow that isn't the selected one we need to select the one
    // being scrolled.
    if viewController != selectedSlideshow {
      selectedSlideshow = viewController
    }

    guard let rank = slideshows.firstIndex(of: viewController) else { return }
    guard rank < self.fragmentMatrix.count, rank >= 0 else { return }

    for fragment in fragmentMatrix[rank] {
      fragment?.disableAdjustmentUI()
    }
  }

  func scrollEnded(viewController: SlideshowViewController) {
    guard Thread.isMainThread else { Fatal.safeError("Should be on main thread") }
    guard let rank = slideshows.firstIndex(of: viewController) else { return }
    guard rank < self.fragmentMatrix.count, rank >= 0 else { return }

    guard let selectedFragment = fragmentMatrix[rank][viewController.currentIndex()] else { return }
    if !selectedFragment.isNilFragment {
      selectedFragment.enableAdjustmentUI()
    }

    updateSelectedFragment(fragment: selectedFragment.fragment)
  }

  func viewTapped(viewController: SlideshowViewController) {
    guard Thread.isMainThread else { Fatal.safeError("Should be on main thread") }
    guard !interactionsAreLocked else {
      promptToUnlockUI()
      return
    }

    self.selectedSlideshow = viewController
  }
}

// MARK: - CreationRecordViewControllerDelegate

extension RemixViewController: CreationRecordViewControllerDelegate {
  func readyToRecord() {
    guard recordState == .none else { return }
    guard let creationRecordViewController = creationRecordViewController,
          creationRecordViewController.isReadyToRecord else { return }

    playbackCoordinator?.unpause(playbackTime: nil)
    next()
  }

  func recordStopped() {
    // Called when the record stack has stopped recording. This doesn't mean that the
    // record stack has finished generating takes but we can use this function to update
    // the UI.
    if isRecording {
      enableSpinner()
    }
    resetRecordingState()
  }

  func restoreUI() {
    navigationItem.leftBarButtonItem?.action = #selector(didTapBack)
    stopSpinner()
  }

  func recordFinished(fragments: [FragmentHost]) {
    guard Thread.isMainThread else { Fatal.safeError("Should be on main thread") }

    // Re-enable interactions now that record is finished.
    interactionsAreLocked = false

    // Catch the case where there are no fragments but we've been waiting to
    // try to generate some.
    if fragments.count == 0 {
      stopSpinner()
      return
    }

    print("--------------------------- RECORD SESSION FINISHED ---------------------------")
    resetRecordingState()

    playbackCoordinator?.pause()

    AppHeadphoneManager.shared.setAudioSessionForPlayback(on: AppDelegate.avSessionQueue).onComplete {_ in

      // ? Can we remove creation state?
      self.nextCreationState()
      self.insertNewRecordedClips(fragments: fragments)
      self.removeCaptureView()

      self.playbackCoordinator?.unpause(playbackTime: nil)
    }
  }

  func didTapDeleteClip(viewController: CreationRecordViewController) {
    // We assume the open camera preview will only exist on the currently selected rank
    guard let selectedRank = selectedRank else { return }
    deleteRankFromCollab(rank: selectedRank)

    renderLayout()
  }
}

// MARK: - LoopPlaybackCoordinatorDelegate

extension RemixViewController: PlaybackCoordinatorDelegate {
  func bufferingStarted() {
    // no-op for now
  }

  func bufferingStopped() {
    // no-op for now
  }

  func looped(atTime: CMTime, loopCount: Int) {
    guard isRecording, loopCount > 0 else { return }
    creationRecordViewController?.looped(atTime: atTime, loopCount: loopCount)

    // Insert a placeholder slide into the clip tray to mimic takes being generated.
    if loopCount > 1 {
      let takeCount = loopCount - 1 // we loop once as part of the countdown
      guard let recordController = creationRecordViewController,
            let lastTakeThumbnail = recordController.getTakeThumbnail(takeNumber: takeCount) else { return }

      let imageView = UIImageView(image: lastTakeThumbnail)

      imageView.frame = CGRect(x: 0, y: 0, width: RemixTrayViewController.clipsTrayHeight, height: RemixTrayViewController.clipsTrayHeight)

      let globalTakeCount = takeCount + playbackData.takeFragments.count
      let slide = SlideView(view: UIView(),
                            thumbnailURL: nil,
                            thumbnailImage: imageView,
                            takeNumber: globalTakeCount)
      remixTrayViewController.optimisticallyInsertClip(index: Constants.firstFragmentIndex, slideView: slide)
    }
  }

  func playbackStarted() {
    stopSpinner()
  }
}

// MARK: - FragmentCreationViewControllerDelegate

extension RemixViewController: FragmentCreationViewControllerDelegate {
  func trimFinished() {
  }

  func select(viewController: FragmentCreationViewController, type: FragmentCreationViewController.SelectionType) {
    switch type {
    case .none:
      return
    case .replaceView:
      // no - op
      return
    }
    // ## TODO : If you want more functionality for selecting a fragment, add selection types and functionality here.
  }

  func fragmentVolumeChanged(fragment: FragmentHost, volume: Float) {
    playbackCoordinator?.adjustVolume(playerHostView: fragment.hostView,
                                      volume: volume)
  }

  func fragmentPlaybackChanged(fragment: FragmentHost,
                               durationChanged: Bool,
                               startTimeChanged: Bool,
                               endTimeChanged: Bool) {
    if durationChanged {
      self.duration = fragment.playbackDuration
    }

    playbackCoordinator?.adjustPlaybackTime(fragment: fragment)
  }

  func fragmentInteractionStarted(viewController: FragmentCreationViewController) {
    guard let (rank, _) = getFragmentPosition(fragment: viewController) else { return }
    guard let slideshow = getSlideshow(rank: rank) else { return }

    slideshow.disableScrolling()
  }

  func fragmentInteractionEnded(viewController: FragmentCreationViewController) {
    guard let (rank, _) = getFragmentPosition(fragment: viewController) else { return }
    guard let slideshow = getSlideshow(rank: rank) else { return }

    if !interactionsAreLocked {
      slideshow.enableScrolling()
    }
  }

  func fragmentNudgeInteractionStarted(viewController: FragmentCreationViewController) {
    guard let (fragmentRank, _) = getFragmentPosition(fragment: viewController) else { return }

    isNudging = true
    interactionsAreLocked = true

    for (rank, slideshow) in slideshows.enumerated() {
      slideshow.disableScrolling()

      guard fragmentRank != rank else { continue }

      // Grey out the fragments not being nudged.
      let index = slideshow.currentIndex()
      let fragmentController = getFragmentController(rank: rank, index: index)
      fragmentController?.activateOverlay()
    }
  }

  func fragmentNudgeInteractionEnded(viewController: FragmentCreationViewController) {
    isNudging = false
    interactionsAreLocked = false

    for (rank, slideshow) in slideshows.enumerated() {
      let index = slideshow.currentIndex()
      let fragmentController = getFragmentController(rank: rank, index: index)
      fragmentController?.deactivateOverlay()
    }
  }

  func didTapDeleteClip(viewController: FragmentCreationViewController) {
    guard let (deletionRank, _) = getFragmentPosition(fragment: viewController) else { return }
    playbackCoordinator?.detachImmediately(fragment: viewController.fragment,
                                           previewImageToo: true)
    deleteRankFromCollab(rank: deletionRank)
    renderLayout()
  }
}

// MARK: - PlaybackDataModelDelegate

extension RemixViewController: PlaybackDataModelDelegate {
  func availableFragmentsChanged() {
    buildClipsTray()
  }

  func selectedFragmentsChanged() {
    updateSelectedClipInTray()
    updateSlideshowViews()
    togglePreviewButtonVisibility(enabled: true, animated: true)

    guard let selectedRank = selectedRank else { return }

    if playbackData.selectedFragments[selectedRank].isRecordPlaceholder {
      setupRecord(rank: selectedRank)
    } else {
      removeCaptureView()
    }
  }

  func updateSelectedFragment(fragment: FragmentHost) {
    guard let selectedRank = selectedRank else { return }
    playbackData.selectedFragments[selectedRank] = fragment
  }
}

// MARK: - ClipsTrayCollectionViewControllerDelegate

extension RemixViewController: RemixTrayViewControllerDelegate {
  func didSelectClip(index: Int) {
    guard let selectedRank = selectedRank,
          let fragmentController = getFragmentController(rank: selectedRank, index: index) else { return }

    updateSelectedFragment(fragment: fragmentController.fragment)
  }
}

// MARK: - User interaction control.
extension RemixViewController {

  func promptToUnlockUI() {
    var unlockInteractionsAlert: CollabAlertViewController?

    if isRecording {
      unlockInteractionsAlert = createRecordStopAlert()
    } else if isNudging {
      unlockInteractionsAlert = createNudgeStopAlert()
    }

    unlockInteractionsAlert?.show(in: self)
  }

  fileprivate func createRecordStopAlert() -> CollabAlertViewController {
    let alert = CollabAlertViewController(title: "Do you want to stop recording?",
                                          message: nil,
                                          titleImage: nil)
    alert.addAction(AlertAction(title: "Stop",
                                style: .normal,
                                handler: { [weak self] _ in
                                  self?.stopRecording(shouldDiscard: false)
                                }))
    alert.addAction(AlertAction(title: "Continue",
                                style: .normal,
                                handler: {_ in
                                  // no - op
                                }))

    return alert
  }

  fileprivate func createNudgeStopAlert() -> CollabAlertViewController {
    let alert = CollabAlertViewController(title: "Save your clip changes?",
                                          message: nil,
                                          titleImage: nil)
    alert.addAction(AlertAction(title: "Save",
                                style: .normal,
                                handler: { [weak self] _ in
                                  guard let selectedRank = self?.selectedRank,
                                        let index = self?.selectedSlideshow.currentIndex(),
                                        let controller = self?.getFragmentController(rank: selectedRank, index: index) else { return }

                                  controller.saveNudge()
                                }))
    alert.addAction(AlertAction(title: "Discard",
                                style: .normal,
                                handler: { [weak self] _ in
                                  guard let selectedRank = self?.selectedRank,
                                        let index = self?.selectedSlideshow.currentIndex(),
                                        let controller = self?.getFragmentController(rank: selectedRank, index: index) else { return }

                                  controller.closeNudge()
                                }))

    return alert
  }

  fileprivate func togglePreviewButtonVisibility(enabled: Bool, animated: Bool) {
    let forceDisablePreviewButton = !previewButtonVisibility()
    let visible = !forceDisablePreviewButton && enabled

    toggleEnabled(button: previewButton, enabled: visible, animated: animated)
  }

  fileprivate func toggleAddButtonVisibility(enabled: Bool, animated: Bool = false) {
    guard Thread.isMainThread else { Fatal.safeError("Should be on main thread") }

    let forceDisableAddButton = fragmentMatrix.count >= Constants.maxClipsPerCollab
    let visible = !forceDisableAddButton && enabled
    toggleEnabled(button: addButton, enabled: visible, animated: animated)
  }

  fileprivate func toggleDeleteButtonsVisibility(enabled: Bool) {
    guard Thread.isMainThread else { Fatal.safeError("Should be on main thread") }

    let forceDisableDeleteButton = playbackData.selectedFragments.count < 2
    let visible = !forceDisableDeleteButton && enabled

    creationRecordViewController?.shouldShowDeletionUI = visible
    fragmentMatrix.joined().forEach { $0?.shouldShowDeletionUI = visible }
  }

  fileprivate func toggleCloseButtonVisibility(enabled: Bool) {
    guard Thread.isMainThread else { Fatal.safeError("Should be on main thread") }

    navigationItem.leftBarButtonItem?.isEnabled = enabled
  }

  fileprivate func previewButtonVisibility() -> Bool {
    // ## TODO : Implement additional rules here to restrict from publishing in specific cases
    // (ex: could disallow publishing one-clip collabs if user isn't the owner of the one clip)

    // A user can't publish if the camera preview is open.
    let temporaryFragments = self.playbackData.selectedFragments.filter { $0.isRecordPlaceholder }
    guard temporaryFragments.count == 0 else { return false }

    return true
  }

  public func toggleEnabled(button: UIButton, enabled: Bool, animated: Bool) {
    guard button.isUserInteractionEnabled != enabled else { return }
    if animated {
      button.alpha = enabled ? Constants.buttonDisabledAlpha : 1.0
      button.isUserInteractionEnabled = enabled
      UIView.animate(withDuration: 0.2, animations: {
        button.alpha = enabled ? 1.0 : Constants.buttonDisabledAlpha
      })
    } else {
      button.alpha = enabled ? 1.0 : Constants.buttonDisabledAlpha
      button.isUserInteractionEnabled = enabled
    }
  }

  fileprivate func getIsEnabled(button: UIButton) -> Bool {
    return button.alpha == 1.0
  }
}
