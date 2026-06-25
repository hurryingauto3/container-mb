// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct ImageSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let sizeBytes: UInt64?
    public let digest: String?
    public let os: String?
    public let architecture: String?
    public let createdAt: Date?
    public let layerCount: Int?
    public let entrypoint: [String]
    public let command: [String]
    public let env: [String]
    public let exposedPorts: [String]
    public let raw: JSONValue

    public init(
        id: String,
        name: String,
        sizeBytes: UInt64? = nil,
        digest: String? = nil,
        os: String? = nil,
        architecture: String? = nil,
        createdAt: Date? = nil,
        layerCount: Int? = nil,
        entrypoint: [String] = [],
        command: [String] = [],
        env: [String] = [],
        exposedPorts: [String] = [],
        raw: JSONValue
    ) {
        self.id = id
        self.name = name
        self.sizeBytes = sizeBytes
        self.digest = digest
        self.os = os
        self.architecture = architecture
        self.createdAt = createdAt
        self.layerCount = layerCount
        self.entrypoint = entrypoint
        self.command = command
        self.env = env
        self.exposedPorts = exposedPorts
        self.raw = raw
    }

    /// The display name, falling back to `<none>` for untagged/anonymous images.
    public var repositoryTag: String {
        name.isEmpty ? "<none>" : name
    }

    /// First 12 hex characters of the digest, stripping any `sha256:` prefix.
    public var shortDigest: String {
        guard let digest else { return String(id.prefix(12)) }
        let hex = digest.contains(":") ? String(digest.split(separator: ":").last ?? "") : digest
        return String(hex.prefix(12))
    }

    /// e.g. "linux/arm64", or "--" when platform is unknown.
    public var platformDisplay: String {
        switch (os, architecture) {
        case let (os?, arch?) where !os.isEmpty && !arch.isEmpty:
            return "\(os)/\(arch)"
        case let (os?, nil) where !os.isEmpty:
            return os
        case let (nil, arch?) where !arch.isEmpty:
            return arch
        default:
            return "--"
        }
    }
}
