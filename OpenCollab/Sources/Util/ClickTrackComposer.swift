// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import AVFoundation

let accentClickURL = Bundle.main.url(forResource: "clickAccent", withExtension: "wav")
let standardClickURL = Bundle.main.url(forResource: "clickStandard", withExtension: "wav")

class ClickTrackComposer: NSObject {
  static func composeClickTrackFor(BPM: Int,
                                   duration: CMTime,
                                   beatsPerBar: Int,
                                   accentedBeatInBar: Int) -> AVAsset? {
    print("Composing a click track for BPM \(BPM) and duration \(duration.toSeconds())")
    // Create the base tracks for the different clicks.
    guard let accentClickURL = accentClickURL, let standardClickURL = standardClickURL else { return nil }
    let options = [AVURLAssetPreferPreciseDurationAndTimingKey: true]

    let accentClickAsset = AVURLAsset(url: accentClickURL, options: options)
    guard let accentClickAudio = accentClickAsset.tracks(withMediaType: .audio).first else {
      print("Tried to build a click track but there is no accent audio.")
      return nil
    }

    let standardClickAsset = AVURLAsset(url: standardClickURL, options: options)
    guard let standardClickAudio = standardClickAsset.tracks(withMediaType: .audio).first else {
      print("Tried to build a click track but there is no standard audio.")
      return nil
    }

    // Setup the composition.
    let composition = AVMutableComposition()

    guard let audioCompTrack =
            composition.addMutableTrack(withMediaType: AVMediaType.audio,
                                        preferredTrackID: CMPersistentTrackID()) else {
      print("Couldn't create a mutable audio track for the click track.")
      return nil
    }

    var currentTime: CMTime = .zero
    var currentBeat = 1
    let timePerBeat = BeatSnapper.timePerBeat(BPM: BPM)

    while CMTimeCompare(currentTime, duration) < 0 {
      // Determine what kind of click to add.
      let track = currentBeat % beatsPerBar == accentedBeatInBar ? accentClickAudio : standardClickAudio
      let trackTimeRange = track.timeRange

      // Determine how long the click track will be once we add the beat.
      let proposedComposedDuration = CMTimeAdd(currentTime, trackTimeRange.duration)

      // Verify we can fit the next beat.
      guard CMTimeCompare(proposedComposedDuration, duration) <= 0 else {
        break
      }

      // Insert into the click track.
      do {
        try audioCompTrack.insertTimeRange(trackTimeRange,
                                           of: track,
                                           at: currentTime)
      } catch let error {
        print("Couldn't insert time range of click \(error.localizedDescription)")
        return nil
      }

      // Increment where we are inserting into the track to the next beat.
      currentTime = CMTimeAdd(currentTime, timePerBeat)
      currentBeat += 1
    }

    return composition
  }
}
