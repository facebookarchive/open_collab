// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import CoreMedia

class BeatSnapper: NSObject {
  private enum Constants {
    static let preferredTimescale: Int32 = 10000
    static let secondsPerMinute: Double = 60
  }

  // Snaps the time so that its divisible by a beat.
  static func snapTimeToBeat(time: CMTime, BPM: Int) -> CMTime {
    let secondsPerBeat = timePerBeat(BPM: BPM).toSeconds()
    guard secondsPerBeat != 0.0 else { return time }

    let roundedSeconds = secondsPerBeat * round(time.toSeconds() / secondsPerBeat)
    return CMTimeMakeWithSeconds(roundedSeconds, preferredTimescale: Constants.preferredTimescale)
  }

  // Snaps the time so that its divisible by a bar.
  static func snapTimeToBar(time: CMTime, BPM: Int, beatsPerBar: Int32) -> CMTime {
    let secondsPerBar = timePerBar(BPM: BPM, beatsPerBar: beatsPerBar).toSeconds()
    guard secondsPerBar != 0.0 else { return time }

    let roundedSeconds = secondsPerBar * round(time.toSeconds() / secondsPerBar)
    return CMTimeMakeWithSeconds(roundedSeconds, preferredTimescale: Constants.preferredTimescale)
  }

  static func getDurationOfBeats(BPM: Int, beatCount: Int) -> CMTime {
    let time = timePerBeat(BPM: BPM)
    return CMTimeMake(value: time.value * Int64(beatCount), timescale: time.timescale)
  }

  static func timePerBeat(BPM: Int) -> CMTime {
    let secondsPerBeat = Constants.secondsPerMinute/Double(BPM)
    return CMTimeMakeWithSeconds(Float64(secondsPerBeat), preferredTimescale: Constants.preferredTimescale)
  }

  static func timePerBar(BPM: Int, beatsPerBar: Int32) -> CMTime {
    let beatTime = timePerBeat(BPM: BPM)
    return CMTimeMultiply(beatTime, multiplier: beatsPerBar)
  }

  // The formula for beatIncrement is = secondsPerBeat * (1 / (2 ^ increment)). We then check
  // increasing or decreasing increments: 0, 1, 2, 3 ... or 0, -1, -2, -3 ... meaning scale
  // secondsPerBeat by 0, 1/2, 1/4... to make it smaller if its bigger than time. Or by
  // 0, 2, 4... to make it bigger if its smaller than time.
  static func getBeatIncrementClosestToButNotLessThanTime(time: CMTime, BPM: Int) -> CMTime? {
    let secondsPerBeat = timePerBeat(BPM: BPM)
    guard secondsPerBeat != .zero, !time.toSeconds().isNaN else { return nil }

    // Determine which way we should scale beatTime before its larger but as close as possible
    // to time.
    let incrementingDirection = CMTimeCompare(secondsPerBeat, time)

    // Indicates beatTime and time are already equal.
    if incrementingDirection == 0 { return secondsPerBeat }

    var increment: Int32 = 0

    while CMTimeCompare(incrementBeat(beat: secondsPerBeat, increment: increment),
                        time) == incrementingDirection {
      increment += incrementingDirection
    }

    let lastValidIncrement = incrementingDirection == -1 ? increment : increment - incrementingDirection
    return incrementBeat(beat: secondsPerBeat, increment: lastValidIncrement)
  }

  private static func incrementBeat(beat: CMTime, increment: Int32) -> CMTime {
    return scaleBeat(beat: beat, factor: beatFactor(scale: increment))
  }

  private static func beatFactor(scale: Int32) -> Float64 {
    return 1 / pow(2.0, Double(scale))
  }

  private static func scaleBeat(beat: CMTime, factor: Float64) -> CMTime {
    return CMTimeMultiplyByFloat64(beat, multiplier: factor)
  }
}
