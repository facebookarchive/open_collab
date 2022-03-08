// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import Foundation

class FileUtil {
  static func removeFileAsync(URL: NSURL, completion: @escaping () -> Void) {
    DispatchQueue.global().async {
      removeFile(URL: URL)
      completion()
    }
  }

  static func removeFile(URL: NSURL) {
    if let filePath = URL.path {
      let fileManager = FileManager.default
      if fileManager.fileExists(atPath: filePath) {
        do {
          try fileManager.removeItem(atPath: filePath)
        } catch {
          Fatal.safeError("Couldn't remove existing destination file: \(URL)")
        }
      }
    }
  }

  static func generateMP4URL() -> URL {
    let outputFileName = NSUUID().uuidString
    let outputFilePath = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent((outputFileName as NSString)
        .appendingPathExtension("mp4")!)
    return URL(fileURLWithPath: outputFilePath)
  }
}
