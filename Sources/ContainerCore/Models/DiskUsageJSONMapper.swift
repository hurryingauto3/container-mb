// SPDX-License-Identifier: Apache-2.0

import Foundation

// `container system df --format json` emits a top-level OBJECT keyed by section
// ("images"/"containers"/"volumes"), not the array shape the rest of the CLI uses.
// `ContainerJSONMapper.rootArray` therefore can't decode it; this mapper reads the
// object directly with `JSONValue` accessors in the project's defensive style.
public enum DiskUsageJSONMapper {
    private static let decoder = JSONDecoder()

    public static func diskUsage(from data: Data) throws -> DiskUsage {
        let value = try decoder.decode(JSONValue.self, from: data)
        guard value.objectValue != nil else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Expected top-level JSON object")
            )
        }

        return DiskUsage(
            images: entry(from: value["images"]),
            containers: entry(from: value["containers"]),
            volumes: entry(from: value["volumes"])
        )
    }

    private static func entry(from value: JSONValue?) -> DiskUsageEntry {
        guard let value, value.objectValue != nil else { return DiskUsageEntry() }
        return DiskUsageEntry(
            sizeBytes: value["sizeInBytes"]?.uint64Value ?? value["size"]?.uint64Value,
            reclaimableBytes: value["reclaimable"]?.uint64Value ?? value["reclaimableInBytes"]?.uint64Value,
            activeCount: value["active"]?.intValue,
            totalCount: value["total"]?.intValue
        )
    }
}
