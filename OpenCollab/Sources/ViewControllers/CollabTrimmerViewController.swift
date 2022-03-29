// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import Foundation

enum TrimState {
  case
    trim,
    precision
}

protocol CollabTrimmerViewController: UIViewController, FragmentPlaybackChangeAnnouncerListener {
  var delegate: CollabTrimmerViewControllerDelegate? { get set }
  var isValidTrim: Bool { get }

  func setFragment(fragment: FragmentHost)

  func resetRange()

  func startProgressIndicator(hotLooper: HotLooper)
}

protocol CollabTrimmerViewControllerDelegate: NSObjectProtocol {
  func didSelectTrimDoneButton()
  func didDragTrimmer(range: ClosedRange<CMTime>)
  func didStartProgressDrag()
  func didDragProgress(time: CMTime)
  func didFinishProgressDrag(time: CMTime)
  func displayMaxTrimNotice()
  func displayMinTrimNotice()
  // Returns -1 or 1 depending on the direction to nudge the start or end time.
  func didNudgeStartTime(direction: Int32)
  func didNudgeEndTime(direction: Int32)
}
