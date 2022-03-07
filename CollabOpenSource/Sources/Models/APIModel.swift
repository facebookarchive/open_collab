// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import Foundation

struct Fragment: Codable {
    let formats: [Format]
    /// A unique ID for the fragment.
    let id: String
    /// Exact url to the fragment's thumbnail.
    let thumbnailURL: String?

    enum CodingKeys: String, CodingKey {
        case formats, id
        case thumbnailURL = "thumbnail_url"
    }
}

struct Collab: Codable {
  // ## TODO : Add fields here if you want to maintain a representation of a finished collab.
  // We aren't using it in client-only creation flow right now
}

/// A format represents a single variant/encoding of a fragment.
struct Format: Codable {
    /// The bitrate of the format.
    let bitrate: Int?
    /// A unique ID for the format.
    let id: String
    /// The url at which the format can be accessed, relative to the server root
    let url: String?

    enum CodingKeys: String, CodingKey {
        case bitrate, id, url
    }
}
