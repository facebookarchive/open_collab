// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import UIKit

protocol RadioTabBarControlViewDelegate: AnyObject {
  func didTapTabView(_ index: Int)
}

// RadioTabBarControlView is a reusable element originally designed for multi-tab
// control, like switching between feed types or different edit modes in remix
// (currently just used as a header for the clips tray, but could toggle between
// clips tray selection and, for example, editing the selected clip in some way)
class RadioTabBarControlView: UIView {

  private struct Constants {
    static let instrinsicWidth = CGFloat(200)
  }

  private var tabs: [RadioTabView]

  private var tabsStackView: UIStackView = UIStackView()

  weak var delegate: RadioTabBarControlViewDelegate?
  var selectedIndex: Int = 0 {
    didSet {
      guard selectedIndex < tabs.count, selectedIndex != oldValue else { return }
      tabs[selectedIndex].isActive = true
      for (i, tab) in tabs.enumerated() {
        if i != selectedIndex {
          tab.isActive = false
        }
      }
    }
  }

  init(tabs: [RadioTabView]) {
    self.tabs = tabs
    super.init(frame: .zero)
    configureUI()

  }

  required init?(coder: NSCoder) {
    self.tabs = []
    super.init(coder: coder)
    configureUI()
  }

  override func layoutSubviews() {
    tabsStackView.frame = self.bounds
    self.layer.cornerRadius = self.frame.height / 2
  }

  private func configureUI() {
    self.backgroundColor = .black.withAlphaComponent(0.1)
    setupStackView()
    self.addSubview(tabsStackView)
    selectedIndex = 0
  }

  private func setupStackView() {
    let newStackView = UIStackView()
    newStackView.axis = .horizontal
    newStackView.distribution = .fillEqually
    for tab in tabs {
      let tabTap = UIGestureRecognizer(target: self, action: #selector(changeTabs(_:)))
      tab.addGestureRecognizer(tabTap)
      newStackView.addArrangedSubview(tab)
    }

    self.tabsStackView = newStackView
  }

  public func addTab(_ tab: RadioTabView) {
    self.tabs.append(tab)
    let tabTap = UITapGestureRecognizer(target: self, action: #selector(changeTabs(_:)))
    tab.addGestureRecognizer(tabTap)
    tabsStackView.addArrangedSubview(tab)
    if tabs.count == 1 {
      tab.isActive = true
    }
  }

  @objc private func changeTabs(_ sender: UITapGestureRecognizer) {
    guard let tab = sender.view as? RadioTabView else { return }
    if let newIndex = getTabItemForTabView(tab) {
      delegate?.didTapTabView(newIndex)
    }
  }

  private func getTabItemForTabView(_ tab: RadioTabView) -> Int? {
    return tabs.firstIndex(of: tab)
  }
}
