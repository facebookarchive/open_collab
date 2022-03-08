// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import Foundation

enum MulticlipType {
  case
    one,
    two,
    three,
    four,
    five,
    six

  var lastRowIndices: [Int] {
    switch self {
    case .one:
      return [0]
    case .two:
      return [1]
    case .three:
      return [2]
    case .four:
      return [2,3]
    case .five:
      return [3,4]
    case .six:
      return [4,5]
    }
  }

  var remixBottomPadding: CGFloat {
    switch self {
    case .one:
      return LayoutEngineViewController.remixClipMargin
    case .two:
      return 2 * LayoutEngineViewController.remixClipMargin
    case .three:
      return 3 * LayoutEngineViewController.remixClipMargin
    default:
      return 0
    }
  }

  static func typeForClipCount(clipCount: Int) -> MulticlipType {
    let clipMapping: [MulticlipType] = [.one, .two, .three, .four, .five, .six]
    return clipMapping[clipCount-1]
  }
}
