// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import UIKit
import AVFoundation
import Kingfisher

@UIApplicationMain
  class AppDelegate: UIResponder, UIApplicationDelegate {
    
    enum Constants {
      static let minDiskSpaceRequiredInBytes: Int = 100 * 1024 * 1024
    }

  var window: UIWindow?
  static private(set) var fragmentAssetManager: LocalAssetManager?
  static let avSessionQueue = DispatchQueue(label: "com.collabOpenSource.avsession")

  override init() {
    super.init()
  }
    
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    configureAudioSession()

    UINavigationBar.appearance().barTintColor = UIColor.black
    UINavigationBar.appearance().tintColor = .black
    
    window = UIWindow(frame: UIScreen.main.bounds)
    window?.overrideUserInterfaceStyle = .light
    AppDelegate.fragmentAssetManager = LocalAssetManager()
    
    let storyboard = UIStoryboard(name: "Main", bundle: nil)
    let creationLaunchScreenViewController = storyboard
      .instantiateViewController(withIdentifier: "CreationLaunchScreen") as! CreationLaunchScreenViewController
    
    let navViewController = UINavigationController(rootViewController: creationLaunchScreenViewController)
    navViewController.modalPresentationStyle = .fullScreen
     
    window?.rootViewController = navViewController
    window?.makeKeyAndVisible()
    
    checkRemainingDiskSpace()
    beginSession()
    
    return true
  }

  func applicationDidEnterBackground(_ application: UIApplication) {
    let backgroundTask = application.beginBackgroundTask(expirationHandler: nil)
    application.endBackgroundTask(backgroundTask)
  }

  // MARK: - Private Helpers

  fileprivate func configureAudioSession() {
    _ = AppHeadphoneManager.shared.setAudioSessionForPlayback()
    AppMuteManager.shared.updateHardwareMuteState()
    AppMuteManager.shared.listenVolumeButtonChanges()
    AppHeadphoneManager.shared.updateHeadphoneState()
    AppHeadphoneManager.shared.updateHeadphoneType()
  }
    
  fileprivate func beginSession() {
    // ## Do any other session handling here
    configureKingfisherCache()
  }

  // MARK: - Kingfisher cache config

  fileprivate func configureKingfisherCache() {
    let cache = ImageCache.default
    cache.memoryStorage.config.totalCostLimit = 25 * 1024 * 1024
    cache.memoryStorage.config.countLimit = 40
  }
    
  // MARK: - Disk Space Handling
  fileprivate func checkRemainingDiskSpace() {
    DispatchQueue.global(qos: .background).async {
      let fileURL = URL(fileURLWithPath: NSHomeDirectory() as String)
      do {
        let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        if let capacity = values.volumeAvailableCapacity {
          // Available disk space: \(Double(capacity) / (1024.0 * 1024.0)) mb
          if capacity < Constants.minDiskSpaceRequiredInBytes {
            DispatchQueue.main.async {
              self.warnOfLowSpace()
            }
          }
        }
      } catch {
        // Error retrieving capacity
      }
    }
  }

  fileprivate func warnOfLowSpace() {
    if let window = self.window {
      Alert.show(in: window.rootViewController!,
                 title: "Low Disk Space",
                 message: "Please free up space on your device to be able to use this app")
    }
  }
}
