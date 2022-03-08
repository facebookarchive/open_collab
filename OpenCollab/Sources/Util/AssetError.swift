// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

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
