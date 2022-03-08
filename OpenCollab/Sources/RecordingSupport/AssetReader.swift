// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import AVFoundation
import Foundation

class AssetReader: NSObject {
  // Asset Info
  let asset: AVAsset
  let timeRange: CMTimeRange
  var videoTrack: AVAssetTrack? {
    return asset.tracks(withMediaType: AVMediaType.video).first
  }
  var audioTrack: AVAssetTrack? {
    return asset.tracks(withMediaType: AVMediaType.audio).first
  }

  // Reader
  var reader: AVAssetReader?
  let videoReaderSettings: [String: Any] =
    [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_422YpCbCr8]
  let audioReaderSettings: [String: Any]? = nil

  // Outputs
  var videoOutput: AVAssetReaderTrackOutput?
  var audioOutput: AVAssetReaderTrackOutput?

  // Status
  var isReady: Bool = false

  required init(asset: AVAsset, timeRange: CMTimeRange) {
    self.asset = asset
    self.timeRange = timeRange
    super.init()
  }

  func prepareToRead() {
    isReady = false

    // Create the reader.
    do {
      self.reader = try AVAssetReader(asset: asset)
    } catch {
      print("ERROR: Failed to initialize the AVAssetReader.")

      return
    }

    // Create the reader outputs
    guard let videoTrack = videoTrack,
          let audioTrack = audioTrack else {
      print("No audio or video track to be read.")
      return
    }

    videoOutput =
      AVAssetReaderTrackOutput(track: videoTrack,
                               outputSettings: videoReaderSettings)
    audioOutput =
      AVAssetReaderTrackOutput(track: audioTrack,
                               outputSettings: audioReaderSettings)

    // We should have returned already if we failed to create the reader so this is
    // for sanity/convenience.
    guard let reader = reader,
          let videoOutput = videoOutput,
          let audioOutput = audioOutput else {
      return
    }

    if reader.canAdd(videoOutput) {
      reader.add(videoOutput)
    } else {
      print("Couldn't add video output reader")
    }

    if reader.canAdd(audioOutput) {
      reader.add(audioOutput)
    } else {
      print("Couldn't add audio output reader")
    }

    // Set the timerange on the reader.
    // TODO : Verify if this is accurate enough or if we should be inspecting
    // the timestamps ourselves.
    reader.timeRange = timeRange
    isReady = reader.startReading()
  }

  func stopReading() {
    reader?.cancelReading()
  }

  func copyNextVideoSampleBuffer() -> CMSampleBuffer? {
    guard isReady, let videoOutput = videoOutput else { return nil }
    return videoOutput.copyNextSampleBuffer()
  }

  func copyNextAudioSampleBuffer() -> CMSampleBuffer? {
    guard isReady, let audioOutput = audioOutput else { return nil }
    return audioOutput.copyNextSampleBuffer()
  }
}
