// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import UIKit

struct Alert {
  static func show(in viewController: UIViewController,
                   title: String?,
                   message: String,
                   showCancel: Bool = false,
                   additionalActions: [UIAlertAction]? = nil,
                   completion: (() -> Void)? = nil) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    if showCancel {
      alert.addAction(UIAlertAction(title: "Cancel",
                                    style: .default,
                                    handler: nil))
    }
    if let additionalActions = additionalActions {
      for action in additionalActions {
        alert.addAction(action)
      }
    }
    alert.addAction(UIAlertAction(title: "OK",
                                  style: .default,
                                  handler: { _ in
                                    completion?()
    }))

    viewController.present(alert, animated: true, completion: nil)
  }
}

struct Fatal {
  /// Use for experience breaking bugs, this should crash in production.
  /// - Parameter string: Description of error
  static func safeError(_ string: String? = nil) -> Never {
    Thread.callStackSymbols.forEach {print($0)}
    print(string ?? "")
    fatalError(string ?? "")
  }

  /// Use for non-experience breaking bugs, this should assert in debug builds but not in production.
  /// - Parameter string: Description of assert
  static func safeAssert(_ string: String? = nil) {
    Thread.callStackSymbols.forEach {print($0)}
    print(string ?? "")
    assertionFailure(string ?? "")
  }
}
