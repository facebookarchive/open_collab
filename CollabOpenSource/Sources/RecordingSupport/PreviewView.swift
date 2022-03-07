// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import UIKit
import AVFoundation

class PreviewView: UIView {

  override init(frame: CGRect) {
    super.init(frame: frame)
    self.videoPreviewLayer.videoGravity = .resizeAspectFill
    self.videoPreviewLayer.contentsGravity = .resizeAspectFill
  }

  required init?(coder: NSCoder) {
    Fatal.safeError()
  }

  override class var layerClass: AnyClass {
    return AVCaptureVideoPreviewLayer.self
  }

  var videoPreviewLayer: AVCaptureVideoPreviewLayer {
    return layer as! AVCaptureVideoPreviewLayer
  }

  var session: AVCaptureSession? {
    get {
      return videoPreviewLayer.session
    }
    set {
      videoPreviewLayer.session = newValue
    }
  }
}
