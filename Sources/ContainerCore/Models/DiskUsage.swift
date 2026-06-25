// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct DiskUsageEntry: Equatable, Sendable {
    public let sizeBytes: UInt64?
    public let reclaimableBytes: UInt64?
    public let activeCount: Int?
    public let totalCount: Int?

    public init(
        sizeBytes: UInt64? = nil,
        reclaimableBytes: UInt64? = nil,
        activeCount: Int? = nil,
        totalCount: Int? = nil
    ) {
        self.sizeBytes = sizeBytes
        self.reclaimableBytes = reclaimableBytes
        self.activeCount = activeCount
        self.totalCount = totalCount
    }
}

public struct DiskUsage: Equatable, Sendable {
    public let images: DiskUsageEntry
    public let containers: DiskUsageEntry
    public let volumes: DiskUsageEntry

    public init(
        images: DiskUsageEntry = DiskUsageEntry(),
        containers: DiskUsageEntry = DiskUsageEntry(),
        volumes: DiskUsageEntry = DiskUsageEntry()
    ) {
        self.images = images
        self.containers = containers
        self.volumes = volumes
    }

    public var totalSizeBytes: UInt64 {
        (images.sizeBytes ?? 0) + (containers.sizeBytes ?? 0) + (volumes.sizeBytes ?? 0)
    }
}
