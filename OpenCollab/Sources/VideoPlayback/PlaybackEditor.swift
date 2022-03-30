// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import CoreMedia
import Foundation

protocol PlaybackEditorDelegate: NSObjectProtocol {
  func playbackTimeChanged(startTime: CMTime?, endTime: CMTime?)
}

// The PlaybackEditor readonly references a fragment and its relevant playback info and validates any
// playback edits that get delegated back to the fragment controller to update the data model.
class PlaybackEditor: NSObject {

  private struct Constants {
    static let frameRate: CMTime = CMTimeMake(value: 20, timescale: 600)
  }

  // MARK: - Data

  // TODO: Set secondsPerUnit depending on the size of the UI slider.
  // This variable casts a "unit" of the slider to some value of time.
  let secondsPerUnit = CMTimeMakeWithSeconds(1, preferredTimescale: 600)

  public static var increment: CMTime {
    return Constants.frameRate
  }

  private var beatIncrement: CMTime? {
    guard let BPM = fragment.BPM else { return nil }
    return BeatSnapper.timePerBeat(BPM: BPM)
  }

  // Used to reset playback to values before edits were applied.
  private var storedPlaybackStartTime: CMTime
  private var storedPlaybackEndTime: CMTime

  // We hold a copy of the fragment for calculating edits but actual edits
  // need to be delegated to the source fragment for them to be applied in
  // playback. We use an announcer/listener pattern to receive updates to
  // the fragment.
  private var fragment: FragmentHost

  // MARK: - Delegate
  weak var delegate: PlaybackEditorDelegate?

  required init(fragment: FragmentHost) {
    self.fragment = fragment
    self.storedPlaybackStartTime = fragment.playbackStartTime
    self.storedPlaybackEndTime = fragment.playbackEndTime

    super.init()
  }

  // MARK: - Public

  func reset() {
    setPlaybackTimes(startTime: storedPlaybackStartTime, endTime: storedPlaybackEndTime)
  }

  func storeValues() {
    storedPlaybackStartTime = fragment.playbackStartTime
    storedPlaybackEndTime = fragment.playbackEndTime
    print("Stored playback start time: \(storedPlaybackStartTime.toSeconds()), end time: \(storedPlaybackEndTime.toSeconds())")
  }

  func setPlaybackTimes(startTime: CMTime, endTime: CMTime) {
    assert(Thread.isMainThread, "should be called on main thread")
    self.delegate?.playbackTimeChanged(startTime: startTime, endTime: endTime)
  }

  func setPlaybackStartTime(time: CMTime) {
    assert(Thread.isMainThread, "should be called on main thread")
    self.delegate?.playbackTimeChanged(startTime: time, endTime: nil)
  }

  func setPlaybackEndTime(time: CMTime) {
    assert(Thread.isMainThread, "should be called on main thread")
    self.delegate?.playbackTimeChanged(startTime: nil, endTime: time)
  }

  func shiftPlayback(direction: Int32) {
    assert(Thread.isMainThread, "should be called on main thread")

    let delta = CMTimeMultiply(PlaybackEditor.increment, multiplier: direction)

    let shiftedStartTime = CMTimeAdd(fragment.playbackStartTime, delta)
    let shiftedEndTime = CMTimeAdd(fragment.playbackEndTime, delta)

    self.delegate?.playbackTimeChanged(startTime: shiftedStartTime,
                                       endTime: shiftedEndTime)
  }

  func shiftPlaybackStartTime(direction: Int32) {
    assert(Thread.isMainThread, "should be called on main thread")

    let delta = CMTimeMultiply(PlaybackEditor.increment, multiplier: direction)

    let shiftedStartTime = CMTimeAdd(fragment.playbackStartTime, delta)
    setPlaybackStartTime(time: shiftedStartTime)
  }

  func shiftPlaybackEndTime(direction: Int32) {
    assert(Thread.isMainThread, "should be called on main thread")

    let delta = CMTimeMultiply(PlaybackEditor.increment, multiplier: direction)

    let shiftedEndTime = CMTimeAdd(fragment.playbackEndTime, delta)
    setPlaybackEndTime(time: shiftedEndTime)
  }

  func setPlaybackRange(range: ClosedRange<CMTime>) {
    let adjustedStartTime = range.lowerBound
    let adjustedEndTime = range.upperBound
    setPlaybackTimes(startTime: adjustedStartTime, endTime: adjustedEndTime)
  }
}

// MARK: - Conversions

extension PlaybackEditor {
  fileprivate func convertDeltaToTime(delta: Float64) -> CMTime {
    return CMTimeMultiplyByFloat64(secondsPerUnit, multiplier: delta)
  }

  fileprivate func convertTimeToDelta(time: CMTime) -> Float64 {
    guard secondsPerUnit.toSeconds() != 0 else { return 0.0 }
    return time.toSeconds() / secondsPerUnit.toSeconds()
  }
}

// MARK: - Validation Interface

extension PlaybackEditor {
  func shiftIsValid(direction: Int32) -> Bool {
    let delta = CMTimeMultiply(PlaybackEditor.increment, multiplier: direction)

    let shiftedStartTime = CMTimeAdd(fragment.playbackStartTime, delta)
    let shiftedEndTime = CMTimeAdd(fragment.playbackEndTime, delta)

    return fragment.startEndTimePairIsValid(startTime: shiftedStartTime,
                                            endTime: shiftedEndTime)
  }
}

// MARK: - FragmentPlaybackChangeAnnouncerListener
extension PlaybackEditor: FragmentPlaybackChangeAnnouncerListener {
  func playbackChanged(fragment: FragmentHost) {
    self.fragment = fragment
  }
}
