// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import UIKit

private let reuseIdentifier = "Cell"

protocol ClipsTrayCollectionViewControllerDelegate: AnyObject {
  func didSelectClip(index: Int)
}

class ClipsTrayCollectionViewController: UICollectionViewController, UICollectionViewDelegateFlowLayout {

  private struct Constants {
    static let minimumLineSpacing = CGFloat(12)
  }

  var slideViews = [SlideView]()
  fileprivate var selectedIndex: IndexPath {
    didSet {
      guard clipSelectionEnabled else { return }
      self.collectionView.deselectItem(at: oldValue, animated: false)
      self.collectionView.selectItem(at: selectedIndex, animated: false, scrollPosition: .centeredHorizontally)
    }
  }
  private lazy var impact = UIImpactFeedbackGenerator()
  fileprivate var clipSelectionEnabled: Bool = true {
    didSet {
      self.collectionView.reloadData()
    }
  }
  var delegate: ClipsTrayCollectionViewControllerDelegate?

  // MARK: - Factory

  class func withDefaultLayout() -> ClipsTrayCollectionViewController {
    let layout = UICollectionViewFlowLayout()
    layout.minimumLineSpacing = Constants.minimumLineSpacing
    let itemSize = RemixTrayViewController.clipsTrayHeight
    layout.itemSize = CGSize(width: itemSize, height: itemSize)
    layout.scrollDirection = .horizontal
    let collectionViewController = ClipsTrayCollectionViewController(layout: layout)
    return collectionViewController
  }

  // MARK: - Init

  init(layout: UICollectionViewLayout) {
    self.selectedIndex = IndexPath(row: 0, section: 0)
    super.init(collectionViewLayout: layout)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - View Lifecycle

  override func viewDidLoad() {
    super.viewDidLoad()

    // Style
    self.collectionView.backgroundColor = .clear
    self.collectionView.dataSource = self
    self.collectionView.delegate = self

    // Register cell classes
    self.collectionView.register(ClipsTrayCollectionViewCell.self,
                                  forCellWithReuseIdentifier: ClipsTrayCollectionViewCell.reuseId)
  }

  // MARK: UICollectionViewDataSource

  override func numberOfSections(in collectionView: UICollectionView) -> Int {
    return 1
  }

  override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    return slideViews.count
  }

  override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ClipsTrayCollectionViewCell.reuseId,
                                                  for: indexPath) as! ClipsTrayCollectionViewCell
    let slide = slideViews[indexPath.row]
    cell.configureCell(slide: slide, enabled: clipSelectionEnabled)
    return cell
  }

  // MARK: UICollectionViewDelegate

  override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    guard clipSelectionEnabled, indexPath.row != selectedIndex.row else { return }
    delegate?.didSelectClip(index: indexPath.row)
  }

  override func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
    return clipSelectionEnabled
  }

  override func collectionView(_ collectionView: UICollectionView, shouldDeselectItemAt indexPath: IndexPath) -> Bool {
    return clipSelectionEnabled
  }

  // MARK: - Public

  func reloadClips(slideViews: [SlideView]) {
    self.slideViews = slideViews
    self.collectionView.performBatchUpdates({
      collectionView?.reloadSections(IndexSet(integer: 0))
    }, completion: {_ in
      // Reselect
      self.selectedIndex = self.selectedIndex
    })
  }

  public func toggleClipSelectionEnabled(enabled: Bool) {
    self.clipSelectionEnabled = enabled
  }

  // Updates the index for when a new slideshow is selected
  func updateSelectedIndex(index: Int) {
    guard index < slideViews.count,
          selectedIndex.row != index else { return }
    selectedIndex = IndexPath(row: index, section: 0)
  }

  func optimisticallyInsertClip(index: Int, slideView: SlideView) {
    self.slideViews.insert(slideView, at: index)
    self.collectionView.reloadData()
  }
}
