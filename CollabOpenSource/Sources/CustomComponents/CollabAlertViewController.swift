// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import UIKit

class AlertAction {
  let title: String
  let style: Style
  let handler: ((AlertAction) -> Void)?
  var dismissHandler: ((AlertAction) -> Void)?

  @objc func actionTrigger() {
    handler?(self)
    dismissHandler?(self)
  }

  enum Style {
    case normal, secondary
  }

  init(title: String, style: Style, handler: ((AlertAction) -> Void)?) {
    self.title = title
    self.style = style
    self.handler = handler
  }
}

extension AlertAction {
  var backgroundColor: UIColor {
    switch self.style {
    case .normal:
      return .black
    case .secondary:
      return .white
    }
  }
  var backgroundHighlightedColor: UIColor {
    switch self.style {
    case .normal:
      return self.backgroundColor.withAlphaComponent(CollabAlertViewController.Constants.buttonPressedAlpha)
    case .secondary:
      return UIColor.gray.withAlphaComponent(CollabAlertViewController.Constants.buttonPressedAlpha)
    }
  }
  var foregroundColor: UIColor {
    switch self.style {
    case .normal:
      return .white
    case .secondary:
      return .black
    }
  }
}

class CollabAlertViewController: UIViewController {

  // MARK: - Properties

  fileprivate (set) var alertTitle: String?
  fileprivate (set) var alertMessage: String?
  fileprivate (set) var alertTitleImage: UIImage?

  fileprivate var actions = [AlertAction]()

  // MARK: - UI

  fileprivate let contentStackView: UIStackView = {
    let contentStackView = UIStackView()
    contentStackView.axis = .vertical
    contentStackView.alignment = .fill
    contentStackView.distribution = .fill
    return contentStackView
  }()

  fileprivate let titleStackView: UIStackView = {
    let contentStackView = UIStackView()
    contentStackView.axis = .horizontal
    contentStackView.alignment = .fill
    contentStackView.distribution = .fill
    return contentStackView
  }()

  fileprivate var titleImageView: UIImageView = {
    let imageView = UIImageView()
    imageView.isUserInteractionEnabled = false
    imageView.contentMode = .scaleAspectFit
    return imageView
  }()

  fileprivate let titleLabel: UILabel = {
    let label = UILabel()
    label.font = Constants.titleFont
    label.textColor = .black
    return label
  }()

  fileprivate let messageLabel: UILabel = {
    let label = UILabel()
    label.font = Constants.messageFont
    label.numberOfLines = 0
    label.lineBreakMode = .byWordWrapping
    label.textColor = .black
    return label
  }()

  // MARK: - Init

  init(title: String?, message: String?, titleImage: UIImage?) {
    super.init(nibName: nil, bundle: nil)
    alertTitle = title
    alertMessage = message
    alertTitleImage = titleImage
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Public

  func addAction(_ action: AlertAction) {
    actions.append(action)
  }

  func show(in viewController: UIViewController) {
    self.modalPresentationStyle = .custom
    self.transitioningDelegate = self
    viewController.present(self, animated: true, completion: nil)
  }

  // MARK: - UIViewController

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()

    contentStackView.spacing = Constants.spacing
    if alertTitleImage != nil {
      titleStackView.spacing = Constants.spacing
    }
    contentStackView.frame = calculatedFrame()
  }

  // MARK: - Helpers

  fileprivate func calculatedFrame() -> CGRect {
    let contentFrame = view.bounds.inset(by: Constants.contentMargins)
    var safeInsets = view.safeAreaInsets
    if safeInsets.bottom < Constants.minContentMargin {
      safeInsets.bottom = Constants.minContentMargin
    }
    safeInsets.top = 0.0
    return contentFrame.inset(by: safeInsets)
  }

  fileprivate func setupUI() {
    view.backgroundColor = .white
    view.clipsToBounds = true
    view.layer.cornerRadius = Constants.viewRadius

    titleLabel.text = alertTitle
    messageLabel.text = alertMessage
    titleImageView.image = alertTitleImage

    view.addSubview(contentStackView)

    if alertTitleImage != nil {
      titleStackView.addArrangedSubview(titleImageView)
    }
    contentStackView.addArrangedSubview(titleStackView)
    titleStackView.addArrangedSubview(titleLabel)
    contentStackView.addArrangedSubview(messageLabel)

    let buttons = actions.map { buildButton(for: $0) }
    buttons.forEach { contentStackView.addArrangedSubview($0) }
  }

  fileprivate func buildButton(for action: AlertAction) -> UIButton {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.highlightedColor = action.backgroundHighlightedColor
    button.setTitle(action.title, for: .normal)
    button.setTitleColor(action.foregroundColor, for: .normal)
    button.titleLabel?.font = Constants.buttonTitleFont
    if action.style == .normal {
      button.setBackgroundImage(UIImage(named: "buttonGradient"), for: .normal)
    } else {
      button.setBackgroundColor(action.backgroundColor, for: .normal)
    }
    button.clipsToBounds = true
    button.layer.cornerRadius = Constants.buttonRadius
    action.dismissHandler = { [weak self] _ in
      self?.dismiss(animated: true, completion: nil)
    }
    button.addTarget(action, action: #selector(AlertAction.actionTrigger), for: .touchUpInside)
    button.heightAnchor.constraint(equalToConstant: Constants.buttonHeight).isActive = true
    return button
  }
}

// MARK: - UIViewControllerTransitioningDelegate

extension CollabAlertViewController: UIViewControllerTransitioningDelegate {
  func presentationController(forPresented presented: UIViewController,
                              presenting: UIViewController?,
                              source: UIViewController) -> UIPresentationController? {
    guard presented === self else { return nil }
    setupUI()
    var safeInsets = source.view.window?.safeAreaInsets ?? UIEdgeInsets.zero
    safeInsets.top = 0.0
    if safeInsets.bottom < Constants.minContentMargin {
      safeInsets.bottom = Constants.minContentMargin
    }
    let maxBounds = view.bounds.inset(by: Constants.contentMargins).inset(by: safeInsets)
    contentStackView.spacing = Constants.spacing
    titleStackView.spacing = Constants.spacing
    messageLabel.preferredMaxLayoutWidth = maxBounds.width
    titleLabel.preferredMaxLayoutWidth = maxBounds.width
    let contentStackViewSize = contentStackView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
    return DimmablePresentationController(presentedViewController: presented,
                                          presenting: presenting,
                                          height: contentStackViewSize.height
                                            + safeInsets.bottom
                                            + Constants.contentMargins.top
                                            + Constants.contentMargins.bottom)
  }
}

// MARK: - Constants

extension CollabAlertViewController {
  enum Constants {
    static let titleFont = UIFont.systemFont(ofSize: 20, weight: .semibold)
    static let messageFont = UIFont.systemFont(ofSize: 14, weight: .medium)
    static let buttonTitleFont = UIFont.systemFont(ofSize: 17, weight: .medium)
    static let contentMargins = UIEdgeInsets(top: 28.0, left: 37.0, bottom: 0.0, right: 37.0)
    static let minContentMargin = CGFloat(28.0)
    static let spacing = CGFloat(12.0)
    static let buttonHeight = CGFloat(44.0)
    static let buttonRadius = CGFloat(6.0)
    static let viewRadius = CGFloat(28.0)
    static let buttonPressedAlpha = CGFloat(0.6)
  }
}
