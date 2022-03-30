// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import FlexLayout
import UIKit

class LayoutEngineViewController: UIViewController {

  struct Constants {
    static let margins = UIEdgeInsets(top: 0, left: 0, bottom: LayoutEngineViewController.remixClipMargin, right: LayoutEngineViewController.remixClipMargin)
  }
  static let remixClipMargin: CGFloat = 8.0
  private lazy var flexContainerView = UIView()
  private var useMargins = false

  private var viewsToLayout: [UIView] = [] {
    willSet {
      viewsToLayout.forEach { view in
        view.removeFromSuperview()
        view.flex.markDirty()
      }
      // Need to re-layout to remove the existing views from the flex parent
      flexContainerView.flex.layout()
    }
    didSet {
      renderLayout()
    }
  }

  init(useMargins: Bool = false) {
    self.useMargins = useMargins
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    if useMargins {
      let multiclipType = MulticlipType.typeForClipCount(clipCount: viewsToLayout.count)
      let bottomMargin: CGFloat = multiclipType.remixBottomPadding
      let frame = self.view.bounds.inset(by: UIEdgeInsets(top: 0, left: 0, bottom: bottomMargin, right: 0))
      flexContainerView.frame = frame
    } else {
      flexContainerView.frame = self.view.bounds
    }
    flexContainerView.flex.layout()
  }

  func configurePlaybackViewCells(playbackViews: [UIView]) {
    self.viewsToLayout = playbackViews
  }

  private func renderLayout() {
    let multiclipType = MulticlipType.typeForClipCount(clipCount: viewsToLayout.count)
    let margins = useMargins ? Constants.margins : UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

    flexContainerView = UIView()
    view.addSubview(flexContainerView)

    switch multiclipType {
      case .one:
        flexContainerView.flex.addItem(viewsToLayout[0]).height(100%).width(100%).margin(margins)
      case .two:
      flexContainerView.flex.direction(.column).alignItems(.stretch).define { (flex) in
        flex.addItem(viewsToLayout[0]).height(50%).width(100%).margin(margins)
        flex.addItem(viewsToLayout[1]).height(50%).width(100%).margin(margins)
      }
      case .three:
      flexContainerView.flex.direction(.column).alignItems(.stretch).define { (flex) in
        flex.addItem(viewsToLayout[0]).height(34%).width(100%).margin(margins)
        flex.addItem(viewsToLayout[1]).height(33%).width(100%).margin(margins)
        flex.addItem(viewsToLayout[2]).height(33%).width(100%).margin(margins)
      }
      case .four:
      flexContainerView.flex.direction(.column).alignItems(.stretch).define { (flex) in
        flex.addItem().grow(1).direction(.row).margin(margins).define { (flex) in
          flex.addItem(viewsToLayout[0]).height(100%).width(50%).margin(margins)
          flex.addItem(viewsToLayout[1]).height(100%).width(50%).margin(margins)
        }
        flex.addItem().grow(1).direction(.row).margin(margins).define { (flex) in
          flex.addItem(viewsToLayout[2]).height(100%).width(50%).margin(margins)
          flex.addItem(viewsToLayout[3]).height(100%).width(50%).margin(margins)
        }
      }
      case .five:
      let singleMargin = UIEdgeInsets(top: 0, left: 0, bottom: useMargins ? LayoutEngineViewController.remixClipMargin : 0, right: 0)
      flexContainerView.flex.direction(.column).alignItems(.stretch).define { (flex) in
        flex.addItem().grow(1).direction(.row).margin(singleMargin).define { (flex) in
          flex.addItem(viewsToLayout[0]).height(100%).width(100%)
        }
        flex.addItem().grow(1).direction(.row).margin(margins).define { (flex) in
          flex.addItem(viewsToLayout[1]).height(100%).width(50%).margin(margins)
          flex.addItem(viewsToLayout[2]).height(100%).width(50%).margin(margins)
        }
        flex.addItem().grow(1).direction(.row).margin(margins).define { (flex) in
          flex.addItem(viewsToLayout[3]).height(100%).width(50%).margin(margins)
          flex.addItem(viewsToLayout[4]).height(100%).width(50%).margin(margins)
        }
      }
      case .six:
      flexContainerView.flex.direction(.column).alignItems(.stretch).define { (flex) in
        flex.addItem().grow(1).direction(.row).margin(margins).define { (flex) in
          flex.addItem(viewsToLayout[0]).height(100%).width(50%).margin(margins)
          flex.addItem(viewsToLayout[1]).height(100%).width(50%).margin(margins)
        }
        flex.addItem().grow(1).direction(.row).margin(margins).define { (flex) in
          flex.addItem(viewsToLayout[2]).height(100%).width(50%).margin(margins)
          flex.addItem(viewsToLayout[3]).height(100%).width(50%).margin(margins)
        }
        flex.addItem().grow(1).direction(.row).margin(margins).define { (flex) in
          flex.addItem(viewsToLayout[4]).height(100%).width(50%).margin(margins)
          flex.addItem(viewsToLayout[5]).height(100%).width(50%).margin(margins)
        }
      }
    }

    flexContainerView.flex.layout()
  }
}
