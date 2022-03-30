// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import AVFoundation
import BrightFutures
import Foundation

class AssetRecorder: NSObject {
  private let writingQueue = DispatchQueue(label: "com.openCollab.assetrecorder")

  private let url: URL

  private var assetWriter: AVAssetWriter?
  private var hasStartedSession: Bool = false
  private var sessionStartTime: CMTime = .zero
  private var readyToWrite: Bool = false

  private var assetHeight: CGFloat
  private var assetWidth: CGFloat

  private var audioWriterInput: AVAssetWriterInput?
  private var videoWriterInput: AVAssetWriterInput?

  private var shouldOffsetAudio: Bool = true
  private var realTime: Bool = true

  required init(assetWidth: CGFloat,
                assetHeight: CGFloat,
                realTime: Bool = true,
                shouldOffsetAudio: Bool = true) {
    let outputFileName = NSUUID().uuidString
    // swiftlint:disable:next force_unwrapping
    let stringPath = (NSTemporaryDirectory() as NSString).appendingPathComponent((outputFileName as NSString).appendingPathExtension("mov")!)
    self.url = URL(fileURLWithPath: stringPath)
    self.assetWidth = assetWidth
    self.assetHeight = assetHeight
    self.shouldOffsetAudio = shouldOffsetAudio
    self.realTime = realTime

    super.init()
  }

  func prepareToRecord() -> Future<Bool, AssetError> {
    return Future<Bool, AssetError> { complete in
      print("Preparing to record \(url)")
      writingQueue.async {
        let backgroundTask =
          UIApplication.shared.beginBackgroundTask(expirationHandler: nil)

        if FileManager.default.fileExists(atPath: self.url.path) {
          do {
            try FileManager.default.removeItem(at: self.url)
          } catch {
            print("Couldn't remove file at url: \(self.url)")
            DispatchQueue.main.async {
              return complete(.failure(.FileError))
            }
          }
        }

        UIApplication.shared.endBackgroundTask(backgroundTask)

        do {
          self.assetWriter = try AVAssetWriter(outputURL: self.url,
                                               fileType: AVFileType.mov)
          self.setupAudioWriterInput()
          self.setupVideoWriterInput()

          self.assetWriter?.startWriting()
          self.readyToWrite = true

          DispatchQueue.main.async {
            return complete(.success(true))
          }
        } catch {
          print("Couldn't create assetWriter.")
          DispatchQueue.main.async {
            return complete(.failure(.AssetWriterInitError))
          }
        }
      }
    }
  }

  func finishRecording() -> Future<(URL, CMTime), AssetError> {
    return Future<(URL, CMTime), AssetError> { complete in
      writingQueue.async {
        guard let assetWriter = self.assetWriter else {
          print("assetWriter is nil in finishRecording.")
          return
        }

        self.readyToWrite = false

        self.audioWriterInput?.markAsFinished()
        self.videoWriterInput?.markAsFinished()

        guard assetWriter.status != .completed else {
          Fatal.safeAssert("finishRecording is called with completed assetWriter")
          return
        }

        assetWriter.finishWriting {
          // callback can be on a different queue
          // make sure we switch to the writing queue
          self.writingQueue.async {
            if assetWriter.status != .completed {
              print("AssetWriter finished unsuccessfully \(assetWriter.status.rawValue) error \(assetWriter.error?.localizedDescription ?? "nil")")
              return complete(.failure(.CouldNotWriteAsset))
            }

            return complete(.success((self.url, self.sessionStartTime)))
          }
        }
      }
    }
  }

  // MARK: - Write Samples

  func appendSampleBuffer(sampleBuffer: CMSampleBuffer,
                          mediaType: AVMediaType) {
    writingQueue.async {
      guard self.readyToWrite else { return }
      if !self.hasStartedSession {
        self.sessionStartTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        self.assetWriter?.startSession(atSourceTime: self.sessionStartTime)
        self.hasStartedSession = true
      }

      mediaType == AVMediaType.video ? self.appendVideoSample(sampleBuffer: sampleBuffer) : self.appendAudioSample(sampleBuffer: sampleBuffer)
    }
  }

  // MARK: - Request Samples

  func requestInput(reader: AssetReader,
                    startTime: CMTime,
                    completion:@escaping (Bool) -> Void) {
    writingQueue.async {
      self.assetWriter?.startSession(atSourceTime: startTime)
      guard let audioWriterInput = self.audioWriterInput,
            let videoWriterInput = self.videoWriterInput else {
        DispatchQueue.main.async {
          self.readyToWrite = false
          self.audioWriterInput?.markAsFinished()
          self.videoWriterInput?.markAsFinished()
          guard self.assetWriter?.status != .completed else {
            Fatal.safeAssert("requestInput is called with completed assetWriter")
            return
          }
          self.assetWriter?.finishWriting {
            DispatchQueue.main.async {
              completion(false)
            }
          }
        }
        return
      }

      var audioFinished = false
      var videoFinished = false

      audioWriterInput.requestMediaDataWhenReady(on: self.writingQueue) {
        while audioWriterInput.isReadyForMoreMediaData {
          guard !audioFinished else {
            audioWriterInput.markAsFinished()
            break
          }
          guard let sample = reader.copyNextAudioSampleBuffer() else {
            audioFinished = true

            if audioFinished && videoFinished {
              completion(true)
            }
            break
          }
          audioWriterInput.append(sample)
        }
      }

      videoWriterInput.requestMediaDataWhenReady(on: self.writingQueue) {
        while videoWriterInput.isReadyForMoreMediaData {
          guard !videoFinished else {
            videoWriterInput.markAsFinished()
            break
          }
          guard let sample = reader.copyNextVideoSampleBuffer() else {
            videoFinished = true

            if audioFinished && videoFinished {
              completion(true)
            }
            break
          }
          videoWriterInput.append(sample)
        }
      }
    }
  }

  // MARK: - Convenience
  private func appendAudioSample(sampleBuffer: CMSampleBuffer) {
    dispatchPrecondition(condition: .onQueue(writingQueue))

    guard let input = audioWriterInput else {
      print("audioWriterInput is nil, returing early.")
      return
    }
    guard input.isReadyForMoreMediaData else {
      print("Not ready for more audio data while writing asset.")
      return
    }

    let bufferToWrite = AssetRecorder.offsetAudioSample(existingSampleBuffer: sampleBuffer)
    guard let buffer = bufferToWrite else { return }
    input.append(buffer)
  }

  private func appendVideoSample(sampleBuffer: CMSampleBuffer) {
    dispatchPrecondition(condition: .onQueue(writingQueue))

    guard let input = videoWriterInput else {
      print("VideoWriterInput is nil, returing early.")
      return
    }

    guard input.isReadyForMoreMediaData else {
      print("Not ready for more video data while writing asset.")
      return
    }

    input.append(sampleBuffer)
  }

  private static func offsetAudioSample(existingSampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
    var sampleBufferToWrite: CMSampleBuffer?
    var sampleTimingInfo: CMSampleTimingInfo = CMSampleTimingInfo.invalid
    CMSampleBufferGetSampleTimingInfo(existingSampleBuffer, at: 0, timingInfoOut: &sampleTimingInfo)

    let previousPresentationTimeStamp = sampleTimingInfo.presentationTimeStamp
    let timeOffset = AppHeadphoneManager.shared.recordingOffset
    sampleTimingInfo.presentationTimeStamp = CMTimeAdd(previousPresentationTimeStamp, timeOffset)

    let status = CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: existingSampleBuffer, sampleTimingEntryCount: 1, sampleTimingArray: &sampleTimingInfo, sampleBufferOut: &sampleBufferToWrite)

    return status == noErr ? sampleBufferToWrite : nil
  }

  private func setupAudioWriterInput() {
    dispatchPrecondition(condition: .onQueue(writingQueue))

    audioWriterInput = AVAssetWriterInput(mediaType: AVMediaType.audio,
                                          outputSettings: nil)
    audioWriterInput?.expectsMediaDataInRealTime = realTime

    addWriterInput(input: audioWriterInput!) // swiftlint:disable:this force_unwrapping
  }

  private func setupVideoWriterInput() {
    dispatchPrecondition(condition: .onQueue(writingQueue))

    let videoSettings = [AVVideoCodecKey: AVVideoCodecType.h264,
                         AVVideoWidthKey: assetWidth,
                         AVVideoHeightKey: assetHeight] as [String: Any]

    videoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video,
                                          outputSettings: videoSettings)
    videoWriterInput?.expectsMediaDataInRealTime = realTime

    addWriterInput(input: videoWriterInput!) // swiftlint:disable:this force_unwrapping
  }

  private func addWriterInput(input: AVAssetWriterInput) {
    dispatchPrecondition(condition: .onQueue(writingQueue))

    guard let assetWriter = assetWriter else {
      print("AssetWriter is Nil, returning early")
      return
    }

    guard assetWriter.canAdd(input) else {
      print("AssetWriter \(assetWriter) can't add input \(input) returning early")
      return
    }
    assetWriter.add(input)
  }
}
