// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import AVFoundation
import BrightFutures
import Foundation

public extension CMTime {
  func toSeconds() -> Double {
    return CMTimeGetSeconds(self)
  }

  func absoluteDifference(other: CMTime) -> CMTime {
    let compare = CMTimeCompare(self, other)
    if compare == -1 {
      // other CMTime is larger
      return CMTimeSubtract(other, self)
    }

    return CMTimeSubtract(self, other)
  }
}

extension AVAsset {
  func getFrameImage(atTime: CMTime = .zero, size: CGSize) -> UIImage? {
    var cappedSize = size
    if cappedSize.width < 1.0 || cappedSize.height < 1.0 {
      cappedSize = CGSize(width: 375.0, height: 200.0)
    }
    let generator = AVAssetImageGenerator(asset: self)
    generator.requestedTimeToleranceAfter = .zero
    generator.requestedTimeToleranceBefore = .zero
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = cappedSize
    do {
      let imageRef = try generator.copyCGImage(at: atTime, actualTime: nil)
      return UIImage(cgImage: imageRef)
    } catch _ {
      return nil
    }
  }

  func getFrameImageAsync(atTime: CMTime = .zero, size: CGSize) -> Future<UIImage, AssetError> {
    return Future<UIImage, AssetError> { complete in
      DispatchQueue.global(qos: .background).async {
        var cappedSize = size
        if cappedSize.width < 1.0 || cappedSize.height < 1.0 {
          cappedSize = CGSize(width: 375.0, height: 200.0)
        }
        let generator = AVAssetImageGenerator(asset: self)
        generator.requestedTimeToleranceAfter = .zero
        generator.requestedTimeToleranceBefore = .zero
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = cappedSize

        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: atTime)]) { (_, image, _, _, _) in
          guard let image = image else {
            return complete(.failure(.FailedToCreateImageForAsset))
          }
          return complete(.success(UIImage(cgImage: image)))
        }
      }
    }
  }
}

extension URL {
  var fileSize: UInt64? {
    guard self.isFileURL else { return nil }
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: self.absoluteURL.path) else { return nil }
    return attributes[FileAttributeKey.size] as? UInt64
  }

  var fileSizeInMB: Double? {
    guard let size = self.fileSize else { return nil }
    return Double(size) / (1024.0 * 1024.0)
  }
}

extension FileManager {
  func clearTmpDirectory() {
    do {
      let tmpDirURL = FileManager.default.temporaryDirectory
      let tmpDirectory = try contentsOfDirectory(atPath: tmpDirURL.path)
      try tmpDirectory.forEach { file in
        let fileUrl = tmpDirURL.appendingPathComponent(file)
        try removeItem(atPath: fileUrl.path)
      }
    } catch {
      print("Couldn't clear temp directory")
    }
  }
}

extension Collab {
  enum Constants {
    static let frameRate: Int32 = 600
    static let defaultMaxFragmentDurationInSeconds: Double = 15.0
    static let longerMaxFragmentDurationInSeconds: Double = 25.0
    static let minClipsPerCollab: Int = 1
  }

  static var minFragmentDuration = CMTimeMakeWithSeconds(3, preferredTimescale: 600)
  static var maxFragmentDuration: CMTime {
    let duration = Constants.longerMaxFragmentDurationInSeconds
    return CMTimeMakeWithSeconds(duration, preferredTimescale: Constants.frameRate)
  }
}

extension UIViewController {
  func addToContainerViewController(_ parent: UIViewController, setBounds: Bool = true) {
    parent.addChild(self)
    parent.view.addSubview(self.view)
    if setBounds {
      self.view.frame = parent.view.bounds
    }
    self.didMove(toParent: parent)
  }
}

extension UICollectionViewCell {
  class var reuseId: String {
    return String(describing: self)
  }
}
