// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import AVFoundation
import BrightFutures
import Foundation

struct ExportInfo {
  let fragment: FragmentHost
  let exportStartTime: CMTime
  let exportEndTime: CMTime
}

class AssetCopier: NSObject {
  let exportInfos: [ExportInfo]
  var fragments: [FragmentHost?]

  fileprivate var activeCopyAssetFutures: [String: Future<URL, AssetError>] = [:]

  required init(exportInfos: [ExportInfo]) {
    self.exportInfos = exportInfos
    // Init the urls with nil so we can slot completed futures into the correct index and
    // leave failed copies as nil URLS.
    self.fragments = [FragmentHost?](repeating: nil, count: exportInfos.count)
    super.init()
  }

  func startCopy() -> Future<[FragmentHost?], AssetError> {
    return executeCopy(exportIndex: 0).flatMap {
      return Future(value: self.fragments)
    }
  }

  private func executeCopy(exportIndex: Int) -> Future<Void, AssetError> {
    print("Executing a copy asset action for index: \(exportIndex)")
    guard exportIndex >= 0,
          exportIndex < exportInfos.count else { return Future(value: ()) }
    let exportInfo = exportInfos[exportIndex]
    let fragment = exportInfo.fragment

    // If we don't need to copy this asset just insert the fragment and move on.
    // If we ever support editing of server assets in remix (nudge someone elses
    // clip) we would make the behaviour uniform here.
    switch fragment.assetInfo {
    case .empty,
         .downloadedFragment:
      self.fragments.insert(fragment, at: exportIndex)
      // Recursively execute the copy for the next export.
      return self.executeCopy(exportIndex: exportIndex + 1)
    case .userRecorded(let URL):
      return getActiveFutureOrCopyAsset(URL: URL,
                                        startTime: exportInfo.exportStartTime,
                                        endTime: exportInfo.exportEndTime)
        .flatMap { URL -> Future<Void, AssetError> in
          print("Successfully copied an asset adding to urls")

          // Create the fragment and then insert it into the arry.
          let duration = CMTimeSubtract(exportInfo.exportEndTime,
                                        exportInfo.exportStartTime)
          let fragment = FragmentHost(assetInfo: AssetInfo.userRecorded(URL),
                                      volume: fragment.volume,
                                      assetDuration: duration,
                                      playbackEndTime: fragment.playbackEndTime,
                                      playbackStartTime: fragment.playbackStartTime)

          self.fragments[exportIndex] = fragment

          // Recursively execute the copy for the next export.
          return self.executeCopy(exportIndex: exportIndex + 1)
        }
    }
  }

  private func getActiveFutureOrCopyAsset(URL: URL,
                                          startTime: CMTime,
                                          endTime: CMTime) -> Future<URL, AssetError> {
    let key = AssetCopier.cacheKey(URL: URL, startTime: startTime, endTime: endTime)
    if let future = activeCopyAssetFutures[key] {
      return future
    }

    let options = [AVURLAssetPreferPreciseDurationAndTimingKey: true]
    let asset = AVURLAsset(url: URL, options: options)
    let future = AssetCopier.copyAsset(asset: asset,
                                       startTime: startTime,
                                       endTime: endTime)

    activeCopyAssetFutures[key] = future
    return future
  }

  static func copyAsset(asset: AVURLAsset,
                        startTime: CMTime,
                        endTime: CMTime) -> Future<URL, AssetError> {
    print("Copying an asset \(asset.url) to a URL")
    let duration = CMTimeSubtract(endTime, startTime)
    let timeRange = CMTimeRangeMake(start: startTime, duration: duration)

    guard let videoTrack =
            asset.tracks(withMediaType: AVMediaType.video).first else {
      print("Asset to be copied has no video track.")
      return Future(error: .EmptyAsset)
    }

    let recorder = AssetRecorder(assetWidth: videoTrack.naturalSize.width,
                                 assetHeight: videoTrack.naturalSize.height,
                                 realTime: false,
                                 shouldOffsetAudio: false)

    return recorder.prepareToRecord()
      .flatMap { success -> Future<URL, AssetError> in
        assert(Thread.isMainThread)

        guard success else { return Future(error: .AssetRecorderError) }
        print("Recorder is ready to record")

        return Future<URL, AssetError> { complete in
          let reader = AssetReader(asset: asset, timeRange: timeRange)
          reader.prepareToRead()
          guard reader.isReady else {
            print("reader is not ready")
            return complete(.failure(.CouldNotRead))
          }

          recorder.requestInput(reader: reader,
                                startTime: startTime) { success in
            print("requestInput finished with success \(success)")

            reader.stopReading()

            // Callback could be on any queue.
            DispatchQueue.main.async {
              guard success else { return complete(.failure(.CouldNotRead)) }

              recorder.finishRecording()
                .onSuccess { (url, _) in
                  print("record finishRecording called with success")
                  DispatchQueue.main.async {
                    return complete(.success(url))
                  }
                }.onFailure { error in
                  print("record finishRecording called with failure \(error.localizedDescription)")
                  DispatchQueue.main.async {
                    return complete(.failure(.CouldNotWriteAsset))
                  }
                }
            }
          }
        }
      }
  }

  static func cacheKey(URL: URL,
                       startTime: CMTime,
                       endTime: CMTime) -> String {
    return "\(startTime.toSeconds())-\(endTime.toSeconds())-\(URL.absoluteString)"
  }
}
