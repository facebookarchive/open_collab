// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import BrightFutures
import AVFoundation

class LocalAssetManager: NSObject {

  private enum Constants {
    static let maxInvalidAVAssetRetryCount: Int = 1
    static let options = [AVURLAssetPreferPreciseDurationAndTimingKey: true]
  }

  // MARK: - Private Variables

  let assetsDirectory: URL
  fileprivate lazy var downloadsQueue = DispatchQueue(label: "collab.assetManager")
  fileprivate lazy var activeDownloads: [String: Future<Bool, AssetError>] = [:]
//  fileprivate (set) lazy var downloadRequestManager = DownloadRequestManager() // ## TODO : Add something like this when we want to import videos from outside app
  fileprivate let loadedAssetsCache = NSCache<AnyObject, AVURLAsset>()

  // MARK: - Init

  override init() {
    let documentsPath = NSSearchPathForDirectoriesInDomains(.cachesDirectory,
                                                            .userDomainMask, true)[0]
    self.assetsDirectory = URL(fileURLWithPath: documentsPath).appendingPathComponent("assets")

    super.init()

    loadedAssetsCache.countLimit = 30
    loadedAssetsCache.evictsObjectsWithDiscardedContent = true
  }
  
  // MARK: - Public Methods
  
  func getAsset(fragment: FragmentHost) -> Future<AVURLAsset?, AssetError> {
    let assetInfo = fragment.assetInfo
    switch assetInfo {
    case .empty:
      return Future(value: nil)
    case .downloadedFragment(let downloadedFragment):
        // ## TODO : Build in a way to import assets from outside the app
        //      return getDownloadedAsset(fragment: downloadedFragment).flatMap { (_, asset) in
        //                                  return Future(value: asset)
        return Future(value: nil)
    case .userRecorded(let recordedURL):
      // Cast the result of getUserAsset to be optional. getUserAsset should never return nil but
      // we cast here to support returning nil assets for empty fragments.
      return getUserAsset(URL: recordedURL).flatMap { asset -> Future<AVURLAsset?, AssetError> in
        return Future(value: asset)
      }
    }
  }

  func preloadAsset(remoteFragment: Fragment) {
    // Download asset to disk
    preloadLocalAsset(fragment: remoteFragment)
  }
  
  func preloadLocalAsset(fragment: Fragment) {
    _ = getDownloadedAsset(fragment: fragment,
                           isPreload: true)
  }

  func loadAsset(fragment: FragmentHost) -> Future<AVURLAsset?, AssetError> {
    // Get the asset and then do nothing with the results. This will load the asset
    // if its not already cached. If the asset is a streamed asset it won't load
    // anything but it will cache the asset for reuse if it doesn't already exist.
    return getAsset(fragment: fragment)
  }

  // ## TODO : Replace this function with a way to load in clips directly, like from
  // a folder that already exists locally, or grabbing from a Google Drive url, etc.
  // The isPreload flag should just be used to decide whether to promote an existing download or start fresh
  func getDownloadedAsset(fragment: Fragment,
                          isPreload: Bool = false) -> Future<(String, AVURLAsset), AssetError> {
//    let fileManger = FileManager.default
//    // if the file exists locally, return it
//    let fileURL = localFileURL(fragment: fragment)
//    if fileManger.fileExists(atPath: fileURL.path) {
//      return getOrLoadAsset(URL: fileURL).flatMap { (asset) in
//        return Future(value: (fragment.id, asset))
//      }
//    }
//
//    return downloadAssetMedia(fragment: fragment,
//                              fileURL: fileURL,
//                              isPreload: isPreload)
//      .flatMap { [weak self] URL -> Future<(String, AVURLAsset), AssetError> in
//        guard let self = self else { return Future(error: .NoAssetManager) }
//        return self.getOrLoadAsset(URL: fileURL).flatMap { (asset) in
//          return Future(value: (fragment.id, asset))
//        }
//      }
    return Future(error: AssetError.AssetNotFound) // ## TODO : remore this after implementing getDownloadedAsset
  }

//  func downloadAssetMedia(fragment: Fragment,
//                          fileURL: URL,
//                          isPreload: Bool) -> Future<URL, AssetError> {
//    createAssetPrefixDirectoryIfNeeded(categoryId: fragment.categoryID)
//    let promise = Promise<URL, AssetError>()
//    downloadsQueue.async { [weak self] in
//      guard let self = self else {
//        promise.failure(.AssetNotFound)
//        return
//      }
//      self.downloadMediaFile(fragment: fragment,
//                             destinationURL: fileURL,
//                             isPreload: isPreload)
//        .onSuccess(callback: { (done) in
//          guard done else {
//            print("downloadMediaFile finished with not done flag")
//            promise.failure(.AssetNotFound)
//            return
//          }
//          promise.success(fileURL)
//        }).onFailure { (error) in
//          promise.failure(error)
//        }
//    }
//
//    return promise.future
//  }

  func getUserAsset(URL: URL) -> Future<AVURLAsset, AssetError> {
    return getOrLoadAsset(URL: URL)
  }

  fileprivate var assetLoadingCache = [String: Future<AVURLAsset, AssetError>]()
  
  func getOrLoadAsset(URL: URL) -> Future<AVURLAsset, AssetError> {
    assert(Thread.isMainThread)

    // 1. check to see if any in-flight asset loading futures exist for this url
    if let future = assetLoadingCache[URL.absoluteString] {
      return future
    }

    // 2. Check if already loaded asset exists in loaded cache
    let key = LocalAssetManager.cacheKey(for: URL)
    if let loadedAssetFromCache =
        loadedAssetsCache.object(forKey: key) {
      return Future(value: loadedAssetFromCache)
    }

    // 3. Load the asset and cache it
    let asset = AVURLAsset(url: URL, options: Constants.options)

    let future = Future<AVURLAsset, AssetError> { complete in
      asset.loadValuesAsynchronously(forKeys: ["duration", "playable"]) {
        DispatchQueue.main.async {
          guard self.assetIsPlayable(asset: asset) else {
            print("Tried to get or load an asset that was not playable.")
            return complete(.failure(.NotPlayable))
          }
          // Add the newly loaded asset to the dictionary
          self.loadedAssetsCache.setObject(asset, forKey: key)
          return complete(.success(asset))
        }
      }
    }
    future.onComplete { [weak self] (_) in
      self?.assetLoadingCache.removeValue(forKey: URL.absoluteString)
    }
    assetLoadingCache[URL.absoluteString] = future
    return future
  }

  func saveTemporaryAsset(from source: URL, categoryId: String) -> URL? {
    createAssetPrefixDirectoryIfNeeded(categoryId: categoryId)
    let target = assetsDirectory.appendingPathComponent(categoryId).appendingPathComponent(source.lastPathComponent)

    do {
      try FileManager.default.moveItem(at: source, to: target)
    } catch _ {
      return nil
    }

    return target
  }
  
  func rasterizationDirectory() -> URL {
    let url = assetsDirectory.appendingPathComponent("export", isDirectory: true)
    let fileManager = FileManager.default
    if !fileManager.fileExists(atPath: url.path) {
      do {
        try fileManager.createDirectory(at: url,
                                       withIntermediateDirectories: true,
                                       attributes: nil)
      } catch let error {
        print("ERROR: ", error)
      }
    }
    return url
  }

  // MARK: - Private Helpers

  fileprivate static func cacheKey(for url: URL) -> AnyObject {
    return "\(url.absoluteString)" as AnyObject
  }

  fileprivate func createAssetPrefixDirectoryIfNeeded(categoryId: String) {
    let fileManager = FileManager.default
    let prefixURL = assetsDirectory.appendingPathComponent(categoryId)
    if !fileManager.fileExists(atPath: prefixURL.path) {
      do {
        try fileManager.createDirectory(at: prefixURL,
                                       withIntermediateDirectories: true,
                                       attributes: nil)
      } catch let error {
        print("ERROR: ", error)
      }
    }
  }

  fileprivate func localTempFileURL(fragment: Fragment) -> URL {
    let fileName = "\(fragment.id).mov"
    let filePath = NSTemporaryDirectory().appending(fileName)
    return URL(fileURLWithPath: filePath)
  }

//  fileprivate func localFileURL(fragment: Fragment) -> URL {
//    let fileName = "\(fragment.id).mp4"
//    let prefixURL = assetsDirectory.appendingPathComponent(fragment.categoryID) // ## TODO : This category ID concept doesn't exist anymore so need to replace with a different way to organize files
//    let fileURL = prefixURL.appendingPathComponent(fileName)
//    return fileURL
//  }

//  fileprivate func downloadMediaFile(fragment: Fragment,
//                                     destinationURL: URL,
//                                     isPreload: Bool = false,
//                                     retryCount: Int = 0) -> Future<Bool, AssetError> {
//    guard let fragmentURL = fragment.formats.first?.urlCdn else {
//      print("downloadMediaFile no format url \(fragment.id)")
//      return Future(error: .EmptyCategory)
//    }
//    let fileName = "\(fragment.categoryID)-\(fragment.id)"
//
//    dispatchPrecondition(condition: .onQueue(downloadsQueue))
//
//    guard let url = URL(string: fragmentURL) else {
//      print("downloadMediaFile nil url for \(fragmentURL)")
//      return Future(error: .AssetNotFound)
//    }
//
//    if let activeFuture = activeDownloads[fileName] {
//      if !isPreload {
//        self.downloadRequestManager.promoteExistingDownload(of: url, shouldContinueInBackground: true)
//      }
//      return activeFuture
//    }
//
//    // store as temp file, verify that it's a valid
//    // avasset with audio/video tracks
//    let tempFileName = "temp_\(arc4random() % 100000)_\(destinationURL.lastPathComponent)"
//    let tempURLPath = destinationURL.deletingLastPathComponent().appendingPathComponent(tempFileName).path
//    let temp = URL(fileURLWithPath: tempURLPath)
//    let fileManger = FileManager.default
//
//    let future = Future<Bool, AssetError> { complete in
//      api.downloadData(from: url,
//                       to: temp,
//                       contentIdentifier: fragment.id,
//                       downloadRequestManager: self.downloadRequestManager,
//                       isPreload: isPreload,
//                       shouldContinueInBackground: true).onSuccess { (localURL) in
//        if AVAsset.isValidAsset(filePath: localURL.path) {
//          do {
//            try fileManger.moveItem(atPath: localURL.path, toPath: destinationURL.path)
//            complete(.success(true))
//          } catch let error {
//            print("ERROR: Couldn't move item error \(error.localizedDescription)")
//            try? fileManger.removeItem(at: localURL)
//            complete(.failure(.AssetNotFound))
//          }
//        } else {
//          print("ERROR: Downloaded asset is not a valid AVAsset for: \(url) local: \(localURL) local file size: \(String(format: "%.2f mb", localURL.fileSizeInMB ?? 0))")
//          try? fileManger.removeItem(at: localURL)
//          complete(.failure(.InvalidAVAsset))
//        }
//      }.onFailure { (error) in
//        try? fileManger.removeItem(at: temp)
//        print("ERROR: failed to download data for \(url) error \(error)")
//        complete(.failure(.AssetNotFound))
//      }.onComplete(downloadsQueue.context) { [weak self] (_) in
//        self?.activeDownloads.removeValue(forKey: fileName)
//      }
//    }
//
//    let futureWithRecovery = future
//      .recoverWith(context: downloadsQueue.context,
//                   task: { [weak self] (error) -> Future<Bool, AssetError> in
//      guard retryCount < Constants.maxInvalidAVAssetRetryCount else { return Future(error: error) }
//      guard let self = self else { return Future(error: error) }
//      guard case AssetError.InvalidAVAsset = error else { return Future(error: error) }
//                    print("Invalid AVAsset, retrying for url \(url)")
//      return self.downloadMediaFile(fragment: fragment,
//                                    destinationURL: destinationURL,
//                                    loggingAppSurface: loggingAppSurface,
//                                    isPreload: isPreload,
//                                    retryCount: retryCount + 1)
//
//    })
//    activeDownloads[fileName] = futureWithRecovery
//    return futureWithRecovery
//  }

  private func assetIsPlayable(asset: AVAsset) -> Bool {
    var durationError: NSError?
    let durationStatus =
      asset.statusOfValue(forKey: "duration",
                               error: &durationError)
    guard durationStatus == .loaded else {
      print("ERROR: Failed to load duration property with error: \(String(describing: durationError))")
      return false
    }

    var playableError: NSError?
    let playableStatus =
      asset.statusOfValue(forKey: "playable",
                               error: &playableError)
    guard playableStatus == .loaded else {
      print("ERROR: Failed to read playable duration property with error: \(String(describing: playableError))")
      return false
    }

    return asset.isPlayable
  }
}
