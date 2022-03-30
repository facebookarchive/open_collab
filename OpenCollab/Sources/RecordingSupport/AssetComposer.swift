// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import AVFoundation
import BrightFutures

class AssetComposer: NSObject {
  static func getAccurateAssetTimeRange(asset: AVURLAsset) -> Future<CMTimeRange?, AssetError> {
    return Future<CMTimeRange?, AssetError> { complete in
      asset.loadValuesAsynchronously(forKeys: ["duration"]) {
        guard let assetVideoTrack = asset.tracks(withMediaType: .video).first else {
          print("Couldn't find common asset range because asset doesn't have video track")
          return complete(.success(nil))
        }
        guard let assetAudioTrack = asset.tracks(withMediaType: .audio).first else {
          print("Couldn't find common asset range because asset doesn't have audio track")
          return complete(.success(nil))
        }

        let tracks = [assetAudioTrack, assetVideoTrack]
        guard var commonAssetTimeRange = tracks.first?.timeRange else {
          return complete(.success(nil))
        }
        for track in tracks {
          commonAssetTimeRange = commonAssetTimeRange.intersection(track.timeRange)
        }

        return complete(.success(commonAssetTimeRange))
      }
    }
  }

  static func rangeIsValid(range: CMTimeRange, startTime: CMTime, endTime: CMTime) -> Bool {
    guard CMTimeCompare(startTime, range.start) >= 0 else {
      print("Proposed start time \(startTime.toSeconds()) is outside the recorded range with start time: \(range.start.toSeconds()).")
      return false
    }

    guard CMTimeCompare(range.end, endTime) >= 0 else {
      print("Proposed end time \(endTime.toSeconds()) is outside the recorded range with end time: \(range.end.toSeconds()).")
      return false
    }

    print("Range is valid for range with end time \(range.end.toSeconds()) for range \(startTime.toSeconds()) to \(endTime.toSeconds())")

    return true
  }
}
