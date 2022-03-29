// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import Foundation

enum AssetInfo {
  // ## Add more types here for different handling of fragments from different sources like for streaming, etc.
  case
    empty,
    downloadedFragment(Fragment),
    userRecorded(URL)

  var isEmpty: Bool {
    switch self {
      case .empty:
        return true
      default:
        return false
    }
  }

  var loggingID: String {
    switch self {
      case .empty:
        return "empty_fragment"
      case .downloadedFragment(let remoteFragment):
        return remoteFragment.id
      case .userRecorded(let url):
        return url.absoluteString
    }
  }

  // nil if not user recorded
  var userRecordedURL: URL? {
    switch self {
      case .userRecorded(let url):
        return url
      default:
        return nil
    }
  }

  var isUserRecorded: Bool {
    return userRecordedURL != nil
  }

  // nil if not a downloaded fragment
  var downloadedFragment: Fragment? {
    switch self {
    case .downloadedFragment(let fragment):
      return fragment
    default:
      return nil
    }
  }

  static func create(fragment: Fragment) -> AssetInfo {
    let assetInfo: AssetInfo
    assetInfo = AssetInfo.downloadedFragment(fragment)

    return assetInfo
  }
}
