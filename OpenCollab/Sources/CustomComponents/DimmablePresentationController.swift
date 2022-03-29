// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import Foundation

class DimmablePresentationController: UIPresentationController {
  private var dimmingView: UIView!
  var containerHeight: CGFloat
  let disableSwipe: Bool!

  init(presentedViewController: UIViewController, presenting presentingViewController: UIViewController?, height: CGFloat, disableSwipe: Bool = false) {
    self.containerHeight = height
    self.disableSwipe = disableSwipe
    super.init(presentedViewController: presentedViewController, presenting: presentingViewController)
    self.setupDimmingView()
  }

  public func changeHeight(newHeight: CGFloat) {
    self.containerHeight = newHeight
    UIView.animate(withDuration: 0.2) { [weak self] in
      self?.containerView?.setNeedsLayout()
      self?.containerView?.layoutIfNeeded()
    }
  }

  override func presentationTransitionWillBegin() {
    guard let dimmingView = dimmingView else { return }

    containerView?.insertSubview(dimmingView, at: 0)

    NSLayoutConstraint.activate(
      NSLayoutConstraint.constraints(withVisualFormat: "V:|[dimmingView]|",
        options: [], metrics: nil, views: ["dimmingView": dimmingView]))
    NSLayoutConstraint.activate(
      NSLayoutConstraint.constraints(withVisualFormat: "H:|[dimmingView]|",
        options: [], metrics: nil, views: ["dimmingView": dimmingView]))

    guard let coordinator = presentedViewController.transitionCoordinator else {
      dimmingView.alpha = 1
      return
    }

    coordinator.animate(alongsideTransition: { _ in
      self.dimmingView.alpha = 1
    })
  }

  override func dismissalTransitionWillBegin() {
    guard let coordinator = presentedViewController.transitionCoordinator else {
      dimmingView.alpha = 0
      return
    }

    coordinator.animate(alongsideTransition: { _ in
      self.dimmingView.alpha = 0
    })
  }

  override func containerViewWillLayoutSubviews() {
    guard let view = presentedView else { return }
    view.frame = frameOfPresentedViewInContainerView

    if !disableSwipe {
      let recognizer = UISwipeGestureRecognizer(
        target: self,
        action: #selector(handleSwipe(recognizer:)))
      recognizer.direction = .down
      view.addGestureRecognizer(recognizer)
    }
  }

  override func size(forChildContentContainer container: UIContentContainer, withParentContainerSize parentSize: CGSize) -> CGSize {
    return CGSize(width: parentSize.width, height: containerHeight)
  }

  override var frameOfPresentedViewInContainerView: CGRect {
    var frame: CGRect = .zero
    frame.size = size(forChildContentContainer: presentedViewController,
                      withParentContainerSize: containerView!.bounds.size)

    frame.origin.y = containerView!.frame.height - containerHeight
    return frame
  }
}

// MARK: - Helpers

private extension DimmablePresentationController {
  private func setupDimmingView() {
    dimmingView = UIView()
    dimmingView.translatesAutoresizingMaskIntoConstraints = false
    dimmingView.backgroundColor = UIColor(white: 0.0, alpha: 0.5)
    dimmingView.alpha = 0

    let recognizer = UITapGestureRecognizer(
      target: self,
      action: #selector(handleTap(recognizer:)))
    dimmingView.addGestureRecognizer(recognizer)
  }

  @objc func handleTap(recognizer: UITapGestureRecognizer) {
    presentingViewController.dismiss(animated: true)
  }

  @objc func handleSwipe(recognizer: UISwipeGestureRecognizer) {
    switch recognizer.direction {
    case .down:
      presentingViewController.dismiss(animated: true)
    default:
      break
    }
  }
}
