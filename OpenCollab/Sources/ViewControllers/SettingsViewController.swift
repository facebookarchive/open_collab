// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import UIKit

class SettingsViewController: UIViewController {

  enum Constants {
    static let disableCameraMirroringKey = "com.openCollab.keys.enableCameraMirroring"
    static let enableUploadFromCameraRollKey = "com.openCollab.keys.enableUploadFromCameraRollKey"
  }

  @IBOutlet weak var stackView: UIStackView!
  @IBOutlet weak var mirroringEnabledSwitch: UISwitch!
  @IBOutlet weak var uploadFromCameraRollEnabledSwitch: UISwitch!

  // Double negatives bc mirroring is on by default.
  static var mirroringEnabled: Bool {
    get {
      return !UserDefaults.standard.bool(forKey: Constants.disableCameraMirroringKey)
    }
    set {
      UserDefaults.standard.set(!newValue, forKey: Constants.disableCameraMirroringKey)
    }
  }

  static var uploadFromCameraRollEnabled: Bool {
    get {
      return UserDefaults.standard.bool(forKey: Constants.enableUploadFromCameraRollKey)
    }
    set {
      UserDefaults.standard.set(newValue, forKey: Constants.enableUploadFromCameraRollKey)
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    mirroringEnabledSwitch.isOn = SettingsViewController.mirroringEnabled
    uploadFromCameraRollEnabledSwitch.isOn = SettingsViewController.uploadFromCameraRollEnabled
  }

  @IBAction func didChangeUploadFromCameraRollEnabledSwitch(_ sender: Any) {
    SettingsViewController.uploadFromCameraRollEnabled = uploadFromCameraRollEnabledSwitch.isOn
  }

  @IBAction func didChangeMirroringEnabledSwitch(_ sender: Any) {
    SettingsViewController.mirroringEnabled = mirroringEnabledSwitch.isOn
  }
}
