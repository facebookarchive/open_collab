// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import AVFoundation
import BrightFutures

enum RasterizationError: Error, CustomDebugStringConvertible {
  case CantCreateExportSession, General(Error?), InputFileDoesNotExists

  public var debugDescription: String {
    let localizedDescription = self.localizedDescription
    switch self {
    case .CantCreateExportSession:
      return "Can't create export session error: \(localizedDescription)"
    case .General(let error):
      return "General Error: \(String(describing: error))"
    case .InputFileDoesNotExists:
      return "Input file is missing error: \(localizedDescription)"
    }
  }
}

class Rasterizer {

  private enum Constants {
    static let watermarkWidth: CGFloat = 180.0
    static let watermarkPadding: CGFloat = 18.0
    static let watermarkPaddingBottom: CGFloat = 14.0
    static let attributionTagRightPadding: CGFloat = 12.0
    static let attributionTagBottomPadding: CGFloat = 3.0
    static let attributionFontSize: CGFloat = 18.0
    static let fontHeightPadding: CGFloat = 4.0
    static let attributionTagTitleAttributes: [NSAttributedString.Key: Any] = [
      .font: UIFont.systemFont(ofSize: Constants.attributionFontSize, weight: .semibold),
      .foregroundColor: UIColor.white
    ]
    static let exportWidth: CGFloat = 540.0
  }

  static let shared = Rasterizer()

  fileprivate func localFileURL(directoryURL: URL) -> URL {
    let userHandle = "unknown_user"
    let collabLabel =
      fileSafeLabel(label: "unknown_label")
    let id: String = UUID().uuidString

    let fileName = "Collab_\(userHandle)_\(collabLabel)_\(id).mp4"
    let fileURL = directoryURL.appendingPathComponent(fileName)
    return fileURL
  }

  fileprivate func fileSafeLabel(label: String) -> String {
    let invalidCharacters = CharacterSet(charactersIn: "\\/:*?\"<>|-,")
      .union(.newlines)
      .union(.illegalCharacters)
      .union(.controlCharacters)

    let labelSanitized =
      label.components(separatedBy: invalidCharacters).joined(separator: " ")
    let labelCondensed = labelSanitized.components(separatedBy: .whitespaces)
      .filter { !$0.isEmpty }
      .joined(separator: "_")

    return labelCondensed
  }

  func rasterize(assetWithVolumeTuples: [(AVAsset?, Float)],
                 directoryURL: URL,
                 replaceLocalCopy: Bool) -> Future<URL, RasterizationError> {
    let fileManger = FileManager.default
    let fileURL = localFileURL(directoryURL: directoryURL)
    if fileManger.fileExists(atPath: fileURL.path) {
      if replaceLocalCopy {
        do {
          try FileManager.default.removeItem(at: fileURL)
        } catch {
          print("Rasterization error while deleting file at local path: ", error.localizedDescription)
          return Future(error: RasterizationError.General(error))
        }
      } else {
        return Future(value: fileURL)
      }
    }

    let validAssetTuples = assetWithVolumeTuples.filter { $0.0 != nil }
    let numberOfClips = assetWithVolumeTuples.count
    guard validAssetTuples.count > 0, let minDuration = (validAssetTuples.compactMap { asset, _ in
      asset?.duration
    }.min()) else { return Future(error: .General(nil)) }
    
    let timeRange = CMTimeRangeMake(start: CMTime.zero, duration: minDuration)

    let mixComposition = AVMutableComposition()
    var arrayLayerInstructions: [AVMutableVideoCompositionLayerInstruction] = []

    let rawWidth = Constants.exportWidth

    let audioMix: AVMutableAudioMix = AVMutableAudioMix()
    var audioMixParam: [AVMutableAudioMixInputParameters] = []

    var verticalPosition: CGFloat = 0.0
    var horizontalPosition: CGFloat = 0.0
    for (index, assetTuple) in assetWithVolumeTuples.enumerated() {
      print("rasterizer: clip with asset: \(String(describing: assetTuple.0))")

      let targetWidth = AspectRatioCalculator.widthForClipInCollab(clip: index, totalNumberOfClips: assetWithVolumeTuples.count, collabWidth: rawWidth)
      let targetHeight = AspectRatioCalculator.height(for: targetWidth, of: index, numberOfClips: numberOfClips)

      guard let asset = assetTuple.0 else {
        verticalPosition += verticalOffsetFor(clip: index + 1, numberOfClips, rawHeight: targetHeight)
        horizontalPosition = 0.0
        continue
      }

      guard let videoCompositionTrack = addTrack(mediaType: .video, of: asset, to: mixComposition, timeRange: timeRange) else { continue }
      let audioCompositionTrack = addTrack(mediaType: .audio, of: asset, to: mixComposition, timeRange: timeRange)

      let incomingClipSize = videoCompositionTrack.naturalSize.applying(asset.preferredTransform)
      let incomingClipFrame = CGRect(origin: .zero, size: incomingClipSize)

      var needsWidthCropping = (incomingClipSize.height < incomingClipSize.width) && (targetWidth < incomingClipSize.width)
      var croppingWidth: CGFloat = AspectRatioCalculator.widthForClipInCollab(clip: index, totalNumberOfClips: assetWithVolumeTuples.count, collabWidth: incomingClipSize.width)
      var clipWidth = needsWidthCropping ? croppingWidth : incomingClipSize.width

      let notEnoughHeight = targetHeight > incomingClipSize.height
      let wrongAspectRatio = targetHeight/targetWidth != incomingClipSize.height/incomingClipSize.width
      let exactlyEnoughWidth = targetWidth == incomingClipSize.width
      if (notEnoughHeight || (!needsWidthCropping && wrongAspectRatio && !exactlyEnoughWidth)) {
        let fittedSize = AspectRatioCalculator.collabSizeThatFits(size: incomingClipSize)
        croppingWidth = fittedSize.width
        needsWidthCropping = true
        clipWidth = croppingWidth
      }

      let croppingHeight: CGFloat = AspectRatioCalculator.height(for: clipWidth, of: index, numberOfClips: numberOfClips)
      horizontalPosition = horizontalOffsetFor(clip: index + 1, numberOfClips, rawWidth: rawWidth)

      let xTranslation = needsWidthCropping ? -(incomingClipSize.width - croppingWidth) / 2.0 : 0
      let transform = videoCompositionTrack.preferredTransform.translatedBy(x: xTranslation, y: -(incomingClipSize.height - croppingHeight) / 2.0)
      let scaleTransform = CGAffineTransform(scaleX: targetWidth / clipWidth, y: (targetHeight / croppingHeight))
      let moveTransform = CGAffineTransform(translationX: horizontalPosition, y: verticalPosition)
      let finalTransform = transform.concatenating(scaleTransform.concatenating(moveTransform))

      let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoCompositionTrack)
      let cropRect = CGRect(x: incomingClipFrame.midX - clipWidth/2.0, y: max(0, incomingClipFrame.midY - croppingHeight/2.0), width: clipWidth, height: croppingHeight)

      layerInstruction.setCropRectangle(cropRect, at: .zero)
      layerInstruction.setTransform(finalTransform, at: CMTime.zero)
      arrayLayerInstructions.append(layerInstruction)

      verticalPosition += verticalOffsetFor(clip: index + 1, numberOfClips, rawHeight: targetHeight)

      let videoParam = AVMutableAudioMixInputParameters(track: videoCompositionTrack)
      videoParam.trackID = videoCompositionTrack.trackID
      videoParam.setVolume(assetTuple.1, at: CMTime.zero)
      audioMixParam.append(videoParam)

      if let audioCompositionTrack = audioCompositionTrack {
        let musicParam = AVMutableAudioMixInputParameters(track: audioCompositionTrack)
        musicParam.trackID = audioCompositionTrack.trackID
        musicParam.setVolume(assetTuple.1, at: CMTime.zero)
        audioMixParam.append(musicParam)
      }
    }

    audioMix.inputParameters = audioMixParam
    let mainInstruction = AVMutableVideoCompositionInstruction()
    mainInstruction.timeRange = timeRange
    mainInstruction.layerInstructions = arrayLayerInstructions

    // Turns out render sizes have to be multiples of 16
    // https://stackoverflow.com/questions/22883525/avassetexportsession-giving-me-a-green-border-on-right-and-bottom-of-output-vide
    let renderSize = CGSize(width: floor(rawWidth / 16) * 16,
                            height: floor(verticalPosition / 16) * 16)

    // Add instruction for video track
    let mainComposition = AVMutableVideoComposition()
    mainComposition.instructions = [mainInstruction]
    mainComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
    mainComposition.renderSize = renderSize

    guard let exporter = AVAssetExportSession(asset: mixComposition,
                                              presetName: AVAssetExportPresetHighestQuality) else {
                                                return Future(error: .CantCreateExportSession)
    }
    exporter.outputURL = fileURL
    exporter.outputFileType = AVFileType.mp4
    exporter.shouldOptimizeForNetworkUse = true
    exporter.videoComposition = mainComposition
    exporter.audioMix = audioMix

    return Future<URL, RasterizationError> { complete in
      exporter.exportAsynchronously {
        DispatchQueue.main.async {
          if exporter.status == .completed {
            complete(.success(fileURL))
          } else {
            complete(.failure(.General(exporter.error)))
          }
        }
      }
    }
  }

  private func verticalOffsetFor(clip: Int, _ numberOfClips: Int, rawHeight: CGFloat) -> CGFloat {
    switch numberOfClips {
      case 1, 2, 3:
        return rawHeight
      case 4, 6:
        if clip % 2 == 0 {
          return rawHeight
        } else {
          return 0.0
        }
      case 5:
        if clip == 1 {
          return rawHeight
        }
        if clip % 2 == 0 {
          return 0.0
        } else {
          return rawHeight
        }
      default:
        return rawHeight
    }
  }

  private func horizontalOffsetFor(clip: Int, _ numberOfClips: Int, rawWidth: CGFloat) -> CGFloat {
    switch numberOfClips {
      case 1, 2, 3:
        return 0.0
      case 4, 6:
        if clip % 2 == 0 {
          return rawWidth / 2.0
        } else {
          return 0.0
        }
      case 5:
        if clip == 1 {
          return 0.0
        }
        if clip % 2 == 0 {
          return 0.0
        } else {
          return rawWidth / 2.0
        }
      default:
        return 0.0
    }
  }

  fileprivate func addTrack(mediaType: AVMediaType, of asset: AVAsset, to composition: AVMutableComposition, timeRange: CMTimeRange) -> AVMutableCompositionTrack? {
    guard let track = composition.addMutableTrack(withMediaType: mediaType,
                                                  preferredTrackID: Int32(kCMPersistentTrackID_Invalid)) else {
        return nil
    }
    do {
      guard let assetTrack = asset.tracks(withMediaType: mediaType).first else {
        return nil
      }
      try track.insertTimeRange(timeRange,
                                of: assetTrack,
                                at: assetTrack.timeRange.start)
      return track
    } catch {
      print("ERROR: Failed to load first track")
    }
    return nil
  }
}

// MARK: - Cropping

extension Rasterizer {
  func cropExportSession(asset: AVAsset, destinationURL: URL, clipIndex: Int, numberOfClips: Int) -> AVAssetExportSession? {
    let mixComposition = AVMutableComposition()
    var arrayLayerInstructions: [AVMutableVideoCompositionLayerInstruction] = []
    let timeRange = CMTimeRangeMake(start: CMTime.zero, duration: asset.duration)

    guard let assetVideoTrack = asset.tracks(withMediaType: .video).first else {
      print("Tried to crop an export session with no video tracks.")
      return nil
    }
    guard let videoCompositionTrack = addTrack(mediaType: .video,
                                               of: asset,
                                               to: mixComposition,
                                               timeRange: timeRange) else {
      print("Tried to crop couldn't add video track.")
      return nil
    }
    _ = addTrack(mediaType: .audio, of: asset, to: mixComposition, timeRange: timeRange)

    videoCompositionTrack.preferredTransform = assetVideoTrack.preferredTransform
    let correctedNaturalSize = videoCompositionTrack.naturalSize.applying(assetVideoTrack.preferredTransform)
    let videoFrame = CGRect(origin: .zero, size: correctedNaturalSize)

    let width: CGFloat = abs(correctedNaturalSize.width)
    let clipHeight: CGFloat = AspectRatioCalculator.height(for: width, of: clipIndex, numberOfClips: numberOfClips)

    let transform = assetVideoTrack.preferredTransform.translatedBy(x: -(correctedNaturalSize.width - width) / 2.0, y: -(correctedNaturalSize.height - clipHeight) / 2.0)
    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoCompositionTrack)
    let cropRect = CGRect(x: videoFrame.midX - width/2.0, y: videoFrame.midY - clipHeight/2.0, width: width, height: clipHeight)
    layerInstruction.setCropRectangle(cropRect, at: .zero)
    layerInstruction.setTransform(transform, at: CMTime.zero)

    arrayLayerInstructions.insert(contentsOf: [layerInstruction], at: 0)

    let mainInstruction = AVMutableVideoCompositionInstruction()
    mainInstruction.timeRange = timeRange
    mainInstruction.layerInstructions = arrayLayerInstructions

    // Add instruction for video track
    let mainComposition = AVMutableVideoComposition()
    mainComposition.instructions = [mainInstruction]
    mainComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
    mainComposition.renderSize = CGSize(width: width, height: clipHeight)

    guard let exporter = AVAssetExportSession(asset: mixComposition,
                                              presetName: AVAssetExportPreset960x540) else {
      print("ERROR: Failed to create an export session while cropping.")
      return nil
    }
    exporter.outputURL = destinationURL
    exporter.outputFileType = AVFileType.mp4
    exporter.shouldOptimizeForNetworkUse = true
    exporter.videoComposition = mainComposition

    return exporter
  }
}
