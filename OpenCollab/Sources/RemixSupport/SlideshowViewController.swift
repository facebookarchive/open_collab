// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import Foundation
import UIKit

protocol SlideshowViewControllerDelegate: AnyObject {
  func attach(viewController: SlideshowViewController, index: Int, previewOnly: Bool)
  func detach(viewController: SlideshowViewController, index: Int, currentIndex: Int)
  func update(viewController: SlideshowViewController, index: Int, progress: Float)
  func scrollStarted(viewController: SlideshowViewController)
  func scrollEnded(viewController: SlideshowViewController)
  func viewTapped(viewController: SlideshowViewController)
}

struct SlideView {
  var view: UIView
  var thumbnailURL: String? = nil
  var thumbnailImage: UIImageView? = nil
  var takeNumber: Int? = nil
}

class SlideshowViewController: UIViewController, UIScrollViewDelegate {

  private enum Constants {
    static let detachVisibilityThreshold: Float = 0.02
    static let cornerRadius: CGFloat = 6.0
    static let borderWidth: CGFloat = 3.0
  }

  enum Direction {
    case Horizontal, Vertical
  }

  let scrollView = CollabScrollView(frame: .zero)
  fileprivate(set) var slideViews: [SlideView]
  fileprivate let direction: Direction
  var setIndex: Int
  fileprivate weak var delegate: SlideshowViewControllerDelegate?
  fileprivate var viewDidDisappear = true
  fileprivate var waitingForInitialScroll = true
  fileprivate var slidePadding: CGFloat = 0.0
  var isSelected: Bool = false {
    didSet {
      self.view.layer.borderColor = isSelected ? UIColor.white.cgColor : UIColor.clear.cgColor
    }
  }

  var additionalHeaderPadding: CGFloat = 0.0 {
    didSet {
      self.view.setNeedsLayout()
      self.view.layoutIfNeeded()
    }
  }
  weak var scrollDelegate: UIScrollViewDelegate?

  // MARK: - Init

  init(slideViews: [SlideView],
       direction: Direction = .Horizontal,
       delegate: SlideshowViewControllerDelegate? = nil,
       slidePadding: CGFloat = 0.0,
       startingIndex: Int = 0) {
    self.slideViews = slideViews
    self.direction = direction
    self.delegate = delegate
    self.slidePadding = slidePadding
    self.setIndex = startingIndex
    super.init(nibName: nil, bundle: nil)

    self.view.layer.borderWidth = Constants.borderWidth
    self.view.layer.cornerRadius = Constants.cornerRadius
    self.view.layer.borderColor = isSelected ? UIColor.white.cgColor : UIColor.clear.cgColor
    self.view.layer.masksToBounds = true
    self.view.clipsToBounds = true
  }

  required init?(coder: NSCoder) {
    Fatal.safeError()
  }

  // MARK: - Public

  func currentIndex() -> Int {
    let index = Int(round(currentPagePortion()))
    return max(min(index, self.slideViews.count - 1), 0)
  }

  func scrollToIndex(index: Int, animated: Bool = false) {
    // We can change the index from the scroll view or from the tray view. Avoid a logic loop.
    guard index != currentIndex() else { return }
    setIndex = index

    let isHorizontal = self.direction == .Horizontal

    guard let slideWidth = isHorizontal ? slideViews.first?.view.bounds.width : slideViews.first?.view.bounds.height else { return }
    let slideLength = slideWidth + self.slidePadding

    let point = CGPoint(x: isHorizontal ?  (slideLength) * CGFloat(index) - scrollView.contentInset.left: 0.0,
                                       y: isHorizontal ? 0.0 : (slideLength) * CGFloat(index) - scrollView.contentInset.top)
    scrollView.setContentOffset(point, animated: animated)

    scrollView.setNeedsLayout()
    scrollView.layoutIfNeeded()
  }

  func appendSlides(leftViews: [SlideView]?, rightViews: [SlideView]?) {
    var index = currentIndex()

    if let leftViews = leftViews {
      slideViews.insert(contentsOf: leftViews, at: 0)
      for v in leftViews {
        scrollView.addSubview(v.view)
      }
      index = slideViews.count
    }

    if let rightViews = rightViews {
      slideViews.insert(contentsOf: rightViews, at: index)
      for v in rightViews {
        scrollView.addSubview(v.view)
      }
    }

    self.setIndex = leftViews?.count ?? 0
    self.waitingForInitialScroll = true
    self.view.setNeedsLayout()
    self.view.layoutIfNeeded()
  }

  func insertSlide(view slide: SlideView, index: Int = 0) {
    slideViews.insert(slide, at: index)
    scrollView.addSubview(slide.view)
    scrollView.contentOffset = CGPoint(x: 0.0, y: 0.0)

    self.view.setNeedsLayout()
    self.view.layoutIfNeeded()
  }

  func appendSlide(view slide: SlideView) {
    slideViews.append(slide)
    scrollView.addSubview(slide.view)
    scrollView.contentOffset = CGPoint(x: 0.0, y: 0.0)

    self.view.setNeedsLayout()
    self.view.layoutIfNeeded()
  }

  func replaceSlide(view slide: SlideView, index: Int) {
    guard slideViews.count > index else { return }
    slideViews[index].view.removeFromSuperview()
    slideViews[index] = slide
    scrollView.addSubview(slide.view)

    self.view.setNeedsLayout()
    self.view.layoutIfNeeded()
  }

  func removeSlides() {
    for slide in slideViews {
      slide.view.removeFromSuperview()
    }
    slideViews.removeAll()

    self.view.setNeedsLayout()
    self.view.layoutIfNeeded()
  }

  func removeSlide(at index: Int) {
    let removed = slideViews.remove(at: index)
    removed.view.removeFromSuperview()

    self.view.setNeedsLayout()
    self.view.layoutIfNeeded()
  }

  func enableScrolling() {
    scrollView.isScrollEnabled = true
  }

  func disableScrolling() {
    scrollView.isScrollEnabled = false
  }

  // MARK: - UIViewController

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    guard viewDidDisappear, slideViews.count > 0  else { return }

    viewDidDisappear = false
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    scrollView.isPagingEnabled = true
    scrollView.showsVerticalScrollIndicator = false
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.contentInsetAdjustmentBehavior = .automatic
    scrollView.clipsToBounds = true
    scrollView.delegate = self

    for slide in slideViews {
      scrollView.addSubview(slide.view)
    }
    self.view.addSubview(scrollView)
    let tap = UITapGestureRecognizer(target: self, action: #selector(didTapView))
    self.scrollView.addGestureRecognizer(tap)

    scrollToIndex(index: setIndex, animated: false)
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()

    let frame = self.view.bounds
    scrollView.frame = frame
    guard frame.width != 0, frame.height != 0 else {
      return
    }

    let isHorizontal = self.direction == .Horizontal
    let width = isHorizontal ? frame.width * CGFloat(slideViews.count) + self.additionalHeaderPadding : frame.width
    let height = isHorizontal ? frame.height : frame.height * CGFloat(slideViews.count) + self.additionalHeaderPadding
    scrollView.contentSize = CGSize(width: width, height: height)

    let scrollViewBounds = scrollView.bounds
    for (i, slideView) in slideViews.enumerated() {
      slideView.view.frame = CGRect(x: isHorizontal ? CGFloat(i) * scrollViewBounds.width : 0.0,
                                    y: isHorizontal ? 0.0 : CGFloat(i) * scrollViewBounds.height,
                                    width: isHorizontal ? scrollViewBounds.width - slidePadding : scrollViewBounds.width,
                                    height: isHorizontal ? scrollViewBounds.height : scrollViewBounds.height - slidePadding)

    }

    scrollToIndex(index: setIndex, animated: false)
  }

  // MARK: - UIScrollViewDelegate

  fileprivate func notify(previewOnly: Bool) {
    let portion = currentPagePortion()
    let index = Int(portion)
    let remainder = portion - CGFloat(index)

    for (i, _) in slideViews.enumerated() {

      var progress: Float = 0.0
      if i == index {
        progress = Float(1.0 - remainder)
      } else if i == index + 1 && portion > 0 {
        progress = Float(remainder)
      }

      delegate?.update(viewController: self, index: i, progress: progress)
      // detach anything that is less than 2% visible
      if progress < Constants.detachVisibilityThreshold {
        delegate?.detach(viewController: self, index: i, currentIndex: index)
      } else {
        delegate?.attach(viewController: self, index: i, previewOnly: previewOnly)
      }
    }
  }

  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    scrollDelegate?.scrollViewDidScroll?(scrollView)
    notify(previewOnly: true)
  }

  func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
    delegate?.scrollStarted(viewController: self)
    scrollDelegate?.scrollViewWillBeginDragging?(scrollView)
  }

  func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
    if !decelerate
    {
      scrollEnded()
      notify(previewOnly: false)
    }
    scrollDelegate?.scrollViewDidEndDragging?(scrollView, willDecelerate: decelerate)
  }

  func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
    scrollEnded()
    notify(previewOnly: false)
  }

  func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
    scrollDelegate?.scrollViewWillEndDragging?(scrollView, withVelocity: velocity, targetContentOffset: targetContentOffset)
  }

  func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
    scrollEnded()
    notify(previewOnly: false)
    scrollDelegate?.scrollViewDidEndDecelerating?(scrollView)
  }

  func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
    scrollEnded()
    notify(previewOnly: false)
    scrollDelegate?.scrollViewDidScrollToTop?(scrollView)
  }

  private func scrollEnded() {
    setIndex = currentIndex()
    delegate?.scrollEnded(viewController: self)
  }

  // MARK: - Private Helpers

  fileprivate func currentPagePortion() -> CGFloat {
    let isHorizontal = self.direction == .Horizontal
    let viewLength = isHorizontal ? scrollView.bounds.width : scrollView.bounds.height

    var offset = isHorizontal ? scrollView.contentOffset.x : scrollView.contentOffset.y

    offset = (isHorizontal ? scrollView.contentOffset.x : scrollView.contentOffset.y) - additionalHeaderPadding

    let portion = viewLength == 0.0 ? 0 : offset / viewLength
    return portion
  }

  @objc fileprivate func didTapView() {
    delegate?.viewTapped(viewController: self)
  }
}
