// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

enum AssetError: Error {
  case AssetNotFound
  case InvalidAVAsset
  case NotPlayable
  case EmptyAsset
  case NoAssetManager
  case FailedToCreateImageForAsset
  case AssetRecorderError
  case CouldNotRead
  case CouldNotWriteAsset
  case FileError
  case AssetWriterInitError
}
