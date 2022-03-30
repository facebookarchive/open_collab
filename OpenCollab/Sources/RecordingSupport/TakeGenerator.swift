// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import AVFoundation
import BrightFutures
import CoreMedia
import UIKit

protocol TakeGeneratorDelegate: NSObjectProtocol {
  func generatedFragments(fragments: [FragmentHost])
  func takeGenerationFailed()
}

class TakeGenerator: NSObject {
  private enum Constants {
    static let recordingFrameErrorPadding = CMTimeMake(value: 60, timescale: 600)
  }

  private let url: URL
  private let takeDuration: CMTime?
  private let durationPadding: CMTime
  private let recordStartTime: CMTime
  private let startTimes: [CMTime]
  private let countDownTime: CMTime
  private var assetCopier: AssetCopier?

  weak var delegate: TakeGeneratorDelegate?

  required init(url: URL,
                takeDuration: CMTime?,
                durationPadding: CMTime,
                recordStartTime: CMTime,
                startTimes: [CMTime],
                countDownTime: Double) {
    self.url = url
    self.takeDuration = takeDuration
    self.durationPadding = durationPadding
    self.recordStartTime = recordStartTime
    self.startTimes = startTimes
    self.countDownTime = CMTimeMakeWithSeconds(countDownTime, preferredTimescale: 600)

    super.init()
  }

  public func generateTakes() {
    // multiclip crops after we know how many clips the users ends with, to get the proper aspect ratio
    getAccurateAssetTimeRange(for: self.url)
  }

  private func getAccurateAssetTimeRange(for url: URL) {
    let sourceAsset = AVURLAsset(url: url,
                                 options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

    AssetComposer.getAccurateAssetTimeRange(asset: sourceAsset)
      .onSuccess { [weak self] (timeRange) in
        guard let self = self else { return }

        guard let timeRange = timeRange else {
          print("Couldn't get the time range for a croppedURL asset because time range unavailable.")
          self.delegate?.takeGenerationFailed()
          return
        }

        self.generate(sourceURL: url,
                      sourceAsset: sourceAsset,
                      timeRange: timeRange)
      }.onFailure { (error) in
        print("ERROR: Failed to get the time range for a croppedURL asset: \(error)")
      }
  }

  static func generateCroppedURL(sourceURL: URL, numberOfClips: Int) -> URL? {
    guard let assetManager = AppDelegate.fragmentAssetManager else {
      print("ERROR: Unable to find asset manager")
      return nil
    }
    let directoryURL = assetManager.rasterizationDirectory()
    return directoryURL.appendingPathComponent("cropped-\(sourceURL.hashValue)-\(numberOfClips).mp4")
  }

  public static func cropFragment(fragment: FragmentHost, clipIndex: Int, numberOfClips: Int) -> Future<FragmentHost, RasterizationError> {
    guard let userRecordedURL = fragment.assetInfo.userRecordedURL else { return Future(error: RasterizationError.InputFileDoesNotExists) }
    return Future<FragmentHost, RasterizationError> { complete in
      fragment.asset().onSuccess { asset in
        let userRecordedAsset: AVURLAsset = asset ?? AVURLAsset(url: userRecordedURL)
        let fileManger = FileManager.default
        guard let fileURL = generateCroppedURL(sourceURL: userRecordedAsset.url, numberOfClips: numberOfClips) else {
          complete(.failure(.CantCreateExportSession))
          return
        }
        if fileManger.fileExists(atPath: fileURL.path) {
          let fragmentHost = FragmentHost(croppedURL: fileURL, originalFragment: fragment)
          complete(.success(fragmentHost))
          return
        } else {
          // ## TODO : For a video uploaded from camera roll, we aren't finding the file at the url and so
          // the preview and exported video is black. This block is being hit.
          print("ERROR: File not found at the designated path. Unable to save cropped version." )
        }

        TakeGenerator.cropVideo(asset: userRecordedAsset, clipIndex: clipIndex, numberOfClips: numberOfClips).onSuccess { url in
          let fragmentHost = FragmentHost(croppedURL: url, originalFragment: fragment)
          complete(.success(fragmentHost))
        }.onFailure { error in
          complete(.failure(error))
        }
      }
    }
  }

  public static func cropVideo(asset: AVURLAsset, clipIndex: Int, numberOfClips: Int) -> Future<URL, RasterizationError> {
    let sourceURL = asset.url
    guard let croppedURL = generateCroppedURL(sourceURL: asset.url, numberOfClips: numberOfClips),
          let exportSession = Rasterizer.shared.cropExportSession(asset: asset, destinationURL: croppedURL, clipIndex: clipIndex, numberOfClips: numberOfClips) else {
      print("ERROR: Failed to create the export session")
      return Future(error: .CantCreateExportSession)
    }

    return Future<URL, RasterizationError> { complete in
      exportSession.exportAsynchronously {
        if exportSession.status == AVAssetExportSession.Status.completed {
          complete(.success(croppedURL))
        } else {
          print("ERROR: Failed to export the AVAssetExportSession with error \(String(describing: exportSession.error))")
          complete(.failure(.General(exportSession.error)))
        }
        try? FileManager.default.removeItem(at: sourceURL)
      }
    }
  }

  fileprivate func generate(sourceURL: URL, sourceAsset: AVURLAsset, timeRange: CMTimeRange) {
    print("Generating takes for time range \(timeRange.start.seconds) to \(timeRange.end.seconds), and asset of length \(sourceAsset.duration.seconds)")
    let exportInfos: [ExportInfo]

    // If we don't have a duration then just generate the video as one take, minus the count down time.
    // This could happen if its the first video recorded by a user while creating from scratch.
    if self.takeDuration == nil {
      let exportStartTime = CMTimeAdd(timeRange.start, countDownTime)
      let exportEndTime = CMTimeSubtract(timeRange.end, Constants.recordingFrameErrorPadding)
      let duration = CMTimeSubtract(exportEndTime, exportStartTime)

      let fragmentInfo = FragmentHost(assetInfo: AssetInfo.userRecorded(sourceURL),
                                      assetDuration: duration)

      let exportInfo = ExportInfo(fragment: fragmentInfo,
                                  exportStartTime: exportStartTime,
                                  exportEndTime: exportEndTime)

      exportInfos = [exportInfo]
    } else {
      exportInfos = self.calculateExportInfos(URL: sourceURL,
                                              asset: sourceAsset,
                                              recordedTimeRange: timeRange,
                                              takeDuration: takeDuration!) // swiftlint:disable:this force_unwrapping
    }

    assetCopier = AssetCopier(exportInfos: exportInfos)
    assetCopier?.startCopy().onSuccess { [weak self] fragments in
      print("Successfully copied assets")
      guard let self = self else { return }
      FileUtil.removeFileAsync(URL: self.url as NSURL) {
        let nonNilFragments = fragments.compactMap { $0 }
        self.delegate?.generatedFragments(fragments: nonNilFragments)
      }
    }.onFailure { [weak self] (error) in
      print("ERROR: Failed to generate takes: \(error)")
      self?.delegate?.takeGenerationFailed()
    }
  }

  fileprivate func calculateExportInfos(URL: URL,
                                        asset: AVURLAsset,
                                        recordedTimeRange: CMTimeRange,
                                        takeDuration: CMTime) -> [ExportInfo] {
    var exportInfos: [ExportInfo] = []

    for (index, startTime) in startTimes.enumerated() {
      let nextIndex = index + 1
      guard nextIndex < startTimes.count else { break }

      guard CMTimeCompare(startTime, recordStartTime) >= 0 else {
        print("Skipping time - tried to calculate interval for \(startTime.toSeconds()) which is before the record start time: \(recordStartTime.toSeconds())")
        continue
      }

      // Adjust the loopTimes to be relative to the recording time frame.
      let takeStartTime = CMTimeSubtract(startTime, recordStartTime)
      let takeEndTime = CMTimeAdd(takeStartTime, takeDuration)

      var exportStartTime = takeStartTime
      var exportEndTime = takeEndTime

      // Check that the initial export interval times are valid.
      guard CMTimeCompare(exportStartTime, recordedTimeRange.start) >= 0 else {
        print("Unbuffered Export startTime for take interval is less than zero.")
        continue
      }
      guard CMTimeCompare(recordedTimeRange.end, exportEndTime) >= 0 else {
        print("Unbuffered Export endTime: \(exportEndTime.toSeconds()) for take interval is larger than the time range ending in \(recordedTimeRange.end.toSeconds()).")
        continue
      }

      // Add a small amount of padding to accommodate frame rounding errors so that the asset duration is always
      // longer than the duration being recorded for.
      let roundedStartTime = CMTimeSubtract(takeStartTime, Constants.recordingFrameErrorPadding)
      if CMTimeCompare(roundedStartTime, recordedTimeRange.start) >= 0 {
        exportStartTime = roundedStartTime
      }
      let roundedEndTime = CMTimeAdd(takeEndTime, Constants.recordingFrameErrorPadding)
      if CMTimeCompare(recordedTimeRange.end, roundedEndTime) >= 0 {
        exportEndTime = roundedEndTime
      }

      // Now add a buffer for editing the asset if valid.
      let bufferedStartTime = CMTimeSubtract(exportStartTime, durationPadding)
      if CMTimeCompare(bufferedStartTime, recordedTimeRange.start) >= 0 {
        exportStartTime = bufferedStartTime
      }
      let bufferedEndTime = CMTimeAdd(exportEndTime, durationPadding)
      if CMTimeCompare(recordedTimeRange.end, bufferedEndTime) >= 0 {
        exportEndTime = bufferedEndTime
      }

      let playbackStartTime = CMTimeSubtract(takeStartTime, exportStartTime)
      let playbackEndTime = CMTimeAdd(playbackStartTime, takeDuration)

      let fragmentInfo = FragmentHost(assetInfo: AssetInfo.userRecorded(URL),
                                      assetDuration: takeDuration,
                                      playbackEndTime: playbackEndTime,
                                      playbackStartTime: playbackStartTime)

      let exportInfo = ExportInfo(fragment: fragmentInfo,
                                  exportStartTime: exportStartTime,
                                  exportEndTime: exportEndTime)

      let exportedDuration = CMTimeSubtract(exportEndTime, exportStartTime)
      // ## Uncomment this line for take recording debugging
//      print("TAKE INTERVAL TIMES - "
//                          + "Asset TimeRange start: \(recordedTimeRange.start.toSeconds()) and end: \(recordedTimeRange.end.toSeconds())"
//                          + "Asset Duration: \(recordedTimeRange.duration.toSeconds()) "
//                          + "Exported Duration: \(exportedDuration.toSeconds()) "
//                          + "Take Duration: \(takeDuration.toSeconds()) "
//                          + "Loop Time: \(startTime.toSeconds()) "
//                          + "Export Start: \(exportStartTime.toSeconds()) "
//                          + "Playback Start: \(playbackStartTime.toSeconds()) "
//                          + "Playback End: \(playbackEndTime.toSeconds()) "
//                          + "Export End: \(exportEndTime.toSeconds()) ")

      // Check the playback interval is valid.
      guard AssetComposer.rangeIsValid(range: CMTimeRangeMake(start: .zero,
                                                              duration: exportedDuration),
                                       startTime: playbackStartTime,
                                       endTime: playbackEndTime) else {
        print("INVALID PLAYBACK INTERVAL FOR TAKE.")
        continue
      }

      // Double check the export interval is valid.
      guard AssetComposer.rangeIsValid(range: recordedTimeRange,
                                       startTime: exportStartTime,
                                       endTime: exportEndTime) else {
        print("INVALID EXPORT INTERVAL FOR TAKE.")
        continue
      }

      exportInfos.append(exportInfo)
    }

    return exportInfos
  }
}
