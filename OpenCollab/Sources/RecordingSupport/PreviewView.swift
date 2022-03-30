// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import AVFoundation
import UIKit

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
    // swiftlint:disable:next force_cast
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
