// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import Foundation
import UIKit

enum Constants {
  static let fullbleedSingleVideoAspectRatio: CGFloat = 9 / 15
  static let multiclip2UpAspectRatio: CGFloat = (16 / 9) / 2
  static let multiclip4UpAspectRatio: CGFloat = 16 / 9
  static let multiclip6UpAspectRatio: CGFloat = (16 / 3) / (9 / 2)
  static let fullbleedCollabAspectRatio: CGFloat = 27 / 15 // 3 vertical 9:15
}

struct AspectRatioCalculator {

  // MARK: - Private Helpers

  private static func height(for width: CGFloat, constant: CGFloat) -> CGFloat {
    return width * constant
  }

  private static func width(for height: CGFloat, constant: CGFloat) -> CGFloat {
    return height / constant
  }

  private static func sizeThatFits(size: CGSize, constant: CGFloat) -> CGSize {
    let heightForFullHorizontalBleed = height(for: size.width, constant: constant)
    if heightForFullHorizontalBleed <= size.height {
      return CGSize(width: size.width, height: heightForFullHorizontalBleed)
    }

    let widthForFullVerticalBleed = width(for: size.height, constant: constant)
    return CGSize(width: widthForFullVerticalBleed, height: size.height)
  }

  // MARK: - Public

  static func height(for width: CGFloat, of clipIndex: Int = 0, numberOfClips: Int) -> CGFloat {
    switch numberOfClips {
      case 1:
        return height(for: width, constant: Constants.multiclip4UpAspectRatio)
      case 2:
        return height(for: width, constant: Constants.multiclip2UpAspectRatio)
      case 3:
        return height(for: width, constant: Constants.fullbleedSingleVideoAspectRatio)
      case 4:
        return height(for: width, constant: Constants.multiclip4UpAspectRatio)
      case 5:
        return clipIndex == 0 ? height(for: width, constant: Constants.fullbleedSingleVideoAspectRatio) : height(for: width, constant: Constants.multiclip6UpAspectRatio)
      case 6:
        return height(for: width, constant: Constants.multiclip6UpAspectRatio)

      default:
        return height(for: width, constant: Constants.fullbleedSingleVideoAspectRatio)
    }
  }

  static func collabHeight(for width: CGFloat) -> CGFloat {
    return height(for: width, constant: Constants.fullbleedCollabAspectRatio)
  }

  static func collabSizeThatFits(size: CGSize) -> CGSize {
    return sizeThatFits(size: size, constant: Constants.fullbleedCollabAspectRatio)
  }

  static func collabFullBleedSizeThatFits(size: CGSize) -> CGSize {
    let constant = Constants.fullbleedCollabAspectRatio
    let widthForFullVerticalBleed = width(for: size.height, constant: constant)

    if widthForFullVerticalBleed >= size.width {
      return CGSize(width: widthForFullVerticalBleed, height: size.height)
    }

    // aspect ratio width for the full bleed height doesn't
    // cover the entire available width. Stretch more to cover
    // horizontally. This will push vertical size a bit out of size
    let heightForFullHorizontalBleed = height(for: size.width, constant: constant)
    return CGSize(width: size.width, height: heightForFullHorizontalBleed)
  }

  static func getSingleVideoAspectRatio() -> CGFloat {
    return Constants.fullbleedSingleVideoAspectRatio
  }

  static func widthForClipInCollab(clip index: Int, totalNumberOfClips: Int, collabWidth: CGFloat) -> CGFloat {
    switch totalNumberOfClips {
      case 1, 2, 3:
        return collabWidth
      case 4, 6:
        return collabWidth / 2.0
      case 5:
        return index == 0 ? collabWidth : collabWidth / 2.0
      default:
        return collabWidth
    }
  }
}
