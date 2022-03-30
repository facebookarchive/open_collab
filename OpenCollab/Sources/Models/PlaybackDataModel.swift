// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import Photos

protocol PlaybackDataModelDelegate: NSObjectProtocol {
  func availableFragmentsChanged()
  func selectedFragmentsChanged()
}

class PlaybackDataModel {
  var recordFragment: FragmentHost?
  var poolFragments = [FragmentHost]() { // shuffled
    didSet {
      self.delegate?.availableFragmentsChanged()
    }
  }
  var takeFragments = [FragmentHost]() { // stored numerically, etc. Take 1, Take 2, Take 3
    didSet {
      self.delegate?.availableFragmentsChanged()
    }
  }

  var selectedFragments = [FragmentHost]() {
    didSet {
      if canNotify {
        self.delegate?.selectedFragmentsChanged()
      }
    }
  }

  var combinedFragments: [FragmentHost] {
    return buildCombinedFragments()
  } // the ordering of takes & pool fragments as they are ordered to the user

  private(set) var collab: Collab?
  var isCFS: Bool {
    return collab == nil // Created from scratch
  }
  // This is gross. We need to move FragmentMatrix into the data model.
  var canNotify: Bool = true
  private(set) var duration: CMTime
  weak var delegate: PlaybackDataModelDelegate?

  // ## TODO: Add the ability to construct a PlaybackDataModel from a pool of mp4 fragment videos
  // Also will need to extend Collab to include a duration calculated using the durations of the
  // videos in the pool. Edit the following commented-out function to take in the desired input
  // type -- "fragmentInstance" here can be replaced by the input type, and

//  init(from collab: Collab) {
//    self.collab = collab
//    self.duration = collab.duration
//
//    // Copy the collab's current fragment assets for the remix session
//    let collabFragments = collab.fragmentInstances.map { (fragmentInstance) -> FragmentHost in
//      guard let remoteFragment = fragmentInstance.fragment else {
//        let fragment = FragmentHost(assetInfo: AssetInfo.empty,
//                                    volume: 0,
//                                    assetDuration: .zero)
//        return fragment
//      }
//
//      // Determine the asset type for this fragment.
//      let assetInfo = AssetInfo.create(fragment: remoteFragment)
//
//      let fragment =
//        FragmentHost(assetInfo: assetInfo,
//                     volume: Float(responseFragmentInstance.volume ?? 0),
//                     assetDuration: collab.duration)
//
//      return fragment
//    }
//
//    // The initial state of the fragment pool can't contain hosts with duplicate IDs
//    var fragmentIDsAdded: [String] = []
//    let dedupedFragments: [FragmentHost] = collabFragments.compactMap { fragment in
//      if let fragmentID = fragment.assetInfo.downloadedFragment?.id {
//        guard !fragmentIDsAdded.contains(fragmentID) else { return nil }
//        fragmentIDsAdded.append(fragmentID)
//      }
//      return fragment
//    }
//
//    // The selected fragments and the pool fragments both start out as the fragments in the collab.
//    self.selectedFragments = collabFragments
//    self.poolFragments = dedupedFragments
//  }

  init(from recordingFragment: FragmentHost) {
    let playbackEndTime = recordingFragment.assetDuration
    let fragment = FragmentHost(assetInfo: recordingFragment.assetInfo,
                                volume: recordingFragment.volume,
                                assetDuration: recordingFragment.assetDuration,
                                playbackEndTime: playbackEndTime,
                                playbackStartTime: .zero,
                                minPlaybackDuration: FragmentHost.minFragmentDuration,
                                maxPlaybackDuration: FragmentHost.maxFragmentDuration)
    selectedFragments = [fragment]
    takeFragments = [fragment]
    self.duration = recordingFragment.assetDuration
  }

  init (from cameraRollVideo: URL) {
    let asset = AVURLAsset(url: cameraRollVideo)
    let assetInfo = AssetInfo.userRecorded(cameraRollVideo)
    let fragment = FragmentHost(assetInfo: assetInfo,
                                volume: 1,
                                assetDuration: asset.duration,
                                playbackEndTime: asset.duration,
                                playbackStartTime: .zero,
                                minPlaybackDuration: FragmentHost.minFragmentDuration,
                                maxPlaybackDuration: FragmentHost.maxFragmentDuration)
    selectedFragments = [fragment]
    takeFragments = [fragment]
    self.duration = asset.duration
  }

  init(trimmerModel: PlaybackDataModel) {
    let recordedFragment = trimmerModel.selectedFragments[0]

    for _ in 1...Collab.Constants.minClipsPerCollab {
      selectedFragments.append(FragmentHost(fragment: recordedFragment))
    }
    self.takeFragments = [selectedFragments.first!] // swiftlint:disable:this force_unwrapping
    self.duration = trimmerModel.duration
  }

  func addTakeFragments(fragments: [FragmentHost]) {
    takeFragments.append(contentsOf: fragments)
  }

  func buildCombinedFragments() -> [FragmentHost] {
    let fragments = recordFragment != nil ? [recordFragment!] : [] // swiftlint:disable:this force_unwrapping
    return fragments + takeFragments.reversed() + poolFragments
  }

  func getSelectedIndex(rank: Int) -> Int? {
    guard rank < selectedFragments.count else { return nil }
    let selectedFragment = selectedFragments[rank]

    // Iterate fragments in the order we serve them to UIs. This is
    // the "combined" order.
    let index = combinedFragments.firstIndex(where: {
      // If the selectedFragment is a user take check to see if
      // the user recorded URL matches anything in the available fragments.
      if selectedFragment.isRecordPlaceholder {
        return $0.isRecordPlaceholder
      } else if selectedFragment.assetInfo.isUserRecorded {
        return selectedFragment.assetInfo.userRecordedURL == $0.assetInfo.userRecordedURL
      } else if let remoteFragment = selectedFragment.assetInfo.downloadedFragment {
        // Otherwise check if the selectedFragment is a remote fragment. If it
        // is then we want to check to see if the fragment ID matches any of the
        // available fragments.
        return remoteFragment.id == $0.assetInfo.downloadedFragment?.id
      }

      // If neither of the above statements is true then we haven't found the
      // fragment yet keep looking.
      return false
    })

    return index
  }

  func randomClip() -> FragmentHost? {
    guard let randomizedClip = (takeFragments + poolFragments).randomElement() else {
      return nil
    }

    return randomizedClip
  }

  func adjustTrimTimes(trimRange: ClosedRange<CMTime>, of fragmentIndex: Int) {
    var fragment = selectedFragments[fragmentIndex]
    fragment.setPlaybackTimes(startTime: trimRange.lowerBound, endTime: trimRange.upperBound)
    selectedFragments[fragmentIndex] = fragment
    duration = trimRange.upperBound - trimRange.lowerBound
  }
}
