// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import AVFoundation
import BrightFutures

struct RecordingAuthorizer {
  static func isAuthorized() -> Future<RecordingAuthorizationStatus, AssetError> {
    let promise = Promise<RecordingAuthorizationStatus, AssetError>()

    switch (AVCaptureDevice.authorizationStatus(for: .video), AVCaptureDevice.authorizationStatus(for: .audio)) {
    case (.authorized, .authorized):
      return Future(value: RecordingAuthorizationStatus.authorized)
    case (.notDetermined, let micAuth):
      AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
        if granted {
          self.isAuthorized().onSuccess { status in
            promise.complete(.success(status))
          }
        } else {
          promise.complete(.success(micAuth == .authorized ? .micAuthorizedOnly : .bothUnauthorized))
        }
      })
    case (let cameraAuth, .notDetermined):
      AVCaptureDevice.requestAccess(for: .audio, completionHandler: { granted in
        if granted {
          self.isAuthorized().onSuccess { status in
            promise.complete(.success(status))
          }
        } else {
          promise.complete(.success(cameraAuth == .authorized ? .cameraAuthorizedOnly : .bothUnauthorized))
        }
      })
    case (let cameraAuth, let micAuth):
      let status: RecordingAuthorizationStatus
      if cameraAuth == .authorized, micAuth != .authorized {
        status = .cameraAuthorizedOnly
      } else if cameraAuth != .authorized, micAuth == .authorized {
        status = .micAuthorizedOnly
      } else {
        status = .bothUnauthorized
      }
      promise.complete(.success(status))
    }
    return promise.future
  }

  enum RecordingAuthorizationStatus {
    case authorized, cameraAuthorizedOnly, micAuthorizedOnly, bothUnauthorized
  }

  static func showUnauthorizedAlert(vc: UIViewController,
                                    status: RecordingAuthorizationStatus) {

    let unauthorizedDevice: String
    switch status {
    case .authorized:
      print("showUnauthorizedAlert called with authorized status")
      return
    case .cameraAuthorizedOnly:
      unauthorizedDevice = "microphone"
    case .micAuthorizedOnly:
      unauthorizedDevice = "camera"
    case .bothUnauthorized:
      unauthorizedDevice = "camera & microphone"
    }

    let message = "Collab Open Source doesn't have permission to use the \(unauthorizedDevice), please change privacy settings"
    let alertController = UIAlertController(title: "Collab", message: message, preferredStyle: .alert)

    alertController.addAction(UIAlertAction(title: "OK",
                                            style: .cancel,
                                            handler: nil))

    alertController.addAction(UIAlertAction(title: "Settings",
                                            style: .`default`,
                                            handler: { _ in
                                              UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!,
                                                                        options: [:],
                                                                        completionHandler: nil)
                                            }))
    vc.present(alertController, animated: true, completion: nil)
  }
}
