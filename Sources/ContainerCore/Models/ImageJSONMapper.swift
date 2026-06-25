// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum ImageJSONMapper {
    private static let decoder = JSONDecoder()
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let fallbackISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public static func images(from data: Data) throws -> [ImageSummary] {
        let items = try rootArray(from: data)
        return items.compactMap(image(from:))
    }

    private static func rootArray(from data: Data) throws -> [JSONValue] {
        guard !data.trimmedString.isEmpty else { return [] }
        let value = try decoder.decode(JSONValue.self, from: data)
        guard let array = value.arrayValue else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Expected top-level JSON array")
            )
        }
        return array
    }

    private static func image(from value: JSONValue) -> ImageSummary? {
        guard let object = value.objectValue else { return nil }
        let configuration = object["configuration"]?.objectValue ?? [:]

        let id = object["id"]?.stringValue
            ?? configuration["id"]?.stringValue
            ?? value.deepValues(named: "id").compactMap(\.stringValue).first
        guard let id, !id.isEmpty else { return nil }

        let variants = value.value(at: ["variants"])?.arrayValue ?? []
        let firstVariant = variants.first

        let name = configuration["name"]?.stringValue
            ?? value.value(at: ["configuration", "name"])?.stringValue
            ?? value.deepValues(named: "name").compactMap(\.stringValue).first
            ?? ""

        // Per-image disk size: sum the compressed sizes of all variants. The
        // manifest size under configuration.descriptor.size is ~10KB — not disk size.
        let sizeBytes: UInt64? = {
            let sizes = variants.compactMap { $0["size"]?.uint64Value }
            return sizes.isEmpty ? nil : sizes.reduce(0, +)
        }()

        let digest = value.value(at: ["configuration", "descriptor", "digest"])?.stringValue
            ?? configuration["descriptor"]?["digest"]?.stringValue

        let platform = firstVariant?["platform"]?.objectValue
        let os = platform?["os"]?.stringValue
        let architecture = platform?["architecture"]?.stringValue

        let createdAt = date(from: configuration["creationDate"] ?? configuration["created"])

        let variantConfig = firstVariant?["config"]?.objectValue
        let layerCount = variantConfig?["rootfs"]?["diff_ids"]?.arrayValue?.count

        let innerConfig = variantConfig?["config"]?.objectValue
        let entrypoint = stringArray(from: innerConfig?["Entrypoint"] ?? innerConfig?["entrypoint"])
        let command = stringArray(from: innerConfig?["Cmd"] ?? innerConfig?["cmd"])
        let env = stringArray(from: innerConfig?["Env"] ?? innerConfig?["env"])
        let exposedPorts = exposedPortKeys(from: innerConfig?["ExposedPorts"] ?? innerConfig?["exposedPorts"])

        return ImageSummary(
            id: id,
            name: name,
            sizeBytes: sizeBytes,
            digest: digest,
            os: os,
            architecture: architecture,
            createdAt: createdAt,
            layerCount: layerCount,
            entrypoint: entrypoint,
            command: command,
            env: env,
            exposedPorts: exposedPorts,
            raw: value
        )
    }

    private static func stringArray(from value: JSONValue?) -> [String] {
        guard let items = value?.arrayValue else { return [] }
        return items.compactMap(\.stringValue)
    }

    // ExposedPorts is an object keyed by "80/tcp" -> {} (or null). Use its keys.
    private static func exposedPortKeys(from value: JSONValue?) -> [String] {
        guard let object = value?.objectValue else { return [] }
        return object.keys.sorted()
    }

    private static func date(from value: JSONValue?) -> Date? {
        guard let value else { return nil }
        if let string = value.stringValue {
            return isoFormatter.date(from: string)
                ?? fallbackISOFormatter.date(from: string)
                ?? Double(string).map(Date.init(timeIntervalSince1970:))
        }

        if let seconds = value.doubleValue {
            return Date(timeIntervalSince1970: seconds)
        }

        return nil
    }
}

private extension Data {
    var trimmedString: String {
        String(data: self, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
